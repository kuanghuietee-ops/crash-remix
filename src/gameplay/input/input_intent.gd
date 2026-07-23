class_name InputIntent
extends RefCounted

const ACTION_MOVE := &"move"
const ACTION_JUMP := &"jump"
const ACTION_SPIN := &"spin"
const ACTION_DOWN := &"down"
const ACTION_PHASE := &"phase"

const SOURCE_TOUCH := &"touch"
const SOURCE_GAMEPAD := &"gamepad"
const SOURCE_KEYBOARD := &"keyboard"

var action: StringName
var pressed: bool
var movement_value: Vector2
var timestamp_s: float
var source: StringName
var is_movement: bool


static func button(
	button_action: StringName,
	is_pressed: bool,
	event_timestamp_s: float,
	input_source: StringName
) -> InputIntent:
	var intent := InputIntent.new()
	intent.action = button_action
	intent.pressed = is_pressed
	intent.timestamp_s = event_timestamp_s
	intent.source = input_source
	return intent


static func move(
	value: Vector2,
	event_timestamp_s: float,
	input_source: StringName
) -> InputIntent:
	var intent := InputIntent.new()
	intent.action = ACTION_MOVE
	intent.movement_value = value
	intent.timestamp_s = event_timestamp_s
	intent.source = input_source
	intent.is_movement = true
	return intent
