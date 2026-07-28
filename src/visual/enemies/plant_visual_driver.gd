class_name PlantVisualDriver
extends Node3D

signal defeat_finished

const IDLE := &"A_plant_idle"
const TELEGRAPH := &"A_plant_telegraph"
const CHOMP := &"A_plant_chomp"
const RECOVER := &"A_plant_recover"
const HIT := &"A_plant_hit"
const DEFEAT := &"A_plant_defeat"

const STATE_DORMANT := &"dormant"
const STATE_TELEGRAPH := &"telegraph"
const STATE_ACTIVE := &"active"
const STATE_COOLDOWN := &"cooldown"

@export var model_path: NodePath

var _animation_player: AnimationPlayer
var _behavior_state := STATE_DORMANT
var _reaction: StringName = &""

@onready var _bite_burst := $BiteBurst as GPUParticles3D
@onready var _defeat_burst := $DefeatBurst as GPUParticles3D


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
	reset_visual()


func set_behavior_state(state: StringName) -> void:
	_behavior_state = state
	if _reaction.is_empty():
		_play_behavior()


func play_defeat() -> void:
	_reaction = HIT
	_restart_particles(_defeat_burst)
	if not _play(HIT):
		_begin_defeat_clip()


func reset_visual() -> void:
	_reaction = &""
	if _bite_burst != null:
		_bite_burst.emitting = false
	if _defeat_burst != null:
		_defeat_burst.emitting = false
	_play_behavior()


func _play_behavior() -> void:
	match _behavior_state:
		STATE_TELEGRAPH:
			_play(TELEGRAPH)
		STATE_ACTIVE:
			_restart_particles(_bite_burst)
			_play(CHOMP)
		STATE_COOLDOWN:
			_play(RECOVER)
		_:
			_play(IDLE)


func _play(clip: StringName) -> bool:
	if (
		_animation_player == null
		or not _animation_player.has_animation(clip)
	):
		push_error("Plant model is missing animation %s" % clip)
		return false
	if _animation_player.current_animation != clip:
		_animation_player.play(clip)
	return true


func _restart_particles(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.emitting = true
	particles.restart()


func _on_animation_finished(clip: StringName) -> void:
	if clip == HIT and _reaction == HIT:
		_begin_defeat_clip()
		return
	if clip == DEFEAT and _reaction == DEFEAT:
		_reaction = &""
		defeat_finished.emit()


func _begin_defeat_clip() -> void:
	_reaction = DEFEAT
	if not _play(DEFEAT):
		_reaction = &""
		defeat_finished.emit()
