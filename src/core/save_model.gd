class_name SaveModel
extends RefCounted

## CTR R8 Task 3 (save v3->v4): resolved by StringName the same way race_
## session.gd's own DriverRegistryType preload already is -- see selected_
## driver()/validate()/_normalize_selected_driver()'s own docs below for the
## one place this file leans on the roster to decide "real id" vs "corrupt/
## unknown, fail closed to crash". src/core depending on src/racing here is
## one-directional: DriverRegistry (and everything it preloads) has no
## dependency back on SaveModel.
const DriverRegistryType := preload("res://src/racing/roster/driver_registry.gd")

const SCHEMA_VERSION: int = 4
# Task 5 (CTR R7, the Cup): the one reserved key inside the "racing" section
# that does NOT hold a per-track best-time record -- see fresh()/validate()/
# _migrate_v2_to_v3()'s own docs for why "cups" lives INSIDE "racing" (not as
# its own new top-level section) and how the validation/normalization loops
# below skip it wherever they walk "racing" expecting per-track records.
const _RACING_CUPS_KEY := "cups"
## CTR R8 Task 3 (save v3->v4): the driver roster's own reserved key inside
## "racing", alongside "cups" above -- see validate()'s own doc on this key,
## _migrate_v3_to_v4()'s own doc for how a legacy profile backfills it, and
## _normalize_selected_driver()'s own doc for why an invalid STORED value
## here is repaired rather than rejecting the whole profile the way every
## other reserved-key/per-record shape in this file does.
const _RACING_SELECTED_DRIVER_KEY := "selected_driver"
## The id every profile predating Task 2's driver roster is treated as
## having raced under -- RaceSession's own pre-Task-2 default (_selected_
## driver_id, race_session.gd), so a legacy profile's driver pick migrating
## in for the first time can never look like a surprising change from what
## that profile already experienced. Also the fail-closed target for a
## corrupt/unknown stored value (_normalize_selected_driver()) and for a
## caller reading a profile that never went through SaveService at all
## (selected_driver()'s own "never hands back a value DriverRegistry does
## not recognize" contract).
const _DEFAULT_SELECTED_DRIVER := "crash"
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
		# CTR R8 Task 3 (save v3->v4): "selected_driver" joins "cups" as a
		# second required reserved key inside "racing" from v4 onward -- see
		# validate()'s own doc on this key.
		"racing": {
			_RACING_CUPS_KEY: {},
			_RACING_SELECTED_DRIVER_KEY: _DEFAULT_SELECTED_DRIVER,
		},
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

	# CTR R8 Task 3 (save v3->v4): "selected_driver" is a second RESERVED key
	# inside "racing", alongside "cups" immediately above -- checked here,
	# BEFORE the per-track loop below ever sees it, and excluded from that
	# loop's own per-track record shape check the same way "cups" already
	# is. Required with the same "not left optional-if-missing" strictness
	# "racing" and "cups" themselves already carry -- a legacy profile only
	# ever passes this check after actually migrating through _migrate_v3_
	# to_v4, which backfills exactly this shape. UNLIKE every other field
	# this function validates, an invalid value stored on disk is never
	# allowed to reach THIS check in the first place during a real load --
	# migrate() always runs _normalize_selected_driver() first (see that
	# function's own doc), repairing a corrupt/unknown id to the registry's
	# own "crash" default before validate() ever runs, so a real bad driver
	# pick on disk fails closed to "crash" rather than losing lifetime_
	# wumpa/levels/racing bests/cups over one cosmetic field. This check
	# still exists (and still rejects) so a caller that hands validate()
	# raw, never-migrated data directly (store_profile()'s own contract --
	# see its own doc) cannot persist a genuinely malformed pick.
	var selected_driver_value: Variant = racing.get(_RACING_SELECTED_DRIVER_KEY)
	if (
		typeof(selected_driver_value) != TYPE_STRING
		and typeof(selected_driver_value) != TYPE_STRING_NAME
	):
		return false
	if DriverRegistryType.entry(StringName(selected_driver_value)) == null:
		return false

	for track_id: Variant in racing:
		if (
			String(track_id) == _RACING_CUPS_KEY
			or String(track_id) == _RACING_SELECTED_DRIVER_KEY
		):
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
	# CTR R8 Task 3 (save v3->v4): repairs racing.selected_driver BEFORE
	# validate() ever runs -- see _normalize_selected_driver()'s own doc for
	# why this is the one field in this file whose invalid stored value
	# self-heals here instead of failing the whole profile closed through
	# validate() below. Runs unconditionally on every migrate() call (not
	# only a profile that just chained through _migrate_v3_to_v4), so an
	# already-v4 profile hand-corrupted on disk is repaired the same way.
	_normalize_selected_driver(migrated)
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


## CTR R8 Task 3 (save v3->v4): the single-scalar counterpart to level_
## record()/racing_record()/cup_record() above -- selected_driver is not a
## per-key record but ONE reserved field inside "racing" (see validate()'s
## own doc on why it is reserved the same way "cups" is), so this reads it
## directly instead of merging defaults into an existing Dictionary. Never
## hands back a value DriverRegistry does not recognize -- an absent,
## wrong-typed, or unknown value in `data` returns the SAME "crash" default
## _normalize_selected_driver() already repairs a corrupt on-disk value to
## during migrate(), so a caller reading ANY profile (one that genuinely
## came from SaveService, or one hand-built in a test/by a caller that never
## validated it) gets the identical safe fallback rather than a StringName
## no DriverRegistry row actually owns.
##
## THE SURFACE TASK 4 READS: this getter. THE SURFACE TASK 4 WRITES: there
## is no dedicated setter here, deliberately -- mirrors racing_record()/cup_
## record()'s own shape, where the caller (game_root.gd's _on_racing_
## finished()/_persist_cup_result_if_improved()) duplicates "racing", sets
## the one key it owns, then calls validate() on the WHOLE updated profile
## before store_profile(). A driver pick has no "is this better" comparison
## the way improved_racing_record()/improved_cup_record() have for their own
## fields, so there is nothing here for a setter to compute -- Task 4 writes
## `racing[_RACING_SELECTED_DRIVER_KEY] = String(id)` (id already a real
## DriverRegistry id, e.g. from a select-screen tap) directly, the identical
## shape those two existing write sites already use for their own reserved/
## per-key racing fields.
static func selected_driver(data: Dictionary) -> StringName:
	var racing_value: Variant = data.get("racing")
	if not racing_value is Dictionary:
		return StringName(_DEFAULT_SELECTED_DRIVER)
	var racing: Dictionary = racing_value
	var value: Variant = racing.get(_RACING_SELECTED_DRIVER_KEY)
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return StringName(_DEFAULT_SELECTED_DRIVER)
	var candidate := StringName(value)
	if DriverRegistryType.entry(candidate) == null:
		return StringName(_DEFAULT_SELECTED_DRIVER)
	return candidate


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
		3:
			return _migrate_v3_to_v4(data)
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


## CTR R8 Task 3 (save v3->v4): the same rigor _migrate_v2_to_v3 above
## carries -- every save through v3 predates the driver roster entirely
## (Task 2's DriverRegistry) and has no "selected_driver" key inside
## "racing" at all. Backfilled to the same "crash" default fresh() now
## authors, before the version number itself moves, the same "backfill the
## structural gap, THEN bump schema_version" order _migrate_v1_to_v2/
## _migrate_v2_to_v3 already established. Existing per-track best-time
## entries and cups are left completely untouched. This step only
## guarantees the KEY exists as a String -- it does not need to guarantee
## that String names a REAL registry id; _normalize_selected_driver() below
## (run unconditionally at the end of every migrate() call, not only a
## chain that passed through here) is the one place that also catches an
## unknown-but-syntactically-String id, so a malformed pre-existing value
## backfills exactly the same way a missing key does.
static func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	var racing_value: Variant = migrated.get("racing")
	var racing: Dictionary = (
		(racing_value as Dictionary).duplicate(true)
		if racing_value is Dictionary
		else {}
	)
	if not racing.get(_RACING_SELECTED_DRIVER_KEY) is String:
		racing[_RACING_SELECTED_DRIVER_KEY] = _DEFAULT_SELECTED_DRIVER
	migrated["racing"] = racing
	migrated["schema_version"] = 4
	return migrated


## Repairs "racing.selected_driver" to the registry's own "crash" default
## whenever the value migrate() is about to hand to validate() is not a
## String/StringName naming a real DriverRegistry id -- called
## unconditionally on every migrate() call (fresh v4 data that just chained
## through _migrate_v3_to_v4, OR an already-v4 profile hand-corrupted on
## disk), BEFORE validate() ever runs. This is the one field in this whole
## file where an invalid stored value self-heals to a safe default INSIDE
## migrate() rather than failing the entire profile closed through
## validate() -- see validate()'s own doc on this key for why: a bad/
## unknown driver pick is cosmetic (which mesh a race seats), and rejecting
## the whole save over it would needlessly lose lifetime_wumpa/levels/
## racing bests/cups that have nothing to do with it. Mutates `data` in
## place (through the SAME Dictionary reference `racing` shares with
## data["racing"] -- Godot Dictionaries are reference types, so no
## reassignment back onto `data` is needed), mirroring _normalize_known_
## integer_fields()'s own in-place shape below. A no-op whenever "racing"
## itself is not a Dictionary -- that shape of corruption is NOT this
## function's concern; validate()'s own "racing" check (independent of
## selected_driver) is what correctly fails the whole profile closed for
## that case, the existing "wholesale corruption still rejects" contract
## every other reserved section in this file already carries.
static func _normalize_selected_driver(data: Dictionary) -> void:
	var racing_value: Variant = data.get("racing")
	if not racing_value is Dictionary:
		return
	var racing: Dictionary = racing_value
	var value: Variant = racing.get(_RACING_SELECTED_DRIVER_KEY)
	var is_stringlike := (
		typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
	)
	if is_stringlike and DriverRegistryType.entry(StringName(value)) != null:
		racing[_RACING_SELECTED_DRIVER_KEY] = String(value)
	else:
		racing[_RACING_SELECTED_DRIVER_KEY] = _DEFAULT_SELECTED_DRIVER


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
		if (
			String(track_id) == _RACING_CUPS_KEY
			# CTR R8 Task 3 (save v3->v4): "selected_driver" is a second
			# reserved key inside "racing" (a String, not a per-track
			# Dictionary record) -- same skip, same reason, as "cups"
			# immediately above.
			or String(track_id) == _RACING_SELECTED_DRIVER_KEY
		):
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
