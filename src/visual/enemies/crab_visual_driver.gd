class_name CrabVisualDriver
extends Node3D

signal defeat_finished

const IDLE := &"A_crab_idle"
const WALK := &"A_crab_walk"
const ATTACK := &"A_crab_attack"
const HIT := &"A_crab_hit"
const DEFEAT := &"A_crab_defeat"

@export var model_path: NodePath

var _animation_player: AnimationPlayer
var _moving: bool = true
var _reaction: StringName = &""

@onready var _attack_burst := $AttackBurst as GPUParticles3D
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


func set_patrolling(moving: bool) -> void:
	_moving = moving
	if _reaction.is_empty():
		_play(WALK if _moving else IDLE)


func play_attack() -> void:
	if _reaction in [HIT, DEFEAT]:
		return
	_reaction = ATTACK
	_restart_particles(_attack_burst)
	_play(ATTACK)


func play_defeat() -> void:
	_reaction = HIT
	_restart_particles(_defeat_burst)
	if not _play(HIT):
		_begin_defeat_clip()


func reset_visual() -> void:
	_reaction = &""
	if _attack_burst != null:
		_attack_burst.emitting = false
	if _defeat_burst != null:
		_defeat_burst.emitting = false
	_play(WALK if _moving else IDLE)


func _play(clip: StringName) -> bool:
	if (
		_animation_player == null
		or not _animation_player.has_animation(clip)
	):
		push_error("Crab model is missing animation %s" % clip)
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
		return
	if clip == ATTACK and _reaction == ATTACK:
		_reaction = &""
		_play(WALK if _moving else IDLE)


func _begin_defeat_clip() -> void:
	_reaction = DEFEAT
	if not _play(DEFEAT):
		_reaction = &""
		defeat_finished.emit()
