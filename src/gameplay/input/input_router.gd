class_name InputRouter
extends Node

signal active_source_changed(source: StringName)

var buffer: InputIntentBuffer = InputIntentBuffer.new()

var _input_tuning: InputTuning
var _corridor_axis := Vector2.UP


func configure(input_tuning: InputTuning) -> void:
	_input_tuning = input_tuning


func push_intent(intent: InputIntent) -> void:
	if intent == null:
		return
	var previous_source := buffer.active_source()
	buffer.push(intent)
	if buffer.active_source() != previous_source:
		active_source_changed.emit(buffer.active_source())


func push_move(value: Vector2, timestamp_s: float, source: StringName) -> void:
	push_intent(InputIntent.move(value, timestamp_s, source))


func push_button(
	action: StringName,
	pressed: bool,
	timestamp_s: float,
	source: StringName
) -> void:
	push_intent(InputIntent.button(action, pressed, timestamp_s, source))


func set_corridor_axis(axis: Vector2) -> void:
	if not axis.is_zero_approx():
		_corridor_axis = axis.normalized()


func corridor_axis() -> Vector2:
	return _corridor_axis


func tuning() -> InputTuning:
	return _input_tuning
