class_name LandingAssist
extends RefCounted


static func probe_end(
	probe_origin: Vector3,
	depth_tuning: DepthTuning
) -> Vector3:
	return (
		probe_origin
		+ Vector3.DOWN * depth_tuning.landing_assist_probe_depth_m
	)


static func adjusted_horizontal_velocity(
	current_horizontal: Vector3,
	correction_direction: Vector3,
	input_direction: Vector3,
	fall_progress: float,
	input_source: StringName,
	depth_tuning: DepthTuning
) -> Vector3:
	var strength := _strength_for_source(input_source, depth_tuning)
	var final_fall_start := 1.0 - clampf(
		depth_tuning.landing_assist_last_fall_ratio,
		0.0,
		1.0
	)
	if strength <= 0.0 or fall_progress < final_fall_start:
		return current_horizontal

	var correction := Vector3(
		correction_direction.x,
		0.0,
		correction_direction.z
	).normalized()
	var intent := Vector3(input_direction.x, 0.0, input_direction.z).normalized()
	if correction.is_zero_approx() or not _is_aimed_at_platform(
		current_horizontal,
		intent,
		correction
	):
		return current_horizontal

	var speed := current_horizontal.length()
	if is_zero_approx(speed):
		return current_horizontal
	var target := correction * speed
	return current_horizontal.lerp(target, clampf(strength, 0.0, 1.0))


static func _strength_for_source(
	input_source: StringName,
	depth_tuning: DepthTuning
) -> float:
	if input_source == InputIntent.SOURCE_TOUCH:
		return depth_tuning.landing_assist_touch_strength
	if input_source == InputIntent.SOURCE_GAMEPAD:
		return depth_tuning.landing_assist_gamepad_strength
	return 0.0


static func _is_aimed_at_platform(
	current_horizontal: Vector3,
	intent: Vector3,
	correction: Vector3
) -> bool:
	if not intent.is_zero_approx():
		return intent.dot(correction) > 0.0
	if current_horizontal.is_zero_approx():
		return false
	return current_horizontal.normalized().dot(correction) > 0.0
