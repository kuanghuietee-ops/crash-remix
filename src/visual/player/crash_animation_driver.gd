class_name CrashAnimationDriver
extends Node

const PlayerStateMachineType := preload(
	"res://src/gameplay/player/player_state_machine.gd"
)
const PlayerFrameDecisionType := preload(
	"res://src/gameplay/player/player_frame_decision.gd"
)

const IDLE := &"A_crash_idle"
const BORED_IDLE := &"A_crash_bored_idle"
const RUN := &"A_crash_run"
const CROUCH := &"A_crash_crouch"
const CRAWL := &"A_crash_crawl"
const JUMP := &"A_crash_jump"
const DOUBLE_JUMP := &"A_crash_double_jump"
const SPIN := &"A_crash_spin"
const SLIDE := &"A_crash_slide"
const SLAM := &"A_crash_slam"
const HIT := &"A_crash_hit"
const DEATH := &"A_crash_death_knockout"
const WIN := &"A_crash_win"
const WALL_RUN := &"A_crash_wall_run"
const GRIND := &"A_crash_grind"
const SWING := &"A_crash_swing"

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
@export_range(0.0, 30.0, 0.25, "or_greater")
var bored_idle_delay_s := 5.0
@export_range(0.0, 0.5, 0.01)
var transition_blend_s := 0.06

var _controller: CharacterBody3D
var _model: Node3D
var _animation_player: AnimationPlayer
var _state := STATE_AIRBORNE
var _airborne_clip := JUMP
var _spinning: bool
var _current_clip := &""
var _idle_elapsed_s := 0.0
var _hit_reaction_active: bool
var _victory_active: bool


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
	_animation_player.animation_finished.connect(_on_animation_finished)
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
	_controller.connect(&"hit_received", Callable(self, "_on_hit_received"))
	_controller.connect(
		&"victory_started",
		Callable(self, "_on_victory_started")
	)
	_controller.connect(&"respawned", Callable(self, "_on_respawned"))
	_refresh()


func _process(delta_s: float) -> void:
	_refresh_facing(delta_s)
	_refresh(delta_s)


func current_clip() -> StringName:
	return _current_clip


static func clip_for(
	state: StringName,
	spinning: bool,
	airborne_clip: StringName,
	moving: bool,
	bored: bool
) -> StringName:
	if spinning:
		return SPIN
	match state:
		STATE_GROUNDED:
			if moving:
				return RUN
			return BORED_IDLE if bored else IDLE
		STATE_CROUCHED:
			return CRAWL if moving else CROUCH
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
		STATE_GRIND:
			return GRIND
		STATE_WALL_RUN:
			return WALL_RUN
		STATE_SWING:
			return SWING
		STATE_RIDE:
			return RUN
	return IDLE


static func idle_elapsed_after(
	current_s: float,
	delta_s: float,
	state: StringName,
	spinning: bool,
	moving: bool
) -> float:
	if state != STATE_GROUNDED or spinning or moving:
		return 0.0
	return maxf(current_s, 0.0) + maxf(delta_s, 0.0)


static func reaction_clip_for(
	respawning: bool,
	hit_active: bool
) -> StringName:
	return override_clip_for(false, respawning, hit_active)


static func override_clip_for(
	victory_active: bool,
	respawning: bool,
	hit_active: bool
) -> StringName:
	if respawning:
		return DEATH
	if victory_active:
		return WIN
	return HIT if hit_active else &""


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


func _on_hit_received(fatal: bool) -> void:
	_hit_reaction_active = not fatal
	_idle_elapsed_s = 0.0
	_refresh()


func _on_victory_started() -> void:
	_victory_active = true
	_hit_reaction_active = false
	_idle_elapsed_s = 0.0
	_refresh()


func _on_respawned() -> void:
	_hit_reaction_active = false
	_victory_active = false
	_airborne_clip = JUMP
	_state = _controller.call("current_state")
	_spinning = _controller.call("is_spinning")
	_refresh()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == HIT:
		_hit_reaction_active = false
		_refresh()
		return
	if animation_name == WIN and _victory_active:
		_controller.call("finish_victory")


func _refresh(delta_s := 0.0) -> void:
	if _controller == null or _animation_player == null:
		return
	var reaction_clip := override_clip_for(
		_victory_active,
		_controller.call("is_respawning"),
		_hit_reaction_active
	)
	if not reaction_clip.is_empty():
		_idle_elapsed_s = 0.0
		_play(reaction_clip)
		return
	var moving := not Vector2(
		_controller.velocity.x,
		_controller.velocity.z
	).is_zero_approx()
	_idle_elapsed_s = idle_elapsed_after(
		_idle_elapsed_s,
		delta_s,
		_state,
		_spinning,
		moving
	)
	var bored := _idle_elapsed_s >= maxf(bored_idle_delay_s, 0.0)
	_play(
		clip_for(
			_state,
			_spinning,
			_airborne_clip,
			moving,
			bored
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
	_animation_player.play(
		clip,
		maxf(transition_blend_s, 0.0)
	)
	_current_clip = clip
