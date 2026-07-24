extends GutTest

const LEVEL_META_PATH := (
	"res://data/tuning/levels/n_sanity_beach.tres"
)


func test_level_meta_loads_with_typed_fields() -> void:
	var meta := load(LEVEL_META_PATH) as Resource

	assert_not_null(meta)
	if meta == null:
		return
	assert_eq(_global_class_name(meta), "LevelMeta")
	assert_eq(meta.get("crate_count"), 0)
	assert_eq(meta.get("design_pace_mps"), 4.5)
	assert_eq(meta.get("relic_sapphire_s"), 0.0)
	assert_eq(meta.get("relic_gold_s"), 0.0)
	assert_eq(meta.get("relic_platinum_s"), 0.0)


func test_level_meta_fingerprint_moves_when_a_par_changes() -> void:
	var loaded := load(LEVEL_META_PATH) as Resource
	assert_not_null(loaded)
	if loaded == null:
		return
	var meta := loaded.duplicate(true) as Resource
	var before: String = meta.call("fingerprint")

	meta.set("relic_gold_s", 42.0)

	assert_ne(before, meta.call("fingerprint"))
	assert_eq(before.length(), 64)


func _global_class_name(resource: Resource) -> String:
	var script := resource.get_script() as Script
	if script == null:
		return ""
	return String(script.get_global_name())
