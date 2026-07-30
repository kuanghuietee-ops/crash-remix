class_name SaveModel
extends RefCounted

const SCHEMA_VERSION: int = 2
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
		"racing": {},
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
	for track_id: Variant in racing:
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
		var racing_entry: Dictionary = racing[track_id]
		racing_entry["best_total_time_ms"] = int(
			racing_entry["best_total_time_ms"]
		)
		racing_entry["best_lap_time_ms"] = int(
			racing_entry["best_lap_time_ms"]
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
