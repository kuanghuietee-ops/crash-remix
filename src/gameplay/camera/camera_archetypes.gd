class_name CameraArchetypes
extends RefCounted


static func wall_run_basis(
	strip_tangent: Vector3,
	strip_normal: Vector3,
	camera_tuning: CameraTuning
) -> Basis:
	if camera_tuning == null:
		return Basis.IDENTITY
	var tangent := _normalized_or(strip_tangent, Vector3.BACK)
	var normal := strip_normal.slide(tangent).normalized()
	if normal.is_zero_approx():
		normal = tangent.cross(Vector3.UP).normalized()
	if normal.is_zero_approx():
		normal = Vector3.RIGHT
	var surface_up := tangent.cross(normal).normalized()
	if surface_up.is_zero_approx():
		surface_up = Vector3.UP
	var camera_position := (
		normal * camera_tuning.wall_run_offset.x
		+ surface_up * camera_tuning.wall_run_offset.y
		- tangent * camera_tuning.wall_run_offset.z
	)
	var look_target := (
		tangent * camera_tuning.look_ahead_m
		+ surface_up * camera_tuning.look_at_height_m
	)
	return wall_run_basis_for_view(
		tangent,
		strip_normal,
		look_target - camera_position,
		camera_tuning
	)


static func grind_basis(
	rail_tangent: Vector3,
	camera_tuning: CameraTuning
) -> Basis:
	if camera_tuning == null:
		return Basis.IDENTITY
	var tangent := _normalized_or(rail_tangent, Vector3.BACK)
	var rail_up := Vector3.UP.slide(tangent).normalized()
	if rail_up.is_zero_approx():
		rail_up = Vector3.UP
	var rail_side := tangent.cross(rail_up).normalized()
	if rail_side.is_zero_approx():
		rail_side = Vector3.RIGHT
	var camera_position := (
		rail_side * camera_tuning.grind_offset.x
		+ rail_up * camera_tuning.grind_offset.y
		- tangent * camera_tuning.grind_offset.z
	)
	var look_target := (
		tangent * camera_tuning.look_ahead_m
		+ rail_up * camera_tuning.look_at_height_m
	)
	return grind_basis_for_view(
		tangent,
		rail_up,
		look_target - camera_position
	)


static func swing_basis(
	plane_forward: Vector3,
	plane_normal: Vector3,
	camera_tuning: CameraTuning
) -> Basis:
	if camera_tuning == null:
		return Basis.IDENTITY
	var forward := _normalized_or(plane_forward, Vector3.FORWARD)
	var normal := plane_normal.slide(forward).normalized()
	if normal.is_zero_approx():
		normal = forward.cross(Vector3.UP).normalized()
	if normal.is_zero_approx():
		normal = Vector3.RIGHT
	var swing_up := normal.cross(forward).normalized()
	if swing_up.is_zero_approx():
		swing_up = Vector3.UP
	var camera_position := (
		normal * camera_tuning.swing_offset.x
		+ swing_up * camera_tuning.swing_offset.y
		- forward * camera_tuning.swing_offset.z
	)
	var look_target := swing_up * camera_tuning.look_at_height_m
	return swing_basis_for_view(
		forward,
		normal,
		look_target - camera_position
	)


static func wall_run_basis_for_view(
	strip_tangent: Vector3,
	strip_normal: Vector3,
	view_direction: Vector3,
	camera_tuning: CameraTuning
) -> Basis:
	var tangent := _normalized_or(strip_tangent, Vector3.BACK)
	var normal := strip_normal.slide(tangent).normalized()
	var view := _normalized_or(view_direction, -normal)
	if view.is_zero_approx():
		view = Vector3.FORWARD
	if normal.is_zero_approx():
		var fallback := _look_basis(view, Vector3.UP)
		if camera_tuning == null:
			return fallback
		return (
			Basis(
				view,
				deg_to_rad(camera_tuning.wall_run_bank_degrees)
			)
			* fallback
		).orthonormalized()
	var surface_up := tangent.cross(normal).normalized()
	var result := _basis_with_horizontal(view, tangent, surface_up)
	return _orient_up(result, surface_up)


static func grind_basis_for_view(
	rail_tangent: Vector3,
	rail_normal: Vector3,
	view_direction: Vector3
) -> Basis:
	var tangent := _normalized_or(rail_tangent, Vector3.BACK)
	var rail_up := rail_normal.slide(tangent).normalized()
	if rail_up.is_zero_approx():
		rail_up = Vector3.UP
	var view := _normalized_or(view_direction, -tangent)
	var result := _basis_with_horizontal(view, tangent, rail_up)
	return _orient_up(result, rail_up)


static func swing_basis_for_view(
	plane_forward: Vector3,
	plane_normal: Vector3,
	view_direction: Vector3
) -> Basis:
	var forward := _normalized_or(plane_forward, Vector3.FORWARD)
	var normal := plane_normal.slide(forward).normalized()
	if normal.is_zero_approx():
		normal = forward.cross(Vector3.UP).normalized()
	var swing_up := normal.cross(forward).normalized()
	if swing_up.is_zero_approx():
		swing_up = Vector3.UP
	var view := _normalized_or(view_direction, -normal)
	var result := _basis_with_horizontal(view, forward, swing_up)
	return _orient_up(result, swing_up)


static func look_basis(
	view_direction: Vector3,
	up_direction: Vector3
) -> Basis:
	return _look_basis(view_direction, up_direction)


static func _basis_with_horizontal(
	view_direction: Vector3,
	horizontal_direction: Vector3,
	fallback_up: Vector3
) -> Basis:
	var view := _normalized_or(view_direction, Vector3.FORWARD)
	var screen_right := horizontal_direction.slide(view).normalized()
	if screen_right.is_zero_approx():
		return _look_basis(view, fallback_up)
	var camera_back := -view
	var screen_up := camera_back.cross(screen_right).normalized()
	if screen_up.is_zero_approx():
		return _look_basis(view, fallback_up)
	return Basis(
		screen_right,
		screen_up,
		camera_back
	).orthonormalized()


static func _look_basis(
	view_direction: Vector3,
	up_direction: Vector3
) -> Basis:
	var view := _normalized_or(view_direction, Vector3.FORWARD)
	var camera_back := -view
	var up := _normalized_or(up_direction, Vector3.UP)
	var camera_right := up.cross(camera_back).normalized()
	if camera_right.is_zero_approx():
		camera_right = Vector3.RIGHT.slide(camera_back).normalized()
	if camera_right.is_zero_approx():
		camera_right = Vector3.FORWARD.slide(camera_back).normalized()
	var camera_up := camera_back.cross(camera_right).normalized()
	return Basis(
		camera_right,
		camera_up,
		camera_back
	).orthonormalized()


static func _orient_up(basis: Basis, desired_up: Vector3) -> Basis:
	if desired_up.is_zero_approx() or basis.y.dot(desired_up) >= 0.0:
		return basis
	return Basis(-basis.x, -basis.y, basis.z)


static func _normalized_or(
	value: Vector3,
	fallback: Vector3
) -> Vector3:
	var normalized := value.normalized()
	if normalized.is_zero_approx():
		return fallback.normalized()
	return normalized
