class_name TraversalRail
extends Path3D

const RAIL_GROUP := &"traversal_rail"

@export var camera_tuning: CameraTuning
@export_node_path("TraversalRail") var left_neighbor_path: NodePath
@export_node_path("TraversalRail") var right_neighbor_path: NodePath

var _cached_samples: Array[TraversalSample] = []
var _cached_global_transform := Transform3D.IDENTITY
var _cached_interval_m := -1.0
var _cached_length_m := -1.0
var _cache_initialized: bool
var _observed_curve: Curve3D


func _ready() -> void:
	add_to_group(RAIL_GROUP)
	_ensure_curve_from_markers()
	_observe_curve()
	_apply_bake_interval()


func samples() -> Array[TraversalSample]:
	_ensure_curve_from_markers()
	_observe_curve()
	_apply_bake_interval()
	if curve == null or curve.point_count == 0:
		return _cached_samples
	var length_m := curve.get_baked_length()
	if (
		_cache_initialized
		and _cached_global_transform == global_transform
		and is_equal_approx(_cached_interval_m, curve.bake_interval)
		and is_equal_approx(_cached_length_m, length_m)
	):
		return _cached_samples
	var result: Array[TraversalSample] = []
	result.append(sample_at_distance(0.0))
	if length_m <= 0.0:
		_store_cache(result, length_m)
		return _cached_samples
	var distance_m := curve.bake_interval
	while distance_m > 0.0 and distance_m < length_m:
		result.append(sample_at_distance(distance_m))
		distance_m += curve.bake_interval
	result.append(sample_at_distance(length_m))
	_store_cache(result, length_m)
	return _cached_samples


func sample_at_distance(distance_along_m: float) -> TraversalSample:
	_ensure_curve_from_markers()
	_apply_bake_interval()
	if curve == null or curve.point_count == 0:
		return null
	var length_m := curve.get_baked_length()
	var clamped_distance_m := clampf(distance_along_m, 0.0, length_m)
	var interval_m := curve.bake_interval
	var tangent_step_m := interval_m if interval_m > 0.0 else length_m
	var before_m := maxf(clamped_distance_m - tangent_step_m, 0.0)
	var after_m := minf(clamped_distance_m + tangent_step_m, length_m)
	var local_position := curve.sample_baked(clamped_distance_m)
	var local_before := curve.sample_baked(before_m)
	var local_after := curve.sample_baked(after_m)
	var local_tangent := (local_after - local_before).normalized()
	var tangent := (global_basis * local_tangent).normalized()
	var normal := (global_basis * Vector3.UP).slide(tangent).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	var sample := TraversalSample.new()
	sample.position = to_global(local_position)
	sample.tangent = tangent
	sample.normal = normal
	sample.distance_along_m = clamped_distance_m
	return sample


func closest_distance_m(world_position: Vector3) -> float:
	_ensure_curve_from_markers()
	_apply_bake_interval()
	if curve == null or curve.point_count == 0:
		return 0.0
	return curve.get_closest_offset(to_local(world_position))


func length_m() -> float:
	_ensure_curve_from_markers()
	_apply_bake_interval()
	return curve.get_baked_length() if curve != null else 0.0


func parallel_neighbor(direction: int) -> TraversalRail:
	var path := NodePath()
	if direction < 0:
		path = left_neighbor_path
	elif direction > 0:
		path = right_neighbor_path
	if path.is_empty():
		return null
	return get_node_or_null(path) as TraversalRail


func refresh_tuning(next_camera_tuning: CameraTuning) -> void:
	camera_tuning = next_camera_tuning
	_invalidate_cache()
	_apply_bake_interval()


func _apply_bake_interval() -> void:
	if (
		curve != null
		and camera_tuning != null
		and not is_equal_approx(
			curve.bake_interval,
			camera_tuning.rail_bake_interval_m
		)
	):
		curve.bake_interval = camera_tuning.rail_bake_interval_m


func _ensure_curve_from_markers() -> void:
	if curve != null and curve.point_count > 0:
		return
	var authored_curve := Curve3D.new()
	for child: Node in get_children():
		if child is Marker3D:
			authored_curve.add_point((child as Marker3D).position)
	curve = authored_curve


func _observe_curve() -> void:
	if _observed_curve == curve:
		return
	var changed_callback := Callable(self, "_invalidate_cache")
	if (
		_observed_curve != null
		and _observed_curve.changed.is_connected(changed_callback)
	):
		_observed_curve.changed.disconnect(changed_callback)
	_observed_curve = curve
	if (
		_observed_curve != null
		and not _observed_curve.changed.is_connected(changed_callback)
	):
		_observed_curve.changed.connect(changed_callback)
	_invalidate_cache()


func _store_cache(
	next_samples: Array[TraversalSample],
	length_m: float
) -> void:
	_cached_samples = next_samples
	_cached_global_transform = global_transform
	_cached_interval_m = curve.bake_interval
	_cached_length_m = length_m
	_cache_initialized = true


func _invalidate_cache() -> void:
	_cached_samples = []
	_cache_initialized = false
