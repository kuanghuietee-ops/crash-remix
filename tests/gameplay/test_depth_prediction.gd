extends GutTest

const PREDICTION_SCRIPT_PATH := "res://src/gameplay/depth/depth_prediction.gd"
const LANDING_ASSIST_SCRIPT_PATH := "res://src/gameplay/depth/landing_assist.gd"
const BLOB_SHADOW_SCRIPT_PATH := "res://src/gameplay/depth/blob_shadow.gd"
const LANDING_RING_SCRIPT_PATH := "res://src/gameplay/depth/landing_ring.gd"
const PLAYER_SCRIPT_PATH := "res://src/gameplay/player/player_controller.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _move: MoveTuning
var _input: InputTuning
var _depth: DepthTuning
var _wall_run: WallRunTuning
var _grind: GrindTuning
var _swing: SwingTuning


class FakePredictionTarget:
	extends CharacterBody3D

	var prediction_context: Dictionary

	func landing_prediction_context() -> Dictionary:
		return prediction_context

	func is_spinning() -> bool:
		return false


class FakeRail:
	extends Node3D

	var rail_samples: Array[TraversalSample] = []

	func samples() -> Array[TraversalSample]:
		return rail_samples


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.move
		_input = catalog.input
		_depth = catalog.depth
		_wall_run = catalog.wall_run
		_grind = catalog.grind
		_swing = catalog.swing


func test_trajectory_starts_at_player_and_advances_with_authored_step() -> void:
	var script: Script = load(PREDICTION_SCRIPT_PATH)
	assert_not_null(script, "DepthPrediction implementation must exist")
	if script == null:
		return
	var origin := Vector3(0.0, 2.0, 0.0)
	var velocity := Vector3(
		3.0,
		JumpKinematics.upward_speed_for_height(_move.jump_full_height_m, _move),
		0.0
	)

	var points: PackedVector3Array = script.call(
		"trajectory_points", origin, velocity, false, _move, _depth
	)

	assert_gt(points.size(), 2)
	assert_eq(points[0], origin)
	assert_almost_eq(points[1].x, velocity.x * _depth.prediction_step_s, 0.0001)
	var first_gravity: float = JumpKinematics.gravity_for_velocity(
		velocity.y,
		false,
		_move
	)
	var expected_first_y := (
		origin.y
		+ (velocity.y - first_gravity * _depth.prediction_step_s)
		* _depth.prediction_step_s
	)
	assert_almost_eq(points[1].y, expected_first_y, 0.0001)
	assert_lt(points[-1].y, origin.y)


func test_ground_crossing_interpolates_a_ballistic_landing() -> void:
	var script: Script = load(PREDICTION_SCRIPT_PATH)
	assert_not_null(script, "DepthPrediction implementation must exist")
	if script == null:
		return
	var points: PackedVector3Array = script.call(
		"trajectory_points",
		Vector3(0.0, 1.0, 0.0),
		Vector3(4.0, 4.0, 0.0),
		false,
		_move,
		_depth
	)
	var landing: Variant = script.call("first_plane_crossing", points, 0.0)

	assert_not_null(landing)
	assert_almost_eq((landing as Vector3).y, 0.0, 0.0001)
	assert_gt((landing as Vector3).x, 0.0)


func test_prediction_respects_air_spin_gravity_stall() -> void:
	var script: Script = load(PREDICTION_SCRIPT_PATH)
	assert_not_null(script, "DepthPrediction implementation must exist")
	if script == null:
		return
	var origin := Vector3(0.0, 3.0, 0.0)
	var falling := Vector3(2.0, -2.0, 0.0)
	var normal: PackedVector3Array = script.call(
		"trajectory_points", origin, falling, false, _move, _depth
	)
	var spinning: PackedVector3Array = script.call(
		"trajectory_points", origin, falling, true, _move, _depth
	)

	assert_gt(spinning[-1].y, normal[-1].y)


func test_collision_probe_sampling_is_strided_and_keeps_final_point() -> void:
	var script: Script = load(PREDICTION_SCRIPT_PATH)
	assert_not_null(script, "DepthPrediction implementation must exist")
	if script == null:
		return

	var indices := PackedInt32Array()
	for index: int in range(1, 11):
		if script.call("should_collision_probe", index, 10, 3):
			indices.append(index)

	assert_eq(indices, PackedInt32Array([3, 6, 9, 10]))


func test_blob_shadow_ray_starts_at_authored_offset_above_target() -> void:
	var script: Script = load(BLOB_SHADOW_SCRIPT_PATH)
	assert_not_null(script, "BlobShadow implementation must exist")
	if script == null:
		return
	var tuning: DepthTuning = _depth.duplicate(true)
	tuning.set("shadow_ray_origin_offset_m", 0.25)
	var target_position := Vector3(2.0, 3.0, 4.0)

	var origin: Vector3 = script.call(
		"ray_origin",
		target_position,
		tuning
	)

	assert_eq(origin, target_position + Vector3.UP * 0.25)


func test_landing_assist_only_steers_during_final_fall_portion() -> void:
	var script: Script = load(LANDING_ASSIST_SCRIPT_PATH)
	assert_not_null(script, "LandingAssist implementation must exist")
	if script == null:
		return
	var horizontal_velocity := Vector3.RIGHT * 4.0
	var before_window: Vector3 = script.call(
		"adjusted_horizontal_velocity",
		horizontal_velocity,
		Vector3.FORWARD,
		Vector3.FORWARD,
		0.69,
		InputIntent.SOURCE_TOUCH,
		_depth
	)
	var inside_window: Vector3 = script.call(
		"adjusted_horizontal_velocity",
		horizontal_velocity,
		Vector3.FORWARD,
		Vector3.FORWARD,
		0.8,
		InputIntent.SOURCE_TOUCH,
		_depth
	)

	assert_eq(before_window, horizontal_velocity)
	assert_almost_eq(inside_window.x, 2.0, 0.0001)
	assert_almost_eq(inside_window.z, -2.0, 0.0001)


func test_landing_assist_probe_depth_is_independent_from_shadow_length() -> void:
	var script: Script = load(LANDING_ASSIST_SCRIPT_PATH)
	assert_not_null(script, "LandingAssist implementation must exist")
	if script == null:
		return
	var tuning: DepthTuning = _depth.duplicate(true)
	tuning.set("shadow_ray_length_m", 20.0)
	tuning.set("landing_assist_probe_depth_m", 2.5)
	var origin := Vector3(1.0, 4.0, 3.0)

	var probe_end: Vector3 = script.call("probe_end", origin, tuning)

	assert_eq(probe_end, origin + Vector3.DOWN * 2.5)


func test_landing_assist_never_overrides_fighting_stick_or_pad_default() -> void:
	var script: Script = load(LANDING_ASSIST_SCRIPT_PATH)
	assert_not_null(script, "LandingAssist implementation must exist")
	if script == null:
		return
	var horizontal_velocity := Vector3.RIGHT * 4.0
	var fighting: Vector3 = script.call(
		"adjusted_horizontal_velocity",
		horizontal_velocity,
		Vector3.FORWARD,
		Vector3.BACK,
		0.9,
		InputIntent.SOURCE_TOUCH,
		_depth
	)
	var gamepad: Vector3 = script.call(
		"adjusted_horizontal_velocity",
		horizontal_velocity,
		Vector3.FORWARD,
		Vector3.FORWARD,
		0.9,
		InputIntent.SOURCE_GAMEPAD,
		_depth
	)

	assert_eq(fighting, horizontal_velocity)
	assert_eq(gamepad, horizontal_velocity)


func test_ring_turns_rail_coloured_when_the_arc_will_attach() -> void:
	var script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"resolve_colour"
	)
	if script == null:
		return
	var samples := _straight_rail_samples(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(0.0, 3.0, 1.0),
		Vector3(0.0, 1.5, 2.0),
		Vector3(0.1, 0.1, 3.0),
	])

	var colour: Color = script.call(
		"resolve_colour",
		arc,
		samples,
		true,
		_depth
	)

	assert_eq(
		colour,
		_depth.rail_predicted_color,
		"attach must be telegraphed, not a surprise"
	)


func test_ring_hazard_red_beats_a_predicted_rail_attach() -> void:
	var script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"resolve_colour"
	)
	if script == null:
		return
	var samples := _straight_rail_samples(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
	])

	var colour: Color = script.call(
		"resolve_colour",
		arc,
		samples,
		false,
		_depth
	)

	assert_eq(colour, _depth.hazard_color)


func test_ring_runtime_snap_matches_grind_attach_not_visual_radius() -> void:
	var script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"resolve_colour"
	)
	if script == null:
		return
	var sample := TraversalSample.new()
	sample.position = Vector3(0.38, 0.0, 0.5)
	sample.tangent = Vector3.BACK
	sample.normal = Vector3.UP
	var samples: Array[TraversalSample] = [sample]
	var arc := PackedVector3Array([
		Vector3.ZERO,
		Vector3.BACK,
	])

	var colour: Color = script.call(
		"resolve_colour",
		arc,
		samples,
		true,
		_depth,
		_grind.attach_snap_m
	)

	assert_eq(
		colour,
		_depth.landable_color,
		"the orange cue must use the same snap contract as real attachment"
	)


func test_player_prediction_context_uses_the_exact_wall_detach_arc() -> void:
	var script := _load_script_with_method(
		PLAYER_SCRIPT_PATH,
		&"landing_prediction_context"
	)
	if script == null:
		return
	var player: CharacterBody3D = script.new()
	player.call(
		"configure",
		_move,
		_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		InputIntentBuffer.new()
	)
	var sample := TraversalSample.new()
	sample.position = Vector3(1.0, 2.0, 3.0)
	sample.tangent = Vector3.BACK
	sample.normal = Vector3.RIGHT
	player.get("_state_machine").set("state", &"wall_run")
	player.set("_active_wall_sample", sample)

	var context: Dictionary = player.call("landing_prediction_context")
	var expected := (
		Vector3.BACK * _wall_run.run_speed_mps
		+ Vector3.RIGHT * _wall_run.detach_outward_speed_mps
	)
	expected.y = JumpKinematics.upward_speed_for_height(
		_wall_run.detach_height_m,
		_move
	)

	assert_eq(context.get(&"state"), &"wall_run")
	assert_eq(context.get(&"origin"), player.position)
	assert_eq(context.get(&"velocity"), expected)
	player.free()


func test_player_prediction_context_uses_current_swing_release_velocity() -> void:
	var script := _load_script_with_method(
		PLAYER_SCRIPT_PATH,
		&"landing_prediction_context"
	)
	if script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var player: CharacterBody3D = script.new()
	root.add_child(player)
	player.call(
		"configure",
		_move,
		_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		InputIntentBuffer.new()
	)
	var anchor := SwingAnchor.new()
	anchor.swing_tuning = _swing
	root.add_child(anchor)
	var angle_rad := 0.35
	var angular_velocity := 1.4
	player.get("_state_machine").set("state", &"swing")
	player.set("_active_swing_anchor", anchor)
	player.set("_swing_angle_rad", angle_rad)
	player.set("_swing_angular_velocity", angular_velocity)

	var context: Dictionary = player.call("landing_prediction_context")
	var expected_local := SwingPendulum.release_velocity(
		angle_rad,
		angular_velocity,
		_swing
	)
	var expected_world := anchor.world_velocity(expected_local)

	assert_eq(context.get(&"state"), &"swing")
	assert_eq(context.get(&"velocity"), expected_world)


func test_ring_draws_on_the_wall_run_detach_target() -> void:
	var ring_script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"current_ring_position"
	)
	if ring_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var target := FakePredictionTarget.new()
	var origin := Vector3(0.0, 2.0, 0.0)
	var detach_velocity := Vector3(4.0, 4.0, 0.0)
	target.position = origin
	target.prediction_context = {
		&"state": &"wall_run",
		&"origin": origin,
		&"velocity": detach_velocity,
		&"spinning": false,
	}
	root.add_child(target)
	var floor := StaticBody3D.new()
	floor.position.y = -0.5
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 1.0, 30.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	root.add_child(floor)
	var ring: Node3D = ring_script.new()
	root.add_child(ring)
	ring.call(
		"configure",
		target,
		_move,
		_depth,
		_grind,
		[]
	)
	var arc: PackedVector3Array = DepthPrediction.trajectory_points(
		origin,
		detach_velocity,
		false,
		_move,
		_depth
	)
	var expected: Vector3 = DepthPrediction.first_plane_crossing(
		arc,
		0.0
	)

	await wait_physics_frames(2)

	var target_position: Vector3 = ring.call("current_ring_position")
	assert_true(ring.visible)
	assert_almost_eq(
		target_position.distance_to(expected),
		0.0,
		0.05,
		"§5.5 requires the ring on the detach target during a wall-run"
	)


func test_ring_draws_at_a_predicted_rail_attach_over_empty_space() -> void:
	var ring_script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"current_ring_position"
	)
	if ring_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var target := FakePredictionTarget.new()
	var origin := Vector3(0.0, 2.0, 0.0)
	var launch_velocity := Vector3.BACK * 4.0
	target.position = origin
	target.prediction_context = {
		&"state": &"airborne",
		&"origin": origin,
		&"velocity": launch_velocity,
		&"spinning": false,
	}
	root.add_child(target)
	var arc := DepthPrediction.trajectory_points(
		origin,
		launch_velocity,
		false,
		_move,
		_depth
	)
	var rail := FakeRail.new()
	var sample := TraversalSample.new()
	sample.position = arc[1]
	sample.tangent = Vector3.BACK
	sample.normal = Vector3.UP
	rail.rail_samples.append(sample)
	root.add_child(rail)
	var ring: Node3D = ring_script.new()
	root.add_child(ring)
	ring.call(
		"configure",
		target,
		_move,
		_depth,
		_grind,
		[rail]
	)

	await wait_physics_frames(2)

	assert_true(
		ring.visible,
		"a rail attach over a pit still needs a visible prediction"
	)
	assert_eq(ring.call("current_ring_position"), sample.position)


func test_ring_hides_while_the_player_is_already_grinding() -> void:
	var ring_script := _load_script_with_method(
		LANDING_RING_SCRIPT_PATH,
		&"current_ring_position"
	)
	if ring_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var target := FakePredictionTarget.new()
	var origin := Vector3(0.0, 2.0, 0.0)
	var grind_velocity := Vector3.BACK * _grind.speed_mps
	target.position = origin
	target.prediction_context = {
		&"state": &"grind",
		&"origin": origin,
		&"velocity": grind_velocity,
		&"spinning": false,
	}
	root.add_child(target)
	var arc := DepthPrediction.trajectory_points(
		origin,
		grind_velocity,
		false,
		_move,
		_depth
	)
	var rail := FakeRail.new()
	var sample := TraversalSample.new()
	sample.position = arc[1]
	sample.tangent = Vector3.BACK
	sample.normal = Vector3.UP
	rail.rail_samples.append(sample)
	root.add_child(rail)
	var ring: Node3D = ring_script.new()
	root.add_child(ring)
	ring.call(
		"configure",
		target,
		_move,
		_depth,
		_grind,
		[rail]
	)

	await wait_physics_frames(2)

	assert_false(
		ring.visible,
		"the attach cue resumes after a hop enters airborne, not underfoot"
	)


func _straight_rail_samples(
	origin: Vector3,
	direction: Vector3,
	length_m: float,
	spacing_m: float
) -> Array[TraversalSample]:
	var samples: Array[TraversalSample] = []
	var distance_m := 0.0
	while distance_m <= length_m:
		var sample := TraversalSample.new()
		sample.position = origin + direction.normalized() * distance_m
		sample.tangent = direction.normalized()
		sample.normal = Vector3.UP
		sample.distance_along_m = distance_m
		samples.append(sample)
		distance_m += spacing_m
	return samples


func _load_script_with_method(
	path: String,
	method_name: StringName
) -> Script:
	var script: Script = load(path)
	assert_not_null(script, "%s must exist" % path)
	if script == null:
		return null
	var has_method := false
	for method: Dictionary in script.get_script_method_list():
		if StringName(method.get("name", &"")) == method_name:
			has_method = true
			break
	assert_true(
		has_method,
		"%s must expose %s" % [path, method_name]
	)
	return script if has_method else null
