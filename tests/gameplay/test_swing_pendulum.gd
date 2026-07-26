extends GutTest

const PENDULUM_SCRIPT_PATH := "res://src/gameplay/traversal/swing_pendulum.gd"
const ANCHOR_SCRIPT_PATH := "res://src/gameplay/traversal/swing_anchor.gd"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"
const SWING_SEGMENT_PATH := "res://scenes/segments/seg_swing_chain.tscn"
const FSM_SCRIPT_PATH := "res://src/gameplay/player/player_state_machine.gd"
const BUFFER_SCRIPT_PATH := "res://src/gameplay/input/input_intent_buffer.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const EXPECTED_MINIMUM_CATCH_SPEED_MPS := 6.5
const WORST_CATCH_SWING_FRAMES := 15
const ASSISTED_EARLY_RELEASE_FRAMES := 10
const ASSISTED_LATE_RELEASE_FRAMES := 20
const MAX_ESCAPE_FRAMES := 60

var _catalog: GameplayTuning
var _move: MoveTuning
var _input: InputTuning
var _swing: SwingTuning


func before_all() -> void:
	_catalog = load(TUNING_PATH)
	assert_not_null(_catalog)
	if _catalog != null:
		_move = _catalog.move
		_input = _catalog.input
		_swing = _catalog.swing


func test_pendulum_damping_bleeds_energy_without_collapsing() -> void:
	var pendulum: Script = _pendulum_script()
	if pendulum == null:
		return
	var state := {
		"angle_rad": 0.6,
		"angular_velocity": 0.0,
	}
	var start_energy := _pendulum_energy(
		state["angle_rad"],
		state["angular_velocity"]
	)

	for _index in 600:
		state = pendulum.call(
			"step",
			state["angle_rad"],
			state["angular_velocity"],
			1.0 / 60.0,
			_swing,
			_move.gravity_mps2
		)

	var final_energy := _pendulum_energy(
		state["angle_rad"],
		state["angular_velocity"]
	)
	assert_lt(final_energy, start_energy, "damping must bleed energy")
	assert_gt(
		final_energy,
		start_energy * 0.5,
		"a 10s swing must not collapse"
	)


func test_pendulum_step_is_stable_across_physics_frame_rates() -> void:
	var pendulum: Script = _pendulum_script()
	if pendulum == null:
		return
	var at_sixty := _integrate_pendulum(
		pendulum,
		120,
		1.0 / 60.0
	)
	var at_one_twenty := _integrate_pendulum(
		pendulum,
		240,
		1.0 / 120.0
	)

	assert_almost_eq(
		at_sixty["angle_rad"],
		at_one_twenty["angle_rad"],
		0.02
	)
	assert_almost_eq(
		at_sixty["angular_velocity"],
		at_one_twenty["angular_velocity"],
		0.04
	)


func test_pendulum_clamps_tangential_speed_to_tuning() -> void:
	var pendulum: Script = _pendulum_script()
	if pendulum == null:
		return

	var state: Dictionary = pendulum.call(
		"step",
		0.0,
		100.0,
		1.0 / 60.0,
		_swing,
		_move.gravity_mps2
	)

	assert_almost_eq(
		absf(state["angular_velocity"]) * _swing.rope_length_m,
		_swing.maximum_speed_mps,
		0.0001
	)


func test_release_velocity_is_tangential_and_includes_boost() -> void:
	var pendulum: Script = _pendulum_script()
	if pendulum == null:
		return
	var angle_rad := 0.5
	var angular_velocity := 1.2

	var velocity: Vector3 = pendulum.call(
		"release_velocity",
		angle_rad,
		angular_velocity,
		_swing
	)
	var radial_direction := (
		Vector3.DOWN * cos(angle_rad)
		+ Vector3.FORWARD * sin(angle_rad)
	).normalized()
	var expected_speed := (
		angular_velocity * _swing.rope_length_m
		+ _swing.release_boost_mps
	)

	assert_almost_eq(
		velocity.dot(radial_direction),
		0.0,
		0.0001,
		"release velocity must be tangent to the rope arc"
	)
	assert_almost_eq(velocity.length(), expected_speed, 0.0001)


func test_release_at_bottom_is_horizontal_in_both_directions() -> void:
	var pendulum: Script = _pendulum_script()
	if pendulum == null:
		return
	var forward_velocity: Vector3 = pendulum.call(
		"release_velocity",
		0.0,
		1.2,
		_swing
	)
	var backward_velocity: Vector3 = pendulum.call(
		"release_velocity",
		0.0,
		-1.2,
		_swing
	)

	assert_almost_eq(forward_velocity.y, 0.0, 0.0001)
	assert_gt(forward_velocity.dot(Vector3.FORWARD), 0.0)
	assert_almost_eq(backward_velocity.y, 0.0, 0.0001)
	assert_gt(backward_velocity.dot(Vector3.BACK), 0.0)


func test_anchor_places_the_hanging_handle_at_rope_length() -> void:
	var anchor: Node3D = _new_anchor(
		&"LengthAnchor",
		Vector3(2.0, 6.0, -3.0)
	)
	if anchor == null:
		return
	add_child_autofree(anchor)

	var catch_position: Vector3 = anchor.call(
		"catch_position",
		_swing
	)

	assert_eq(catch_position, Vector3(2.0, 2.0, -3.0))
	assert_almost_eq(
		catch_position.distance_to(anchor.global_position),
		_swing.rope_length_m,
		0.0001
	)


func test_game_boot_and_live_tuning_refresh_swing_anchors() -> void:
	var packed: PackedScene = load(GAME_SCENE_PATH)
	assert_not_null(packed)
	if packed == null:
		return
	var game := packed.instantiate()
	var anchor: Node3D = _new_anchor(
		&"RuntimeAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	if anchor == null:
		game.free()
		return
	var sentinel: SwingTuning = _swing.duplicate()
	sentinel.rope_length_m = 3.5
	anchor.set("swing_tuning", sentinel)
	game.add_child(anchor)
	add_child_autofree(game)
	await wait_process_frames(1)
	var catalog: GameplayTuning = game.get(
		"tuning_service"
	).get("catalog")

	assert_eq(anchor.get("swing_tuning"), catalog.swing)

	var replacement: SwingTuning = catalog.swing.duplicate()
	replacement.rope_length_m = 3.75
	catalog.swing = replacement
	game.call("_on_tuning_changed", &"test")

	assert_eq(anchor.get("swing_tuning"), replacement)


func test_controller_rejects_a_remote_swing_catch() -> void:
	var anchor: Node3D = _new_anchor(
		&"RemoteAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	var setup := _new_controller_with_anchor(anchor)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_swing_catch"):
		assert_true(false, "controller must expose deterministic swing catch")
		return
	var catch_position: Vector3 = anchor.call(
		"catch_position",
		_swing
	)
	player.global_position = (
		catch_position
		+ Vector3.RIGHT * (_swing.catch_radius_m + 0.01)
	)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps

	assert_false(player.call("try_swing_catch", anchor, 2.0))
	assert_eq(player.call("current_state"), &"airborne")


func test_physics_loop_auto_catches_the_hanging_handle() -> void:
	var anchor: Node3D = _new_anchor(
		&"AutomaticAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	var setup := _new_controller_with_anchor(anchor)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps

	await wait_physics_frames(1)

	assert_eq(player.call("current_state"), &"swing")
	assert_eq(player.get("_active_swing_anchor"), anchor)


func test_authored_rope_refuses_a_zero_speed_catch() -> void:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	player.global_position = first_anchor.call("catch_position", _swing)
	player.velocity = Vector3.ZERO

	assert_false(
		player.call("try_swing_catch", first_anchor, 2.6),
		"a motionless player must fall past instead of entering a fixed point"
	)
	assert_eq(player.call("current_state"), &"airborne")


func test_authored_rope_catch_uses_the_minimum_speed_boundary() -> void:
	assert_almost_eq(
		_swing.minimum_catch_speed_mps,
		EXPECTED_MINIMUM_CATCH_SPEED_MPS,
		0.0001,
		"the escape-tested boundary must come from live tuning"
	)
	var below_setup := _new_authored_swing_setup()
	var boundary_setup := _new_authored_swing_setup()
	if below_setup.is_empty() or boundary_setup.is_empty():
		return
	var below_segment: Node3D = below_setup["segment"]
	var below_player: CharacterBody3D = below_setup["player"]
	var below_anchor := below_segment.get_node("FirstAnchor") as Node3D
	below_player.global_position = below_anchor.call(
		"catch_position",
		_swing
	)
	below_player.velocity = (
		Vector3.FORWARD
		* (_swing.minimum_catch_speed_mps - 0.01)
	)

	assert_false(
		below_player.call("try_swing_catch", below_anchor, 2.7),
		"a sub-boundary arrival cannot enter an inescapable swing"
	)

	var boundary_segment: Node3D = boundary_setup["segment"]
	var boundary_player: CharacterBody3D = boundary_setup["player"]
	var boundary_anchor := boundary_segment.get_node(
		"FirstAnchor"
	) as Node3D
	boundary_player.global_position = boundary_anchor.call(
		"catch_position",
		_swing
	)
	boundary_player.velocity = (
		Vector3.FORWARD * _swing.minimum_catch_speed_mps
	)

	assert_true(
		boundary_player.call(
			"try_swing_catch",
			boundary_anchor,
			2.7
		),
		"the exact authored boundary must remain inclusive"
	)
	assert_eq(boundary_player.call("current_state"), &"swing")


func test_slowest_authored_catch_reaches_the_next_real_anchor() -> void:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	var second_anchor := segment.get_node("SecondAnchor") as Node3D
	player.global_position = first_anchor.call("catch_position", _swing)
	player.velocity = (
		Vector3.FORWARD * _swing.minimum_catch_speed_mps
	)
	var caught_s := float(Time.get_ticks_usec()) / 1_000_000.0
	assert_true(player.call("try_swing_catch", first_anchor, caught_s))

	await wait_physics_frames(WORST_CATCH_SWING_FRAMES)

	var release_s := float(Time.get_ticks_usec()) / 1_000_000.0
	_press(buffer, &"jump", release_s)
	var reached_next_anchor := false
	for _frame: int in range(MAX_ESCAPE_FRAMES):
		await wait_physics_frames(1)
		if player.get("_active_swing_anchor") == second_anchor:
			reached_next_anchor = true
			break
		if player.call("is_respawning"):
			break

	assert_true(
		reached_next_anchor,
		"the slowest permitted catch must reach SecondAnchor in the real chain"
	)


func test_first_to_second_rope_accepts_an_early_human_release() -> void:
	assert_true(
		await _first_transfer_catches_after(
			ASSISTED_EARLY_RELEASE_FRAMES
		),
		"the second rope needs release tolerance before the reference timing"
	)


func test_first_to_second_rope_accepts_a_late_human_release() -> void:
	assert_true(
		await _first_transfer_catches_after(
			ASSISTED_LATE_RELEASE_FRAMES
		),
		"the second rope needs release tolerance after the reference timing"
	)


func test_chain_transfer_assist_restores_a_safe_escape_speed() -> void:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	var second_anchor := segment.get_node("SecondAnchor") as Node3D
	var assisted_offset_m := (
		_swing.catch_radius_m
		+ _swing.transfer_catch_radius_m
	) * 0.5
	player.global_position = (
		second_anchor.call("catch_position", _swing)
		+ Vector3.RIGHT * assisted_offset_m
	)
	player.velocity = (
		Vector3.FORWARD
		* _swing.transfer_minimum_catch_speed_mps
	)
	player.set("_swing_attach_blocked", first_anchor)

	assert_true(
		player.call("try_swing_catch", second_anchor, 2.75),
		"a real chain transfer must use its authored spatial and speed assist"
	)
	assert_almost_eq(
		absf(player.get("_swing_angular_velocity"))
		* _swing.rope_length_m,
		_swing.minimum_catch_speed_mps,
		0.0001,
		"an assisted catch must leave enough momentum for the next rope"
	)


func test_chain_transfer_still_rejects_below_its_assist_floor() -> void:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	var second_anchor := segment.get_node("SecondAnchor") as Node3D
	player.global_position = second_anchor.call("catch_position", _swing)
	player.velocity = (
		Vector3.FORWARD
		* (_swing.transfer_minimum_catch_speed_mps - 0.01)
	)
	player.set("_swing_attach_blocked", first_anchor)

	assert_false(
		player.call("try_swing_catch", second_anchor, 2.76),
		"transfer forgiveness must remain bounded by live tuning"
	)


func test_a_caught_rope_never_releases_with_zero_velocity() -> void:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	player.global_position = first_anchor.call("catch_position", _swing)
	player.velocity = (
		Vector3.FORWARD * _swing.minimum_catch_speed_mps
	)
	assert_true(player.call("try_swing_catch", first_anchor, 2.8))
	player.set("_swing_angle_rad", 0.0)
	player.set("_swing_angular_velocity", 0.0)
	_press(buffer, &"jump", 2.9)

	var decision: RefCounted = player.call(
		"advance_logic",
		2.9,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"swing_release")
	assert_false(
		player.velocity.is_zero_approx(),
		"an already-caught rope must always provide a release direction"
	)
	assert_gt(player.velocity.dot(Vector3.FORWARD), 0.0)


func test_real_physics_keeps_the_player_at_rope_length() -> void:
	var anchor: Node3D = _new_anchor(
		&"PhysicsAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	var setup := _new_controller_with_anchor(anchor)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_swing_catch"):
		assert_true(false, "controller must expose deterministic swing catch")
		return
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps
	assert_true(player.call("try_swing_catch", anchor, 3.0))

	await wait_physics_frames(3)

	assert_eq(player.call("current_state"), &"swing")
	assert_almost_eq(
		player.global_position.distance_to(anchor.global_position),
		_swing.rope_length_m,
		0.0001
	)


func test_buffered_jump_releases_at_the_current_arc_point() -> void:
	var pendulum: Script = _pendulum_script()
	var anchor: Node3D = _new_anchor(
		&"ReleaseAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	var setup := _new_controller_with_anchor(anchor)
	if pendulum == null or setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	if not player.has_method("try_swing_catch"):
		assert_true(false, "controller must expose deterministic swing catch")
		return
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps
	assert_true(player.call("try_swing_catch", anchor, 4.0))
	player.call(
		"advance_logic",
		4.1,
		false,
		0.1,
		Vector3.FORWARD
	)
	var release_position := player.global_position
	var local_velocity: Vector3 = pendulum.call(
		"release_velocity",
		player.get("_swing_angle_rad"),
		player.get("_swing_angular_velocity"),
		_swing
	)
	var expected_velocity: Vector3 = anchor.call(
		"world_velocity",
		local_velocity
	)
	var release_s := 4.2
	_press(
		buffer,
		&"jump",
		release_s - _input.jump_buffer_s * 0.5
	)

	var decision: RefCounted = player.call(
		"advance_logic",
		release_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"swing_release")
	assert_eq(decision.get("state"), &"airborne")
	assert_eq(player.global_position, release_position)
	assert_eq(player.velocity, expected_velocity)
	assert_null(player.get("_active_swing_anchor"))
	assert_eq(player.get("_swing_attach_blocked"), anchor)
	assert_eq(
		player.motion_mode,
		CharacterBody3D.MOTION_MODE_GROUNDED
	)


func test_swing_release_cannot_immediately_recapture_the_same_anchor() -> void:
	var anchor: Node3D = _new_anchor(
		&"BlockedAnchor",
		Vector3(0.0, 5.0, 0.0)
	)
	var setup := _new_controller_with_anchor(anchor)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	if not player.has_method("try_swing_catch"):
		assert_true(false, "controller must expose deterministic swing catch")
		return
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps
	assert_true(player.call("try_swing_catch", anchor, 5.0))
	_press(buffer, &"jump", 5.01)
	player.call(
		"advance_logic",
		5.01,
		false,
		0.0,
		Vector3.FORWARD
	)
	player.global_position = anchor.call("catch_position", _swing)
	player.velocity = Vector3.FORWARD * _move.run_speed_mps

	assert_false(player.call("try_swing_catch", anchor, 5.02))
	assert_eq(player.call("current_state"), &"airborne")


func test_swing_state_consumes_the_jump_buffer_as_release() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	if not fsm.has_method("enter_swing"):
		assert_true(false, "state machine must expose swing entry")
		return
	fsm.call("enter_swing", 6.0)
	_press(
		buffer,
		&"jump",
		6.1 - _input.jump_buffer_s * 0.5
	)

	var decision: RefCounted = fsm.call(
		"step",
		6.1,
		false,
		0.0,
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(decision.get("impulse"), &"swing_release")
	assert_eq(decision.get("state"), &"airborne")


func test_swing_segment_has_three_noncolliding_anchors_over_a_pit() -> void:
	assert_true(
		ResourceLoader.exists(SWING_SEGMENT_PATH),
		"the swing-chain graybox segment must exist"
	)
	if not ResourceLoader.exists(SWING_SEGMENT_PATH):
		return
	var packed: PackedScene = load(SWING_SEGMENT_PATH)
	assert_not_null(packed)
	if packed == null:
		return
	var segment := packed.instantiate()
	add_child_autofree(segment)
	var anchors: Array[Node] = []
	for node: Node in segment.find_children("*", "", true, false):
		if node.has_method("catch_position") and node.has_method("position_for"):
			anchors.append(node)

	assert_eq(anchors.size(), 3)
	var catch_positions: Array[Vector3] = []
	for anchor: Node in anchors:
		assert_true(
			anchor.find_children(
				"*",
				"CollisionObject3D",
				true,
				false
			).is_empty(),
			"rope and handle visuals must not collide with the player"
		)
		assert_almost_eq(
			anchor.call(
				"catch_position",
				_swing
			).distance_to((anchor as Node3D).global_position),
			_swing.rope_length_m,
			0.0001
		)
		catch_positions.append(anchor.call("catch_position", _swing))
	catch_positions.sort_custom(
		func(first: Vector3, second: Vector3) -> bool:
			return first.z > second.z
	)
	for index in range(catch_positions.size() - 1):
		assert_almost_eq(
			catch_positions[index].distance_to(
				catch_positions[index + 1]
			),
			_swing.rope_length_m,
			0.0001,
			"default-entry momentum must reach the next handle"
		)
	assert_not_null(segment.find_child("PitFloor", true, false))
	assert_not_null(segment.find_child("LandingPad", true, false))
	var camera_region: Node = segment.find_child(
		"SwingCameraRegion",
		true,
		false
	)
	assert_not_null(camera_region)
	if camera_region != null:
		assert_eq(camera_region.get("camera_mode"), &"swing")


func _pendulum_script() -> Script:
	assert_true(
		ResourceLoader.exists(PENDULUM_SCRIPT_PATH),
		"SwingPendulum implementation must exist"
	)
	if not ResourceLoader.exists(PENDULUM_SCRIPT_PATH):
		return null
	var script: Script = load(PENDULUM_SCRIPT_PATH)
	assert_not_null(script)
	return script


func _new_anchor(
	anchor_name: StringName,
	anchor_position: Vector3
) -> Node3D:
	assert_true(
		ResourceLoader.exists(ANCHOR_SCRIPT_PATH),
		"SwingAnchor implementation must exist"
	)
	if not ResourceLoader.exists(ANCHOR_SCRIPT_PATH):
		return null
	var script: Script = load(ANCHOR_SCRIPT_PATH)
	assert_not_null(script)
	if script == null:
		return null
	var anchor := script.new() as Node3D
	anchor.name = anchor_name
	anchor.position = anchor_position
	anchor.set("swing_tuning", _swing)
	return anchor


func _new_controller_with_anchor(anchor: Node3D) -> Dictionary:
	if anchor == null:
		return {}
	var anchor_root := Node3D.new()
	anchor_root.add_child(anchor)
	add_child_autofree(anchor_root)
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
		buffer,
		null,
		false,
		_catalog.hog
	)
	return {
		"player": player,
		"buffer": buffer,
	}


func _new_authored_swing_setup() -> Dictionary:
	var segment_packed: PackedScene = load(SWING_SEGMENT_PATH)
	var player_packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(segment_packed)
	assert_not_null(player_packed)
	if segment_packed == null or player_packed == null:
		return {}
	var segment := segment_packed.instantiate() as Node3D
	var player := player_packed.instantiate() as CharacterBody3D
	add_child_autofree(segment)
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
		buffer,
		null,
		false,
		_catalog.hog
	)
	return {
		"segment": segment,
		"player": player,
		"buffer": buffer,
	}


func _new_fsm() -> RefCounted:
	var script: Script = load(FSM_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


func _first_transfer_catches_after(release_frames: int) -> bool:
	var setup := _new_authored_swing_setup()
	if setup.is_empty():
		return false
	var segment: Node3D = setup["segment"]
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var first_anchor := segment.get_node("FirstAnchor") as Node3D
	var second_anchor := segment.get_node("SecondAnchor") as Node3D
	player.global_position = first_anchor.call("catch_position", _swing)
	player.velocity = (
		Vector3.FORWARD * _swing.minimum_catch_speed_mps
	)
	var caught_s := float(Time.get_ticks_usec()) / 1_000_000.0
	if not player.call("try_swing_catch", first_anchor, caught_s):
		return false

	await wait_physics_frames(release_frames)

	var release_s := float(Time.get_ticks_usec()) / 1_000_000.0
	_press(buffer, &"jump", release_s)
	for _frame: int in range(MAX_ESCAPE_FRAMES):
		await wait_physics_frames(1)
		if player.get("_active_swing_anchor") == second_anchor:
			return true
		if player.call("is_respawning"):
			return false
	return false


func _new_buffer() -> InputIntentBuffer:
	var script: Script = load(BUFFER_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


func _press(
	buffer: InputIntentBuffer,
	action: StringName,
	timestamp_s: float
) -> void:
	buffer.push(InputIntent.button(action, true, timestamp_s, &"test"))


func _integrate_pendulum(
	pendulum: Script,
	step_count: int,
	delta_s: float
) -> Dictionary:
	var state := {
		"angle_rad": 0.6,
		"angular_velocity": 0.0,
	}
	for _index in step_count:
		state = pendulum.call(
			"step",
			state["angle_rad"],
			state["angular_velocity"],
			delta_s,
			_swing,
			_move.gravity_mps2
		)
	return state


func _pendulum_energy(
	angle_rad: float,
	angular_velocity: float
) -> float:
	var tangential_speed := (
		angular_velocity * _swing.rope_length_m
	)
	return (
		_move.gravity_mps2
		* _swing.gravity_scale
		* _swing.rope_length_m
		* (1.0 - cos(angle_rad))
		+ 0.5 * tangential_speed * tangential_speed
	)
