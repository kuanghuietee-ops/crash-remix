extends GutTest

const LookDevType := preload("res://src/debug/look_dev.gd")
const STANDARD_CRATE_PATH := "res://assets/models/props/SM_crate_standard.glb"
const CRATE_MODEL_ROOT := "res://assets/models/props"
const LOOK_DEV_SCENE := "res://scenes/debug/look_dev.tscn"
const LAB_ASSISTANT_PATH := (
	"res://assets/models/enemies/SK_lab_assistant.glb"
)
const LAB_ASSISTANT_WALK := &"A_lab_assistant_walk"


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


func test_lab_assistant_import_is_one_skinned_budget_mesh_with_walk() -> void:
	assert_true(
		ResourceLoader.exists(LAB_ASSISTANT_PATH),
		"art-ladder rung 2 must export the original lab assistant"
	)
	if not ResourceLoader.exists(LAB_ASSISTANT_PATH):
		return
	var asset_scene := load(LAB_ASSISTANT_PATH) as PackedScene
	assert_not_null(asset_scene)
	if asset_scene == null:
		return
	var asset: Node = autofree(asset_scene.instantiate())
	var meshes: Array[Node] = asset.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)
	var skeletons: Array[Node] = asset.find_children(
		"*",
		"Skeleton3D",
		true,
		false
	)
	var animation_players: Array[Node] = asset.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)

	assert_eq(meshes.size(), 1, "the enemy must stay one draw-call surface")
	assert_eq(skeletons.size(), 1, "the exported biped must keep one skeleton")
	assert_eq(
		animation_players.size(),
		1,
		"the exported biped must keep its animation player"
	)
	if (
		meshes.size() != 1
		or skeletons.size() != 1
		or animation_players.size() != 1
	):
		return

	var mesh_instance := meshes[0] as MeshInstance3D
	var skeleton := skeletons[0] as Skeleton3D
	var animation_player := animation_players[0] as AnimationPlayer
	assert_eq(mesh_instance.mesh.get_surface_count(), 1)
	assert_not_null(mesh_instance.skin, "the mesh must retain exported skin weights")
	assert_gt(skeleton.get_bone_count(), 0)
	for required_bone: String in [
		"DEF-spine",
		"DEF-upper_arm.L",
		"DEF-upper_arm.R",
		"DEF-thigh.L",
		"DEF-thigh.R",
	]:
		assert_ne(
			skeleton.find_bone(required_bone),
			-1,
			"the Rigify deform skeleton must retain %s" % required_bone
		)

	var material := (
		mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
	)
	assert_not_null(material)
	if material != null:
		assert_true(
			material.vertex_color_use_as_albedo,
			"the original hand-painted palette must render in Godot"
		)
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var unique_colors: Dictionary = {}
	for color: Color in colors:
		unique_colors[color] = true
	assert_gt(unique_colors.size(), 4)
	assert_false(bones.is_empty(), "the surface must carry bone indices")
	assert_false(weights.is_empty(), "the surface must carry skin weights")

	assert_true(animation_player.has_animation(LAB_ASSISTANT_WALK))
	if not animation_player.has_animation(LAB_ASSISTANT_WALK):
		return
	var walk := animation_player.get_animation(LAB_ASSISTANT_WALK)
	assert_not_null(walk)
	if walk != null:
		assert_gt(walk.length, 0.0)
		assert_gt(walk.get_track_count(), 0)
		assert_eq(walk.loop_mode, Animation.LOOP_LINEAR)


func test_look_dev_auto_plays_the_lab_assistant_walk() -> void:
	assert_true(ResourceLoader.exists(LAB_ASSISTANT_PATH))
	if not ResourceLoader.exists(LAB_ASSISTANT_PATH):
		return
	var packed := load(LOOK_DEV_SCENE) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var look_dev := packed.instantiate() as LookDev
	look_dev.set_assets(PackedStringArray([LAB_ASSISTANT_PATH]))
	add_child_autofree(look_dev)
	await wait_process_frames(1)
	var animation_players: Array[Node] = look_dev.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	var animation_player := (
		animation_players[0] as AnimationPlayer
		if not animation_players.is_empty()
		else null
	)

	assert_not_null(animation_player)
	if animation_player == null:
		return
	assert_true(animation_player.is_playing())
	assert_eq(
		StringName(animation_player.current_animation),
		LAB_ASSISTANT_WALK
	)


func test_look_dev_frames_the_tall_lab_assistant_inside_the_camera() -> void:
	var packed := load(LOOK_DEV_SCENE) as PackedScene
	var look_dev := packed.instantiate() as LookDev
	look_dev.set_assets(PackedStringArray([LAB_ASSISTANT_PATH]))
	add_child_autofree(look_dev)
	await wait_process_frames(1)
	var camera := look_dev.get_node("Camera3D") as Camera3D
	var meshes: Array[Node] = look_dev.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)

	assert_not_null(camera)
	assert_eq(meshes.size(), 1)
	if camera == null or meshes.size() != 1:
		return
	assert_gt(
		camera.global_position.z,
		0.0,
		"Look Dev must face the imported +Z model front"
	)
	var mesh_instance := meshes[0] as MeshInstance3D
	for endpoint_index: int in range(8):
		var endpoint := (
			mesh_instance.global_transform
			* mesh_instance.get_aabb().get_endpoint(endpoint_index)
		)
		assert_true(
			camera.is_position_in_frustum(endpoint),
			"the tall character endpoint %d must remain on screen"
			% endpoint_index
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
