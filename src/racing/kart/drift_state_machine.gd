class_name DriftStateMachine
extends RefCounted

## Pure-logic CTR-style drift + slide-boost state machine (Task 2). Poll
## model, no signals: the caller pushes input edges (hop_pressed/
## hop_released/steer), calls tick(delta_s, grounded) once per physics
## frame, and reads state back through getters -- mirrors
## src/gameplay/player/player_state_machine.gd's idiom.
##
## A slide starts once, while grounded, the hop button is held and |steer|
## has crossed slide_min_steer; slide_direction locks to sign(steer) at that
## instant and never changes for the life of the slide. While sliding, each
## boost stage n (0-based, capped at kart.boost_stack_max) opens a tap
## window timed from the slide start (stage 0) or the previous successful
## fire (stage n): [open_s, close_s] scaled by shrink^n. A tap inside the
## window fires (stacks kart.boost_duration_s of accrued boost and advances
## the stage); a tap after the window has closed is simply ignored and the
## slide keeps going with that stage frozen; but a tap BEFORE the window has
## even opened is CTR's punish -- it forfeits everything accrued this slide
## and ends it immediately, same as releasing hop before slide_min_duration_s
## has elapsed. Only a valid end (hop released at/after slide_min_duration_s)
## leaves any accrued boost consumable afterward.
##
## Because a punished end never calls hop_released(), it also clears the
## internal "hop held" latch itself -- so holding the physical button through
## a punish cannot instantly re-arm a fresh slide; a new hop_pressed() edge
## is required, same as CTR requiring you to hop again after blowing the
## timing.

var _tuning: KartTuning

var _hop_held: bool
var _steer: float

var _sliding: bool
var _slide_direction := 1
var _slide_elapsed_s: float
var _window_elapsed_s: float
var _boost_stage: int
var _accrued_boost_s: float


func configure(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning


func hop_pressed() -> void:
	_hop_held = true


func hop_released() -> void:
	_hop_held = false
	if not _sliding:
		return
	if _slide_elapsed_s < _tuning.slide_min_duration_s:
		_cancel_slide()
	else:
		_sliding = false


func steer(value: float) -> void:
	_steer = value


func tick(delta_s: float, grounded: bool) -> void:
	if _sliding:
		_slide_elapsed_s += delta_s
		_window_elapsed_s += delta_s
		return
	if grounded and _hop_held and absf(_steer) >= _tuning.slide_min_steer:
		_start_slide()


func is_sliding() -> bool:
	return _sliding


func slide_direction() -> int:
	return _slide_direction


func boost_stage() -> int:
	return _boost_stage


func boost_tap() -> StringName:
	if not _sliding:
		return &"ignored"
	var stack_max := roundi(_tuning.boost_stack_max)
	if _boost_stage >= stack_max:
		return &"ignored"

	var stage_factor: float = pow(_tuning.boost_window_shrink_factor, float(_boost_stage))
	var open_s: float = _tuning.boost_window_open_s * stage_factor
	var close_s: float = _tuning.boost_window_close_s * stage_factor

	if _window_elapsed_s < open_s:
		_cancel_slide()
		return &"mistimed"
	if _window_elapsed_s > close_s:
		return &"ignored"

	_accrued_boost_s += _tuning.boost_duration_s
	_boost_stage += 1
	_window_elapsed_s = 0.0
	return &"fired"


func consume_boost() -> float:
	var boost_s := _accrued_boost_s
	_accrued_boost_s = 0.0
	return boost_s


func _start_slide() -> void:
	_sliding = true
	_slide_direction = 1 if _steer > 0.0 else -1
	_slide_elapsed_s = 0.0
	_window_elapsed_s = 0.0
	_boost_stage = 0


func _cancel_slide() -> void:
	_sliding = false
	_hop_held = false
	_boost_stage = 0
	_accrued_boost_s = 0.0
	_window_elapsed_s = 0.0
