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


func set_corridor_axis(axis: Vector2) -> void:
	if axis.is_zero_approx():
		return
	var next_axis := axis.normalized()
	if next_axis.is_equal_approx(_corridor_axis):
		return
	_corridor_axis = next_axis


func corridor_axis() -> Vector2:
	return _corridor_axis


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
