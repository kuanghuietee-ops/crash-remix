class_name SaveModel
extends RefCounted

const SCHEMA_VERSION: int = 1
const _RELIC_TIERS: Array[String] = [
	"none",
	"sapphire",
	"gold",
	"platinum",
]


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
	if _schema_version(data) != SCHEMA_VERSION:
		return {}

	var migrated: Dictionary = data.duplicate(true)
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
		var existing: Dictionary = existing_value
		for key: Variant in existing:
			record[key] = existing[key]
	return record


static func _fresh_level_record() -> Dictionary:
	return {
		"completed": false,
		"gem": false,
		"relic_tier": "none",
		"best_relic_time_ms": 0,
		"flawless": false,
	}


static func _normalize_known_integer_fields(data: Dictionary) -> void:
	data["schema_version"] = int(data["schema_version"])
	data["lifetime_wumpa"] = int(data["lifetime_wumpa"])
	var levels: Dictionary = data["levels"]
	for level_id: Variant in levels:
		var record: Dictionary = levels[level_id]
		record["best_relic_time_ms"] = int(record["best_relic_time_ms"])


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
