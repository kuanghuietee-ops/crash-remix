class_name SwingPendulum
extends RefCounted


static func step(
	angle_rad: float,
	angular_velocity: float,
	delta_s: float,
	swing_tuning: SwingTuning,
	gravity_mps2: float
) -> Dictionary:
	if (
		swing_tuning == null
		or swing_tuning.rope_length_m <= 0.0
		or delta_s <= 0.0
	):
		return {
			"angle_rad": angle_rad,
			"angular_velocity": angular_velocity,
		}
	var angular_acceleration := (
		-maxf(gravity_mps2, 0.0)
		* maxf(swing_tuning.gravity_scale, 0.0)
		/ swing_tuning.rope_length_m
		* sin(angle_rad)
	)
	var damping := exp(
		-maxf(swing_tuning.damping_per_s, 0.0) * delta_s
	)
	var next_angular_velocity := (
		angular_velocity + angular_acceleration * delta_s
	) * damping
	var maximum_angular_speed := (
		maxf(swing_tuning.maximum_speed_mps, 0.0)
		/ swing_tuning.rope_length_m
	)
	next_angular_velocity = clampf(
		next_angular_velocity,
		-maximum_angular_speed,
		maximum_angular_speed
	)
	return {
		"angle_rad": angle_rad + next_angular_velocity * delta_s,
		"angular_velocity": next_angular_velocity,
	}


static func release_velocity(
	angle_rad: float,
	angular_velocity: float,
	swing_tuning: SwingTuning
) -> Vector3:
	if swing_tuning == null or swing_tuning.rope_length_m <= 0.0:
		return Vector3.ZERO
	var linear_speed_mps := clampf(
		angular_velocity * swing_tuning.rope_length_m,
		-maxf(swing_tuning.maximum_speed_mps, 0.0),
		maxf(swing_tuning.maximum_speed_mps, 0.0)
	)
	if is_zero_approx(linear_speed_mps):
		return Vector3.ZERO
	var boost_direction := 1.0 if linear_speed_mps > 0.0 else -1.0
	var tangent := (
		Vector3.UP * sin(angle_rad)
		+ Vector3.FORWARD * cos(angle_rad)
	).normalized()
	return tangent * (
		linear_speed_mps
		+ boost_direction * maxf(swing_tuning.release_boost_mps, 0.0)
	)


static func position_offset(
	angle_rad: float,
	swing_tuning: SwingTuning
) -> Vector3:
	if swing_tuning == null:
		return Vector3.ZERO
	return (
		Vector3.DOWN * cos(angle_rad)
		+ Vector3.FORWARD * sin(angle_rad)
	) * maxf(swing_tuning.rope_length_m, 0.0)
