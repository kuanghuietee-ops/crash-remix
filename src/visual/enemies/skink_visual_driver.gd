class_name SkinkVisualDriver
extends Node3D

signal defeat_finished

const IDLE := &"A_skink_idle"
const TELEGRAPH := &"A_skink_telegraph"
const DART := &"A_skink_dart"
const RETURN := &"A_skink_return"
const HIT := &"A_skink_hit"
const DEFEAT := &"A_skink_defeat"

const STATE_DORMANT := &"dormant"
const STATE_TELEGRAPH := &"telegraph"
const STATE_ACTIVE := &"active"
const STATE_COOLDOWN := &"cooldown"

@export var model_path: NodePath
@export var pivot_path: NodePath

var _animation_player: AnimationPlayer
var _pivot: Node3D
var _behavior_state := STATE_DORMANT
var _reaction: StringName = &""

@onready var _dart_burst := $DartBurst as GPUParticles3D
@onready var _defeat_burst := $DefeatBurst as GPUParticles3D


func _ready() -> void:
	var model := get_node_or_null(model_path)
	_pivot = get_node_or_null(pivot_path) as Node3D
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
	if not _reaction.is_empty():
		return
	_play_behavior()


func play_defeat() -> void:
	_reaction = HIT
	_restart_particles(_defeat_burst)
	if not _play(HIT):
		_begin_defeat_clip()


func reset_visual() -> void:
	_reaction = &""
	if _dart_burst != null:
		_dart_burst.emitting = false
	if _defeat_burst != null:
		_defeat_burst.emitting = false
	_play_behavior()


func _play_behavior() -> void:
	match _behavior_state:
		STATE_TELEGRAPH:
			_face_yaw(PI)
			_play(TELEGRAPH)
		STATE_ACTIVE:
			_face_yaw(PI * 0.5)
			_restart_particles(_dart_burst)
			_play(DART)
		STATE_COOLDOWN:
			_face_yaw(-PI * 0.5)
			_play(RETURN)
		_:
			_face_yaw(PI)
			_play(IDLE)


func _face_yaw(yaw: float) -> void:
	if _pivot != null:
		_pivot.rotation.y = yaw


func _play(clip: StringName) -> bool:
	if (
		_animation_player == null
		or not _animation_player.has_animation(clip)
	):
		push_error("Skink model is missing animation %s" % clip)
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
