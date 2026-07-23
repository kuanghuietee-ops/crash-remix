class_name LandingRing
extends Node3D

const DepthPredictionType := preload("res://src/gameplay/depth/depth_prediction.gd")

var _target: CharacterBody3D
var _move_tuning: MoveTuning
var _depth_tuning: DepthTuning
var _grind_tuning: GrindTuning
var _traversal_rails: Array[Node] = []
var _mesh_instance: MeshInstance3D
var _probe_shape: SphereShape3D = SphereShape3D.new()
var _current_ring_position := Vector3.ZERO


func _ready() -> void:
	top_level = true
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	visible = false


func configure(
	target: CharacterBody3D,
	move_tuning: MoveTuning,
	depth_tuning: DepthTuning,
	grind_tuning: GrindTuning = null,
	traversal_rails: Array = []
) -> void:
	_set_target(target)
	_move_tuning = move_tuning
	_depth_tuning = depth_tuning
	_grind_tuning = grind_tuning
	_traversal_rails.clear()
	for candidate: Variant in traversal_rails:
		if candidate is Node and candidate.has_method("samples"):
			_traversal_rails.append(candidate as Node)
	_probe_shape.radius = _depth_tuning.collision_probe_radius_m
	if _mesh_instance == null:
		_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance != null and _mesh_instance.mesh is TorusMesh:
		var torus := _mesh_instance.mesh as TorusMesh
		torus.outer_radius = _depth_tuning.ring_outer_radius_m
		torus.inner_radius = _depth_tuning.ring_inner_radius_m


static func resolve_colour(
	arc_points: PackedVector3Array,
	rail_samples: Array[TraversalSample],
	surface_is_landable: bool,
	depth_tuning: DepthTuning,
	rail_attach_snap_m := -1.0
) -> Color:
	if depth_tuning == null:
		return Color.TRANSPARENT
	if not surface_is_landable:
		return depth_tuning.hazard_color
	var resolved_snap_m := rail_attach_snap_m
	if resolved_snap_m < 0.0:
		resolved_snap_m = depth_tuning.ring_outer_radius_m
	if (
		DepthPredictionType.first_rail_contact_index(
			arc_points,
			rail_samples,
			resolved_snap_m
		)
		>= 0
	):
		return depth_tuning.rail_predicted_color
	return depth_tuning.landable_color


func current_ring_position() -> Vector3:
	return _current_ring_position


func _physics_process(_delta_s: float) -> void:
	if _target == null or _move_tuning == null or _depth_tuning == null:
		visible = false
		return
	var context := _landing_prediction_context()
	if context.get(&"state", &"") == &"grind":
		visible = false
		return
	if (
		_target.is_on_floor()
		and _target.velocity.y <= 0.0
		and context.get(&"state", &"") != &"wall_run"
		and context.get(&"state", &"") != &"swing"
	):
		visible = false
		return
	var points := DepthPredictionType.trajectory_points_for_context(
		context,
		_move_tuning,
		_depth_tuning
	)
	var rail_samples := _rail_samples()
	var rail_snap_m := _depth_tuning.ring_outer_radius_m
	if _grind_tuning != null:
		rail_snap_m = _grind_tuning.attach_snap_m
	var rail_index := DepthPredictionType.first_rail_contact_index(
		points,
		rail_samples,
		rail_snap_m
	)
	var hit := _first_trajectory_hit(points)
	var surface_is_landable := not _hit_is_hazard(hit)
	var color := resolve_colour(
		points,
		rail_samples,
		surface_is_landable,
		_depth_tuning,
		rail_snap_m
	)
	if not surface_is_landable and not hit.is_empty():
		_show_hit(hit, color)
		return
	if rail_index >= 0:
		var rail_sample := rail_samples[rail_index]
		_show_at(
			rail_sample.position,
			rail_sample.normal,
			color
		)
		return
	if hit.is_empty():
		visible = false
		return
	_show_hit(hit, color)


func _landing_prediction_context() -> Dictionary:
	var spinning := false
	if _target.has_method("is_spinning"):
		spinning = bool(_target.call("is_spinning"))
	var context := {
		&"state": &"",
		&"origin": _target.global_position,
		&"velocity": _target.velocity,
		&"spinning": spinning,
	}
	# This is the named FSM/pendulum channel consumed by the ring.
	if _target.has_method("landing_prediction_context"):
		var value: Variant = _target.call("landing_prediction_context")
		if value is Dictionary:
			for key: Variant in (value as Dictionary):
				context[key] = (value as Dictionary)[key]
	return context


func _rail_samples() -> Array[TraversalSample]:
	var result: Array[TraversalSample] = []
	for rail: Node in _traversal_rails:
		if not is_instance_valid(rail) or not rail.has_method("samples"):
			continue
		var value: Variant = rail.call("samples")
		if not value is Array:
			continue
		for candidate: Variant in value as Array:
			if candidate is TraversalSample:
				result.append(candidate as TraversalSample)
	return result


func _hit_is_hazard(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider", null)
	if collider == null and hit.has("collider_id"):
		collider = instance_from_id(int(hit["collider_id"]))
	return (
		collider is Node
		and (collider as Node).is_in_group("hazard")
	)


func _show_hit(hit: Dictionary, color: Color) -> void:
	var surface_position: Vector3 = hit["position"]
	var surface_normal: Vector3 = hit["normal"]
	_show_at(surface_position, surface_normal, color)


func _show_at(
	surface_position: Vector3,
	surface_normal: Vector3,
	color: Color
) -> void:
	var normal := surface_normal.normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	visible = true
	_current_ring_position = surface_position
	global_position = (
		surface_position
		+ normal * _depth_tuning.ring_surface_offset_m
	)
	_align_to_normal(normal)
	_set_color(color)


func _first_trajectory_hit(points: PackedVector3Array) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var final_index := points.size() - 1
	for index in range(1, points.size()):
		var query := PhysicsRayQueryParameters3D.create(
			points[index - 1],
			points[index]
		)
		query.exclude = [_target.get_rid()]
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit
		if not DepthPredictionType.should_collision_probe(
			index,
			final_index,
			_depth_tuning.collision_probe_stride
		):
			continue
		var probe := PhysicsShapeQueryParameters3D.new()
		probe.shape = _probe_shape
		probe.transform = Transform3D(Basis.IDENTITY, points[index])
		probe.exclude = [_target.get_rid()]
		probe.collide_with_areas = false
		var nearby_hit := space_state.get_rest_info(probe)
		if not nearby_hit.is_empty():
			nearby_hit["position"] = nearby_hit["point"]
			return nearby_hit
	return {}


func _align_to_normal(surface_normal: Vector3) -> void:
	var tangent := Vector3.RIGHT.slide(surface_normal).normalized()
	if tangent.is_zero_approx():
		tangent = Vector3.FORWARD.slide(surface_normal).normalized()
	var bitangent := tangent.cross(surface_normal).normalized()
	global_basis = Basis(tangent, surface_normal, bitangent)


func _set_color(color: Color) -> void:
	if _mesh_instance == null:
		return
	var material := _mesh_instance.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color


func _set_target(target: CharacterBody3D) -> void:
	var callback := Callable(self, "_on_target_respawned")
	if (
		is_instance_valid(_target)
		and _target.has_signal("respawned")
		and _target.is_connected("respawned", callback)
	):
		_target.disconnect("respawned", callback)
	_target = target
	if (
		is_instance_valid(_target)
		and _target.has_signal("respawned")
		and not _target.is_connected("respawned", callback)
	):
		_target.connect("respawned", callback)


func _on_target_respawned() -> void:
	reset_physics_interpolation()
