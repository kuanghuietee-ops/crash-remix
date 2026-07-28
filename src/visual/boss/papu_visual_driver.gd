class_name PapuVisualDriver
extends Node3D

const IDLE := &"A_papu_idle"
const SLAM := &"A_papu_slam"
const HIT := &"A_papu_hit"
const PHASE := &"A_papu_phase"
const DEFEAT := &"A_papu_defeat"
const SLAM_IMPACT_S := 11.0 / 24.0

@export var model_path: NodePath
@export var arena_path: NodePath

var _animation_player: AnimationPlayer
var _arena: Node
var _pivot: Node3D
var _phase := 0
var _slams := 0
var _reaction: StringName = &""
var _defeated := false

@onready var _slam_burst := $SlamBurst as GPUParticles3D
@onready var _phase_burst := $PhaseBurst as GPUParticles3D
@onready var _defeat_burst := $DefeatBurst as GPUParticles3D


func _ready() -> void:
	_pivot = get_parent() as Node3D
	_arena = get_node_or_null(arena_path)
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
	if _arena != null and _arena.has_signal(&"boss_defeated"):
		var callback := Callable(self, &"_on_boss_defeated")
		if not _arena.is_connected(&"boss_defeated", callback):
			_arena.connect(&"boss_defeated", callback)
	if _arena != null:
		_phase = int(_arena.call("current_phase"))
		_slams = int(_arena.call("slams_emitted"))
	_sync_anchor()
	_play(IDLE)


func _process(_delta: float) -> void:
	_sync_anchor()
	if _arena == null or _defeated:
		return
	var next_phase := int(_arena.call("current_phase"))
	var next_slams := int(_arena.call("slams_emitted"))
	if next_phase != _phase:
		_phase = next_phase
		_slams = next_slams
		_reaction = PHASE
		_restart_particles(_phase_burst)
		_play(PHASE, true)
		return
	if next_slams < _slams:
		_slams = next_slams
		_reaction = &""
		_play(IDLE)
		return
	if next_slams > _slams:
		_slams = next_slams
		_reaction = SLAM
		_restart_particles(_slam_burst)
		if _play(SLAM, true):
			# Gameplay reports a slam when it lands, so enter the authored
			# clip on its contact pose instead of replaying the wind-up late.
			_animation_player.seek(SLAM_IMPACT_S, true)


func _sync_anchor() -> void:
	if (
		_arena == null
		or _pivot == null
		or not _arena.has_method("visual_anchor_position")
	):
		return
	var anchor: Variant = _arena.call("visual_anchor_position")
	if typeof(anchor) == TYPE_VECTOR3:
		_pivot.global_position = anchor as Vector3


func _on_boss_defeated() -> void:
	_defeated = true
	_reaction = HIT
	_restart_particles(_defeat_burst)
	_play(HIT, true)


func _play(clip: StringName, restart := false) -> bool:
	if (
		_animation_player == null
		or not _animation_player.has_animation(clip)
	):
		push_error("Papu model is missing animation %s" % clip)
		return false
	if (
		restart
		or _animation_player.current_animation != clip
		or not _animation_player.is_playing()
	):
		_animation_player.play(clip)
	return true


func _restart_particles(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.emitting = true
	particles.restart()


func _on_animation_finished(clip: StringName) -> void:
	if clip == HIT and _defeated:
		_reaction = DEFEAT
		_play(DEFEAT, true)
		return
	if clip in [SLAM, PHASE] and _reaction == clip:
		_reaction = &""
		_play(IDLE)
