class_name BlobShadow
extends Node3D

var _target: Node3D
var _depth_tuning: DepthTuning
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	top_level = true
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D


func configure(target: Node3D, depth_tuning: DepthTuning) -> void:
	_set_target(target)
	_depth_tuning = depth_tuning
	if _mesh_instance == null:
		_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance != null and _mesh_instance.mesh is PlaneMesh:
		var plane := _mesh_instance.mesh as PlaneMesh
		plane.size = Vector2.ONE * _depth_tuning.shadow_diameter_m
		var material := _mesh_instance.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter(
				"shadow_opacity",
				_depth_tuning.shadow_opacity
			)


static func ray_origin(
	target_position: Vector3,
	depth_tuning: DepthTuning,
	projection_direction_value := Vector3.DOWN
) -> Vector3:
	var direction := projection_direction_value.normalized()
	if direction.is_zero_approx():
		direction = Vector3.DOWN
	return (
		target_position
		- direction * depth_tuning.shadow_ray_origin_offset_m
	)


static func projection_direction(
	state: StringName,
	surface_normal: Vector3
) -> Vector3:
	if state == &"wall_run" and not surface_normal.is_zero_approx():
		return -surface_normal.normalized()
	return Vector3.DOWN


func _physics_process(_delta_s: float) -> void:
	if _target == null or _depth_tuning == null or not is_inside_tree():
		visible = false
		return
	var traversal_state := &""
	var surface_normal := Vector3.ZERO
	if _target.has_method("traversal_camera_context"):
		var context: Dictionary = _target.call(
			"traversal_camera_context"
		)
		traversal_state = context.get(&"state", &"")
		var normal_value: Variant = context.get(
			&"normal",
			Vector3.ZERO
		)
		if normal_value is Vector3:
			surface_normal = normal_value as Vector3
	var direction := projection_direction(
		traversal_state,
		surface_normal
	)
	var space_state := get_world_3d().direct_space_state
	var from := ray_origin(
		_target.global_position,
		_depth_tuning,
		direction
	)
	var to := from + direction * _depth_tuning.shadow_ray_length_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _target is CollisionObject3D:
		query.exclude = [(_target as CollisionObject3D).get_rid()]
	query.collide_with_areas = false
	var hit := space_state.intersect_ray(query)
	visible = not hit.is_empty()
	if hit.is_empty():
		return
	var surface_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	global_position = (
		surface_position
		+ hit_normal * _depth_tuning.shadow_surface_offset_m
	)
	_align_to_normal(hit_normal)


func _align_to_normal(surface_normal: Vector3) -> void:
	var tangent := Vector3.RIGHT.slide(surface_normal).normalized()
	if tangent.is_zero_approx():
		tangent = Vector3.FORWARD.slide(surface_normal).normalized()
	var bitangent := tangent.cross(surface_normal).normalized()
	global_basis = Basis(tangent, surface_normal, bitangent)


func _set_target(target: Node3D) -> void:
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
