class_name GameFlow
extends RefCounted

enum State {
	BOOT,
	WARP_ROOM,
	LEVEL,
	RESULTS,
	PAUSED,
}

const EVENT_SAVE_LOADED := &"save_loaded"
const EVENT_PORTAL_ENTER := &"portal_enter"
const EVENT_LEVEL_COMPLETE := &"level_complete"
const EVENT_QUIT_LEVEL := &"quit_level"
const EVENT_PAUSE := &"pause"
const EVENT_RESUME := &"resume"

const TRANSITIONS: Dictionary = {
	State.BOOT: {
		EVENT_SAVE_LOADED: State.WARP_ROOM,
	},
	State.WARP_ROOM: {
		EVENT_PORTAL_ENTER: State.LEVEL,
	},
	State.LEVEL: {
		EVENT_LEVEL_COMPLETE: State.RESULTS,
		EVENT_QUIT_LEVEL: State.WARP_ROOM,
	},
}
const STATE_NAMES: Dictionary = {
	State.BOOT: &"boot",
	State.WARP_ROOM: &"warp_room",
	State.LEVEL: &"level",
	State.RESULTS: &"results",
	State.PAUSED: &"paused",
}

var state: int = State.BOOT
var active_level_id: StringName = &""
var _resume_state: int = State.BOOT


func dispatch(event: Dictionary) -> Error:
	var type_value: Variant = event.get("type")
	if typeof(type_value) != TYPE_STRING and typeof(type_value) != TYPE_STRING_NAME:
		return ERR_INVALID_PARAMETER
	var event_type := StringName(type_value)

	if event_type == EVENT_PAUSE:
		if state == State.PAUSED:
			return ERR_INVALID_PARAMETER
		_resume_state = state
		state = State.PAUSED
		return OK

	if state == State.PAUSED:
		if event_type != EVENT_RESUME:
			return ERR_INVALID_PARAMETER
		state = _resume_state
		return OK

	var state_transitions: Dictionary = TRANSITIONS.get(state, {})
	if not state_transitions.has(event_type):
		return ERR_INVALID_PARAMETER

	if event_type == EVENT_PORTAL_ENTER:
		var level_value: Variant = event.get("level_id")
		if (
			typeof(level_value) != TYPE_STRING
			and typeof(level_value) != TYPE_STRING_NAME
		):
			return ERR_INVALID_DATA
		var requested_level := StringName(level_value)
		if requested_level.is_empty():
			return ERR_INVALID_DATA
		active_level_id = requested_level

	state = int(state_transitions[event_type])
	if event_type == EVENT_QUIT_LEVEL:
		active_level_id = &""
	return OK


func state_name() -> StringName:
	return STATE_NAMES.get(state, &"unknown")
