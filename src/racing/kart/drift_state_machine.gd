class_name DriftStateMachine
extends RefCounted

## Pure-logic CTR-style drift + slide-boost state machine (Task 2, revised
## for Task 4's fix round 1). Poll model, no signals: the caller pushes
## input edges (hop_pressed/hop_released/steer), calls tick(delta_s,
## grounded) once per physics frame, and reads state back through getters --
## mirrors src/gameplay/player/player_state_machine.gd's idiom.
##
## STEER-SUSTAINED SLIDES (one-thumb mobile). Original CTR holds a shoulder
## button (sustain) while tapping a face button (boost) -- two independent
## inputs a controller lets you hold and tap at once. This game merges hop
## and boost onto the SAME single touch button (CTR muscle memory), which
## makes "hold this button while also tapping it" physically impossible: a
## tap is a release-then-press of the very button you'd need to be holding.
## So the button can no longer be what sustains the slide. Sustain moves to
## STEER instead -- an analog axis the thumb can hold at a deflection
## indefinitely without conflicting with a second thumb tapping HOP. A slide
## still STARTS the same way (grounded + a hop press while |steer| has
## crossed slide_min_steer; slide_direction locks to sign(steer) at that
## instant and never changes for the life of the slide), but once started,
## it SUSTAINS for as long as steer stays past slide_min_steer in the locked
## direction (sign(steer) == slide_direction and |steer| >= slide_min_steer)
## -- hop_released() no longer touches slide state at all, it only clears
## the "hop held" latch that gates a fresh slide START. Every hop press
## while already sliding is therefore free to mean "boost tap" instead of
## "hop" with no ambiguity (see RacingInputAdapter, which is what actually
## makes that routing decision -- this class only exposes boost_tap() as a
## caller-invoked action, same as before).
##
## The slide ENDS when the sustain condition fails (steer drops below
## slide_min_steer, or crosses to the opposite sign):
##   (a) VALID end, at or after slide_min_duration_s has elapsed -- ends the
##       slide but leaves any accrued boost consumable, same as before.
##   (b) CANCEL, before slide_min_duration_s has elapsed -- forfeits
##       everything accrued and clears the hop-held latch, same shape as the
##       old "released too early" cancel.
##
## While sliding, each boost stage n (0-based, capped at kart.
## boost_stack_max) opens a tap window timed from the slide start (stage 0)
## or the previous successful fire (stage n): [open_s, close_s] scaled by
## shrink^n. A tap inside the window fires (stacks kart.boost_duration_s of
## accrued boost and advances the stage); a tap after the window has closed
## is simply ignored and the slide keeps going with that stage frozen; but a
## tap BEFORE the window has even opened is CTR's punish -- it forfeits
## everything accrued this slide and ends it immediately, the same
## forfeit-and-cancel shape as (b) above.
##
## Both the punish and the before-min-duration cancel clear the "hop held"
## latch as part of forfeiting -- so a fresh hop_pressed() edge is always
## required to arm the next slide's start, whether the previous one ended by
## punish or by cancel. A VALID end also clears the latch (nothing about a
## valid end should let a stale hop-held flag instantly re-arm a new slide
## off of leftover state); the only paths that leave the latch untouched are
## an in-progress slide's own hop_pressed()/hop_released() calls, which no
## longer affect slide state at all.

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


func steer(value: float) -> void:
	_steer = value


func tick(delta_s: float, grounded: bool) -> void:
	if _sliding:
		_slide_elapsed_s += delta_s
		_window_elapsed_s += delta_s
		if not _steer_sustains_slide():
			if _slide_elapsed_s >= _tuning.slide_min_duration_s:
				_end_slide()
			else:
				_cancel_slide()
		return
	if grounded and _hop_held and absf(_steer) >= _tuning.slide_min_steer:
		_start_slide()


## Whether the currently-held steer keeps the active slide alive: past
## slide_min_steer in magnitude, in the direction locked at slide start.
func _steer_sustains_slide() -> bool:
	if absf(_steer) < _tuning.slide_min_steer:
		return false
	return (_steer > 0.0) == (_slide_direction > 0)


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


## A VALID end: the slide ran at least slide_min_duration_s before the
## steer condition failed, so any accrued boost stays consumable. Still
## clears the hop-held latch -- an end is an end, not license for stale
## held-button state to instantly re-arm a new slide next tick.
func _end_slide() -> void:
	_sliding = false
	_hop_held = false


func _cancel_slide() -> void:
	_sliding = false
	_hop_held = false
	_boost_stage = 0
	_accrued_boost_s = 0.0
	_window_elapsed_s = 0.0
