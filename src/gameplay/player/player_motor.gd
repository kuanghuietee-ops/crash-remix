class_name PlayerMotor
extends RefCounted

const JumpKinematicsType := preload("res://src/gameplay/player/jump_kinematics.gd")

const STATE_AIRBORNE := &"airborne"
const STATE_BODY_SLAM := &"body_slam"
const STATE_CROUCHED := &"crouched"
const STATE_SLIDING := &"sliding"
const STATE_GRIND := &"grind"
const STATE_WALL_RUN := &"wall_run"
const STATE_SWING := &"swing"
const STATE_RIDE := &"ride"

const IMPULSE_JUMP := &"jump"
const IMPULSE_DOUBLE_JUMP := &"double_jump"
const IMPULSE_HIGH_JUMP := &"high_jump"
const IMPULSE_SLIDE_JUMP := &"slide_jump"
const IMPULSE_BODY_SLAM := &"body_slam"
const IMPULSE_RIDE_JUMP := &"ride_jump"


static func uses_airborne_momentum_model(state: StringName) -> bool:
	match state:
		STATE_AIRBORNE:
			return true
		STATE_BODY_SLAM:
			# A committed descent deliberately brakes horizontal drift so the
			# panic verb can target a nearby landing rather than overshoot it.
			return false
	return false


static func uses_spline_motion(state: StringName) -> bool:
	return (
		state == STATE_GRIND
		or state == STATE_WALL_RUN
		or state == STATE_SWING
	)


static func horizontal_velocity(
	current_velocity: Vector3,
	input_vector: Vector2,
	state: StringName,
	delta_s: float,
	forward_axis: Vector3,
	move_tuning: MoveTuning,
	hog_tuning: HogTuning
) -> Vector3:
	if uses_spline_motion(state):
		return Vector3.ZERO
	var horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	var forward := Vector3(forward_axis.x, 0.0, forward_axis.z).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	if state == STATE_RIDE:
		if hog_tuning == null:
			return Vector3.ZERO
		return (
			forward * hog_tuning.ride_speed_mps
			+ right
			* clampf(input_vector.x, -1.0, 1.0)
			* hog_tuning.steer_lateral_speed_mps
		)
	var desired_direction := right * input_vector.x - forward * input_vector.y
	if not desired_direction.is_zero_approx():
		desired_direction = desired_direction.normalized()
	if state == STATE_SLIDING:
		var slide_direction := horizontal.normalized()
		if slide_direction.is_zero_approx():
			slide_direction = desired_direction
		return (
			slide_direction
			* move_tuning.slide_distance_m
			/ move_tuning.slide_duration_s
		)
	if uses_airborne_momentum_model(state):
		if desired_direction.is_zero_approx():
			return horizontal
		var current_speed := horizontal.length()
		var desired_speed := (
			move_tuning.run_speed_mps * input_vector.length()
		)
		var maximum_change := (
			move_tuning.run_speed_mps
			/ move_tuning.run_time_to_speed_s
			* delta_s
		)
		var next_speed := current_speed
		if current_speed < desired_speed:
			next_speed = minf(
				current_speed + maximum_change,
				desired_speed
			)
		if is_zero_approx(current_speed):
			return desired_direction * next_speed
		var current_direction := horizontal / current_speed
		var turn_angle := current_direction.signed_angle_to(
			desired_direction,
			Vector3.UP
		)
		# Treat the acceleration budget as steering arc length, so faster
		# momentum intentionally turns through a smaller angle per frame.
		var maximum_turn_radians := maximum_change / current_speed
		var next_direction := current_direction.rotated(
			Vector3.UP,
			clampf(
				turn_angle,
				-maximum_turn_radians,
				maximum_turn_radians
			)
		)
		return next_direction * next_speed

	var target_speed := move_tuning.run_speed_mps
	if state == STATE_CROUCHED:
		target_speed = move_tuning.crawl_speed_mps

	var target := desired_direction * target_speed * input_vector.length()
	var transition_time := move_tuning.run_time_to_speed_s
	var transition_speed := target_speed
	if target.is_zero_approx():
		transition_time = move_tuning.stop_time_s
		transition_speed = move_tuning.run_speed_mps
	var maximum_change := transition_speed / transition_time * delta_s
	return horizontal.move_toward(target, maximum_change)


static func impulse_velocity(
	impulse: StringName,
	current_velocity: Vector3,
	forward_axis: Vector3,
	move_tuning: MoveTuning,
	hog_tuning: HogTuning
) -> Vector3:
	var result := current_velocity
	match impulse:
		IMPULSE_JUMP:
			result.y = JumpKinematicsType.upward_speed_for_height(
				move_tuning.jump_full_height_m,
				move_tuning
			)
		IMPULSE_DOUBLE_JUMP:
			result.y = JumpKinematicsType.upward_speed_for_height(
				move_tuning.double_jump_height_m,
				move_tuning
			)
		IMPULSE_HIGH_JUMP:
			result.y = JumpKinematicsType.upward_speed_for_height(
				move_tuning.high_jump_height_m,
				move_tuning
			)
		IMPULSE_SLIDE_JUMP:
			var horizontal := Vector3(result.x, 0.0, result.z)
			var direction := horizontal.normalized()
			if direction.is_zero_approx():
				direction = Vector3(forward_axis.x, 0.0, forward_axis.z).normalized()
			result = direction * JumpKinematicsType.horizontal_speed_for_jump(
				move_tuning.slide_jump_distance_m,
				move_tuning.slide_jump_height_m,
				move_tuning
			)
			result.y = JumpKinematicsType.upward_speed_for_height(
				move_tuning.slide_jump_height_m,
				move_tuning
			)
		IMPULSE_BODY_SLAM:
			result.y = -move_tuning.body_slam_speed_mps
		IMPULSE_RIDE_JUMP:
			if hog_tuning != null:
				result.y = JumpKinematicsType.upward_speed_for_height(
					hog_tuning.hog_jump_height_m,
					move_tuning
				)
	return result
