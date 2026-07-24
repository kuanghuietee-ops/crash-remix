class_name SaveModel
extends RefCounted

const SCHEMA_VERSION: int = 1
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
	tier: StringName
) -> Dictionary:
	if (
		not _validate_level_record(record)
		or not is_finite(elapsed_s)
		or elapsed_s < 0.0
		or String(tier) not in _RELIC_TIERS
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
		updated["relic_tier"] = String(tier)
	return updated if _validate_level_record(updated) else {}


static func _fresh_level_record() -> Dictionary:
	return {
		"completed": false,
		"gem": false,
		"relic_tier": "none",
		"best_relic_time_ms": 0,
		"flawless": false,
		"last_missed_crate_ids": [],
	}


static func _migration_step(
	version: int,
	data: Dictionary
) -> Dictionary:
	match version:
		0:
			return _migrate_v0_to_v1(data)
		1:
			return _migrate_v1_to_v2_identity(data)
		_:
			return {}


static func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated["schema_version"] = 1
	return migrated


static func _migrate_v1_to_v2_identity(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
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
