extends GutTest

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const CAMERA_SCENE_PATH := "res://scenes/camera_rig.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"
const GAME_SCRIPT_PATH := "res://src/core/phase0_game.gd"
const CRASH_IDLE := &"A_crash_idle"
const CRASH_RUN := &"A_crash_run"
const CRASH_JUMP := &"A_crash_jump"
const CRASH_SPIN := &"A_crash_spin"


func test_player_scene_contains_controller_and_both_depth_aids() -> void:
	var player := _instantiate(PLAYER_SCENE_PATH)
	if player == null:
		return
	add_child_autofree(player)
	assert_true(player is CharacterBody3D)
	assert_true(player.get_node("CollisionShape3D") is CollisionShape3D)
	assert_true(player.get_node("Hurtbox") is Area3D)
	assert_false((player.get_node("Hurtbox") as Area3D).monitorable)
	assert_true(player.get_node("SpinArea") is Area3D)
	assert_true(player.get_node("SlamArea") is Area3D)
	assert_true(player.has_node("BlobShadow"))
	assert_true(player.has_node("LandingRing"))


func test_player_scene_mounts_the_colored_rig_instead_of_the_gray_capsule() -> void:
	var player := _instantiate(PLAYER_SCENE_PATH) as CharacterBody3D
	if player == null:
		return
	add_child_autofree(player)
	var crash_model := player.get_node_or_null(
		"Visual/SpinPivot/CrashModel"
	) as Node3D
	var animation_driver := player.get_node_or_null(
		"Visual/CrashAnimationDriver"
	)

	assert_not_null(crash_model)
	assert_not_null(animation_driver)
	assert_false(player.has_node("Visual/SpinPivot/Body"))
	assert_false(player.has_node("Visual/SpinPivot/ForwardMarker"))
	if crash_model == null or animation_driver == null:
		return
	var meshes: Array[Node] = crash_model.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)
	var animation_players: Array[Node] = crash_model.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	assert_eq(meshes.size(), 1)
	assert_eq(animation_players.size(), 1)
	if meshes.size() != 1 or animation_players.size() != 1:
		return
	var mesh := meshes[0] as MeshInstance3D
	var world_bounds := mesh.global_transform * mesh.get_aabb()
	assert_almost_eq(
		world_bounds.position.y,
		player.global_position.y,
		0.03,
		"Crash's shoes must remain on the gameplay floor plane"
	)
	assert_almost_eq(
		absf(crash_model.rotation.y),
		PI,
		0.001,
		"the imported +Z-facing model must face gameplay's -Z corridor"
	)
	assert_true(animation_driver.has_method("current_clip"))
	if animation_driver.has_method("current_clip"):
		assert_true(
			animation_driver.call("current_clip") in [CRASH_IDLE, CRASH_JUMP]
		)


func test_camera_rig_has_path_camera_and_overlapping_region_volumes() -> void:
	var rig := _instantiate(CAMERA_SCENE_PATH)
	if rig == null:
		return
	add_child_autofree(rig)
	assert_true(rig.get_node("Rail") is Path3D)
	assert_true(rig.get_node("Camera3D") is Camera3D)
	var regions := rig.get_node("Regions").get_children()
	assert_gte(regions.size(), 2)
	for region: Node in regions:
		assert_true(region is Area3D)


func test_camera_configure_applies_nondefault_authored_rail_bake_interval() -> void:
	var rig := _instantiate(CAMERA_SCENE_PATH)
	var player := _instantiate(PLAYER_SCENE_PATH) as CharacterBody3D
	if rig == null or player == null:
		return
	add_child_autofree(rig)
	add_child_autofree(player)
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	catalog.camera.rail_bake_interval_m = 0.37

	rig.call(
		"configure",
		player,
		rig.get_node("Rail"),
		rig.get_node("Camera3D"),
		catalog.camera,
		rig.get_node("Regions").get_children()
	)

	assert_almost_eq(
		(rig.get_node("Rail") as Path3D).curve.bake_interval,
		0.37,
		0.0001
	)


func test_camera_routes_projected_corridor_axis_to_input_router() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(4)
	var player := game.get_node("Player") as CharacterBody3D
	var rig := game.get_node("CameraRig") as Node3D
	var camera := game.get_node("CameraRig/Camera3D") as Camera3D
	var router := game.get_node("Input/InputRouter") as InputRouter
	var corridor_forward: Vector3 = rig.call("corridor_forward")
	var screen_origin := camera.unproject_position(player.global_position)
	var screen_forward := camera.unproject_position(
		player.global_position + corridor_forward
	)
	var expected_axis := (screen_forward - screen_origin).normalized()

	assert_lt(
		absf(router.corridor_axis().angle_to(expected_axis)),
		0.0001
	)


func test_game_scene_is_only_a_graybox_phase_zero_toybox() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	assert_true(game.has_node("Player"))
	assert_true(game.has_node("CameraRig"))
	assert_true(game.has_node("Input/InputRouter"))
	assert_true(game.has_node("Input/GamepadInput"))
	assert_true(game.has_node("UI/TouchControls"))
	assert_gte(game.get_node("Graybox").get_child_count(), 8)
	assert_gt(get_tree().get_nodes_in_group("hazard").size(), 0)


func test_high_jump_ledge_requires_high_jump_but_remains_reachable() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	var catalog: GameplayTuning = load("res://data/tuning/gameplay.tres")
	var ledge := game.get_node("Graybox/HighJumpLedge")
	var ledge_top: float = ledge.position.y + ledge.get("size").y / 2.0

	assert_gt(ledge_top, catalog.move.jump_full_height_m)
	assert_lte(ledge_top, catalog.move.high_jump_height_m)


func test_tuning_tools_are_enabled_only_for_debug_builds() -> void:
	var script: Script = load(GAME_SCRIPT_PATH)
	assert_not_null(script, "PhaseZeroGame implementation must exist")
	if script == null:
		return

	assert_true(script.call("should_enable_debug_tools", true))
	assert_false(script.call("should_enable_debug_tools", false))


func test_booted_toybox_runs_player_camera_and_depth_aids_in_physics() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(8)
	var player := game.get_node("Player") as CharacterBody3D
	var rail := game.get_node("CameraRig/Rail") as Path3D
	var camera := game.get_node("CameraRig/Camera3D") as Camera3D
	var landing_ring := player.get_node("LandingRing") as Node3D
	var animation_driver := player.get_node("Visual/CrashAnimationDriver")
	var landing_probe: Variant = landing_ring.get("_probe_shape")
	assert_true(player.is_on_floor())
	assert_gte(rail.curve.point_count, 5)
	assert_true(player.get_node("BlobShadow").visible)
	assert_false(player.get_node("LandingRing").visible)
	assert_true(landing_probe is SphereShape3D)
	if landing_probe is SphereShape3D:
		assert_almost_eq(
			(landing_probe as SphereShape3D).radius,
			game.get("tuning_service").get("catalog").get("depth").get(
				"collision_probe_radius_m"
			),
			0.0001
		)
	assert_true(camera.current)

	var buffer: InputIntentBuffer = game.get_node("Input/InputRouter").get("buffer")
	var before_run := player.global_position
	var now_s := float(Time.get_ticks_usec()) / 1_000_000.0
	buffer.push(InputIntent.move(Vector2.UP, now_s, &"test"))
	await wait_physics_frames(8)
	assert_lt(player.global_position.z, before_run.z)
	assert_eq(animation_driver.call("current_clip"), CRASH_RUN)

	now_s = float(Time.get_ticks_usec()) / 1_000_000.0
	buffer.push(InputIntent.button(&"jump", true, now_s, &"test"))
	var before_jump_y := player.global_position.y
	await wait_physics_frames(2)
	assert_gt(player.global_position.y, before_jump_y)
	assert_eq(animation_driver.call("current_clip"), CRASH_JUMP)
	assert_true(player.get_node("LandingRing").visible)
	buffer.push(InputIntent.button(&"jump", false, now_s + 0.05, &"test"))


func test_depth_aids_reset_interpolation_when_player_respawns() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var player := game.get_node("Player") as CharacterBody3D
	var shadow := player.get_node("BlobShadow")
	var ring := player.get_node("LandingRing")

	assert_true(player.respawned.is_connected(
		Callable(shadow, "_on_target_respawned")
	))
	assert_true(player.respawned.is_connected(
		Callable(ring, "_on_target_respawned")
	))


func test_edge_landing_nudge_moves_a_near_miss_onto_safe_floor() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(4)
	var player := game.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(4.1, 0.08, 5.0)
	player.velocity = Vector3.DOWN
	await wait_physics_frames(1)
	var before_x := player.global_position.x

	var nudged: bool = player.call("try_edge_landing_nudge")

	assert_true(nudged)
	assert_lt(player.global_position.x, before_x)
	assert_lte(before_x - player.global_position.x, 0.1201)


func test_edge_landing_nudge_refuses_to_move_through_blocking_geometry() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(4)
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 1.1, 3.0)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	blocker.position = Vector3(3.63, 0.55, 5.0)
	game.add_child(blocker)
	await wait_physics_frames(1)
	var player := game.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(4.1, 0.08, 5.0)
	player.velocity = Vector3.DOWN
	await wait_physics_frames(1)
	var before := player.global_position

	var nudged: bool = player.call("try_edge_landing_nudge")

	assert_false(nudged)
	assert_eq(player.global_position, before)


func test_booted_player_receives_live_landing_assist_tuning() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var player := game.get_node("Player") as CharacterBody3D
	var configured_depth: Variant = player.get("_depth_tuning")

	assert_not_null(configured_depth)
	if configured_depth != null:
		assert_eq(
			configured_depth.get("landing_assist_touch_strength"),
			0.5
		)


func test_live_tuning_reaches_cached_camera_and_touch_consumers() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var debug_ui := game.get_node("UI/TuningDebug") as Control
	var camera := game.get_node("CameraRig/Camera3D") as Camera3D
	var touch := game.get_node("UI/TouchControls") as Control
	var old_radius: float = touch.call("current_layout")["jump_radius"]

	assert_eq(debug_ui.call("set_live_value", &"camera", &"field_of_view_degrees", 71.0), OK)
	assert_eq(debug_ui.call("set_live_value", &"input", &"jump_button_diameter_mm", 18.0), OK)
	await wait_process_frames(1)

	assert_eq(camera.fov, 71.0)
	assert_gt(touch.call("current_layout")["jump_radius"], old_radius)


func test_touch_spin_reaches_player_and_rotates_visible_pivot() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(4)
	var player := game.get_node("Player") as CharacterBody3D
	var touch := game.get_node("UI/TouchControls") as Control
	var spin_area := player.get_node("SpinArea") as Area3D
	var animation_driver := player.get_node("Visual/CrashAnimationDriver")
	assert_true(player.has_node("Visual/SpinPivot"))
	if not player.has_node("Visual/SpinPivot"):
		return
	var spin_pivot := player.get_node("Visual/SpinPivot") as Node3D
	var rotation_before := spin_pivot.rotation.y
	var spin_press := InputEventScreenTouch.new()
	spin_press.index = 12
	spin_press.position = touch.call("current_layout")["spin_center"]
	spin_press.pressed = true

	touch.call("handle_touch_event", spin_press)
	await wait_physics_frames(2)

	assert_true(player.call("is_spinning"))
	assert_true(spin_area.monitoring)
	assert_ne(spin_pivot.rotation.y, rotation_before)
	assert_eq(animation_driver.call("current_clip"), CRASH_SPIN)
	spin_press.pressed = false
	touch.call("handle_touch_event", spin_press)


func _instantiate(path: String) -> Node:
	var packed: PackedScene = load(path)
	assert_not_null(packed, path + " must load")
	return packed.instantiate() if packed != null else null
