extends GutTest

const RAIL_SCRIPT_PATH := "res://src/gameplay/traversal/traversal_rail.gd"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"
const GRIND_SEGMENT_PATH := "res://scenes/segments/seg_grind_rails.tscn"
const WALL_SEGMENT_PATH := "res://scenes/segments/seg_wall_run_canyon.tscn"
const SWING_SEGMENT_PATH := "res://scenes/segments/seg_swing_chain.tscn"
const FSM_SCRIPT_PATH := "res://src/gameplay/player/player_state_machine.gd"
const BUFFER_SCRIPT_PATH := "res://src/gameplay/input/input_intent_buffer.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const MISSED_HOP_ENTRY_DISTANCE_M := 31.0
const MISSED_HOP_START_DISTANCE_M := 30.8
const SCENARIO_START_S := 8.0

var _catalog: GameplayTuning
var _move: MoveTuning
var _input: InputTuning
var _camera: CameraTuning
var _grind: GrindTuning
var _wall_run: WallRunTuning
var _swing: SwingTuning


func before_all() -> void:
	_catalog = load(TUNING_PATH)
	assert_not_null(_catalog)
	if _catalog != null:
		_move = _catalog.move
		_input = _catalog.input
		_camera = _catalog.camera
		_grind = _catalog.grind
		_wall_run = _catalog.wall_run
		_swing = _catalog.swing


func test_stick_and_jump_hops_to_the_parallel_rail() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.set("state", &"grind")
	buffer.push(InputIntent.move(Vector2.RIGHT, 0.49, &"test"))
	_press(buffer, &"jump", 0.5)

	var decision: RefCounted = fsm.call(
		"step",
		0.5,
		false,
		0.0,
		buffer,
		_move,
		_input,
		true
	)

	assert_eq(decision.get("impulse"), &"rail_hop")
	assert_eq(decision.get("state"), &"airborne")


func test_bare_jump_exits_the_rail_even_with_a_neighbour() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.set("state", &"grind")
	buffer.push(InputIntent.move(Vector2.ZERO, 0.49, &"test"))
	_press(buffer, &"jump", 0.5)

	var decision: RefCounted = fsm.call(
		"step",
		0.5,
		false,
		0.0,
		buffer,
		_move,
		_input,
		true
	)

	assert_eq(
		decision.get("impulse"),
		&"rail_exit",
		"bare JUMP must always exit"
	)
	assert_eq(decision.get("state"), &"airborne")


func test_hop_falls_back_to_exit_without_a_neighbour() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.set("state", &"grind")
	buffer.push(InputIntent.move(Vector2.RIGHT, 0.49, &"test"))
	_press(buffer, &"jump", 0.5)

	var decision: RefCounted = fsm.call(
		"step",
		0.5,
		false,
		0.0,
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(decision.get("impulse"), &"rail_exit")


func test_floor_contact_does_not_reinterpret_a_rail_exit_as_ground_jump() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.set("state", &"grind")
	_press(buffer, &"jump", 0.75)

	var decision: RefCounted = fsm.call(
		"step",
		0.75,
		true,
		0.0,
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(decision.get("impulse"), &"rail_exit")
	assert_false(decision.get("landed"))


func test_rail_attach_resets_double_jump_availability() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	assert_true(fsm.has_method("enter_grind"))
	if not fsm.has_method("enter_grind"):
		return
	fsm.set("_double_jump_available", false)
	fsm.call("enter_grind", 1.0)
	_press(buffer, &"jump", 1.01)
	fsm.call("step", 1.01, false, 0.0, buffer, _move, _input, false)
	_release(buffer, &"jump", 1.02)
	_press(buffer, &"jump", 1.03)

	var decision: RefCounted = fsm.call(
		"step",
		1.03,
		false,
		0.0,
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(
		decision.get("impulse"),
		&"double_jump",
		"a rail contact starts a fresh airtime"
	)


func test_traversal_rail_bakes_world_space_samples_from_camera_tuning() -> void:
	var rail: Path3D = _new_rail(
		&"SampleRail",
		Vector3(3.0, 2.0, 1.0),
		Vector3(0.0, 0.0, -2.0)
	)
	if rail == null:
		return
	add_child_autofree(rail)

	var samples: Array = rail.call("samples")

	assert_gt(samples.size(), 2)
	assert_almost_eq(rail.curve.bake_interval, _camera.rail_bake_interval_m, 0.0001)
	assert_eq(samples.front().get("position"), Vector3(3.0, 2.0, 1.0))
	assert_eq(samples.back().get("position"), Vector3(3.0, 2.0, -1.0))
	assert_eq(samples.front().get("tangent"), Vector3.FORWARD)
	assert_eq(samples.front().get("normal"), Vector3.UP)
	assert_almost_eq(samples.back().get("distance_along_m"), 2.0, 0.0001)


func test_traversal_rail_refreshes_its_live_sample_interval() -> void:
	var rail: Path3D = _new_rail(
		&"LiveRail",
		Vector3.ZERO,
		Vector3(0.0, 0.0, -2.0)
	)
	if rail == null:
		return
	add_child_autofree(rail)
	var camera_variant: CameraTuning = _camera.duplicate()
	camera_variant.rail_bake_interval_m = 0.37

	rail.call("refresh_tuning", camera_variant)
	rail.call("samples")

	assert_almost_eq(rail.curve.bake_interval, 0.37, 0.0001)


func test_traversal_rail_reuses_samples_until_the_curve_contract_changes() -> void:
	var rail: Path3D = _new_rail(
		&"CachedRail",
		Vector3.ZERO,
		Vector3(0.0, 0.0, -2.0)
	)
	if rail == null:
		return
	add_child_autofree(rail)

	var first: Array = rail.call("samples")
	var second: Array = rail.call("samples")
	assert_eq(first.front(), second.front())

	var camera_variant: CameraTuning = _camera.duplicate()
	camera_variant.rail_bake_interval_m = 0.41
	rail.call("refresh_tuning", camera_variant)
	var refreshed: Array = rail.call("samples")

	assert_ne(first.front(), refreshed.front())


func test_game_boot_and_live_tuning_refresh_traversal_rail_sampling() -> void:
	var packed: PackedScene = load(GAME_SCENE_PATH)
	assert_not_null(packed)
	if packed == null:
		return
	var game := packed.instantiate()
	var rail: Path3D = _new_rail(
		&"RuntimeRail",
		Vector3.ZERO,
		Vector3(0.0, 0.0, -2.0)
	)
	if rail == null:
		game.free()
		return
	var sentinel: CameraTuning = _camera.duplicate()
	sentinel.rail_bake_interval_m = 0.37
	rail.set("camera_tuning", sentinel)
	game.add_child(rail)
	add_child_autofree(game)
	await wait_process_frames(1)
	var catalog: GameplayTuning = game.get("tuning_service").get("catalog")

	assert_eq(rail.get("camera_tuning"), catalog.camera)

	var replacement: CameraTuning = catalog.camera.duplicate()
	replacement.rail_bake_interval_m = 0.41
	catalog.camera = replacement
	game.call("_on_tuning_changed", &"test")
	rail.call("samples")

	assert_eq(rail.get("camera_tuning"), replacement)
	assert_almost_eq(rail.curve.bake_interval, 0.41, 0.0001)


func test_parallel_neighbour_uses_the_authored_lateral_direction() -> void:
	var holder := Node3D.new()
	var left: Path3D = _new_rail(
		&"Left",
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -4.0)
	)
	var center: Path3D = _new_rail(
		&"Center",
		Vector3.ZERO,
		Vector3(0.0, 0.0, -4.0)
	)
	var right: Path3D = _new_rail(
		&"Right",
		Vector3(2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -4.0)
	)
	if left == null or center == null or right == null:
		holder.free()
		return
	holder.add_child(left)
	holder.add_child(center)
	holder.add_child(right)
	center.set("left_neighbor_path", NodePath("../Left"))
	center.set("right_neighbor_path", NodePath("../Right"))
	add_child_autofree(holder)

	assert_eq(center.call("parallel_neighbor", -1), left)
	assert_eq(center.call("parallel_neighbor", 1), right)
	assert_null(center.call("parallel_neighbor", 0))


func test_controller_attaches_near_the_predicted_arc_and_drives_the_spline() -> void:
	var rail: Path3D = _new_rail(
		&"DriveRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = Vector3(0.2, 1.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	var arc := PackedVector3Array([
		player.global_position,
		Vector3(0.0, 1.0, -1.0),
	])
	assert_true(player.has_method("try_rail_attach"))
	if not player.has_method("try_rail_attach"):
		return

	assert_true(player.call("try_rail_attach", arc, 2.0))
	assert_eq(player.call("current_state"), &"grind")
	assert_eq(player.get("_active_rail"), rail)
	assert_eq(player.global_position, Vector3(0.0, 1.0, 0.0))

	var decision: RefCounted = player.call(
		"advance_logic",
		2.1,
		false,
		0.1,
		Vector3.FORWARD
	)
	var expected_speed := minf(
		2.0 + _grind.acceleration_mps2 * 0.1,
		_grind.speed_mps
	)
	assert_eq(decision.get("state"), &"grind")
	assert_almost_eq(player.velocity.length(), expected_speed, 0.0001)
	assert_lt(player.velocity.z, 0.0)


func test_real_physics_loop_advances_and_reprojects_the_grind() -> void:
	var rail: Path3D = _new_rail(
		&"PhysicsRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = Vector3(0.2, 1.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([
			player.global_position,
			Vector3(0.0, 1.0, -1.0),
		]),
		2.15
	))
	var before_z := player.global_position.z

	await wait_physics_frames(2)

	assert_lt(player.global_position.z, before_z)
	assert_eq(player.call("current_state"), &"grind")
	assert_almost_eq(
		player.get("_active_rail_distance_m"),
		rail.call("closest_distance_m", player.global_position),
		0.0001
	)


func test_reaching_rail_end_reports_the_airborne_exit_in_the_same_frame() -> void:
	var rail: Path3D = _new_rail(
		&"ShortRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -1.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = Vector3(0.2, 1.0, -1.0)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([
			player.global_position,
			Vector3(0.0, 1.0, -1.0),
		]),
		2.2
	))
	player.set("_active_rail_distance_m", rail.call("length_m"))

	var decision: RefCounted = player.call(
		"advance_logic",
		2.3,
		false,
		0.1,
		Vector3.FORWARD
	)

	assert_eq(decision.get("state"), &"airborne")
	assert_eq(player.call("current_state"), &"airborne")
	assert_eq(
		player.motion_mode,
		CharacterBody3D.MOTION_MODE_GROUNDED
	)


func test_predicted_future_arc_contact_is_the_attach_trigger() -> void:
	var rail: Path3D = _new_rail(
		&"FutureRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = Vector3(0.0, 5.0, 4.0)
	player.velocity = Vector3(0.0, 2.0, -3.0)

	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([
			player.global_position,
			Vector3(0.0, 1.0, -2.0),
		]),
		2.5
	))
	assert_eq(player.call("current_state"), &"grind")
	assert_eq(player.get("_active_rail"), rail)


func test_bare_rail_exit_uses_tuning_instead_of_inherited_velocity() -> void:
	var rail: Path3D = _new_rail(
		&"ExitRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	player.global_position = Vector3(0.2, 1.0, 0.0)
	player.velocity = Vector3(20.0, -4.0, 10.0)
	var arc := PackedVector3Array([
		player.global_position,
		Vector3(0.0, 1.0, -1.0),
	])
	if not player.has_method("try_rail_attach"):
		assert_true(false, "controller must expose deterministic rail attach")
		return
	assert_true(player.call("try_rail_attach", arc, 3.0))
	assert_almost_eq(
		(player.get_node("Visual") as Node3D).rotation.z,
		deg_to_rad(_grind.bank_degrees),
		0.0001
	)
	_press(buffer, &"jump", 3.01)

	var decision: RefCounted = player.call(
		"advance_logic",
		3.01,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"rail_exit")
	assert_eq(player.call("current_state"), &"airborne")
	assert_almost_eq(
		Vector2(player.velocity.x, player.velocity.z).length(),
		_grind.exit_forward_speed_mps,
		0.0001
	)
	assert_almost_eq(
		player.velocity.y,
		JumpKinematics.upward_speed_for_height(_grind.hop_height_m, _move),
		0.0001
	)
	assert_null(player.get("_active_rail"))
	assert_almost_eq(
		(player.get_node("Visual") as Node3D).rotation.z,
		0.0,
		0.0001
	)


func test_rail_exit_cannot_immediately_reattach_the_departed_rail() -> void:
	var rail: Path3D = _new_rail(
		&"BlockedRail",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var setup := _new_controller_with_rails([rail])
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	player.global_position = Vector3(0.2, 1.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	var arc := PackedVector3Array([
		player.global_position,
		Vector3(0.0, 1.0, -1.0),
	])
	assert_true(player.call("try_rail_attach", arc, 3.5))
	_press(buffer, &"jump", 3.51)
	player.call("advance_logic", 3.51, false, 0.0, Vector3.FORWARD)
	player.global_position = Vector3(0.0, 3.0, 2.0)
	player.velocity.y = -1.0
	var return_arc := PackedVector3Array([
		player.global_position,
		Vector3(0.0, 1.0, -1.0),
	])

	assert_false(player.call("try_rail_attach", return_arc, 3.52))
	assert_eq(player.call("current_state"), &"airborne")


func test_stick_jump_targets_and_reacquires_the_parallel_rail() -> void:
	var holder := Node3D.new()
	var center: Path3D = _new_rail(
		&"Center",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	var right: Path3D = _new_rail(
		&"Right",
		Vector3(2.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -10.0)
	)
	if center == null or right == null:
		holder.free()
		return
	holder.add_child(center)
	holder.add_child(right)
	center.set("right_neighbor_path", NodePath("../Right"))
	right.set("left_neighbor_path", NodePath("../Center"))
	var setup := _new_controller_with_rail_root(holder)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	player.global_position = Vector3(0.2, 1.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, -2.0)
	if not player.has_method("try_rail_attach"):
		assert_true(false, "controller must expose deterministic rail attach")
		return
	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([
			player.global_position,
			Vector3(0.0, 1.0, -1.0),
		]),
		4.0
	))
	buffer.push(InputIntent.move(Vector2.RIGHT, 4.01, &"test"))
	_press(buffer, &"jump", 4.01)

	var hop: RefCounted = player.call(
		"advance_logic",
		4.01,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(hop.get("impulse"), &"rail_hop")
	assert_eq(player.get("_rail_hop_target"), right)
	assert_gt(player.velocity.x, 0.0)
	assert_gt(player.velocity.y, 0.0)

	player.global_position = Vector3(1.8, 1.0, -1.0)
	player.velocity.y = -1.0
	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([
			player.global_position,
			Vector3(2.0, 1.0, -2.0),
		]),
		4.5
	))
	assert_eq(player.get("_active_rail"), right)
	assert_null(player.get("_rail_hop_target"))
	assert_eq(player.call("current_state"), &"grind")


func test_missed_authored_hop_still_allows_reachable_wall_attach() -> void:
	var setup := _new_authored_missed_hop_setup()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var wall_segment: Node3D = setup["wall_segment"]
	var strip := wall_segment.get_node("LeftStrip") as Path3D
	var sample: TraversalSample = strip.call("sample_at_distance", 4.0)
	assert_not_null(sample)
	if sample == null:
		return
	player.global_position = (
		sample.position
		+ sample.normal * _wall_run.surface_stick_distance_m
	)
	player.velocity = sample.tangent * _wall_run.run_speed_mps

	player.call("_try_automatic_wall_attach", SCENARIO_START_S + 0.03)

	assert_eq(player.call("current_state"), &"wall_run")
	assert_eq(player.get("_active_wall_strip"), strip)


func test_missed_authored_hop_still_allows_reachable_swing_catch() -> void:
	var setup := _new_authored_missed_hop_setup()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var swing_segment: Node3D = setup["swing_segment"]
	var anchor := swing_segment.get_node("FirstAnchor") as Node3D
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = (
		anchor.global_basis
		* Vector3.FORWARD
		* _swing.minimum_catch_speed_mps
	)

	player.call("_try_automatic_swing_catch", SCENARIO_START_S + 0.03)

	assert_eq(player.call("current_state"), &"swing")
	assert_eq(player.get("_active_swing_anchor"), anchor)


func test_missed_authored_hop_still_allows_third_authored_rail_attach() -> void:
	var setup := _new_authored_missed_hop_setup()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var third_rail: Path3D = setup["third_rail"]
	var sample: TraversalSample = third_rail.call(
		"sample_at_distance",
		MISSED_HOP_START_DISTANCE_M
	)
	assert_not_null(sample)
	if sample == null:
		return
	player.global_position = sample.position
	player.velocity = sample.tangent * _grind.speed_mps

	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([sample.position]),
		SCENARIO_START_S + 0.03
	))
	assert_eq(player.call("current_state"), &"grind")
	assert_eq(player.get("_active_rail"), third_rail)


func test_missed_authored_hop_keeps_departed_rail_blocked() -> void:
	var setup := _new_authored_missed_hop_setup()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var departed_rail: Path3D = setup["departed_rail"]
	var sample: TraversalSample = departed_rail.call(
		"sample_at_distance",
		MISSED_HOP_START_DISTANCE_M
	)
	assert_not_null(sample)
	if sample == null:
		return
	player.global_position = sample.position
	player.velocity = sample.tangent * _grind.speed_mps

	assert_false(player.call(
		"try_rail_attach",
		PackedVector3Array([sample.position]),
		SCENARIO_START_S + 0.03
	))
	assert_eq(player.call("current_state"), &"airborne")
	assert_null(player.get("_active_rail"))
	assert_eq(player.get("_rail_attach_blocked"), departed_rail)


func test_grind_segment_has_three_symmetric_noncolliding_rails() -> void:
	var packed: PackedScene = load(GRIND_SEGMENT_PATH)
	assert_not_null(packed, "the grind graybox segment must exist")
	if packed == null:
		return
	var segment := packed.instantiate()
	add_child_autofree(segment)
	var rails: Array[Node] = []
	for node: Node in segment.find_children("*", "", true, false):
		if node.has_method("samples") and node.has_method("parallel_neighbor"):
			rails.append(node)

	assert_eq(rails.size(), 3)
	for rail: Node in rails:
		assert_true(
			rail.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"rail visuals must not collide with the player"
		)
		for direction: int in [-1, 1]:
			var neighbour: Node = rail.call("parallel_neighbor", direction)
			if neighbour != null:
				assert_eq(
					neighbour.call("parallel_neighbor", -direction),
					rail,
					"parallel-neighbour links must be symmetric"
				)
	assert_not_null(segment.find_child("LandingPad", true, false))
	var grind_region: Node = segment.find_child("GrindCameraRegion", true, false)
	assert_not_null(grind_region)
	if grind_region != null:
		assert_eq(grind_region.get("camera_mode"), &"grind")


func _new_fsm() -> RefCounted:
	var script: Script = load(FSM_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


func _new_buffer() -> InputIntentBuffer:
	var script: Script = load(BUFFER_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


func _press(buffer: InputIntentBuffer, action: StringName, timestamp_s: float) -> void:
	buffer.push(InputIntent.button(action, true, timestamp_s, &"test"))


func _release(
	buffer: InputIntentBuffer,
	action: StringName,
	timestamp_s: float
) -> void:
	buffer.push(InputIntent.button(action, false, timestamp_s, &"test"))


func _new_rail(
	rail_name: StringName,
	origin: Vector3,
	local_end: Vector3
) -> Path3D:
	var script: Script = load(RAIL_SCRIPT_PATH)
	assert_not_null(script, "TraversalRail implementation must exist")
	if script == null:
		return null
	var rail := script.new() as Path3D
	rail.name = rail_name
	rail.position = origin
	rail.set("camera_tuning", _camera)
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(local_end)
	rail.curve = curve
	return rail


func _new_controller_with_rails(rails: Array) -> Dictionary:
	var holder := Node3D.new()
	for rail: Node in rails:
		if rail == null:
			holder.free()
			return {}
		holder.add_child(rail)
	return _new_controller_with_rail_root(holder)


func _new_controller_with_rail_root(rail_root: Node3D) -> Dictionary:
	add_child_autofree(rail_root)
	var packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(packed)
	if packed == null:
		return {}
	var player := packed.instantiate() as CharacterBody3D
	add_child_autofree(player)
	var buffer := InputIntentBuffer.new()
	player.call(
		"configure",
		_catalog.move,
		_catalog.input,
		_catalog.depth,
		_catalog.wall_run,
		_catalog.grind,
		_catalog.swing,
		buffer
	)
	return {
		"player": player,
		"buffer": buffer,
	}


func _new_authored_missed_hop_setup() -> Dictionary:
	var grind_packed: PackedScene = load(GRIND_SEGMENT_PATH)
	var wall_packed: PackedScene = load(WALL_SEGMENT_PATH)
	var swing_packed: PackedScene = load(SWING_SEGMENT_PATH)
	var player_packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(grind_packed)
	assert_not_null(wall_packed)
	assert_not_null(swing_packed)
	assert_not_null(player_packed)
	if (
		grind_packed == null
		or wall_packed == null
		or swing_packed == null
		or player_packed == null
	):
		return {}

	var grind_segment := grind_packed.instantiate() as Node3D
	var wall_segment := wall_packed.instantiate() as Node3D
	var swing_segment := swing_packed.instantiate() as Node3D
	var player := player_packed.instantiate() as CharacterBody3D
	add_child_autofree(grind_segment)
	add_child_autofree(wall_segment)
	add_child_autofree(swing_segment)
	add_child_autofree(player)
	var buffer := InputIntentBuffer.new()
	player.call(
		"configure",
		_catalog.move,
		_catalog.input,
		_catalog.depth,
		_catalog.wall_run,
		_catalog.grind,
		_catalog.swing,
		buffer
	)

	var departed_rail := grind_segment.get_node("CenterRail") as Path3D
	var target_rail := grind_segment.get_node("RightRail") as Path3D
	var third_rail := grind_segment.get_node("LeftRail") as Path3D
	var start_sample: TraversalSample = departed_rail.call(
		"sample_at_distance",
		MISSED_HOP_ENTRY_DISTANCE_M
	)
	assert_not_null(start_sample)
	if start_sample == null:
		return {}
	player.global_position = start_sample.position
	player.velocity = start_sample.tangent * _grind.speed_mps
	assert_true(player.call(
		"try_rail_attach",
		PackedVector3Array([start_sample.position]),
		SCENARIO_START_S
	))
	assert_almost_eq(
		player.get("_active_rail_distance_m"),
		MISSED_HOP_START_DISTANCE_M,
		0.0001
	)
	buffer.push(InputIntent.move(
		Vector2.RIGHT,
		SCENARIO_START_S + 0.01,
		&"test"
	))
	_press(buffer, &"jump", SCENARIO_START_S + 0.01)

	var hop: RefCounted = player.call(
		"advance_logic",
		SCENARIO_START_S + 0.01,
		false,
		0.0,
		Vector3.FORWARD
	)
	assert_eq(hop.get("impulse"), &"rail_hop")
	assert_eq(player.call("current_state"), &"airborne")
	assert_eq(player.get("_rail_hop_target"), target_rail)
	assert_eq(player.get("_rail_attach_blocked"), departed_rail)
	assert_null(player.get("_active_rail"))

	var missed_arc := DepthPrediction.trajectory_points(
		player.global_position,
		player.velocity,
		false,
		_move,
		_catalog.depth
	)
	assert_eq(
		DepthPrediction.first_rail_contact_index(
			missed_arc,
			target_rail.call("samples"),
			_grind.attach_snap_m
		),
		-1,
		"the authored neighbour must be beyond this late hop's reach"
	)
	player.call("_try_automatic_rail_attach", SCENARIO_START_S + 0.02)
	assert_eq(player.call("current_state"), &"airborne")
	assert_null(player.get("_active_rail"))

	return {
		"player": player,
		"wall_segment": wall_segment,
		"swing_segment": swing_segment,
		"departed_rail": departed_rail,
		"target_rail": target_rail,
		"third_rail": third_rail,
	}
