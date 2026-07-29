class_name InputRouter
extends Node

const InputVectorFilterType := preload(
	"res://src/gameplay/input/input_vector_filter.gd"
)

signal active_source_changed(source: StringName)

var buffer: InputIntentBuffer = InputIntentBuffer.new()

var _input_tuning: InputTuning
var _corridor_axis := Vector2.UP
var _gesture_corridor_axis := Vector2.UP
var _screen_movement := Vector2.ZERO
var _movement_timestamp_s: float
var _movement_source := &""
var _screen_relative_tracking_enabled: bool


func configure(input_tuning: InputTuning) -> void:
	_input_tuning = input_tuning
	_route_screen_movement()


func push_intent(intent: InputIntent) -> void:
	if intent == null:
		return
	var previous_source := buffer.active_source()
	buffer.push(intent)
	if buffer.active_source() != previous_source:
		active_source_changed.emit(buffer.active_source())


func push_move(value: Vector2, timestamp_s: float, source: StringName) -> void:
	if (
		not value.is_zero_approx()
		and (
			_screen_movement.is_zero_approx()
			or source != _movement_source
		)
	):
		_gesture_corridor_axis = _corridor_axis
	_screen_movement = value
	_movement_timestamp_s = timestamp_s
	_movement_source = source
	_route_screen_movement()


func push_button(
	action: StringName,
	pressed: bool,
	timestamp_s: float,
	source: StringName
) -> void:
	push_intent(InputIntent.button(action, pressed, timestamp_s, source))


func set_corridor_axis(axis: Vector2, delta_s: float = 0.0) -> void:
	if axis.is_zero_approx():
		return
	var next_axis := axis.normalized()
	if next_axis.is_equal_approx(_corridor_axis):
		return
	_corridor_axis = next_axis
	if _screen_relative_tracking_enabled:
		_gesture_corridor_axis = _corridor_axis
		_route_screen_movement()
	elif not _screen_movement.is_zero_approx():
		_slew_gesture_corridor_axis(delta_s)
		_route_screen_movement()


func _slew_gesture_corridor_axis(delta_s: float) -> void:
	if _input_tuning == null or delta_s <= 0.0:
		return
	var remaining_radians := _gesture_corridor_axis.angle_to(_corridor_axis)
	var max_step_radians := (
		deg_to_rad(_input_tuning.gesture_axis_slew_degrees_per_s) * delta_s
	)
	var step_radians := clampf(
		remaining_radians,
		-max_step_radians,
		max_step_radians
	)
	_gesture_corridor_axis = _gesture_corridor_axis.rotated(step_radians)


func corridor_axis() -> Vector2:
	return _corridor_axis


func set_screen_relative_tracking_enabled(enabled: bool) -> void:
	if enabled == _screen_relative_tracking_enabled:
		return
	_screen_relative_tracking_enabled = enabled
	_gesture_corridor_axis = _corridor_axis
	_route_screen_movement()


func tuning() -> InputTuning:
	return _input_tuning


func _route_screen_movement() -> void:
	if _movement_source.is_empty():
		return
	var filtered := _screen_movement
	if _input_tuning != null:
		filtered = InputVectorFilterType.apply_corridor_magnet(
			_screen_movement,
			_gesture_corridor_axis,
			_input_tuning,
			_movement_source == InputIntent.SOURCE_GAMEPAD
		)
	var corridor_input := InputVectorFilterType.to_corridor_input(
		filtered,
		_gesture_corridor_axis
	)
	push_intent(InputIntent.move(
		corridor_input,
		_movement_timestamp_s,
		_movement_source
	))
