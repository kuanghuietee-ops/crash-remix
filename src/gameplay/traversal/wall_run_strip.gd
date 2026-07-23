class_name WallRunStrip
extends Path3D

const STRIP_GROUP := &"wall_run_strip"

@export var surface_normal := Vector3.RIGHT


func _ready() -> void:
	add_to_group(STRIP_GROUP)
	_ensure_curve_from_markers()


func sample_at(world_position: Vector3) -> TraversalSample:
	_ensure_curve_from_markers()
	if curve == null or curve.point_count == 0:
		return null
	return sample_at_distance(
		curve.get_closest_offset(to_local(world_position))
	)


func sample_at_distance(distance_along_m: float) -> TraversalSample:
	_ensure_curve_from_markers()
	if curve == null or curve.point_count == 0:
		return null
	var length_m := curve.get_baked_length()
	var clamped_distance_m := clampf(distance_along_m, 0.0, length_m)
	var tangent_step_m := curve.bake_interval
	if tangent_step_m <= 0.0:
		tangent_step_m = length_m
	var before_m := maxf(clamped_distance_m - tangent_step_m, 0.0)
	var after_m := minf(clamped_distance_m + tangent_step_m, length_m)
	var local_position := curve.sample_baked(clamped_distance_m)
	var local_before := curve.sample_baked(before_m)
	var local_after := curve.sample_baked(after_m)
	var tangent := (
		global_basis * (local_after - local_before).normalized()
	).normalized()
	var normal := (
		global_basis * surface_normal.normalized()
	).slide(tangent).normalized()
	if normal.is_zero_approx():
		normal = (global_basis * Vector3.RIGHT).slide(tangent).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	var sample := TraversalSample.new()
	sample.position = to_global(local_position)
	sample.tangent = tangent
	sample.normal = normal
	sample.distance_along_m = clamped_distance_m
	return sample


func length_m() -> float:
	_ensure_curve_from_markers()
	return curve.get_baked_length() if curve != null else 0.0


func _ensure_curve_from_markers() -> void:
	if curve != null and curve.point_count > 0:
		return
	var authored_curve := Curve3D.new()
	for child: Node in get_children():
		if child is Marker3D:
			authored_curve.add_point((child as Marker3D).position)
	curve = authored_curve
