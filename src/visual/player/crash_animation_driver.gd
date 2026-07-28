class_name CrashAnimationDriver
extends Node

const PlayerStateMachineType := preload(
	"res://src/gameplay/player/player_state_machine.gd"
)
const PlayerFrameDecisionType := preload(
	"res://src/gameplay/player/player_frame_decision.gd"
)

const IDLE := &"A_crash_idle"
const RUN := &"A_crash_run"
const CROUCH := &"A_crash_crouch"
const JUMP := &"A_crash_jump"
const DOUBLE_JUMP := &"A_crash_double_jump"
const SPIN := &"A_crash_spin"
const SLIDE := &"A_crash_slide"
const SLAM := &"A_crash_slam"

const STATE_GROUNDED := PlayerStateMachineType.STATE_GROUNDED
const STATE_CROUCHED := PlayerStateMachineType.STATE_CROUCHED
const STATE_SLIDING := PlayerStateMachineType.STATE_SLIDING
const STATE_AIRBORNE := PlayerStateMachineType.STATE_AIRBORNE
const STATE_BODY_SLAM := PlayerStateMachineType.STATE_BODY_SLAM
const STATE_SLAM_RECOVERY := PlayerStateMachineType.STATE_SLAM_RECOVERY
const STATE_GRIND := PlayerStateMachineType.STATE_GRIND
const STATE_WALL_RUN := PlayerStateMachineType.STATE_WALL_RUN
const STATE_SWING := PlayerStateMachineType.STATE_SWING
const STATE_RIDE := PlayerStateMachineType.STATE_RIDE

@export var controller_path: NodePath
@export var model_path: NodePath
@export var facing_turn_speed_radians_per_second := 24.0

var _controller: CharacterBody3D
var _model: Node3D
var _animation_player: AnimationPlayer
var _state := STATE_AIRBORNE
var _airborne_clip := JUMP
var _spinning: bool
var _current_clip := &""


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as CharacterBody3D
	_model = get_node_or_null(model_path) as Node3D
	if _controller == null or _model == null:
		push_error("Crash animation driver paths must resolve")
		set_process(false)
		return
	var animation_players := _model.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	if animation_players.size() != 1:
		push_error("Crash model must contain exactly one AnimationPlayer")
		set_process(false)
		return
	_animation_player = animation_players[0] as AnimationPlayer
	_state = _controller.call("current_state")
	_spinning = _controller.call("is_spinning")
	_controller.connect(
		&"state_changed",
		Callable(self, "_on_state_changed")
	)
	_controller.connect(
		&"spin_changed",
		Callable(self, "_on_spin_changed")
	)
	_controller.connect(
		&"movement_impulse_applied",
		Callable(self, "_on_movement_impulse_applied")
	)
	_refresh()


func _process(delta_s: float) -> void:
	_refresh_facing(delta_s)
	_refresh()


func current_clip() -> StringName:
	return _current_clip


static func clip_for(
	state: StringName,
	spinning: bool,
	airborne_clip: StringName,
	moving: bool
) -> StringName:
	if spinning:
		return SPIN
	match state:
		STATE_GROUNDED:
			return RUN if moving else IDLE
		STATE_CROUCHED:
			return CROUCH
		STATE_SLIDING:
			return SLIDE
		STATE_BODY_SLAM, STATE_SLAM_RECOVERY:
			return SLAM
		STATE_AIRBORNE:
			return (
				airborne_clip
				if airborne_clip in [JUMP, DOUBLE_JUMP]
				else JUMP
			)
		STATE_GRIND, STATE_WALL_RUN, STATE_RIDE:
			return RUN
		STATE_SWING:
			return JUMP
	return IDLE


static func clip_for_impulse(impulse: StringName) -> StringName:
	if impulse == PlayerFrameDecisionType.IMPULSE_DOUBLE_JUMP:
		return DOUBLE_JUMP
	if impulse == PlayerFrameDecisionType.IMPULSE_BODY_SLAM:
		return SLAM
	if impulse in [
		PlayerFrameDecisionType.IMPULSE_JUMP,
		PlayerFrameDecisionType.IMPULSE_HIGH_JUMP,
		PlayerFrameDecisionType.IMPULSE_SLIDE_JUMP,
		PlayerFrameDecisionType.IMPULSE_RAIL_HOP,
		PlayerFrameDecisionType.IMPULSE_RAIL_EXIT,
		PlayerFrameDecisionType.IMPULSE_WALL_DETACH,
		PlayerFrameDecisionType.IMPULSE_SWING_RELEASE,
		PlayerFrameDecisionType.IMPULSE_RIDE_JUMP,
	]:
		return JUMP
	return &""


static func yaw_for_velocity(
	velocity: Vector3,
	fallback_yaw: float
) -> float:
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.is_zero_approx():
		return fallback_yaw
	return atan2(horizontal.x, horizontal.y)


func _on_state_changed(
	previous_state: StringName,
	state: StringName
) -> void:
	_state = state
	if state == STATE_AIRBORNE and previous_state != STATE_AIRBORNE:
		_airborne_clip = JUMP
	_refresh()


func _on_spin_changed(active: bool) -> void:
	_spinning = active
	_refresh()


func _on_movement_impulse_applied(impulse: StringName) -> void:
	var clip := clip_for_impulse(impulse)
	if clip in [JUMP, DOUBLE_JUMP]:
		_airborne_clip = clip
	_refresh()


func _refresh() -> void:
	if _controller == null or _animation_player == null:
		return
	var moving := not Vector2(
		_controller.velocity.x,
		_controller.velocity.z
	).is_zero_approx()
	_play(
		clip_for(
			_state,
			_spinning,
			_airborne_clip,
			moving
		)
	)


func _refresh_facing(delta_s: float) -> void:
	if _controller == null or _model == null or _spinning:
		return
	var target_yaw := yaw_for_velocity(
		_controller.velocity,
		_model.rotation.y
	)
	var turn_weight := minf(
		maxf(facing_turn_speed_radians_per_second, 0.0)
		* maxf(delta_s, 0.0),
		1.0
	)
	_model.rotation.y = lerp_angle(
		_model.rotation.y,
		target_yaw,
		turn_weight
	)


func _play(clip: StringName) -> void:
	if clip == _current_clip:
		return
	if not _animation_player.has_animation(clip):
		push_error("Crash model is missing animation %s" % clip)
		return
	_animation_player.play(clip)
	_current_clip = clip
