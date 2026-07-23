extends Node

signal phase_changed(active_set: StringName)

const PhaseSetType := preload("res://src/gameplay/phase/phase_set.gd")
const GHOST_SHADER := preload("res://assets/shaders/phase_ghost.gdshader")

var _phase_set: PhaseSetType = PhaseSetType.new()
var _phase_tuning: PhaseTuning
var _ghost_material := ShaderMaterial.new()


func _ready() -> void:
	_ghost_material.shader = GHOST_SHADER


func configure(phase_tuning: PhaseTuning) -> void:
	_phase_tuning = phase_tuning
	_ghost_material.set_shader_parameter(
		&"ghost_opacity",
		_phase_tuning.ghost_opacity
	)
	_ghost_material.set_shader_parameter(
		&"ghost_outline_width_m",
		_phase_tuning.ghost_outline_width_m
	)
	_apply_active_set()


func request_toggle(now_s: float) -> bool:
	if _phase_tuning == null:
		return false
	if not _phase_set.try_toggle(now_s, _phase_tuning):
		return false
	_apply_active_set()
	phase_changed.emit(_phase_set.active_set)
	return true


func active_set() -> StringName:
	return _phase_set.active_set


func _apply_active_set() -> void:
	if not is_inside_tree():
		return
	_apply_group(
		PhaseSetType.SET_BLUE,
		_phase_set.is_solid(PhaseSetType.SET_BLUE)
	)
	_apply_group(
		PhaseSetType.SET_ORANGE,
		_phase_set.is_solid(PhaseSetType.SET_ORANGE)
	)


func _apply_group(set_name: StringName, solid: bool) -> void:
	var group_name := StringName("phase_" + set_name)
	for phase_object: Node in get_tree().get_nodes_in_group(group_name):
		for child: Node in phase_object.find_children(
			"*",
			"CollisionShape3D",
			true,
			false
		):
			(child as CollisionShape3D).disabled = not solid
		for child: Node in phase_object.find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		):
			(child as MeshInstance3D).material_override = (
				null if solid else _ghost_material
			)
