class_name TraversalAttachSolver
extends RefCounted


static func solve_rail_attach(
	arc_points: PackedVector3Array,
	samples: Array[TraversalSample],
	snap_distance_m: float
) -> int:
	if arc_points.is_empty() or samples.is_empty() or snap_distance_m < 0.0:
		return -1
	var snap_distance_squared := snap_distance_m * snap_distance_m
	if arc_points.size() == 1:
		for sample_index in samples.size():
			var sample := samples[sample_index]
			if (
				sample != null
				and _within_distance_squared(
					sample.position.distance_squared_to(arc_points[0]),
					snap_distance_squared
				)
			):
				return sample_index
		return -1

	for arc_index in range(arc_points.size() - 1):
		var segment_start := arc_points[arc_index]
		var segment_end := arc_points[arc_index + 1]
		var first_sample_index := -1
		var first_contact_along := INF
		for sample_index in samples.size():
			var sample := samples[sample_index]
			if sample == null:
				continue
			var contact_along := _point_segment_parameter(
				sample.position,
				segment_start,
				segment_end
			)
			var closest := segment_start + (
				segment_end - segment_start
			) * contact_along
			var distance_squared := sample.position.distance_squared_to(
				closest
			)
			if _within_distance_squared(
				distance_squared,
				snap_distance_squared
			):
				if contact_along < first_contact_along:
					first_contact_along = contact_along
					first_sample_index = sample_index
		if first_sample_index >= 0:
			return first_sample_index
	return -1


static func solve_wall_attach(
	_player_position: Vector3,
	player_velocity: Vector3,
	sample: TraversalSample,
	cone_degrees: float,
	minimum_entry_speed_mps: float
) -> bool:
	if sample == null:
		return false
	var horizontal_velocity := Vector3(
		player_velocity.x,
		0.0,
		player_velocity.z
	)
	var horizontal_speed := horizontal_velocity.length()
	if horizontal_velocity.is_zero_approx():
		return false
	if (
		horizontal_speed < minimum_entry_speed_mps
		and not is_equal_approx(horizontal_speed, minimum_entry_speed_mps)
	):
		return false
	var horizontal_tangent := Vector3(
		sample.tangent.x,
		0.0,
		sample.tangent.z
	)
	if horizontal_tangent.is_zero_approx():
		return false
	var heading_angle := horizontal_velocity.angle_to(horizontal_tangent)
	var cone_radians := maxf(deg_to_rad(cone_degrees), 0.0)
	return heading_angle < cone_radians or is_equal_approx(
		heading_angle,
		cone_radians
	)


static func nearest_sample_index(
	position: Vector3,
	samples: Array[TraversalSample]
) -> int:
	var nearest_index := -1
	var nearest_distance_squared := INF
	for sample_index in samples.size():
		var sample := samples[sample_index]
		if sample == null:
			continue
		var distance_squared := position.distance_squared_to(sample.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_index = sample_index
	return nearest_index


static func _point_segment_parameter(
	point: Vector3,
	segment_start: Vector3,
	segment_end: Vector3
) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if is_zero_approx(length_squared):
		return 0.0
	return clampf(
		(point - segment_start).dot(segment) / length_squared,
		0.0,
		1.0
	)


static func _within_distance_squared(
	distance_squared: float,
	maximum_distance_squared: float
) -> bool:
	return (
		distance_squared < maximum_distance_squared
		or is_equal_approx(distance_squared, maximum_distance_squared)
	)
