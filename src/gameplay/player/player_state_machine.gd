class_name PlayerStateMachine
extends RefCounted

const STATE_GROUNDED := &"grounded"
const STATE_CROUCHED := &"crouched"
const STATE_SLIDING := &"sliding"
const STATE_AIRBORNE := &"airborne"
const STATE_BODY_SLAM := &"body_slam"
const STATE_SLAM_RECOVERY := &"slam_recovery"
const STATE_GRIND := &"grind"
const STATE_WALL_RUN := &"wall_run"
const STATE_SWING := &"swing"

var state := STATE_AIRBORNE
var is_spinning: bool

var _was_grounded: bool
var _last_grounded_s := -1.0
var _state_entered_s := 0.0
var _spin_ends_s := -1.0
var _wall_run_maximum_duration_s := -1.0
var _ground_jump_available: bool
var _double_jump_available := true
var _air_spin_available := true
var _slide_requires_down_release: bool


func step(
	now_s: float,
	grounded: bool,
	horizontal_speed_mps: float,
	intents: InputIntentBuffer,
	move_tuning: MoveTuning,
	input_tuning: InputTuning,
	_neighbour_available: bool
) -> PlayerFrameDecision:
	var decision := PlayerFrameDecision.new()
	decision.previous_state = state
	_update_spin_timer(now_s, decision)
	intents.prune_expired(
		now_s,
		maxf(input_tuning.jump_buffer_s, input_tuning.action_buffer_s)
	)

	var effective_grounded := grounded and not _is_traversal_state(state)
	var just_landed := effective_grounded and not _was_grounded
	decision.landed = just_landed
	if effective_grounded:
		_last_grounded_s = now_s
		if just_landed:
			_ground_jump_available = true
			_double_jump_available = true
			_air_spin_available = true
			if state == STATE_BODY_SLAM:
				_set_state(STATE_SLAM_RECOVERY, now_s)
			elif state == STATE_AIRBORNE:
				_set_state(STATE_GROUNDED, now_s)
	elif _was_grounded and _is_ground_state(state):
		_set_state(STATE_AIRBORNE, now_s)

	_expire_coyote_if_needed(now_s, effective_grounded, input_tuning)
	_update_timed_ground_states(
		now_s,
		effective_grounded,
		intents,
		move_tuning
	)
	_expire_wall_run_if_needed(now_s)

	if state == STATE_GRIND:
		_process_grind_jump(
			now_s,
			intents,
			input_tuning,
			_neighbour_available
		)
	elif state == STATE_WALL_RUN:
		_process_wall_run_jump(now_s, intents, input_tuning)
	elif state == STATE_SWING:
		_process_swing_jump(now_s, intents, input_tuning)
	elif state != STATE_BODY_SLAM and state != STATE_SLAM_RECOVERY:
		if effective_grounded:
			_process_ground_actions(
				now_s,
				horizontal_speed_mps,
				intents,
				move_tuning,
				input_tuning
			)
		else:
			_process_jump(now_s, false, intents, input_tuning)
			_process_air_down(now_s, intents, input_tuning)
		_process_spin(now_s, intents, move_tuning, input_tuning, decision)

	decision.impulse = _pending_impulse
	_pending_impulse = PlayerFrameDecision.IMPULSE_NONE
	decision.state = state
	_was_grounded = effective_grounded
	return decision


var _pending_impulse := PlayerFrameDecision.IMPULSE_NONE


func enter_grind(now_s: float) -> void:
	# A rail is a new traversal contact, so it starts a fresh airtime.
	_ground_jump_available = false
	_double_jump_available = true
	_air_spin_available = true
	_set_state(STATE_GRIND, now_s)


func enter_wall_run(
	now_s: float,
	maximum_duration_s: float
) -> void:
	_wall_run_maximum_duration_s = maxf(maximum_duration_s, 0.0)
	_set_state(STATE_WALL_RUN, now_s)


func enter_swing(now_s: float) -> void:
	_set_state(STATE_SWING, now_s)


func enter_airborne(now_s: float) -> void:
	_ground_jump_available = false
	_wall_run_maximum_duration_s = -1.0
	_set_state(STATE_AIRBORNE, now_s)


func _process_grind_jump(
	now_s: float,
	intents: InputIntentBuffer,
	input_tuning: InputTuning,
	neighbour_available: bool
) -> void:
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	):
		return
	intents.consume_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	)
	var lateral_input := intents.movement().x
	if not is_zero_approx(lateral_input) and neighbour_available:
		_pending_impulse = PlayerFrameDecision.IMPULSE_RAIL_HOP
	else:
		_pending_impulse = PlayerFrameDecision.IMPULSE_RAIL_EXIT
	_set_state(STATE_AIRBORNE, now_s)


func _process_wall_run_jump(
	now_s: float,
	intents: InputIntentBuffer,
	input_tuning: InputTuning
) -> void:
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	):
		return
	intents.consume_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	)
	_pending_impulse = PlayerFrameDecision.IMPULSE_WALL_DETACH
	enter_airborne(now_s)


func _expire_wall_run_if_needed(now_s: float) -> void:
	if (
		state == STATE_WALL_RUN
		and _wall_run_maximum_duration_s >= 0.0
		and now_s - _state_entered_s >= _wall_run_maximum_duration_s
	):
		enter_airborne(now_s)


func _process_swing_jump(
	now_s: float,
	intents: InputIntentBuffer,
	input_tuning: InputTuning
) -> void:
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	):
		return
	intents.consume_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	)
	_pending_impulse = PlayerFrameDecision.IMPULSE_SWING_RELEASE
	enter_airborne(now_s)


func _process_ground_actions(
	now_s: float,
	horizontal_speed_mps: float,
	intents: InputIntentBuffer,
	move_tuning: MoveTuning,
	input_tuning: InputTuning
) -> void:
	var jump_is_buffered := intents.has_buffered_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	)
	var down_is_buffered := intents.has_buffered_pressed(
		InputIntent.ACTION_DOWN,
		now_s,
		input_tuning.action_buffer_s
	)
	if jump_is_buffered and down_is_buffered:
		_process_jump(now_s, true, intents, input_tuning)
		if _pending_impulse != PlayerFrameDecision.IMPULSE_NONE:
			intents.consume_pressed(
				InputIntent.ACTION_DOWN,
				now_s,
				input_tuning.action_buffer_s
			)
		return
	_process_ground_down(
		now_s,
		horizontal_speed_mps,
		intents,
		move_tuning,
		input_tuning
	)
	_process_jump(now_s, true, intents, input_tuning)


func _process_jump(
	now_s: float,
	grounded: bool,
	intents: InputIntentBuffer,
	input_tuning: InputTuning
) -> void:
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		input_tuning.jump_buffer_s
	):
		return

	var impulse := PlayerFrameDecision.IMPULSE_NONE
	if grounded:
		if state == STATE_SLIDING:
			impulse = PlayerFrameDecision.IMPULSE_SLIDE_JUMP
		elif state == STATE_CROUCHED:
			impulse = PlayerFrameDecision.IMPULSE_HIGH_JUMP
		else:
			impulse = PlayerFrameDecision.IMPULSE_JUMP
	elif state == STATE_AIRBORNE:
		if _ground_jump_available:
			impulse = PlayerFrameDecision.IMPULSE_JUMP
		elif _double_jump_available:
			impulse = PlayerFrameDecision.IMPULSE_DOUBLE_JUMP

	if impulse == PlayerFrameDecision.IMPULSE_NONE:
		return
	intents.consume_pressed(InputIntent.ACTION_JUMP, now_s, input_tuning.jump_buffer_s)
	_pending_impulse = impulse
	if impulse == PlayerFrameDecision.IMPULSE_DOUBLE_JUMP:
		_double_jump_available = false
	else:
		_ground_jump_available = false
	_set_state(STATE_AIRBORNE, now_s)


func _process_ground_down(
	now_s: float,
	horizontal_speed_mps: float,
	intents: InputIntentBuffer,
	move_tuning: MoveTuning,
	input_tuning: InputTuning
) -> void:
	if not intents.is_action_pressed(InputIntent.ACTION_DOWN):
		_slide_requires_down_release = false
		if state == STATE_CROUCHED:
			_set_state(STATE_GROUNDED, now_s)

	if _slide_requires_down_release:
		return
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_DOWN,
		now_s,
		input_tuning.action_buffer_s
	):
		return

	intents.consume_pressed(InputIntent.ACTION_DOWN, now_s, input_tuning.action_buffer_s)
	if absf(horizontal_speed_mps) >= move_tuning.slide_minimum_speed_mps:
		_slide_requires_down_release = true
		_set_state(STATE_SLIDING, now_s)
	else:
		_set_state(STATE_CROUCHED, now_s)


func _process_air_down(
	now_s: float,
	intents: InputIntentBuffer,
	input_tuning: InputTuning
) -> void:
	if state != STATE_AIRBORNE:
		return
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_DOWN,
		now_s,
		input_tuning.action_buffer_s
	):
		return
	intents.consume_pressed(InputIntent.ACTION_DOWN, now_s, input_tuning.action_buffer_s)
	if _pending_impulse != PlayerFrameDecision.IMPULSE_NONE:
		return
	_pending_impulse = PlayerFrameDecision.IMPULSE_BODY_SLAM
	_set_state(STATE_BODY_SLAM, now_s)


func _process_spin(
	now_s: float,
	intents: InputIntentBuffer,
	move_tuning: MoveTuning,
	input_tuning: InputTuning,
	decision: PlayerFrameDecision
) -> void:
	if is_spinning:
		return
	var is_airborne := state == STATE_AIRBORNE
	if is_airborne and not _air_spin_available:
		return
	if not intents.has_buffered_pressed(
		InputIntent.ACTION_SPIN,
		now_s,
		input_tuning.action_buffer_s
	):
		return

	intents.consume_pressed(InputIntent.ACTION_SPIN, now_s, input_tuning.action_buffer_s)
	is_spinning = true
	_spin_ends_s = now_s + move_tuning.spin_active_s
	decision.spin_started = true
	if is_airborne:
		_air_spin_available = false


func _update_spin_timer(now_s: float, decision: PlayerFrameDecision) -> void:
	if is_spinning and now_s >= _spin_ends_s:
		is_spinning = false
		decision.spin_ended = true


func _expire_coyote_if_needed(
	now_s: float,
	grounded: bool,
	input_tuning: InputTuning
) -> void:
	if grounded or not _ground_jump_available or _last_grounded_s < 0.0:
		return
	var airborne_age_s := now_s - _last_grounded_s
	if (
		airborne_age_s > input_tuning.coyote_time_s
		and not is_equal_approx(airborne_age_s, input_tuning.coyote_time_s)
	):
		_ground_jump_available = false


func _update_timed_ground_states(
	now_s: float,
	grounded: bool,
	intents: InputIntentBuffer,
	move_tuning: MoveTuning
) -> void:
	if not grounded:
		return
	if state == STATE_SLIDING and now_s - _state_entered_s >= move_tuning.slide_duration_s:
		if intents.is_action_pressed(InputIntent.ACTION_DOWN):
			_set_state(STATE_CROUCHED, now_s)
		else:
			_set_state(STATE_GROUNDED, now_s)
	elif (
		state == STATE_SLAM_RECOVERY
		and now_s - _state_entered_s >= move_tuning.body_slam_recovery_s
	):
		_set_state(STATE_GROUNDED, now_s)


func _is_ground_state(candidate: StringName) -> bool:
	return (
		candidate == STATE_GROUNDED
		or candidate == STATE_CROUCHED
		or candidate == STATE_SLIDING
		or candidate == STATE_SLAM_RECOVERY
	)


func _is_traversal_state(candidate: StringName) -> bool:
	return (
		candidate == STATE_GRIND
		or candidate == STATE_WALL_RUN
		or candidate == STATE_SWING
	)


func _set_state(next_state: StringName, now_s: float) -> void:
	if state == next_state:
		return
	state = next_state
	_state_entered_s = now_s
