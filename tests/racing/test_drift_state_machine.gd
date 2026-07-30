extends GutTest

# Task 2 (CTR racing mode): the drift + slide-boost state machine is pure
# logic (RefCounted, poll model — configure/hop_pressed/hop_released/steer
# push input, tick(delta_s, grounded) advances state, getters read it back).
# See docs/superpowers/plans/2026-07-30-ctr-r1-r2-kart-and-circuit.md task 2
# and .superpowers/sdd/2026-07-30-ctr-r1-r2-kart-and-circuit/task-2-brief.md.

const FSM_SCRIPT_PATH := "res://src/racing/kart/drift_state_machine.gd"
const TUNING_PATH := "res://data/tuning/racing/kart.tres"
const RESULT_FIRED := &"fired"
const RESULT_MISTIMED := &"mistimed"
const RESULT_IGNORED := &"ignored"
# Boundary-timing ticks use a small offset past a window edge; the authored
# kart.tres windows (0.55-0.85s at stage 0, shrinking by 0.8 per stage) are
# comfortably wider than this, so it can never itself cross the next edge.
const _EPSILON_S := 0.01

var _kart: KartTuning


func before_all() -> void:
	_kart = load(TUNING_PATH)
	assert_not_null(_kart, "kart.tres must load — Task 1 registers it")


# ---------------------------------------------------------------------------
# Slide start: grounded + hop held + |steer| >= slide_min_steer.
# ---------------------------------------------------------------------------


func test_slide_starts_when_grounded_with_hop_held_and_steer_past_threshold() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("hop_pressed")
	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, true)

	assert_true(
		fsm.call("is_sliding"),
		"hop held + steer at slide_min_steer while grounded must start a slide"
	)


func test_slide_does_not_start_when_steer_is_below_threshold() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("hop_pressed")
	fsm.call("steer", _kart.slide_min_steer / 2.0)
	fsm.call("tick", 0.0, true)

	assert_false(
		fsm.call("is_sliding"),
		"steer under slide_min_steer must not start a slide"
	)


func test_slide_does_not_start_without_hop_held() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, true)

	assert_false(
		fsm.call("is_sliding"),
		"steer alone without a hop press must not start a slide"
	)


func test_slide_does_not_start_while_airborne() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("hop_pressed")
	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, false)

	assert_false(
		fsm.call("is_sliding"),
		"hop+steer while airborne must not start a slide before landing"
	)


func test_airborne_hop_then_landing_with_steer_starts_slide() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("hop_pressed")
	fsm.call("tick", 0.1, false)
	assert_false(fsm.call("is_sliding"), "must still be airborne mid-hop")

	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, true)

	assert_true(
		fsm.call("is_sliding"),
		"landing with hop already held and steer applied must start the slide"
	)


func test_grounded_hop_pressed_after_steer_already_held_starts_slide() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return
	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, true)
	assert_false(
		fsm.call("is_sliding"),
		"steer alone while grounded, with no hop yet, must not slide"
	)

	fsm.call("hop_pressed")
	fsm.call("tick", 0.0, true)

	assert_true(
		fsm.call("is_sliding"),
		"pressing hop while already grounded and steering must start the slide"
	)


func test_tap_when_not_sliding_is_ignored() -> void:
	var fsm := _new_fsm()
	if fsm == null:
		return

	assert_eq(fsm.call("boost_tap"), RESULT_IGNORED)


# ---------------------------------------------------------------------------
# Direction lock.
# ---------------------------------------------------------------------------


func test_slide_direction_locks_positive() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return

	assert_eq(fsm.call("slide_direction"), 1)


func test_slide_direction_locks_negative() -> void:
	var fsm := _start_sliding(-_kart.slide_min_steer)
	if fsm == null:
		return

	assert_eq(fsm.call("slide_direction"), -1)


func test_slide_direction_does_not_retroactively_change_when_a_reversal_ends_it() -> void:
	# Fix round 1: reversing steer this early (well before slide_min_duration_s)
	# now CANCELS the slide via the sustain check in tick() -- it no longer
	# continues sliding with a stale locked direction. The direction lock
	# itself still matters: slide_direction() must keep reporting the value
	# recorded at slide start, even once the reversal that ended the slide
	# has happened.
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return

	fsm.call("steer", -_kart.slide_min_steer)
	fsm.call("tick", _EPSILON_S, true)

	assert_false(
		fsm.call("is_sliding"),
		"reversing steer before slide_min_duration_s must cancel the slide"
	)
	assert_eq(
		fsm.call("slide_direction"),
		1,
		"the recorded direction must not retroactively change once the slide has ended"
	)


# ---------------------------------------------------------------------------
# Boost windows: fired / mistimed / ignored.
# ---------------------------------------------------------------------------


func test_tap_before_window_opens_is_mistimed_and_ends_slide() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return

	var result: StringName = fsm.call("boost_tap")

	assert_eq(result, RESULT_MISTIMED)
	assert_false(
		fsm.call("is_sliding"),
		"a mistimed tap must end the slide immediately (CTR's punish)"
	)


func test_tap_exactly_at_window_open_fires() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.boost_window_open_s, true)

	assert_eq(
		fsm.call("boost_tap"),
		RESULT_FIRED,
		"the open boundary itself must count as inside the window"
	)


func test_tap_exactly_at_window_close_fires() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.boost_window_close_s, true)

	assert_eq(
		fsm.call("boost_tap"),
		RESULT_FIRED,
		"the close boundary itself must count as inside the window"
	)


func test_tap_inside_the_window_fires_and_advances_stage() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)

	var result: StringName = fsm.call("boost_tap")

	assert_eq(result, RESULT_FIRED)
	assert_true(fsm.call("is_sliding"), "a fired tap must not end the slide")
	assert_eq(fsm.call("boost_stage"), 1)


func test_tap_after_window_close_is_ignored_and_slide_continues() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.boost_window_close_s + _EPSILON_S, true)

	var result: StringName = fsm.call("boost_tap")

	assert_eq(result, RESULT_IGNORED)
	assert_true(fsm.call("is_sliding"), "missing the window must not end the slide")
	assert_eq(fsm.call("boost_stage"), 0, "a missed window must not advance the stage")


func test_three_timed_taps_stack_then_cap() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	var stack_max := roundi(_kart.boost_stack_max)
	var stage := 0
	while stage < stack_max:
		var open_s: float = (
			_kart.boost_window_open_s
			* pow(_kart.boost_window_shrink_factor, float(stage))
		)
		var close_s: float = (
			_kart.boost_window_close_s
			* pow(_kart.boost_window_shrink_factor, float(stage))
		)
		fsm.call("tick", _window_midpoint(open_s, close_s), true)

		var result: StringName = fsm.call("boost_tap")

		assert_eq(result, RESULT_FIRED, "tap %d inside its window must fire" % stage)
		stage += 1
		assert_eq(fsm.call("boost_stage"), stage)

	assert_eq(fsm.call("boost_stage"), stack_max)
	assert_true(fsm.call("is_sliding"), "reaching the cap must not end the slide")

	var capped_result: StringName = fsm.call("boost_tap")

	assert_eq(capped_result, RESULT_IGNORED, "tapping past boost_stack_max must be ignored")
	assert_eq(
		fsm.call("boost_stage"),
		stack_max,
		"an ignored tap past the cap must not increase the stage"
	)
	assert_almost_eq(
		float(fsm.call("consume_boost")),
		_kart.boost_duration_s * stack_max,
		0.0001,
		"boost_stack_max successful taps must stack their accrued boost duration"
	)


func test_mistimed_tap_forfeits_previously_accrued_boost() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)
	assert_eq(fsm.call("boost_tap"), RESULT_FIRED)

	var stage1_open_s: float = _kart.boost_window_open_s * _kart.boost_window_shrink_factor
	fsm.call("tick", stage1_open_s / 2.0, true)

	var result: StringName = fsm.call("boost_tap")

	assert_eq(result, RESULT_MISTIMED)
	assert_false(fsm.call("is_sliding"))
	assert_eq(
		float(fsm.call("consume_boost")),
		0.0,
		"CTR's punish forfeits everything accrued so far this slide, not just this tap"
	)


# ---------------------------------------------------------------------------
# Steer-sustained end: min duration cancel vs. valid end (fix round 1 —
# hop_released() no longer ends or cancels a slide; steer does).
# ---------------------------------------------------------------------------


func test_steer_below_threshold_before_min_duration_cancels_with_no_boost() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.slide_min_duration_s / 2.0, true)

	fsm.call("steer", 0.0)
	fsm.call("tick", 0.0, true)

	assert_false(
		fsm.call("is_sliding"),
		"steer dropping below slide_min_steer before slide_min_duration_s must cancel the slide"
	)
	assert_eq(float(fsm.call("consume_boost")), 0.0)


func test_steer_below_threshold_at_exactly_min_duration_is_a_valid_end() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.slide_min_duration_s, true)

	fsm.call("steer", 0.0)
	fsm.call("tick", 0.0, true)

	assert_false(fsm.call("is_sliding"))


func test_steer_reversal_ends_the_slide() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _kart.slide_min_duration_s, true)

	fsm.call("steer", -_kart.slide_min_steer)
	fsm.call("tick", 0.0, true)

	assert_false(
		fsm.call("is_sliding"),
		"steering past the threshold in the opposite direction must end the slide, not sustain it"
	)


func test_steer_valid_end_keeps_accrued_boost_consumable() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)
	assert_eq(fsm.call("boost_tap"), RESULT_FIRED)

	fsm.call("steer", 0.0)
	fsm.call("tick", 0.0, true)

	assert_false(fsm.call("is_sliding"), "a valid steer-based end must end the slide")
	assert_almost_eq(
		float(fsm.call("consume_boost")),
		_kart.boost_duration_s,
		0.0001,
		"boost earned before a valid end must remain consumable afterward"
	)


func test_hop_released_mid_slide_does_not_end_the_slide() -> void:
	# The reviewer's finding: a second hop press is always preceded by a
	# release. Under the old hop-sustained model that release ended the
	# slide synchronously, so is_sliding() was already false by the time a
	# caller's boost branch ran -- boost_tap() could never fire from a
	# second press. Steer now sustains the slide, so releasing hop mid-slide
	# (steer unchanged, still past threshold) must be a complete no-op for
	# slide state.
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return

	fsm.call("hop_released")

	assert_true(
		fsm.call("is_sliding"),
		"releasing hop mid-slide must not end it -- steer sustains now"
	)


func test_press_release_press_mid_slide_fires_boost() -> void:
	# The reviewer's exact scenario, proven end to end: start a slide, let
	# go of hop entirely (as the one-thumb mobile flow expects — hop is
	# only held long enough to register the initial press), tick into the
	# tap window, then press hop again. is_sliding() must still read true at
	# that second press (this is what RacingInputAdapter checks to decide
	# hop_pressed() vs boost_tap() -- see tests/racing/
	# test_racing_input_adapter.gd for the adapter-level proof), and the
	# fired tap must land normally.
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("hop_released")
	assert_true(fsm.call("is_sliding"), "release mid-slide must not end it")

	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)
	fsm.call("hop_pressed")

	assert_true(
		fsm.call("is_sliding"),
		"a second hop press mid-slide must not itself disturb slide state"
	)
	var result: StringName = fsm.call("boost_tap")
	assert_eq(result, RESULT_FIRED, "the same press's boost tap must fire inside the window")
	assert_eq(fsm.call("boost_stage"), 1)


func test_consume_boost_clears_the_accrued_value() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)
	fsm.call("boost_tap")

	var first: float = fsm.call("consume_boost")
	var second: float = fsm.call("consume_boost")

	assert_almost_eq(first, _kart.boost_duration_s, 0.0001)
	assert_eq(second, 0.0, "consume_boost must clear the accrued seconds")


# ---------------------------------------------------------------------------
# Cross-slide behavior and degenerate-input safety.
# ---------------------------------------------------------------------------


func test_new_slide_resets_boost_stage_to_zero() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call("tick", _window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s), true)
	fsm.call("boost_tap")
	assert_eq(fsm.call("boost_stage"), 1)
	# End this slide validly via steer (elapsed is already well past
	# slide_min_duration_s from the tick above) rather than hop_released(),
	# which no longer touches slide state.
	fsm.call("steer", 0.0)
	fsm.call("tick", 0.0, true)
	assert_false(fsm.call("is_sliding"))

	fsm.call("hop_pressed")
	fsm.call("steer", _kart.slide_min_steer)
	fsm.call("tick", 0.0, true)

	assert_true(fsm.call("is_sliding"))
	assert_eq(fsm.call("boost_stage"), 0, "a fresh slide must start a fresh boost budget")


func test_mistimed_end_does_not_auto_restart_without_a_fresh_hop_press() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	assert_eq(fsm.call("boost_tap"), RESULT_MISTIMED)
	assert_false(fsm.call("is_sliding"))

	# hop_released() was never called here -- the physical button is
	# conceptually still down, and steer is still past the threshold -- but a
	# punished end must still require a fresh hop press before another slide
	# can start, or the punish is free to shrug off every frame.
	fsm.call("tick", 0.0, true)
	assert_false(fsm.call("is_sliding"), "a punish must not silently rearm the slide")

	fsm.call("hop_pressed")
	fsm.call("tick", 0.0, true)
	assert_true(fsm.call("is_sliding"), "a fresh hop press must be able to start a new slide")


func test_zero_delta_ticks_do_not_advance_the_boost_window() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	for _i in range(5):
		fsm.call("tick", 0.0, true)

	assert_true(fsm.call("is_sliding"))
	assert_eq(fsm.call("boost_stage"), 0)
	assert_eq(
		fsm.call("boost_tap"),
		RESULT_MISTIMED,
		"no time has passed across repeated zero-delta ticks, so the window still has not opened"
	)


func test_slide_continues_through_a_brief_airborne_moment() -> void:
	var fsm := _start_sliding(_kart.slide_min_steer)
	if fsm == null:
		return
	fsm.call(
		"tick",
		_window_midpoint(_kart.boost_window_open_s, _kart.boost_window_close_s),
		false
	)

	assert_true(
		fsm.call("is_sliding"),
		"an already-active slide must not cancel just because grounded went false"
	)
	assert_eq(
		fsm.call("boost_tap"),
		RESULT_FIRED,
		"the boost window must keep advancing (and stay tappable) while briefly airborne"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_fsm() -> RefCounted:
	var script: Script = load(FSM_SCRIPT_PATH)
	assert_not_null(script)
	if script == null:
		return null
	var fsm: RefCounted = script.new()
	fsm.call("configure", _kart)
	return fsm


func _start_sliding(steer_value: float) -> RefCounted:
	var fsm := _new_fsm()
	if fsm == null:
		return null
	fsm.call("hop_pressed")
	fsm.call("steer", steer_value)
	fsm.call("tick", 0.0, true)
	assert_true(fsm.call("is_sliding"), "fixture setup must land inside a slide")
	return fsm


func _window_midpoint(open_s: float, close_s: float) -> float:
	return (open_s + close_s) / 2.0
