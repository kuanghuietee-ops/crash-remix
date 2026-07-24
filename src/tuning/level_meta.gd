class_name LevelMeta
extends Resource

@export_category("Identity")
@export var level_id: StringName
@export var display_name: String

@export_category("Completion")
@export var crate_count: int
@export var wumpa_total: int

@export_category("Authoring")
@export var design_pace_mps: float

@export_category("Relic Pars")
@export var relic_sapphire_s: float
@export var relic_gold_s: float
@export var relic_platinum_s: float


func fingerprint() -> String:
	var canonical_lines := PackedStringArray()
	for property_info: Dictionary in get_property_list():
		var usage: int = property_info["usage"]
		if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var property_name: StringName = property_info["name"]
		canonical_lines.append(
			String(property_name) + "=" + var_to_str(get(property_name))
		)
	canonical_lines.sort()
	return "\n".join(canonical_lines).sha256_text()
