extends GutTest

const STRIP_SCRIPT_PATH := "res://src/gameplay/traversal/wall_run_strip.gd"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const WALL_RUN_SEGMENT_PATH := "res://scenes/segments/seg_wall_run_canyon.tscn"
const FSM_SCRIPT_PATH := "res://src/gameplay/player/player_state_machine.gd"
const BUFFER_SCRIPT_PATH := "res://src/gameplay/input/input_intent_buffer.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const NONZERO_ATTACH_DISTANCE_M := 4.0
const TEST_TOLERANCE := 0.0001
const LANDING_PAD_MIN_Z := -32.0
const LANDING_PAD_MAX_Z := -24.0
const MAX_LANDING_FRAMES := 300

var _catalog: GameplayTuning
var _move: MoveTuning
var _input: InputTuning
var _wall_run: WallRunTuning


func before_all() -> void:
	_catalog = load(TUNING_PATH)
	assert_not_null(_catalog)
	if _catalog != null:
		_move = _catalog.move
		_input = _catalog.input
		_wall_run = _catalog.wall_run


func test_wall_run_strip_samples_the_closest_world_space_point() -> void:
	var strip: Path3D = _new_strip(
		&"SampleStrip",
		Vector3(2.0, 3.0, 4.0),
		Vector3(0.0, 0.0, -10.0),
		Vector3.RIGHT
	)
	if strip == null:
		return
	add_child_autofree(strip)

	var sample: RefCounted = strip.call(
		"sample_at",
		Vector3(2.4, 3.0, -1.0)
	)

	assert_not_null(sample)
	if sample == null:
		return
	assert_eq(sample.get("position"), Vector3(2.0, 3.0, -1.0))
	assert_eq(sample.get("tangent"), Vector3.FORWARD)
	assert_eq(sample.get("normal"), Vector3.RIGHT)
	assert_almost_eq(sample.get("distance_along_m"), 5.0, 0.0001)


func test_controller_wall_attach_obeys_the_authored_cone() -> void:
	var strip: Path3D = _new_strip(
		&"ConeStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD.rotated(
		Vector3.UP,
		deg_to_rad(_wall_run.attach_cone_degrees + 1.0)
	) * 6.0

	assert_false(player.call("try_wall_attach", strip, 2.0))
	assert_eq(player.call("current_state"), &"airborne")

	player.velocity = Vector3.FORWARD.rotated(
		Vector3.UP,
		deg_to_rad(_wall_run.attach_cone_degrees - 1.0)
	) * 6.0
	assert_true(player.call("try_wall_attach", strip, 2.1))
	assert_eq(player.call("current_state"), &"wall_run")


func test_matching_heading_does_not_attach_without_wall_contact() -> void:
	var strip: Path3D = _new_strip(
		&"ContactStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m * 3.0,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0

	assert_false(player.call("try_wall_attach", strip, 2.2))
	assert_eq(player.call("current_state"), &"airborne")


func test_physics_loop_auto_attaches_on_authored_contact() -> void:
	var strip: Path3D = _new_strip(
		&"AutomaticStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0

	await wait_physics_frames(1)

	assert_eq(player.call("current_state"), &"wall_run")
	assert_eq(player.get("_active_wall_strip"), strip)


func test_wall_attach_snaps_to_the_authored_surface_distance() -> void:
	var strip: Path3D = _new_strip(
		&"SnapStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m * 0.5,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0

	assert_true(player.call("try_wall_attach", strip, 3.0))

	var sample: RefCounted = strip.call("sample_at", player.global_position)
	assert_not_null(sample)
	if sample == null:
		return
	var normal: Vector3 = sample.get("normal")
	var surface_position: Vector3 = sample.get("position")
	assert_almost_eq(
		(player.global_position - surface_position).dot(normal),
		_wall_run.surface_stick_distance_m,
		0.0001
	)
	assert_eq(
		player.motion_mode,
		CharacterBody3D.MOTION_MODE_FLOATING
	)


func test_wall_run_expires_at_the_exact_maximum_duration() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: InputIntentBuffer = _new_buffer()
	if fsm == null or buffer == null:
		return
	if not fsm.has_method("enter_wall_run"):
		assert_true(false, "state machine must own the wall-run timeout")
		return
	var entered_s := 10.0
	var epsilon_s := 0.001
	fsm.call(
		"enter_wall_run",
		entered_s,
		_wall_run.maximum_duration_s
	)

	var during: RefCounted = fsm.call(
		"step",
		entered_s + _wall_run.maximum_duration_s - epsilon_s,
		false,
		0.0,
		buffer,
		_move,
		_input,
		false
	)
	var at_boundary: RefCounted = fsm.call(
		"step",
		entered_s + _wall_run.maximum_duration_s,
		false,
		0.0,
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(during.get("state"), &"wall_run")
	assert_eq(
		at_boundary.get("state"),
		&"airborne",
		"wall-run must expire at maximum_duration_s"
	)


func test_expiry_frame_jump_detaches_from_a_nonzero_strip_distance() -> void:
	var strip: Path3D = _new_strip(
		&"ExpiryJumpStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var entered_s := 20.0
	var sample := _attach_at_distance(
		player,
		strip,
		NONZERO_ATTACH_DISTANCE_M,
		entered_s
	)
	if sample == null:
		return
	var expiry_s := entered_s + _wall_run.maximum_duration_s
	_press(
		buffer,
		&"jump",
		expiry_s - _input.jump_buffer_s * 0.5
	)

	var decision: RefCounted = player.call(
		"advance_logic",
		expiry_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"wall_detach")
	assert_ne(decision.get("impulse"), &"double_jump")
	assert_eq(decision.get("state"), &"airborne")


func test_strip_end_exits_with_tuned_velocity_from_a_nonzero_attach() -> void:
	var strip: Path3D = _new_strip(
		&"EndStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var entered_s := 30.0
	var attached_sample := _attach_at_distance(
		player,
		strip,
		NONZERO_ATTACH_DISTANCE_M,
		entered_s
	)
	if attached_sample == null:
		return
	var near_end_sample: TraversalSample = strip.call(
		"sample_at_distance",
		strip.call("length_m") - _wall_run.run_speed_mps * 0.05
	)
	assert_not_null(near_end_sample)
	if near_end_sample == null:
		return
	player.global_position = (
		near_end_sample.position
		+ near_end_sample.normal * _wall_run.surface_stick_distance_m
	)

	var decision: RefCounted = player.call(
		"advance_logic",
		entered_s + 0.1,
		false,
		0.1,
		Vector3.FORWARD
	)

	assert_eq(
		decision.get("state"),
		&"airborne",
		"the run must end at the authored strip end, not its infinite extension"
	)
	assert_null(player.get("_active_wall_strip"))
	assert_almost_eq(
		player.velocity.dot(near_end_sample.tangent),
		_wall_run.run_speed_mps,
		TEST_TOLERANCE
	)
	assert_almost_eq(
		player.velocity.dot(near_end_sample.normal),
		_wall_run.detach_outward_speed_mps,
		TEST_TOLERANCE
	)
	assert_almost_eq(
		player.velocity.y,
		JumpKinematics.upward_speed_for_height(
			_wall_run.detach_height_m,
			_move
		),
		TEST_TOLERANCE
	)


func test_buffered_jump_detaches_on_the_tuned_outward_arc() -> void:
	var strip: Path3D = _new_strip(
		&"DetachStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0
	assert_true(player.call("try_wall_attach", strip, 4.0))
	var step_s := 4.2
	_press(
		buffer,
		&"jump",
		step_s - _input.jump_buffer_s * 0.5
	)

	var decision: RefCounted = player.call(
		"advance_logic",
		step_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"wall_detach")
	assert_eq(decision.get("state"), &"airborne")
	assert_almost_eq(
		player.velocity.dot(Vector3.RIGHT),
		_wall_run.detach_outward_speed_mps,
		0.0001
	)
	assert_almost_eq(
		player.velocity.dot(Vector3.FORWARD),
		_wall_run.run_speed_mps,
		0.0001
	)
	assert_almost_eq(
		player.velocity.y,
		JumpKinematics.upward_speed_for_height(
			_wall_run.detach_height_m,
			_move
		),
		0.0001
	)
	assert_null(player.get("_active_wall_strip"))
	assert_eq(
		player.motion_mode,
		CharacterBody3D.MOTION_MODE_GROUNDED
	)


func test_wall_run_applies_reduced_gravity_instead_of_full_gravity() -> void:
	var strip: Path3D = _new_strip(
		&"GravityStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0
	assert_true(player.call("try_wall_attach", strip, 5.0))
	var delta_s := 0.25

	var decision: RefCounted = player.call(
		"advance_logic",
		5.0 + delta_s,
		false,
		delta_s,
		Vector3.FORWARD
	)

	assert_eq(decision.get("state"), &"wall_run")
	assert_almost_eq(
		player.velocity.y,
		-_move.gravity_mps2 * _wall_run.gravity_multiplier * delta_s,
		0.0001
	)
	assert_almost_eq(
		Vector2(player.velocity.x, player.velocity.z).length(),
		_wall_run.run_speed_mps,
		0.0001
	)


func test_real_physics_holds_the_wall_distance_while_running() -> void:
	var strip: Path3D = _new_strip(
		&"PhysicsStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0
	assert_true(
		player.call("try_wall_attach", strip, MonotonicClock.now_s())
	)
	var before_z := player.global_position.z

	await wait_physics_frames(2)

	var sample: RefCounted = strip.call("sample_at", player.global_position)
	assert_not_null(sample)
	if sample == null:
		return
	assert_lt(player.global_position.z, before_z)
	assert_eq(player.call("current_state"), &"wall_run")
	assert_almost_eq(
		(
			player.global_position
			- sample.get("position")
		).dot(sample.get("normal")),
		_wall_run.surface_stick_distance_m,
		0.0001
	)


func test_timeout_clears_the_active_strip_and_restores_grounded_motion() -> void:
	var strip: Path3D = _new_strip(
		&"ExpiryStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	var entered_s := 7.0
	var sample := _attach_at_distance(
		player,
		strip,
		NONZERO_ATTACH_DISTANCE_M,
		entered_s
	)
	if sample == null:
		return

	var decision: RefCounted = player.call(
		"advance_logic",
		entered_s + _wall_run.maximum_duration_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("state"), &"airborne")
	assert_eq(decision.get("impulse"), &"wall_detach")
	assert_null(player.get("_active_wall_strip"))
	assert_eq(player.get("_wall_attach_blocked"), strip)
	assert_almost_eq(
		player.velocity.dot(sample.tangent),
		_wall_run.run_speed_mps,
		TEST_TOLERANCE
	)
	assert_almost_eq(
		player.velocity.dot(sample.normal),
		_wall_run.detach_outward_speed_mps,
		TEST_TOLERANCE
	)
	assert_almost_eq(
		player.velocity.y,
		JumpKinematics.upward_speed_for_height(
			_wall_run.detach_height_m,
			_move
		),
		TEST_TOLERANCE
	)
	assert_eq(
		player.motion_mode,
		CharacterBody3D.MOTION_MODE_GROUNDED
	)


func test_mid_strip_attach_reaches_the_authored_landing_pad() -> void:
	var segment_packed: PackedScene = load(WALL_RUN_SEGMENT_PATH)
	var player_packed: PackedScene = load(PLAYER_SCENE_PATH)
	assert_not_null(segment_packed)
	assert_not_null(player_packed)
	if segment_packed == null or player_packed == null:
		return
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
		false
	)
	var strip := segment.get_node("LeftStrip") as Path3D
	var entered_s := MonotonicClock.now_s()
	var sample := _attach_at_distance(
		player,
		strip,
		NONZERO_ATTACH_DISTANCE_M,
		entered_s
	)
	if sample == null:
		return
	var reached_pad := false

	for _frame: int in range(MAX_LANDING_FRAMES):
		await wait_physics_frames(1)
		if (
			player.is_on_floor()
			and player.global_position.z >= LANDING_PAD_MIN_Z
			and player.global_position.z <= LANDING_PAD_MAX_Z
		):
			reached_pad = true
			break
		if player.call("is_respawning"):
			break

	assert_true(
		reached_pad,
		"a real player attaching 4 m along the strip must reach LandingPad"
	)


func test_wall_detach_cannot_immediately_reattach_the_departed_strip() -> void:
	var strip: Path3D = _new_strip(
		&"BlockedStrip",
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -12.0),
		Vector3.RIGHT
	)
	var setup := _new_controller_with_strip(strip)
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var buffer: InputIntentBuffer = setup["buffer"]
	if not player.has_method("try_wall_attach"):
		assert_true(false, "controller must expose deterministic wall attach")
		return
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		0.0
	)
	player.velocity = Vector3.FORWARD * 6.0
	assert_true(player.call("try_wall_attach", strip, 8.0))
	_press(buffer, &"jump", 8.01)
	player.call(
		"advance_logic",
		8.01,
		false,
		0.0,
		Vector3.FORWARD
	)
	player.global_position = Vector3(
		_wall_run.surface_stick_distance_m,
		1.0,
		-1.0
	)
	player.velocity = Vector3.FORWARD * 6.0

	assert_false(player.call("try_wall_attach", strip, 8.02))
	assert_eq(player.call("current_state"), &"airborne")


func test_wall_run_segment_has_two_noncolliding_strips_and_an_exit_pad() -> void:
	assert_true(
		ResourceLoader.exists(WALL_RUN_SEGMENT_PATH),
		"the wall-run graybox segment must exist"
	)
	if not ResourceLoader.exists(WALL_RUN_SEGMENT_PATH):
		return
	var packed: PackedScene = load(WALL_RUN_SEGMENT_PATH)
	assert_not_null(packed)
	if packed == null:
		return
	var segment := packed.instantiate()
	add_child_autofree(segment)
	var strips: Array[Node] = []
	for node: Node in segment.find_children("*", "", true, false):
		if node.has_method("sample_at") and node.has_method("length_m"):
			strips.append(node)

	assert_eq(strips.size(), 2)
	var normals: Array[Vector3] = []
	for strip: Node in strips:
		assert_true(
			strip.find_children(
				"*",
				"CollisionObject3D",
				true,
				false
			).is_empty(),
			"strip visuals must not collide with the player"
		)
		var sample: RefCounted = strip.call(
			"sample_at",
			(strip as Node3D).global_position
		)
		assert_not_null(sample)
		if sample != null:
			normals.append(sample.get("normal"))
	assert_true(normals.has(Vector3.RIGHT))
	assert_true(normals.has(Vector3.LEFT))
	assert_not_null(segment.find_child("LandingPad", true, false))
	assert_not_null(segment.find_child("LeftWall", true, false))
	assert_not_null(segment.find_child("RightWall", true, false))
	var camera_region: Node = segment.find_child(
		"WallRunCameraRegion",
		true,
		false
	)
	assert_not_null(camera_region)
	if camera_region != null:
		assert_eq(camera_region.get("camera_mode"), &"wall_run")


func _new_fsm() -> RefCounted:
	var script: Script = load(FSM_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null


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


func _attach_at_distance(
	player: CharacterBody3D,
	strip: Path3D,
	distance_along_m: float,
	now_s: float
) -> TraversalSample:
	var sample: TraversalSample = strip.call(
		"sample_at_distance",
		distance_along_m
	)
	assert_not_null(sample)
	if sample == null:
		return null
	assert_gt(
		sample.distance_along_m,
		0.0,
		"fresh-eyes wall-run coverage must never attach at strip distance 0"
	)
	player.global_position = (
		sample.position
		+ sample.normal * _wall_run.surface_stick_distance_m
	)
	player.velocity = sample.tangent * 6.0
	assert_true(player.call("try_wall_attach", strip, now_s))
	return sample


func _new_strip(
	strip_name: StringName,
	origin: Vector3,
	local_end: Vector3,
	local_normal: Vector3
) -> Path3D:
	assert_true(
		ResourceLoader.exists(STRIP_SCRIPT_PATH),
		"WallRunStrip implementation must exist"
	)
	if not ResourceLoader.exists(STRIP_SCRIPT_PATH):
		return null
	var script: Script = load(STRIP_SCRIPT_PATH)
	assert_not_null(script)
	if script == null:
		return null
	var strip := script.new() as Path3D
	strip.name = strip_name
	strip.position = origin
	strip.set("surface_normal", local_normal)
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(local_end)
	strip.curve = curve
	return strip


func _new_controller_with_strip(strip: Path3D) -> Dictionary:
	if strip == null:
		return {}
	var strip_root := Node3D.new()
	strip_root.add_child(strip)
	add_child_autofree(strip_root)
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
		false
	)
	return {
		"player": player,
		"buffer": buffer,
	}
