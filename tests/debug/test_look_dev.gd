extends GutTest

const LookDevType := preload("res://src/debug/look_dev.gd")
const STANDARD_CRATE_PATH := "res://assets/models/props/SM_crate_standard.glb"


func test_discovers_glb_assets_under_a_root() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	var found := look_dev.discover_assets("res://assets/models")

	assert_not_null(found)
	assert_has(found, STANDARD_CRATE_PATH)
	for path: String in found:
		assert_true(path.ends_with(".glb"), "%s should be a .glb" % path)


func test_import_suffix_normalizes_to_a_loadable_asset_path() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	var normalized: String = look_dev.normalize_resource_path(
		STANDARD_CRATE_PATH + ".import"
	)

	assert_eq(normalized, STANDARD_CRATE_PATH)
	assert_true(
		ResourceLoader.exists(normalized),
		"%s should resolve through the real importer" % normalized
	)


func test_a_nonexistent_discovery_root_returns_empty() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	var found := look_dev.discover_assets("res://assets/models/not_present")

	assert_eq(found, PackedStringArray())


func test_selection_wraps_around_an_empty_list_without_erroring() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())
	look_dev.set_assets(PackedStringArray())

	look_dev.select(0)

	assert_eq(look_dev.current_asset_path(), "")


func test_selection_wraps_forward_and_backward() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())
	look_dev.set_assets(
		PackedStringArray(["res://a.glb", "res://b.glb", "res://c.glb"])
	)

	look_dev.select(1)
	assert_eq(look_dev.current_asset_path(), "res://b.glb")

	look_dev.select(3)
	assert_eq(look_dev.current_asset_path(), "res://a.glb", "index past the end wraps")

	look_dev.select(-1)
	assert_eq(look_dev.current_asset_path(), "res://c.glb", "negative index wraps")


func test_turntable_advances_and_wraps_at_a_full_turn() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	look_dev.advance_turntable(1.0)
	var after_one_second := look_dev.turntable_degrees()
	assert_gt(after_one_second, 0.0)

	look_dev.advance_turntable(LookDevType.FULL_TURN_DEGREES)
	assert_lt(
		look_dev.turntable_degrees(),
		LookDevType.FULL_TURN_DEGREES,
		"the turntable angle must stay bounded rather than growing all session"
	)
