class_name LandingRing
extends Node3D

const DepthPredictionType := preload("res://src/gameplay/depth/depth_prediction.gd")

var _target: CharacterBody3D
var _move_tuning: MoveTuning
var _depth_tuning: DepthTuning
var _mesh_instance: MeshInstance3D
var _probe_shape: SphereShape3D = SphereShape3D.new()


func _ready() -> void:
	top_level = true
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	visible = false


func configure(
	target: CharacterBody3D,
	move_tuning: MoveTuning,
	depth_tuning: DepthTuning
) -> void:
	_set_target(target)
	_move_tuning = move_tuning
	_depth_tuning = depth_tuning
	_probe_shape.radius = _depth_tuning.collision_probe_radius_m
	if _mesh_instance == null:
		_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance != null and _mesh_instance.mesh is TorusMesh:
		var torus := _mesh_instance.mesh as TorusMesh
		torus.outer_radius = _depth_tuning.ring_outer_radius_m
		torus.inner_radius = _depth_tuning.ring_inner_radius_m


func _physics_process(_delta_s: float) -> void:
	if _target == null or _move_tuning == null or _depth_tuning == null:
		visible = false
		return
	if _target.is_on_floor() and _target.velocity.y <= 0.0:
		visible = false
		return
	var spinning := false
	if _target.has_method("is_spinning"):
		spinning = bool(_target.call("is_spinning"))
	var points := DepthPredictionType.trajectory_points(
		_target.global_position,
		_target.velocity,
		spinning,
		_move_tuning,
		_depth_tuning
	)
	var hit := _first_trajectory_hit(points)
	visible = not hit.is_empty()
	if hit.is_empty():
		return
	var surface_position: Vector3 = hit["position"]
	var surface_normal: Vector3 = hit["normal"]
	global_position = (
		surface_position
		+ surface_normal * _depth_tuning.ring_surface_offset_m
	)
	_align_to_normal(surface_normal)
	var collider: Object = hit.get("collider", null)
	if collider == null and hit.has("collider_id"):
		collider = instance_from_id(int(hit["collider_id"]))
	var color := _depth_tuning.landable_color
	if collider is Node and (collider as Node).is_in_group("hazard"):
		color = _depth_tuning.hazard_color
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
