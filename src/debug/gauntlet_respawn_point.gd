class_name GauntletRespawnPoint
extends Area3D

@export_node_path("Marker3D") var spawn_marker_path := NodePath("Spawn")

var _activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func activate_for(body: Node3D) -> bool:
	var spawn := get_node_or_null(spawn_marker_path) as Marker3D
	if spawn == null or not body.has_method("set_spawn_transform"):
		return false
	body.call("set_spawn_transform", spawn.global_transform)
	_activated = true
	return true


func is_activated() -> bool:
	return _activated


func _on_body_entered(body: Node3D) -> void:
	activate_for(body)
