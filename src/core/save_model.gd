class_name SaveModel
extends RefCounted

const SCHEMA_VERSION: int = 3
# Task 5 (CTR R7, the Cup): the one reserved key inside the "racing" section
# that does NOT hold a per-track best-time record -- see fresh()/validate()/
# _migrate_v2_to_v3()'s own docs for why "cups" lives INSIDE "racing" (not as
# its own new top-level section) and how the validation/normalization loops
# below skip it wherever they walk "racing" expecting per-track records.
const _RACING_CUPS_KEY := "cups"
const _RELIC_TIERS: Array[String] = [
	"none",
	"sapphire",
	"gold",
	"platinum",
]
const _MILLISECONDS_PER_SECOND: float = 1000.0


static func fresh() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"levels": {},
		"lifetime_wumpa": 0,
		"boss_defeated": {
			"papu_papu": false,
		},
		# Task 5 (CTR R7, the Cup): "cups" is required inside "racing" from
		# v3 onward -- the same "not left optional-if-missing" strictness
		# Task 9's own "racing" top-level section carries (see validate()'s
		# own doc on that section), so a legacy profile can only ever pass
		# validate() after actually migrating through _migrate_v2_to_v3
		# below, which backfills exactly this shape.
		"racing": {_RACING_CUPS_KEY: {}},
	}


static func validate(data: Dictionary) -> bool:
	if _schema_version(data) != SCHEMA_VERSION:
		return false

	var levels_value: Variant = data.get("levels")
	if not levels_value is Dictionary:
		return false
	var levels: Dictionary = levels_value
	for level_id: Variant in levels:
		if typeof(level_id) != TYPE_STRING and typeof(level_id) != TYPE_STRING_NAME:
			return false
		var record_value: Variant = levels[level_id]
		if not record_value is Dictionary:
			return false
		if not _validate_level_record(record_value):
			return false

	if not _is_non_negative_integer(data.get("lifetime_wumpa")):
		return false

	var boss_value: Variant = data.get("boss_defeated")
	if not boss_value is Dictionary:
		return false
	var boss_defeated: Dictionary = boss_value
	if typeof(boss_defeated.get("papu_papu")) != TYPE_BOOL:
		return false

	# Task 9 (CTR racing mode, R2): "racing" is a required top-level section,
	# the same strictness "levels" and "boss_defeated" already carry above --
	# not left optional-if-missing, so a legacy profile can only ever pass
	# this check after actually migrating through _migrate_v1_to_v2 (see
	# below), which is what proves old saves keep loading rather than merely
	# happening to.
	var racing_value: Variant = data.get("racing")
	if not racing_value is Dictionary:
		return false
	var racing: Dictionary = racing_value

	# Task 5 (CTR R7, the Cup): "cups" is a RESERVED key inside "racing" --
	# checked and validated on its own here, BEFORE the per-track loop below
	# ever sees it, and excluded from that loop's own per-track record shape
	# check (a cups dict has no best_total_time_ms/best_lap_time_ms and would
	# fail _validate_racing_record() if the loop tried to validate it as one).
	# Required with the same strictness "racing" itself carries one section
	# up -- see fresh()'s own doc -- so a legacy profile only ever passes this
	# check after actually migrating through _migrate_v2_to_v3.
	var cups_value: Variant = racing.get(_RACING_CUPS_KEY)
	if not cups_value is Dictionary:
		return false
	var cups: Dictionary = cups_value
	for cup_id: Variant in cups:
		if typeof(cup_id) != TYPE_STRING and typeof(cup_id) != TYPE_STRING_NAME:
			return false
		var cup_record_value: Variant = cups[cup_id]
		if not cup_record_value is Dictionary:
			return false
		if not _validate_cup_record(cup_record_value):
			return false

	for track_id: Variant in racing:
		if String(track_id) == _RACING_CUPS_KEY:
			continue
		if typeof(track_id) != TYPE_STRING and typeof(track_id) != TYPE_STRING_NAME:
			return false
		var racing_record_value: Variant = racing[track_id]
		if not racing_record_value is Dictionary:
			return false
		if not _validate_racing_record(racing_record_value):
			return false

	return true


static func migrate(data: Dictionary) -> Dictionary:
	if is_future_version(data):
		return {}
	var version := _schema_version(data)
	if version < 0:
		return {}

	var migrated: Dictionary = data.duplicate(true)
	while version < SCHEMA_VERSION:
		migrated = _migration_step(version, migrated)
		if migrated.is_empty():
			return {}
		var next_version := _schema_version(migrated)
		if next_version != version + 1:
			return {}
		version = next_version
	if not validate(migrated):
		return {}
	_normalize_known_integer_fields(migrated)
	return migrated


static func is_future_version(data: Dictionary) -> bool:
	return _schema_version(data) > SCHEMA_VERSION


static func level_record(data: Dictionary, level_id: StringName) -> Dictionary:
	var record := _fresh_level_record()
	var levels_value: Variant = data.get("levels")
	if not levels_value is Dictionary:
		return record

	var levels: Dictionary = levels_value
	var existing_value: Variant = levels.get(String(level_id))
	if existing_value == null:
		existing_value = levels.get(level_id)
	if existing_value is Dictionary:
		var existing: Dictionary = (
			existing_value as Dictionary
		).duplicate(true)
		for key: Variant in existing:
			record[key] = existing[key]
	return record


static func improved_relic_record(
	record: Dictionary,
	elapsed_s: float,
	level_meta: LevelMeta
) -> Dictionary:
	if (
		not _validate_level_record(record)
		or not is_finite(elapsed_s)
		or elapsed_s < 0.0
		or level_meta == null
	):
		return {}
	var updated := record.duplicate(true)
	var candidate_ms := maxi(
		roundi(elapsed_s * _MILLISECONDS_PER_SECOND),
		1
	)
	var existing_ms := int(
		updated.get("best_relic_time_ms", 0)
	)
	if existing_ms == 0 or candidate_ms < existing_ms:
		updated["best_relic_time_ms"] = candidate_ms
	# relic_tier is always re-derived from best_relic_time_ms against
	# the level's current pars -- never trusted from a caller -- so it
	# can never disagree with the time it is supposed to describe, and
	# self-heals a tier stored before the level's pars were re-tuned.
	updated["relic_tier"] = String(
		LevelRunState.relic_tier_for_time(
			int(updated["best_relic_time_ms"])
			/ _MILLISECONDS_PER_SECOND,
			level_meta
		)
	)
	return updated if _validate_level_record(updated) else {}


## Task 9 (CTR racing mode, R2): racing's counterpart to level_record() above
## -- same "supply fresh defaults, never mutate the caller's profile" shape,
## keyed by track id (a StringName, e.g. &"graybox_loop") instead of level
## id.
static func racing_record(data: Dictionary, track_id: StringName) -> Dictionary:
	var record := _fresh_racing_record()
	var racing_value: Variant = data.get("racing")
	if not racing_value is Dictionary:
		return record

	var racing: Dictionary = racing_value
	var existing_value: Variant = racing.get(String(track_id))
	if existing_value == null:
		existing_value = racing.get(track_id)
	if existing_value is Dictionary:
		var existing: Dictionary = (
			existing_value as Dictionary
		).duplicate(true)
		for key: Variant in existing:
			record[key] = existing[key]
	return record


## racing's counterpart to improved_relic_record() above -- same ms-rounded,
## "0 means never set" comparison shape, but tracks TWO independent bests
## (best total time and best single lap) instead of relic's one time plus a
## derived tier, since a race has no equivalent par-tier concept. Either
## best can improve without the other: a slower total with one blazing lap
## still raises best_lap_time_ms, and a personal-best total set with only
## average laps still raises best_total_time_ms.
static func improved_racing_record(
	record: Dictionary,
	total_elapsed_s: float,
	lap_times_s: Array
) -> Dictionary:
	if (
		not _validate_racing_record(record)
		or not is_finite(total_elapsed_s)
		or total_elapsed_s < 0.0
	):
		return {}
	var updated := record.duplicate(true)
	var candidate_total_ms := maxi(
		roundi(total_elapsed_s * _MILLISECONDS_PER_SECOND),
		1
	)
	var existing_total_ms := int(updated.get("best_total_time_ms", 0))
	if existing_total_ms == 0 or candidate_total_ms < existing_total_ms:
		updated["best_total_time_ms"] = candidate_total_ms

	var best_lap_s := _fastest_finite_non_negative(lap_times_s)
	if best_lap_s >= 0.0:
		var candidate_lap_ms := maxi(
			roundi(best_lap_s * _MILLISECONDS_PER_SECOND),
			1
		)
		var existing_lap_ms := int(updated.get("best_lap_time_ms", 0))
		if existing_lap_ms == 0 or candidate_lap_ms < existing_lap_ms:
			updated["best_lap_time_ms"] = candidate_lap_ms

	return updated if _validate_racing_record(updated) else {}


## Task 5 (CTR R7, the Cup): cup's own counterpart to racing_record()/
## level_record() above -- same "supply fresh defaults, never mutate the
## caller's profile" shape, but reaches one level deeper: through "racing",
## then into its reserved "cups" key (see validate()'s own doc on why "cups"
## lives there instead of as a new top-level section), keyed by cup id (a
## StringName, e.g. &"island_cup" -- CupSession's own CUP_ID constant).
static func cup_record(data: Dictionary, cup_id: StringName) -> Dictionary:
	var record := _fresh_cup_record()
	var racing_value: Variant = data.get("racing")
	if not racing_value is Dictionary:
		return record
	var racing: Dictionary = racing_value
	var cups_value: Variant = racing.get(_RACING_CUPS_KEY)
	if not cups_value is Dictionary:
		return record

	var cups: Dictionary = cups_value
	var existing_value: Variant = cups.get(String(cup_id))
	if existing_value == null:
		existing_value = cups.get(cup_id)
	if existing_value is Dictionary:
		var existing: Dictionary = (
			existing_value as Dictionary
		).duplicate(true)
		for key: Variant in existing:
			record[key] = existing[key]
	return record


## Cup's counterpart to improved_racing_record() above -- same "validate
## input, compute a candidate, validate output" shape, but LOWER-is-better
## (a finishing placement, 1 = first) instead of faster-is-better times, and
## a single field instead of two independent ones. 0 is the "never set"
## sentinel _fresh_cup_record() establishes (the same convention best_relic_
## time_ms/best_total_time_ms/best_lap_time_ms already use throughout this
## file) -- any real placement (placement >= 1) always beats it, so a cup's
## first-ever result always writes, exactly like a level's first relic time
## or a track's first best time. A worse-or-equal placement changes nothing
## and is reported back unchanged (never {}) so a caller can compare the
## returned record's own best_placement against the one it passed in to
## decide whether anything actually improved, the same pattern game_root.gd's
## own _on_racing_finished already uses for best_total_time_ms/best_lap_
## time_ms.
static func improved_cup_record(record: Dictionary, placement: int) -> Dictionary:
	if not _validate_cup_record(record) or placement < 1:
		return {}
	var updated := record.duplicate(true)
	var existing_placement := int(updated.get("best_placement", 0))
	if existing_placement == 0 or placement < existing_placement:
		updated["best_placement"] = placement
	return updated if _validate_cup_record(updated) else {}


static func _fresh_cup_record() -> Dictionary:
	return {
		"best_placement": 0,
	}


static func _fresh_level_record() -> Dictionary:
	return {
		"completed": false,
		"gem": false,
		"relic_tier": "none",
		"best_relic_time_ms": 0,
		"flawless": false,
		"last_missed_crate_ids": [],
	}


static func _fresh_racing_record() -> Dictionary:
	return {
		"best_total_time_ms": 0,
		"best_lap_time_ms": 0,
	}


static func _migration_step(
	version: int,
	data: Dictionary
) -> Dictionary:
	match version:
		0:
			return _migrate_v0_to_v1(data)
		1:
			return _migrate_v1_to_v2(data)
		2:
			return _migrate_v2_to_v3(data)
		_:
			return {}


static func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 1
	return migrated


## Task 9 (CTR racing mode, R2): the one real structural change this
## version bump makes -- every save through v1 predates racing entirely and
## has no "racing" key at all, so a v1 profile is backfilled with the same
## empty section fresh() now authors, before the version number itself
## moves. This is what lets validate()'s "racing" check stay strictly
## required (matching "levels" and "boss_defeated") instead of quietly
## tolerating a missing top-level section -- see test_pre_racing_v1_
## profile_migrates_with_empty_racing_section in test_save_service.gd for
## the round-trip proof.
static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	if not migrated.get("racing") is Dictionary:
		migrated["racing"] = {}
	migrated["schema_version"] = 2
	return migrated


## Task 5 (CTR R7, the Cup): the same rigor _migrate_v1_to_v2 above carries --
## every save through v2 has a "racing" dict (possibly empty) but NO "cups"
## key inside it at all, since the Cup did not exist yet. This backfills
## exactly the empty {} fresh() now authors under that key, before the
## version number itself moves, the same "backfill the structural gap, THEN
## bump schema_version" order _migrate_v1_to_v2 already established. A v1
## profile chains through BOTH migration steps in one migrate() call (see
## that function's own while-loop) -- _migrate_v1_to_v2 runs first and
## guarantees "racing" is always a Dictionary by the time this step reads
## it, so the `is Dictionary` fallback below only ever matters for a
## hypothetical malformed v2 input, never a genuine v1->v3 chain. Existing
## per-track best-time entries already inside "racing" are left completely
## untouched -- this only ever ADDS the one new reserved key, mirroring
## _migrate_v1_to_v2's own "backfill one thing, touch nothing else" shape.
## See test_save_model.gd's test_migrate_v2_to_v3_backfills_empty_cups_
## without_touching_existing_racing_bests and test_save_service.gd's own
## v1->v3 and v2->v3 chain round-trip proofs for the scratch-verification
## CLAUDE.md's save-migration rigor rule demands.
static func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	var racing_value: Variant = migrated.get("racing")
	var racing: Dictionary = (
		(racing_value as Dictionary).duplicate(true)
		if racing_value is Dictionary
		else {}
	)
	if not racing.get(_RACING_CUPS_KEY) is Dictionary:
		racing[_RACING_CUPS_KEY] = {}
	migrated["racing"] = racing
	migrated["schema_version"] = 3
	return migrated


static func _normalize_known_integer_fields(data: Dictionary) -> void:
	data["schema_version"] = int(data["schema_version"])
	data["lifetime_wumpa"] = int(data["lifetime_wumpa"])
	var levels: Dictionary = data["levels"]
	for level_id: Variant in levels:
		var record: Dictionary = levels[level_id]
		record["best_relic_time_ms"] = int(record["best_relic_time_ms"])
		if record.has("last_missed_crate_ids"):
			var normalized_ids: Array[int] = []
			for crate_id: Variant in record["last_missed_crate_ids"]:
				var normalized_id := int(crate_id)
				if normalized_id not in normalized_ids:
					normalized_ids.append(normalized_id)
			normalized_ids.sort()
			record["last_missed_crate_ids"] = normalized_ids
	var racing: Dictionary = data["racing"]
	for track_id: Variant in racing:
		# Task 5 (CTR R7, the Cup): "cups" is not a per-track record -- see
		# validate()'s own doc on this same reserved key. Indexing it as one
		# here (best_total_time_ms/best_lap_time_ms) would read a missing key
		# off a real Dictionary, which is a Godot runtime error, not a silent
		# no-op -- skipped the same way validate()'s own per-track loop skips
		# it, and normalized separately immediately below instead.
		if String(track_id) == _RACING_CUPS_KEY:
			continue
		var racing_entry: Dictionary = racing[track_id]
		racing_entry["best_total_time_ms"] = int(
			racing_entry["best_total_time_ms"]
		)
		racing_entry["best_lap_time_ms"] = int(
			racing_entry["best_lap_time_ms"]
		)
	var cups_value: Variant = racing.get(_RACING_CUPS_KEY)
	if cups_value is Dictionary:
		var cups: Dictionary = cups_value
		for cup_id: Variant in cups:
			var cup_record: Dictionary = cups[cup_id]
			if cup_record.has("best_placement"):
				cup_record["best_placement"] = int(
					cup_record["best_placement"]
				)


static func _validate_level_record(record: Dictionary) -> bool:
	if typeof(record.get("completed")) != TYPE_BOOL:
		return false
	if typeof(record.get("gem")) != TYPE_BOOL:
		return false

	var relic_tier_value: Variant = record.get("relic_tier")
	if (
		typeof(relic_tier_value) != TYPE_STRING
		and typeof(relic_tier_value) != TYPE_STRING_NAME
	):
		return false
	if String(relic_tier_value) not in _RELIC_TIERS:
		return false

	if not _is_non_negative_integer(record.get("best_relic_time_ms")):
		return false
	if typeof(record.get("flawless")) != TYPE_BOOL:
		return false
	if record.has("last_missed_crate_ids"):
		var missed_value: Variant = record["last_missed_crate_ids"]
		if not missed_value is Array:
			return false
		var seen_ids: Array[int] = []
		for crate_id: Variant in missed_value:
			if not _is_non_negative_integer(crate_id):
				return false
			var normalized_id := int(crate_id)
			if normalized_id in seen_ids:
				return false
			seen_ids.append(normalized_id)
	return true


static func _validate_racing_record(record: Dictionary) -> bool:
	if not _is_non_negative_integer(record.get("best_total_time_ms")):
		return false
	if not _is_non_negative_integer(record.get("best_lap_time_ms")):
		return false
	return true


## Task 5 (CTR R7, the Cup): best_placement follows the same "0 means never
## set" convention every other best-* field in this file already uses (see
## _validate_racing_record()/_validate_level_record()'s own best_relic_
## time_ms/best_total_time_ms/best_lap_time_ms checks, all plain _is_non_
## negative_integer() with no lower bound beyond zero) -- NOT a stricter
## ">= 1" floor. A real placement is always written as >= 1 by construction
## (improved_cup_record() only ever raises placement, never lowers it to 0),
## so this stays consistent with the rest of the file rather than inventing
## a one-off rule for this one field.
static func _validate_cup_record(record: Dictionary) -> bool:
	return _is_non_negative_integer(record.get("best_placement"))


## The smallest finite, non-negative value in lap_times_s, or -1.0 if none
## qualifies (an empty array, or every entry non-finite/negative) --
## improved_racing_record() treats a negative return as "no lap to compare",
## the same way it treats best_*_time_ms == 0 as "no time recorded yet".
static func _fastest_finite_non_negative(values: Array) -> float:
	var fastest := -1.0
	for value: Variant in values:
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			continue
		var candidate: float = value
		if not is_finite(candidate) or candidate < 0.0:
			continue
		if fastest < 0.0 or candidate < fastest:
			fastest = candidate
	return fastest


static func _schema_version(data: Dictionary) -> int:
	var value: Variant = data.get("schema_version")
	if not _is_integer(value):
		return -1
	return int(value)


static func _is_non_negative_integer(value: Variant) -> bool:
	return _is_integer(value) and float(value) >= 0.0


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return is_finite(numeric_value) and numeric_value == floor(numeric_value)
