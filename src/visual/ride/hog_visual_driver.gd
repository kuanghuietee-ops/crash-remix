class_name HogVisualDriver
extends Node

const IDLE := &"A_hog_idle"
const RUN := &"A_hog_run"
const JUMP := &"A_hog_jump"
const LAND := &"A_hog_land"

@export var model_path: NodePath

var _animation_player: AnimationPlayer
var _mounted := false
var _airborne := false
var _landing := false


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model != null:
		var candidates := model.find_children(
			"*",
			"AnimationPlayer",
			true,
			false
		)
		if candidates.size() == 1:
			_animation_player = candidates[0] as AnimationPlayer
	if (
		_animation_player != null
		and not _animation_player.animation_finished.is_connected(
			_on_animation_finished
		)
	):
		_animation_player.animation_finished.connect(
			_on_animation_finished
		)
	var mount := get_parent().get_parent()
	if mount != null and mount.has_signal(&"mounted"):
		mount.connect(&"mounted", _on_mounted)
	if mount != null and mount.has_signal(&"dismounted"):
		mount.connect(&"dismounted", _on_dismounted)
	_play(IDLE)


func _process(_delta: float) -> void:
	if not _mounted or _landing:
		return
	var rider := get_parent().get_parent() as CharacterBody3D
	if rider == null:
		return
	if _airborne:
		if not rider.is_on_floor():
			return
		_airborne = false
		_landing = _play(LAND)
	elif absf(rider.velocity.y) > 0.35:
		_airborne = true
		_play(JUMP)
	elif (
		_animation_player != null
		and _animation_player.current_animation != RUN
	):
		_play(RUN)


func _on_mounted() -> void:
	_mounted = true
	_airborne = false
	_landing = false
	_play(RUN)


func _on_dismounted() -> void:
	_mounted = false
	_airborne = false
	_landing = false
	_play(IDLE)


func _play(clip: StringName) -> bool:
	if (
		_animation_player == null
		or not _animation_player.has_animation(clip)
	):
		push_error("Hog model is missing animation %s" % clip)
		return false
	if _animation_player.current_animation != clip:
		_animation_player.play(clip)
	return true


func _on_animation_finished(clip: StringName) -> void:
	if clip != LAND or not _landing:
		return
	_landing = false
	if _mounted:
		_play(RUN)
	else:
		_play(IDLE)
