class_name PhaseSet
extends RefCounted

const SET_BLUE := &"blue"
const SET_ORANGE := &"orange"

var active_set: StringName = SET_BLUE
var _last_toggle_s := -1.0


func can_toggle(now_s: float, phase_tuning: PhaseTuning) -> bool:
	return (
		_last_toggle_s < 0.0
		or now_s - _last_toggle_s >= phase_tuning.retoggle_cooldown_s
	)


func try_toggle(now_s: float, phase_tuning: PhaseTuning) -> bool:
	if not can_toggle(now_s, phase_tuning):
		return false
	active_set = SET_ORANGE if active_set == SET_BLUE else SET_BLUE
	_last_toggle_s = now_s
	return true


func is_solid(set_name: StringName) -> bool:
	return set_name == active_set


func is_ghost(set_name: StringName) -> bool:
	return not is_solid(set_name)
