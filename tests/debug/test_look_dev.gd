extends GutTest

const LookDevType := preload("res://src/debug/look_dev.gd")
const STANDARD_CRATE_PATH := "res://assets/models/props/SM_crate_standard.glb"
const CRATE_MODEL_ROOT := "res://assets/models/props"


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


func test_crate_models_enable_their_authored_vertex_colors_after_import() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())
	var crate_paths: PackedStringArray = look_dev.discover_assets(CRATE_MODEL_ROOT)

	assert_eq(crate_paths.size(), 7)
	for path: String in crate_paths:
		var asset_scene := load(path) as PackedScene
		assert_not_null(asset_scene, "%s must load as a scene" % path)
		if asset_scene == null:
			continue
		var asset: Node = autofree(asset_scene.instantiate())
		var meshes: Array[Node] = asset.find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		)
		assert_eq(meshes.size(), 1, "%s must keep one imported mesh" % path)
		if meshes.size() != 1:
			continue
		var mesh_instance := meshes[0] as MeshInstance3D
		var material := (
			mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
		)
		assert_not_null(material, "%s must have a base material" % path)
		if material == null:
			continue
		assert_true(
			material.vertex_color_use_as_albedo,
			"%s must render COLOR_0 instead of the white base material" % path
		)
		var arrays := mesh_instance.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var unique_colors: Dictionary = {}
		for color: Color in colors:
			unique_colors[color] = true
		assert_gt(
			unique_colors.size(),
			1,
			"%s must retain visibly distinct authored colors" % path
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
