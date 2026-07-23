class_name InputVectorFilter
extends RefCounted


static func apply_corridor_magnet(
	input_vector: Vector2,
	corridor_axis: Vector2,
	input_tuning: InputTuning,
	is_gamepad: bool
) -> Vector2:
	var magnitude := input_vector.length()
	if is_zero_approx(magnitude) or corridor_axis.is_zero_approx():
		return input_vector
	if is_gamepad and magnitude > input_tuning.gamepad_magnet_disable_magnitude:
		return input_vector

	var direction := input_vector / magnitude
	var axis := corridor_axis.normalized()
	var target_axis := axis if direction.dot(axis) >= 0.0 else -axis
	var cone_radians := deg_to_rad(input_tuning.corridor_magnet_cone_degrees)
	if absf(direction.angle_to(target_axis)) > cone_radians:
		return input_vector

	var strength := clampf(input_tuning.corridor_magnet_strength, 0.0, 1.0)
	var filtered_direction := direction.slerp(target_axis, strength).normalized()
	return filtered_direction * magnitude


static func to_corridor_input(
	screen_input: Vector2,
	corridor_axis: Vector2
) -> Vector2:
	if screen_input.is_zero_approx() or corridor_axis.is_zero_approx():
		return screen_input
	var screen_forward := corridor_axis.normalized()
	var screen_right := Vector2(
		-screen_forward.y,
		screen_forward.x
	)
	return Vector2(
		screen_input.dot(screen_right),
		-screen_input.dot(screen_forward)
	)
