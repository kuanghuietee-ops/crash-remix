@tool
extends EditorScenePostImport

## glTF defines COLOR_0 as a multiplier for the material's base color, but the
## Godot 4.7 scene importer leaves that material flag disabled for these
## Blender-authored meshes. Preserve the imported material while making its
## authored vertex colors visible in gameplay and Look Dev. Preview cycles are
## also made explicitly cyclic here because glTF does not carry Blender's
## action-level looping intent.

const LOOPING_ANIMATION_SUFFIXES := [
	"_walk",
	"_idle",
	"_run",
	"_crawl",
	"_spin",
	"_grind",
	"_swing",
]


func _post_import(scene: Node) -> Object:
	_enable_vertex_color_albedo(scene)
	_enable_preview_loops(scene)
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


func _enable_preview_loops(node: Node) -> void:
	if node is AnimationPlayer:
		var animation_player := node as AnimationPlayer
		for animation_name: StringName in animation_player.get_animation_list():
			var should_loop := false
			for suffix: String in LOOPING_ANIMATION_SUFFIXES:
				if String(animation_name).ends_with(suffix):
					should_loop = true
					break
			if not should_loop:
				continue
			var animation := animation_player.get_animation(animation_name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR
	for child: Node in node.get_children():
		_enable_preview_loops(child)
