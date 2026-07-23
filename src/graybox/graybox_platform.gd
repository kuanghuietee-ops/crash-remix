class_name GrayboxPlatform
extends StaticBody3D

@export var size := Vector3.ONE
@export var color := Color.WHITE
@export var hazard: bool


func _ready() -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collision_shape.shape = box_shape
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance != null:
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		mesh_instance.material_override = material
	if hazard:
		add_to_group("hazard")
