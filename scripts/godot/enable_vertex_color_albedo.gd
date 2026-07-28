@tool
extends EditorScenePostImport

## glTF defines COLOR_0 as a multiplier for the material's base color, but the
## Godot 4.7 scene importer leaves that material flag disabled for these
## Blender-authored crate meshes. Preserve the single imported material while
## making its authored vertex colors visible in gameplay and Look Dev.


func _post_import(scene: Node) -> Object:
	_enable_vertex_color_albedo(scene)
	return scene


func _enable_vertex_color_albedo(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index: int in range(
				mesh_instance.mesh.get_surface_count()
			):
				var material := (
					mesh_instance.mesh.surface_get_material(surface_index)
					as BaseMaterial3D
				)
				if material != null:
					material.vertex_color_use_as_albedo = true
	for child: Node in node.get_children():
		_enable_vertex_color_albedo(child)
