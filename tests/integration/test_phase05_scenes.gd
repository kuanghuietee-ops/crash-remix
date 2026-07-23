extends GutTest

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const GAUNTLET_SCENE_PATH := "res://scenes/levels/phase05_gauntlet.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"


func test_gauntlet_chains_all_four_segments_with_camera_regions() -> void:
	var gauntlet := _instantiate(GAUNTLET_SCENE_PATH)
	if gauntlet == null:
		return
	add_child_autofree(gauntlet)
	var wall := gauntlet.get_node_or_null("WallRunCanyon") as Node3D
	var grind := gauntlet.get_node_or_null("GrindRails") as Node3D
	var swing := gauntlet.get_node_or_null("SwingChain") as Node3D
	var phase := gauntlet.get_node_or_null("PhaseGauntlet") as Node3D

	assert_not_null(wall)
	assert_not_null(grind)
	assert_not_null(swing)
	assert_not_null(phase)
	if wall == null or grind == null or swing == null or phase == null:
		return
	assert_gt(wall.position.z, grind.position.z)
	assert_gt(grind.position.z, swing.position.z)
	assert_gt(swing.position.z, phase.position.z)
	assert_eq(
		wall.find_child("WallRunCameraRegion", true, false).get("camera_mode"),
		&"wall_run"
	)
	assert_eq(
		grind.find_child("GrindCameraRegion", true, false).get("camera_mode"),
		&"grind"
	)
	assert_eq(
		swing.find_child("SwingCameraRegion", true, false).get("camera_mode"),
		&"swing"
	)
	assert_eq(
		phase.find_child("PhaseCameraRegion", true, false).get("camera_mode"),
		&"default"
	)


func test_gauntlet_has_bare_debug_respawns_between_segments() -> void:
	var gauntlet := _instantiate(GAUNTLET_SCENE_PATH)
	if gauntlet == null:
		return
	add_child_autofree(gauntlet)
	var player := _instantiate(PLAYER_SCENE_PATH) as CharacterBody3D
	if player == null:
		return
	add_child_autofree(player)
	var respawns := gauntlet.find_children(
		"DebugRespawn*",
		"Area3D",
		true,
		false
	)

	assert_eq(respawns.size(), 3)
	for candidate: Node in respawns:
		assert_true(candidate.has_method("activate_for"))
		assert_not_null(candidate.get_node_or_null("Spawn"))
	if respawns.is_empty():
		return
	var respawn := respawns[0]
	var marker := respawn.get_node("Spawn") as Marker3D

	assert_true(respawn.call("activate_for", player))
	assert_eq(player.get("_spawn_transform"), marker.global_transform)


func test_segment_transfer_surfaces_form_one_continuous_route() -> void:
	var gauntlet := _instantiate(GAUNTLET_SCENE_PATH)
	if gauntlet == null:
		return
	add_child_autofree(gauntlet)
	var transitions: Array[Array] = [
		[
			gauntlet.get_node("WallRunCanyon/LandingPad"),
			gauntlet.get_node("GrindRails/ApproachPad"),
			gauntlet.get_node("DebugRespawnAfterWall"),
		],
		[
			gauntlet.get_node("GrindRails/LandingPad"),
			gauntlet.get_node("SwingChain/ApproachPad"),
			gauntlet.get_node("DebugRespawnAfterGrind"),
		],
		[
			gauntlet.get_node("SwingChain/LandingPad"),
			gauntlet.get_node(
				"PhaseGauntlet/BlueSet/BlueLaunch"
			),
			gauntlet.get_node("DebugRespawnAfterSwing"),
		],
	]

	for transition: Array in transitions:
		var exit := transition[0] as Node3D
		var next_approach := transition[1] as Node3D
		var next_bounds := _box_world_bounds(next_approach)
		var respawn := transition[2] as Node3D
		assert_true(
			_transfer_surfaces_connect(exit, next_approach),
			"adjacent surfaces must overlap laterally, meet in Z, and align in Y"
		)
		assert_gte(respawn.global_position.x, next_bounds.position.x)
		assert_lte(respawn.global_position.x, next_bounds.end.x)
		assert_gte(respawn.global_position.z, next_bounds.position.z)
		assert_lte(respawn.global_position.z, next_bounds.end.z)
		assert_lte(
			absf(respawn.global_position.y - next_bounds.end.y),
			1.0
		)


func test_continuity_check_rejects_lateral_and_vertical_segment_breaks() -> void:
	var gauntlet := _instantiate(GAUNTLET_SCENE_PATH)
	if gauntlet == null:
		return
	add_child_autofree(gauntlet)
	var exit := gauntlet.get_node(
		"WallRunCanyon/LandingPad"
	) as Node3D
	var next_approach := gauntlet.get_node(
		"GrindRails/ApproachPad"
	) as Node3D
	var authored_position := next_approach.position
	next_approach.position.y += 10.0

	assert_false(
		_transfer_surfaces_connect(exit, next_approach),
		"a Z-only continuity check misses an unreachable vertical offset"
	)
	next_approach.position = authored_position
	next_approach.position.x += 10.0
	assert_false(
		_transfer_surfaces_connect(exit, next_approach),
		"continuity also requires lateral surface overlap"
	)


func test_game_loads_phase05_gauntlet_without_legacy_collision_overlap() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)

	assert_true(game.has_node("Phase05Gauntlet"))
	for candidate: Node in game.get_node("Graybox").get_children():
		if candidate is Node3D:
			assert_gt(
				absf((candidate as Node3D).global_position.x),
				50.0,
				"legacy Phase 0 geometry must remain off the gauntlet corridor"
			)


func test_gauntlet_presents_phase_button() -> void:
	var scene := _instantiate(GAME_SCENE_PATH)
	if scene == null:
		return
	add_child_autofree(scene)
	await wait_physics_frames(2)
	var controls := scene.find_child("TouchControls", true, false)

	assert_true(
		controls.call("has_action", &"phase"),
		"Gate F2 criterion 3 is unrunnable without the PHASE button"
	)


func test_game_registers_nested_gauntlet_camera_regions() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(2)
	var regions: Array = game.get_node("CameraRig").get("_regions")
	var region_names: Array[StringName] = []
	for region: Node in regions:
		region_names.append(region.name)

	assert_true(region_names.has(&"WallRunCameraRegion"))
	assert_true(region_names.has(&"GrindCameraRegion"))
	assert_true(region_names.has(&"SwingCameraRegion"))
	assert_true(region_names.has(&"PhaseCameraRegion"))


func test_camera_rail_reaches_the_end_of_the_phase_gauntlet() -> void:
	var game := _instantiate(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var rail_finish := game.get_node("CameraRig/Rail/Finish") as Marker3D
	var phase_finish := game.get_node(
		"Phase05Gauntlet/PhaseGauntlet/OrangeSet/OrangeFinish"
	) as Node3D

	assert_lte(rail_finish.global_position.z, phase_finish.global_position.z)


func _instantiate(path: String) -> Node:
	var packed: PackedScene = load(path)
	assert_not_null(packed, path + " must load")
	return packed.instantiate() if packed != null else null


func _box_world_bounds(body: Node3D) -> AABB:
	var collision := body.find_child(
		"CollisionShape3D",
		true,
		false
	) as CollisionShape3D
	assert_not_null(collision)
	if collision == null:
		return AABB()
	var box := collision.shape as BoxShape3D
	assert_not_null(box)
	if box == null:
		return AABB()
	var local_bounds := AABB(
		-box.size * 0.5,
		box.size
	)
	return collision.global_transform * local_bounds


func _transfer_surfaces_connect(
	exit: Node3D,
	next_approach: Node3D
) -> bool:
	var exit_bounds := _box_world_bounds(exit)
	var next_bounds := _box_world_bounds(next_approach)
	var lateral_overlap_m := (
		minf(exit_bounds.end.x, next_bounds.end.x)
		- maxf(exit_bounds.position.x, next_bounds.position.x)
	)
	var vertical_step_m := absf(
		exit_bounds.end.y - next_bounds.end.y
	)
	var longitudinal_overlap_m := (
		next_bounds.end.z - exit_bounds.position.z
	)
	return (
		lateral_overlap_m > 0.0
		and vertical_step_m <= 1.0
		and longitudinal_overlap_m >= 0.0
		and longitudinal_overlap_m <= 1.0
	)
