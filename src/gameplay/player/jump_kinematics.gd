class_name JumpKinematics
extends RefCounted

const ScalarMathType := preload("res://src/core/scalar_math.gd")


static func upward_speed_for_height(
	height_m: float,
	move_tuning: MoveTuning
) -> float:
	var gravity := move_tuning.gravity_mps2
	var apex_gravity := gravity * move_tuning.apex_gravity_multiplier
	if height_m <= 0.0 or gravity <= 0.0 or apex_gravity <= 0.0:
		return 0.0
	var threshold := maxf(move_tuning.apex_velocity_threshold_mps, 0.0)
	var doubled := ScalarMathType.DOUBLE
	var apex_band_height := threshold * threshold / (doubled * apex_gravity)
	if height_m <= apex_band_height:
		return sqrt(doubled * apex_gravity * height_m)
	return sqrt(
		threshold * threshold
		+ doubled * gravity * (height_m - apex_band_height)
	)


static func air_time_for_height(
	height_m: float,
	move_tuning: MoveTuning
) -> float:
	var gravity := move_tuning.gravity_mps2
	var apex_gravity := gravity * move_tuning.apex_gravity_multiplier
	var fall_gravity := gravity * move_tuning.fall_gravity_multiplier
	if (
		height_m <= 0.0
		or gravity <= 0.0
		or apex_gravity <= 0.0
		or fall_gravity <= 0.0
	):
		return 0.0
	var threshold := maxf(move_tuning.apex_velocity_threshold_mps, 0.0)
	var doubled := ScalarMathType.DOUBLE
	var apex_band_height := threshold * threshold / (doubled * apex_gravity)
	var upward_speed := upward_speed_for_height(height_m, move_tuning)
	if height_m <= apex_band_height:
		var half_time := upward_speed / apex_gravity
		return half_time + half_time

	var rise_time := (
		(upward_speed - threshold) / gravity
		+ threshold / apex_gravity
	)
	var fall_time := threshold / apex_gravity
	var remaining_fall_height := height_m - apex_band_height
	fall_time += (
		-threshold
		+ sqrt(
			threshold * threshold
			+ doubled * fall_gravity * remaining_fall_height
		)
	) / fall_gravity
	return rise_time + fall_time


static func horizontal_speed_for_jump(
	distance_m: float,
	height_m: float,
	move_tuning: MoveTuning
) -> float:
	var air_time := air_time_for_height(height_m, move_tuning)
	if distance_m <= 0.0 or air_time <= 0.0:
		return 0.0
	return distance_m / air_time


static func velocity_after_release(
	current_upward_velocity_mps: float,
	hold_duration_s: float,
	tap_height_m: float,
	move_tuning: MoveTuning,
	input_tuning: InputTuning
) -> float:
	if current_upward_velocity_mps <= 0.0 or tap_height_m <= 0.0:
		return current_upward_velocity_mps
	var minimum_jump_speed := upward_speed_for_height(
		tap_height_m,
		move_tuning
	)
	if hold_duration_s < input_tuning.minimum_hop_release_s:
		return minf(current_upward_velocity_mps, minimum_jump_speed)
	if hold_duration_s >= input_tuning.full_jump_hold_s:
		return current_upward_velocity_mps

	var hold_range_s := (
		input_tuning.full_jump_hold_s - input_tuning.minimum_hop_release_s
	)
	if hold_range_s <= 0.0:
		return current_upward_velocity_mps
	var blend := clampf(
		(hold_duration_s - input_tuning.minimum_hop_release_s) / hold_range_s,
		0.0,
		1.0
	)
	var release_ceiling := lerpf(
		minimum_jump_speed,
		current_upward_velocity_mps,
		blend
	)
	return minf(current_upward_velocity_mps, release_ceiling)


static func gravity_for_velocity(
	vertical_velocity_mps: float,
	is_air_spinning: bool,
	move_tuning: MoveTuning
) -> float:
	if vertical_velocity_mps < 0.0 and is_air_spinning:
		return move_tuning.gravity_mps2 * move_tuning.air_spin_gravity_multiplier
	if absf(vertical_velocity_mps) <= move_tuning.apex_velocity_threshold_mps:
		return move_tuning.gravity_mps2 * move_tuning.apex_gravity_multiplier
	if vertical_velocity_mps < 0.0:
		return move_tuning.gravity_mps2 * move_tuning.fall_gravity_multiplier
	return move_tuning.gravity_mps2
