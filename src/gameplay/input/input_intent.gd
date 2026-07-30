class_name InputIntent
extends RefCounted

const ACTION_MOVE := &"move"
const ACTION_JUMP := &"jump"
const ACTION_SPIN := &"spin"
const ACTION_DOWN := &"down"
const ACTION_PHASE := &"phase"
## R4 Task 2 (CTR item loop): racing-only. Reuses the platformer SPIN
## button's own authored screen metrics (position/size) in TouchControls'
## racing layout -- see touch_controls.gd's _recalculate_layout() -- but is
## a genuinely distinct action from ACTION_SPIN, not a relabeling of it, so
## a gamepad or touch press in racing mode can never be misread as the
## platformer's SPIN.
const ACTION_ITEM := &"item"

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
