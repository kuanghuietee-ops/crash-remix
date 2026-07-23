extends GutTest

const PREDICTION_SCRIPT_PATH := "res://src/gameplay/depth/depth_prediction.gd"
const LANDING_ASSIST_SCRIPT_PATH := "res://src/gameplay/depth/landing_assist.gd"
const BLOB_SHADOW_SCRIPT_PATH := "res://src/gameplay/depth/blob_shadow.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _move: MoveTuning
var _depth: DepthTuning


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.move
		_depth = catalog.depth


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
