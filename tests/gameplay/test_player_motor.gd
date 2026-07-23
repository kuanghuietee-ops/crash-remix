extends GutTest

const MOTOR_SCRIPT_PATH := "res://src/gameplay/player/player_motor.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const FRAME_DELTA_S := 1.0 / 60.0
const FLOAT_TOLERANCE := 0.0001
const DISTANCE_TOLERANCE_M := 0.01

var _move: MoveTuning


func before_all() -> void:
	var catalog: Resource = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.get("move")


func test_run_acceleration_makes_partial_frame_scaled_progress() -> void:
	var script: Script = _motor_script()
	if script == null:
		return

	var velocity: Vector3 = script.call(
		"horizontal_velocity",
		Vector3.ZERO,
		Vector2.UP,
		&"grounded",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)
	var expected_speed: float = (
		_move.run_speed_mps
		/ _move.run_time_to_speed_s
		* FRAME_DELTA_S
	)

	assert_almost_eq(velocity.length(), expected_speed, FLOAT_TOLERANCE)
	assert_lt(velocity.length(), _move.run_speed_mps)
	assert_lt(velocity.z, 0.0)


func test_stopping_makes_partial_frame_scaled_progress() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var current: Vector3 = Vector3.FORWARD * _move.get("run_speed_mps")

	var velocity: Vector3 = script.call(
		"horizontal_velocity",
		current,
		Vector2.ZERO,
		&"grounded",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)
	var expected_speed: float = (
		_move.run_speed_mps
		- _move.run_speed_mps
		/ _move.stop_time_s
		* FRAME_DELTA_S
	)

	assert_almost_eq(velocity.length(), expected_speed, FLOAT_TOLERANCE)
	assert_gt(velocity.length(), 0.0)
	assert_lt(velocity.length(), current.length())


func test_crouched_acceleration_makes_partial_frame_scaled_progress() -> void:
	var script: Script = _motor_script()
	if script == null:
		return

	var velocity: Vector3 = script.call(
		"horizontal_velocity",
		Vector3.ZERO,
		Vector2.UP,
		&"crouched",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)
	var expected_speed: float = (
		_move.crawl_speed_mps
		/ _move.run_time_to_speed_s
		* FRAME_DELTA_S
	)

	assert_almost_eq(velocity.length(), expected_speed, FLOAT_TOLERANCE)
	assert_lt(velocity.length(), _move.crawl_speed_mps)


func test_slide_keeps_authored_momentum_after_stick_release() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var current: Vector3 = Vector3.FORWARD * _move.get("run_speed_mps")

	var velocity: Vector3 = script.call(
		"horizontal_velocity",
		current,
		Vector2.ZERO,
		&"sliding",
		_move.get("run_time_to_speed_s"),
		Vector3.FORWARD,
		_move
	)

	assert_almost_eq(
		velocity.length(),
		_move.get("slide_distance_m") / _move.get("slide_duration_s"),
		0.0001
	)


func test_body_slam_explicitly_uses_committed_ground_braking() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var exposes_momentum_policy := false
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == &"uses_airborne_momentum_model":
			exposes_momentum_policy = true
			break
	assert_true(exposes_momentum_policy)
	if not exposes_momentum_policy:
		return

	assert_true(script.call("uses_airborne_momentum_model", &"airborne"))
	assert_false(script.call("uses_airborne_momentum_model", &"body_slam"))

	var current_speed := JumpKinematics.horizontal_speed_for_jump(
		_move.slide_jump_distance_m,
		_move.slide_jump_height_m,
		_move
	)
	var velocity: Vector3 = script.call(
		"horizontal_velocity",
		Vector3.FORWARD * current_speed,
		Vector2.ZERO,
		&"body_slam",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)
	var expected_speed := maxf(
		current_speed
			- _move.run_speed_mps
			/ _move.stop_time_s
			* FRAME_DELTA_S,
		0.0
	)

	assert_almost_eq(velocity.length(), expected_speed, FLOAT_TOLERANCE)
	assert_lt(velocity.length(), current_speed)


func test_slide_jump_and_body_slam_impulses_use_tuning() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var current: Vector3 = Vector3.FORWARD * _move.get("run_speed_mps")

	var slide_jump: Vector3 = script.call(
		"impulse_velocity", &"slide_jump", current, Vector3.FORWARD, _move
	)
	var slam: Vector3 = script.call(
		"impulse_velocity", &"body_slam", current, Vector3.FORWARD, _move
	)

	assert_almost_eq(
		slide_jump.y,
		JumpKinematics.upward_speed_for_height(_move.slide_jump_height_m, _move),
		0.0001
	)
	assert_almost_eq(
		Vector2(slide_jump.x, slide_jump.z).length(),
		JumpKinematics.horizontal_speed_for_jump(
			_move.slide_jump_distance_m,
			_move.slide_jump_height_m,
			_move
		),
		0.0001
	)
	assert_eq(slam.y, -_move.get("body_slam_speed_mps"))


func test_slide_jump_travels_authored_distance_across_full_airtime() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var launch: Vector3 = script.call(
		"impulse_velocity",
		&"slide_jump",
		Vector3.FORWARD * _move.run_speed_mps,
		Vector3.FORWARD,
		_move
	)
	var horizontal := Vector3(launch.x, 0.0, launch.z)
	var position := Vector3.ZERO
	var elapsed_s := 0.0
	var air_time_s := JumpKinematics.air_time_for_height(
		_move.slide_jump_height_m,
		_move
	)
	while elapsed_s < air_time_s:
		var step_s := minf(FRAME_DELTA_S, air_time_s - elapsed_s)
		horizontal = script.call(
			"horizontal_velocity",
			horizontal,
			Vector2.UP,
			&"airborne",
			step_s,
			Vector3.FORWARD,
			_move
		)
		position += horizontal * step_s
		elapsed_s += step_s

	assert_almost_eq(
		position.length(),
		_move.slide_jump_distance_m,
		DISTANCE_TOLERANCE_M
	)


func test_releasing_stick_in_air_preserves_slide_jump_momentum() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var launch: Vector3 = script.call(
		"impulse_velocity",
		&"slide_jump",
		Vector3.FORWARD * _move.run_speed_mps,
		Vector3.FORWARD,
		_move
	)
	var horizontal := Vector3(launch.x, 0.0, launch.z)

	var after_release: Vector3 = script.call(
		"horizontal_velocity",
		horizontal,
		Vector2.ZERO,
		&"airborne",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)

	assert_almost_eq(
		after_release.length(),
		horizontal.length(),
		FLOAT_TOLERANCE
	)
	assert_eq(after_release.normalized(), horizontal.normalized())


func test_air_input_steers_without_spending_slide_jump_boost() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var launch: Vector3 = script.call(
		"impulse_velocity",
		&"slide_jump",
		Vector3.FORWARD * _move.run_speed_mps,
		Vector3.FORWARD,
		_move
	)
	var horizontal := Vector3(launch.x, 0.0, launch.z)

	var steered: Vector3 = script.call(
		"horizontal_velocity",
		horizontal,
		Vector2.RIGHT,
		&"airborne",
		FRAME_DELTA_S,
		Vector3.FORWARD,
		_move
	)

	assert_almost_eq(
		steered.length(),
		horizontal.length(),
		FLOAT_TOLERANCE
	)
	assert_gt(
		steered.normalized().dot(Vector3.RIGHT),
		horizontal.normalized().dot(Vector3.RIGHT)
	)


func test_authored_jump_geometry_directly_drives_impulses() -> void:
	var script: Script = _motor_script()
	if script == null:
		return
	var taller_jump: Resource = _move.duplicate(true)
	taller_jump.set(
		"jump_full_height_m",
		_move.get("jump_full_height_m") + 1.0
	)
	var longer_slide_jump: Resource = _move.duplicate(true)
	longer_slide_jump.set(
		"slide_jump_distance_m",
		_move.get("slide_jump_distance_m") + 1.0
	)
	var higher_slide_jump: Resource = _move.duplicate(true)
	higher_slide_jump.set(
		"slide_jump_height_m",
		_move.get("slide_jump_height_m") + 1.0
	)
	var current: Vector3 = Vector3.FORWARD * float(_move.get("run_speed_mps"))
	var base_jump: Vector3 = script.call(
		"impulse_velocity", &"jump", Vector3.ZERO, Vector3.FORWARD, _move
	)
	var tall_jump: Vector3 = script.call(
		"impulse_velocity", &"jump", Vector3.ZERO, Vector3.FORWARD, taller_jump
	)
	var base_slide: Vector3 = script.call(
		"impulse_velocity", &"slide_jump", current, Vector3.FORWARD, _move
	)
	var long_slide: Vector3 = script.call(
		"impulse_velocity",
		&"slide_jump",
		current,
		Vector3.FORWARD,
		longer_slide_jump
	)
	var high_slide: Vector3 = script.call(
		"impulse_velocity",
		&"slide_jump",
		current,
		Vector3.FORWARD,
		higher_slide_jump
	)

	assert_gt(tall_jump.y, base_jump.y)
	assert_gt(
		Vector2(long_slide.x, long_slide.z).length(),
		Vector2(base_slide.x, base_slide.z).length()
	)
	assert_gt(high_slide.y, base_slide.y)


func _motor_script() -> Script:
	var script: Script = load(MOTOR_SCRIPT_PATH)
	assert_not_null(script, "PlayerMotor implementation must exist")
	return script
