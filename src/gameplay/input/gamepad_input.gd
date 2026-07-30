class_name GamepadInput
extends Node

const InputRouterType := preload("res://src/gameplay/input/input_router.gd")
const MonotonicClockType := preload("res://src/core/monotonic_clock.gd")

var _router: InputRouterType
var _input_tuning: InputTuning
var _left_stick := Vector2.ZERO
var _dpad := Vector2.ZERO


func configure(router: InputRouterType, input_tuning: InputTuning) -> void:
	_router = router
	_input_tuning = input_tuning
	set_process_input(true)


func _input(event: InputEvent) -> void:
	handle_input(event)


func handle_input(event: InputEvent) -> void:
	if _router == null or _input_tuning == null:
		return
	if event is InputEventJoypadMotion:
		_handle_motion(event as InputEventJoypadMotion)
	elif event is InputEventJoypadButton:
		_handle_button(event as InputEventJoypadButton)


func _handle_motion(event: InputEventJoypadMotion) -> void:
	if event.axis == JOY_AXIS_LEFT_X:
		_left_stick.x = event.axis_value
	elif event.axis == JOY_AXIS_LEFT_Y:
		_left_stick.y = event.axis_value
	else:
		return

	if not _dpad.is_zero_approx():
		_router.push_move(
			_dpad,
			MonotonicClockType.now_s(),
			InputIntent.SOURCE_GAMEPAD
		)
		return
	var movement := _apply_dead_zone(_left_stick)
	_router.push_move(movement, MonotonicClockType.now_s(), InputIntent.SOURCE_GAMEPAD)


func _handle_button(event: InputEventJoypadButton) -> void:
	if _update_dpad(event):
		var movement := _dpad
		if movement.is_zero_approx():
			movement = _apply_dead_zone(_left_stick)
		_router.push_move(
			movement,
			MonotonicClockType.now_s(),
			InputIntent.SOURCE_GAMEPAD
		)
		return
	var actions := _actions_for_button(event.button_index)
	if actions.is_empty():
		return
	var timestamp_s := MonotonicClockType.now_s()
	for action: StringName in actions:
		_router.push_button(
			action,
			event.pressed,
			timestamp_s,
			InputIntent.SOURCE_GAMEPAD
		)


func _update_dpad(event: InputEventJoypadButton) -> bool:
	var value := 1.0 if event.pressed else 0.0
	match event.button_index:
		JOY_BUTTON_DPAD_LEFT:
			_dpad.x = -value
		JOY_BUTTON_DPAD_RIGHT:
			_dpad.x = value
		JOY_BUTTON_DPAD_UP:
			_dpad.y = -value
		JOY_BUTTON_DPAD_DOWN:
			_dpad.y = value
		_:
			return false
	return true


func _apply_dead_zone(raw_value: Vector2) -> Vector2:
	var magnitude := raw_value.length()
	var dead_zone := clampf(_input_tuning.gamepad_dead_zone, 0.0, 1.0)
	if magnitude <= dead_zone or is_equal_approx(dead_zone, 1.0):
		return Vector2.ZERO
	var remapped := clampf((magnitude - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	return raw_value.normalized() * remapped


## R4 Task 2 (CTR item loop): a button may map to more than one action --
## this shared script has no notion of which mode (platformer or racing) is
## currently active, the same "push everything, let the consumer decide
## what matters" shape TouchControls already uses in racing layout for the
## platformer SPIN/DOWN/PHASE buttons it simply stops rendering (see
## touch_controls.gd's _recalculate_layout()): the platformer's
## PlayerStateMachine never reads ACTION_ITEM and RaceSession never reads
## ACTION_DOWN, so pushing both off one real button press is harmless in
## either mode. JOY_BUTTON_B is CTR's own B/circle-equivalent item button
## (see input_intent.gd's ACTION_ITEM doc); JOY_BUTTON_RIGHT_SHOULDER stays
## DOWN-only, unchanged from before.
func _actions_for_button(button_index: JoyButton) -> Array[StringName]:
	match button_index:
		JOY_BUTTON_A:
			return [InputIntent.ACTION_JUMP]
		JOY_BUTTON_X:
			return [InputIntent.ACTION_SPIN]
		JOY_BUTTON_Y:
			return [InputIntent.ACTION_PHASE]
		JOY_BUTTON_B:
			return [InputIntent.ACTION_DOWN, InputIntent.ACTION_ITEM]
		JOY_BUTTON_RIGHT_SHOULDER:
			return [InputIntent.ACTION_DOWN]
	return []
