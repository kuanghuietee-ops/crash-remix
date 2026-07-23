class_name CameraBlend
extends RefCounted


static func resolve_offset(
	default_offset: Vector3,
	region_offsets: Array
) -> Vector3:
	if region_offsets.is_empty():
		return default_offset
	var sum := Vector3.ZERO
	for candidate: Variant in region_offsets:
		if candidate is Vector3:
			sum += candidate as Vector3
	return sum / float(region_offsets.size())


static func offset_at_elapsed(
	origin_offset: Vector3,
	target_offset: Vector3,
	elapsed_s: float,
	camera_tuning: CameraTuning
) -> Vector3:
	if camera_tuning.region_blend_s <= 0.0:
		return target_offset
	var weight := clampf(
		elapsed_s / camera_tuning.region_blend_s,
		0.0,
		1.0
	)
	return origin_offset.lerp(target_offset, weight)


static func basis_at_elapsed(
	origin_basis: Basis,
	target_basis: Basis,
	elapsed_s: float,
	camera_tuning: CameraTuning
) -> Basis:
	if camera_tuning.region_blend_s <= 0.0:
		return target_basis
	var weight := clampf(
		elapsed_s / camera_tuning.region_blend_s,
		0.0,
		1.0
	)
	if weight >= 1.0:
		return target_basis
	return Basis(
		origin_basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			weight
		)
	).orthonormalized()


static func depression_degrees(camera_offset: Vector3) -> float:
	var horizontal_distance := Vector2(camera_offset.x, camera_offset.z).length()
	return rad_to_deg(atan2(camera_offset.y, horizontal_distance))
