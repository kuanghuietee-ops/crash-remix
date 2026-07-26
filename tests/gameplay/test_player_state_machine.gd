extends GutTest

const INTENT_SCRIPT_PATH := "res://src/gameplay/input/input_intent.gd"
const BUFFER_SCRIPT_PATH := "res://src/gameplay/input/input_intent_buffer.gd"
const FSM_SCRIPT_PATH := "res://src/gameplay/player/player_state_machine.gd"
const FRAME_DECISION_SCRIPT_PATH := "res://src/gameplay/player/player_frame_decision.gd"
const KINEMATICS_SCRIPT_PATH := "res://src/gameplay/player/jump_kinematics.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _move: Resource
var _input: Resource


func before_all() -> void:
	var catalog: Resource = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.get("move")
		_input = catalog.get("input")


func test_ground_jump_then_only_one_double_jump() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 0.0, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 0.01)
	var ground_jump: RefCounted = fsm.call(
		"step", 0.01, true, 0.0, buffer, _move, _input, false
	)
	_release(buffer, &"jump", 0.02)
	_press(buffer, &"jump", 0.2)
	var double_jump: RefCounted = fsm.call(
		"step", 0.2, false, 0.0, buffer, _move, _input, false
	)
	_release(buffer, &"jump", 0.21)
	_press(buffer, &"jump", 0.4)
	var third_jump: RefCounted = fsm.call(
		"step", 0.4, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(ground_jump.get("impulse"), &"jump")
	assert_eq(double_jump.get("impulse"), &"double_jump")
	assert_eq(third_jump.get("impulse"), &"none")


func test_coyote_jump_uses_ground_jump_inside_exact_window() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 1.0, true, 0.0, buffer, _move, _input, false)
	fsm.call("step", 1.01, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 1.14)

	var decision: RefCounted = fsm.call(
		"step", 1.14, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"jump")


func test_coyote_boundary_stays_inclusive_at_a_later_clock_origin() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 10.0, true, 0.0, buffer, _move, _input, false)
	fsm.call("step", 10.01, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 10.14)

	var decision: RefCounted = fsm.call(
		"step", 10.14, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"jump")


func test_jump_just_outside_coyote_window_uses_double_jump() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 2.0, true, 0.0, buffer, _move, _input, false)
	fsm.call("step", 2.01, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 2.141)

	var decision: RefCounted = fsm.call(
		"step", 2.141, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"double_jump")


func test_buffered_jump_fires_on_landing_after_both_jumps_are_spent() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 3.0, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 3.01)
	fsm.call("step", 3.01, true, 0.0, buffer, _move, _input, false)
	_release(buffer, &"jump", 3.02)
	_press(buffer, &"jump", 3.2)
	fsm.call("step", 3.2, false, 0.0, buffer, _move, _input, false)
	_release(buffer, &"jump", 3.21)
	_press(buffer, &"jump", 4.0)
	fsm.call("step", 4.0, false, 0.0, buffer, _move, _input, false)

	var decision: RefCounted = fsm.call(
		"step", 4.119, true, 0.0, buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"jump")
	assert_true(decision.get("landed"))


func test_down_still_crouches_and_down_while_running_slides() -> void:
	var crouch_fsm: RefCounted = _new_fsm()
	var crouch_buffer: RefCounted = _new_buffer()
	var slide_fsm: RefCounted = _new_fsm()
	var slide_buffer: RefCounted = _new_buffer()
	if crouch_fsm == null or crouch_buffer == null or slide_fsm == null or slide_buffer == null:
		return
	crouch_fsm.call("step", 5.0, true, 0.0, crouch_buffer, _move, _input, false)
	_press(crouch_buffer, &"down", 5.01)
	var crouch: RefCounted = crouch_fsm.call(
		"step", 5.01, true, 0.0, crouch_buffer, _move, _input, false
	)
	slide_fsm.call("step", 5.0, true, _move.get("run_speed_mps"), slide_buffer, _move, _input, false)
	_press(slide_buffer, &"down", 5.01)
	var slide: RefCounted = slide_fsm.call(
		"step", 5.01, true, _move.get("run_speed_mps"), slide_buffer, _move, _input, false
	)

	assert_eq(crouch.get("state"), &"crouched")
	assert_eq(slide.get("state"), &"sliding")


func test_tiny_analog_drift_counts_as_still_for_crouch() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 5.0, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"down", 5.01)

	var decision: RefCounted = fsm.call(
		"step", 5.01, true, 0.5, buffer, _move, _input, false
	)

	assert_eq(decision.get("state"), &"crouched")


func test_jump_during_slide_becomes_slide_jump() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 6.0, true, _move.get("run_speed_mps"), buffer, _move, _input, false)
	_press(buffer, &"down", 6.01)
	fsm.call("step", 6.01, true, _move.get("run_speed_mps"), buffer, _move, _input, false)
	_press(buffer, &"jump", 6.1)

	var decision: RefCounted = fsm.call(
		"step", 6.1, true, _move.get("run_speed_mps"), buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"slide_jump")
	assert_eq(decision.get("state"), &"airborne")


func test_same_frame_ground_jump_beats_new_down_press_without_zero_length_slide() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 6.25, true, _move.get("run_speed_mps"), buffer, _move, _input, false)
	_press(buffer, &"down", 6.26)
	_press(buffer, &"jump", 6.26)

	var jump_decision: RefCounted = fsm.call(
		"step",
		6.26,
		true,
		_move.get("run_speed_mps"),
		buffer,
		_move,
		_input,
		false
	)
	var next_air_frame: RefCounted = fsm.call(
		"step",
		6.27,
		false,
		_move.get("run_speed_mps"),
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(jump_decision.get("impulse"), &"jump")
	assert_eq(next_air_frame.get("impulse"), &"none")


func test_crouch_jump_uses_the_section_4_2_high_jump() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 6.5, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"down", 6.51)
	fsm.call("step", 6.51, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 6.6)

	var decision: RefCounted = fsm.call(
		"step", 6.6, true, 0.0, buffer, _move, _input, false
	)

	assert_eq(decision.get("impulse"), &"high_jump")


func test_down_in_air_starts_uncancellable_body_slam() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 7.0, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"down", 7.01)
	var slam: RefCounted = fsm.call(
		"step", 7.01, false, 0.0, buffer, _move, _input, false
	)
	_press(buffer, &"jump", 7.02)
	var attempted_cancel: RefCounted = fsm.call(
		"step", 7.02, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(slam.get("impulse"), &"body_slam")
	assert_eq(attempted_cancel.get("impulse"), &"none")
	assert_eq(attempted_cancel.get("state"), &"body_slam")


func test_double_jump_wins_same_frame_and_discards_losing_slam() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 7.5, true, 0.0, buffer, _move, _input, false)
	_press(buffer, &"jump", 7.51)
	fsm.call("step", 7.51, true, 0.0, buffer, _move, _input, false)
	_release(buffer, &"jump", 7.52)
	_press(buffer, &"jump", 7.6)
	_press(buffer, &"down", 7.61)

	var jump_decision: RefCounted = fsm.call(
		"step", 7.62, false, 0.0, buffer, _move, _input, false
	)
	var slam_decision: RefCounted = fsm.call(
		"step", 7.63, false, 0.0, buffer, _move, _input, false
	)

	assert_eq(jump_decision.get("impulse"), &"double_jump")
	assert_eq(jump_decision.get("state"), &"airborne")
	assert_eq(slam_decision.get("impulse"), &"none")
	assert_eq(slam_decision.get("state"), &"airborne")


func test_air_spin_is_once_per_airtime_and_a_late_second_press_fires_on_landing() -> void:
	var fsm: RefCounted = _new_fsm()
	var buffer: RefCounted = _new_buffer()
	if fsm == null or buffer == null:
		return
	fsm.call("step", 8.0, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"spin", 8.01)
	var first_spin: RefCounted = fsm.call(
		"step", 8.01, false, 0.0, buffer, _move, _input, false
	)
	_release(buffer, &"spin", 8.02)
	fsm.call("step", 8.5, false, 0.0, buffer, _move, _input, false)
	_press(buffer, &"spin", 8.51)
	var blocked_spin: RefCounted = fsm.call(
		"step", 8.51, false, 0.0, buffer, _move, _input, false
	)
	var landing_spin: RefCounted = fsm.call(
		"step", 8.6, true, 0.0, buffer, _move, _input, false
	)

	assert_true(first_spin.get("spin_started"))
	assert_false(blocked_spin.get("spin_started"))
	assert_true(landing_spin.get("spin_started"))


func test_variable_jump_release_has_minimum_and_full_hold_boundaries() -> void:
	var script: Script = load(KINEMATICS_SCRIPT_PATH)
	assert_not_null(script, "JumpKinematics implementation must exist")
	if script == null:
		return
	var current_velocity: float = script.call(
		"upward_speed_for_height",
		_move.get("jump_full_height_m"),
		_move
	)
	var minimum_velocity: float = script.call(
		"velocity_after_release",
		current_velocity,
		0.089,
		_move.get("jump_tap_height_m"),
		_move,
		_input
	)
	var full_velocity: float = script.call(
		"velocity_after_release",
		current_velocity,
		0.22,
		_move.get("jump_tap_height_m"),
		_move,
		_input
	)

	var expected_minimum: float = script.call(
		"upward_speed_for_height",
		_move.get("jump_tap_height_m"),
		_move
	)
	assert_almost_eq(minimum_velocity, expected_minimum, 0.0001)
	assert_eq(full_velocity, current_velocity)


func test_traversal_state_and_impulse_vocabulary_is_declared() -> void:
	var state_constants: Dictionary = (
		load(FSM_SCRIPT_PATH) as Script
	).get_script_constant_map()
	var decision_constants: Dictionary = (
		load(FRAME_DECISION_SCRIPT_PATH) as Script
	).get_script_constant_map()

	assert_eq(state_constants.get("STATE_GRIND"), &"grind")
	assert_eq(state_constants.get("STATE_WALL_RUN"), &"wall_run")
	assert_eq(state_constants.get("STATE_SWING"), &"swing")
	assert_eq(state_constants.get("STATE_RIDE"), &"ride")
	assert_eq(decision_constants.get("IMPULSE_RAIL_HOP"), &"rail_hop")
	assert_eq(decision_constants.get("IMPULSE_RAIL_EXIT"), &"rail_exit")
	assert_eq(
		decision_constants.get("IMPULSE_WALL_DETACH"),
		&"wall_detach"
	)
	assert_eq(
		decision_constants.get("IMPULSE_RIDE_JUMP"),
		&"ride_jump"
	)


func test_step_exposes_the_neighbour_availability_channel() -> void:
	var script: Script = load(FSM_SCRIPT_PATH)
	var step_argument_count := -1
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == &"step":
			step_argument_count = (method["args"] as Array).size()
			break

	assert_eq(step_argument_count, 7)


func _new_fsm() -> RefCounted:
	var script: Script = load(FSM_SCRIPT_PATH)
	assert_not_null(script, "PlayerStateMachine implementation must exist")
	return script.new() if script != null else null


func _new_buffer() -> RefCounted:
	var script: Script = load(BUFFER_SCRIPT_PATH)
	assert_not_null(script, "InputIntentBuffer implementation must exist")
	return script.new() if script != null else null


func _press(buffer: RefCounted, action: StringName, timestamp_s: float) -> void:
	buffer.call("push", _button_intent(action, true, timestamp_s))


func _release(buffer: RefCounted, action: StringName, timestamp_s: float) -> void:
	buffer.call("push", _button_intent(action, false, timestamp_s))


func _button_intent(action: StringName, pressed: bool, timestamp_s: float) -> RefCounted:
	var script: Script = load(INTENT_SCRIPT_PATH)
	assert_not_null(script, "InputIntent implementation must exist")
	return script.call("button", action, pressed, timestamp_s, &"test") if script != null else null
