extends GutTest

const LookDevType := preload("res://src/debug/look_dev.gd")
const STANDARD_CRATE_PATH := "res://assets/models/props/SM_crate_standard.glb"
const CRATE_MODEL_ROOT := "res://assets/models/props"
const LOOK_DEV_SCENE := "res://scenes/debug/look_dev.tscn"
const LAB_ASSISTANT_PATH := (
	"res://assets/models/enemies/SK_lab_assistant.glb"
)
const LAB_ASSISTANT_WALK := &"A_lab_assistant_walk"
const CRASH_PATH := "res://assets/models/characters/SK_crash.glb"
const CRASH_IDLE := &"A_crash_idle"
const CRASH_CORE_CLIPS := [
	&"A_crash_run",
	&"A_crash_jump",
	&"A_crash_double_jump",
	&"A_crash_spin",
	&"A_crash_slide",
	&"A_crash_slam",
]


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


func test_crash_color_pass_is_one_vertex_painted_rigged_hero() -> void:
	assert_true(
		ResourceLoader.exists(CRASH_PATH),
		"art-ladder rung 3 must export the colored Crash candidate"
	)
	if not ResourceLoader.exists(CRASH_PATH):
		return
	var asset_scene := load(CRASH_PATH) as PackedScene
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

	assert_eq(meshes.size(), 1, "Crash must stay one draw-call surface")
	assert_eq(skeletons.size(), 1, "Crash must retain one Rigify skeleton")
	assert_eq(animation_players.size(), 1, "the idle preview must be exported")
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
	assert_not_null(mesh_instance.skin)
	var bounds := mesh_instance.get_aabb()
	assert_almost_eq(
		bounds.position.y,
		0.0,
		0.03,
		"the hero origin must remain at the shoes"
	)
	assert_between(
		bounds.size.y,
		1.05,
		1.15,
		"the likeness candidate must preserve the authored 1.1 m scale"
	)

	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var triangle_count := indices.size() / 3
	assert_between(
		triangle_count,
		10000,
		12000,
		"the hero must remain inside the immutable design budget"
	)
	assert_false(bones.is_empty())
	assert_false(weights.is_empty())
	var unique_colors: Dictionary = {}
	for color: Color in colors:
		unique_colors[color] = true
	assert_gt(
		unique_colors.size(),
		8,
		"the reviewed silhouette must now carry Crash's readable color regions"
	)
	var material := (
		mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
	)
	assert_not_null(material)
	if material != null:
		assert_eq(
			material.resource_name,
			"M_crash_body",
			"the one-slot hero material must follow the import contract"
		)
		assert_null(
			material.albedo_texture,
			"the first color pass must stay self-contained and vertex painted"
		)
		assert_true(material.vertex_color_use_as_albedo)

	for required_bone: String in [
		"DEF-spine",
		"DEF-upper_arm.L",
		"DEF-upper_arm.R",
		"DEF-thigh.L",
		"DEF-thigh.R",
		"DEF-foot.L",
		"DEF-foot.R",
	]:
		assert_ne(
			skeleton.find_bone(required_bone),
			-1,
			"the Rigify deform skeleton must retain %s" % required_bone
		)

	assert_true(animation_player.has_animation(CRASH_IDLE))
	if not animation_player.has_animation(CRASH_IDLE):
		return
	var idle := animation_player.get_animation(CRASH_IDLE)
	assert_not_null(idle)
	if idle != null:
		assert_gt(idle.length, 0.0)
		assert_gt(idle.get_track_count(), 0)
		assert_eq(idle.loop_mode, Animation.LOOP_LINEAR)
	for clip_name: StringName in CRASH_CORE_CLIPS:
		assert_true(
			animation_player.has_animation(clip_name),
			"%s must ship in Crash's first gameplay animation set" % clip_name
		)
		if not animation_player.has_animation(clip_name):
			continue
		var clip := animation_player.get_animation(clip_name)
		assert_not_null(clip)
		if clip == null:
			continue
		assert_gt(clip.length, 0.0)
		assert_gt(clip.get_track_count(), 0)
		if clip_name in [&"A_crash_run", &"A_crash_spin"]:
			assert_eq(clip.loop_mode, Animation.LOOP_LINEAR)


func test_crash_core_actions_move_hands_and_feet_through_readable_arcs() -> void:
	var asset_scene := load(CRASH_PATH) as PackedScene
	assert_not_null(asset_scene)
	if asset_scene == null:
		return
	var asset := asset_scene.instantiate()
	add_child_autofree(asset)
	await wait_process_frames(1)
	var skeletons := asset.find_children("*", "Skeleton3D", true, false)
	var animation_players := asset.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	assert_eq(skeletons.size(), 1)
	assert_eq(animation_players.size(), 1)
	if skeletons.size() != 1 or animation_players.size() != 1:
		return
	var skeleton := skeletons[0] as Skeleton3D
	var animation_player := animation_players[0] as AnimationPlayer

	var run := animation_player.get_animation(&"A_crash_run")
	var run_early := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_run",
		run.length * 0.25
	)
	var run_late := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_run",
		run.length * 0.75
	)
	assert_gt(
		run_early[&"hand_l"].distance_to(run_late[&"hand_l"]),
		0.08,
		"the left hand must visibly swing with the run stride"
	)
	assert_gt(
		run_early[&"hand_r"].distance_to(run_late[&"hand_r"]),
		0.08,
		"the right hand must visibly swing with the run stride"
	)
	assert_gt(
		run_early[&"foot_l"].distance_to(run_late[&"foot_l"]),
		0.06,
		"the run must move the feet instead of sliding a stiff body"
	)

	var spin := animation_player.get_animation(&"A_crash_spin")
	var spin_early := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_spin",
		spin.length * 0.1
	)
	var spin_late := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_spin",
		spin.length * 0.55
	)
	assert_gt(
		spin_early[&"hand_l"].distance_to(spin_late[&"hand_l"]),
		0.08,
		"the spin clip must sweep the arms through the silhouette"
	)

	var slam := animation_player.get_animation(&"A_crash_slam")
	var slam_windup := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_slam",
		slam.length * 0.05
	)
	var slam_impact := _sample_bones(
		animation_player,
		skeleton,
		&"A_crash_slam",
		slam.length * 0.7
	)
	assert_gt(
		slam_windup[&"hand_l"].distance_to(slam_impact[&"hand_l"]),
		0.10,
		"the stomp must carry the hands from windup into impact"
	)


func test_look_dev_auto_plays_and_phone_frames_crash_idle() -> void:
	assert_true(ResourceLoader.exists(CRASH_PATH))
	if not ResourceLoader.exists(CRASH_PATH):
		return
	var packed := load(LOOK_DEV_SCENE) as PackedScene
	var look_dev := packed.instantiate() as LookDev
	look_dev.set_assets(PackedStringArray([CRASH_PATH]))
	add_child_autofree(look_dev)
	await wait_process_frames(1)
	var camera := look_dev.get_node("Camera3D") as Camera3D
	var meshes: Array[Node] = look_dev.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)
	var animation_players: Array[Node] = look_dev.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)

	assert_not_null(camera)
	assert_eq(meshes.size(), 1)
	assert_eq(animation_players.size(), 1)
	if (
		camera == null
		or meshes.size() != 1
		or animation_players.size() != 1
	):
		return
	var animation_player := animation_players[0] as AnimationPlayer
	assert_true(animation_player.is_playing())
	assert_eq(
		StringName(animation_player.current_animation),
		CRASH_IDLE
	)

	var mesh_instance := meshes[0] as MeshInstance3D
	var min_screen_y := INF
	var max_screen_y := -INF
	for endpoint_index: int in range(8):
		var endpoint := (
			mesh_instance.global_transform
			* mesh_instance.get_aabb().get_endpoint(endpoint_index)
		)
		var screen_point := camera.unproject_position(endpoint)
		min_screen_y = minf(min_screen_y, screen_point.y)
		max_screen_y = maxf(max_screen_y, screen_point.y)
	var viewport_height := look_dev.get_viewport().get_visible_rect().size.y
	var screen_height_ratio := (
		(max_screen_y - min_screen_y) / viewport_height
	)
	assert_between(
		screen_height_ratio,
		0.35,
		0.85,
		"the 1.1 m hero must remain readable without clipping at phone size"
	)


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


func _sample_bones(
	animation_player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip: StringName,
	time_s: float
) -> Dictionary:
	animation_player.play(clip)
	animation_player.seek(time_s, true)
	animation_player.advance(0.0)
	skeleton.force_update_all_bone_transforms()
	var positions := {}
	for key: StringName in [
		&"hand_l",
		&"hand_r",
		&"foot_l",
	]:
		var bone_name := {
			&"hand_l": "DEF-hand.L",
			&"hand_r": "DEF-hand.R",
			&"foot_l": "DEF-foot.L",
		}[key] as String
		var bone_index := skeleton.find_bone(bone_name)
		assert_ne(bone_index, -1, "%s must remain exported" % bone_name)
		positions[key] = (
			skeleton.get_bone_global_pose(bone_index).origin
			if bone_index >= 0
			else Vector3.ZERO
		)
	return positions
