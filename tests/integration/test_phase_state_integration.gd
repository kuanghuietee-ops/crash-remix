extends GutTest

const PHASE_GAUNTLET_PATH := "res://scenes/segments/seg_phase_gauntlet.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"
const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _test_clock_s := 0.0


func after_each() -> void:
	var phase_state := get_node_or_null("/root/PhaseState")
	if phase_state != null:
		phase_state.call("reset_to_authored_set")


func test_ghost_set_has_collision_disabled_and_solid_set_enabled() -> void:
	var scene: Node = _instance_phase_gauntlet()
	if scene == null:
		return
	add_child_autofree(scene)
	await wait_physics_frames(2)

	var phase_state: Node = get_node("/root/PhaseState")
	phase_state.call("configure", load(BASE_CATALOG_PATH).get("phase"))
	var observed_at_signal: Dictionary = {}
	phase_state.connect(
		&"phase_changed",
		func(signaled_set: StringName) -> void:
			observed_at_signal["active_set"] = signaled_set
			observed_at_signal["blue_matches"] = _group_collision_matches(
				&"phase_blue",
				signaled_set == &"blue"
			)
			observed_at_signal["orange_matches"] = _group_collision_matches(
				&"phase_orange",
				signaled_set == &"orange"
			),
		Object.CONNECT_ONE_SHOT
	)
	assert_true(phase_state.call("request_toggle", _next_test_time_s()))

	# Same frame — yielding here would hide incoherent signal-time state.
	var active: StringName = phase_state.call("active_set")
	var blue_bodies := get_tree().get_nodes_in_group(&"phase_blue")
	var orange_bodies := get_tree().get_nodes_in_group(&"phase_orange")
	assert_gt(blue_bodies.size(), 0, "gauntlet must contain blue phase objects")
	assert_gt(orange_bodies.size(), 0, "gauntlet must contain orange phase objects")
	for body: Node in blue_bodies:
		assert_eq(_collision_enabled(body), active == &"blue")
	for body: Node in orange_bodies:
		assert_eq(_collision_enabled(body), active == &"orange")
	assert_eq(observed_at_signal.get("active_set"), active)
	assert_true(observed_at_signal.get("blue_matches", false))
	assert_true(observed_at_signal.get("orange_matches", false))


func test_both_sets_remain_visible_and_ghost_uses_authored_tuning() -> void:
	var scene: Node = _instance_phase_gauntlet()
	if scene == null:
		return
	add_child_autofree(scene)
	await wait_process_frames(1)
	var phase_tuning: PhaseTuning = load(BASE_CATALOG_PATH).get("phase")
	var phase_state: Node = get_node("/root/PhaseState")
	phase_state.call("configure", phase_tuning)
	var active: StringName = phase_state.call("active_set")
	var ghost_mesh_count := 0
	var solid_mesh_count := 0

	for group_name: StringName in [&"phase_blue", &"phase_orange"]:
		var set_name := &"blue" if group_name == &"phase_blue" else &"orange"
		var solid := set_name == active
		for phase_object: Node3D in get_tree().get_nodes_in_group(group_name):
			assert_true(phase_object.is_visible_in_tree())
			for mesh: MeshInstance3D in phase_object.find_children(
				"*",
				"MeshInstance3D",
				true,
				false
			):
				assert_true(mesh.is_visible_in_tree())
				if solid:
					solid_mesh_count += 1
					assert_null(mesh.material_override)
				else:
					ghost_mesh_count += 1
					var material := mesh.material_override as ShaderMaterial
					assert_not_null(material)
					if material == null:
						continue
					assert_almost_eq(
						material.get_shader_parameter(&"ghost_opacity"),
						phase_tuning.ghost_opacity,
						0.0001
					)
					assert_almost_eq(
						material.get_shader_parameter(
							&"ghost_outline_width_m"
						),
						phase_tuning.ghost_outline_width_m,
						0.0001
					)

	assert_gt(solid_mesh_count, 0)
	assert_gt(ghost_mesh_count, 0)


func test_player_phase_press_toggles_while_airborne() -> void:
	var player := _instance(PLAYER_SCENE_PATH) as CharacterBody3D
	if player == null:
		return
	add_child_autofree(player)
	var catalog: GameplayTuning = load(BASE_CATALOG_PATH)
	var intents := InputIntentBuffer.new()
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		intents
	)
	var phase_state: Node = get_node("/root/PhaseState")
	phase_state.call("configure", catalog.phase)
	var before: StringName = phase_state.call("active_set")
	var now_s := _next_test_time_s()
	intents.push(InputIntent.button(
		InputIntent.ACTION_PHASE,
		true,
		now_s,
		&"test"
	))
	player.velocity = Vector3.UP

	player.call("advance_logic", now_s, false, 0.0, Vector3.FORWARD)

	assert_ne(phase_state.call("active_set"), before)
	assert_null(intents.consume_pressed(
		InputIntent.ACTION_PHASE,
		now_s,
		catalog.input.action_buffer_s
	))


func test_game_boot_and_live_tuning_both_configure_phase_state() -> void:
	var phase_state: Node = get_node("/root/PhaseState")
	var sentinel: PhaseTuning = load(BASE_CATALOG_PATH).get("phase").duplicate()
	sentinel.ghost_opacity = 0.73
	phase_state.call("configure", sentinel)
	var game: Node = _instance(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var catalog: GameplayTuning = game.get("tuning_service").get("catalog")
	var ghost_material := phase_state.get("_ghost_material") as ShaderMaterial
	assert_almost_eq(
		ghost_material.get_shader_parameter(&"ghost_opacity"),
		catalog.phase.ghost_opacity,
		0.0001
	)

	catalog.phase.ghost_opacity = 0.41
	game.call("_on_tuning_changed", &"test")

	assert_almost_eq(
		ghost_material.get_shader_parameter(&"ghost_opacity"),
		0.41,
		0.0001
	)


func test_game_boot_and_live_tuning_route_every_traversal_resource() -> void:
	var game: Node = _instance(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_process_frames(1)
	var catalog: GameplayTuning = game.get("tuning_service").get("catalog")
	var player := game.get_node("Player") as CharacterBody3D

	assert_eq(player.get("_wall_run_tuning"), catalog.wall_run)
	assert_eq(player.get("_grind_tuning"), catalog.grind)
	assert_eq(player.get("_swing_tuning"), catalog.swing)

	catalog.wall_run = catalog.wall_run.duplicate()
	catalog.grind = catalog.grind.duplicate()
	catalog.swing = catalog.swing.duplicate()
	game.call("_on_tuning_changed", &"test")

	assert_eq(player.get("_wall_run_tuning"), catalog.wall_run)
	assert_eq(player.get("_grind_tuning"), catalog.grind)
	assert_eq(player.get("_swing_tuning"), catalog.swing)


func test_respawn_restores_a_solid_platform_under_the_player() -> void:
	var game: Node = _instance(GAME_SCENE_PATH)
	if game == null:
		return
	add_child_autofree(game)
	await wait_physics_frames(2)
	var phase_state: Node = get_node("/root/PhaseState")
	var player := game.get_node("Player") as CharacterBody3D
	var respawn_point := game.get_node(
		"Phase05Gauntlet/DebugRespawnAfterSwing"
	)
	var spawn := respawn_point.get_node("Spawn") as Marker3D
	var blue_launch := game.get_node(
		"Phase05Gauntlet/PhaseGauntlet/BlueSet/BlueLaunch"
	)
	assert_true(respawn_point.call("activate_for", player))
	assert_true(phase_state.call("request_toggle", _next_test_time_s()))
	assert_eq(phase_state.call("active_set"), &"orange")
	assert_false(_collision_enabled(blue_launch))

	player.call("respawn")
	var respawn_position := player.global_position
	await wait_physics_frames(1)

	assert_true(
		respawn_position.is_equal_approx(spawn.global_position),
		"the test must execute the real post-swing debug respawn"
	)
	assert_eq(
		phase_state.call("active_set"),
		&"blue",
		"respawning onto a blue platform while orange is solid drops the player through it"
	)
	assert_true(
		_collision_enabled(blue_launch),
		"the actual platform under the respawn must be solid synchronously"
	)


func _instance_phase_gauntlet() -> Node:
	return _instance(PHASE_GAUNTLET_PATH)


func _next_test_time_s() -> float:
	_test_clock_s += 1.0
	return _test_clock_s


func _instance(path: String) -> Node:
	var packed: PackedScene = load(path)
	assert_not_null(packed, path + " must load")
	return packed.instantiate() if packed != null else null


func _collision_enabled(body: Node) -> bool:
	var shapes := body.find_children("*", "CollisionShape3D", true, false)
	assert_gt(shapes.size(), 0, body.name + " must own collision")
	for shape: CollisionShape3D in shapes:
		if shape.disabled:
			return false
	return not shapes.is_empty()


func _group_collision_matches(
	group_name: StringName,
	expected_enabled: bool
) -> bool:
	var bodies := get_tree().get_nodes_in_group(group_name)
	if bodies.is_empty():
		return false
	for body: Node in bodies:
		if _collision_enabled(body) != expected_enabled:
			return false
	return true
