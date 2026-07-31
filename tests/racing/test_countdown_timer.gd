extends GutTest

# CTR R5 Task 1: CountdownTimer is pure RefCounted phase-clock logic
# (configure/tick poll model, same shape lap_validator.gd/drift_state_
# machine.gd already establish) -- see countdown_timer.gd's own class doc
# and .superpowers/sdd/2026-07-31-ctr-r5-race-flow/task-1-brief.md.

const COUNTDOWN_TIMER_PATH := "res://src/racing/flow/countdown_timer.gd"

const THREE := &"three"
const TWO := &"two"
const ONE := &"one"
const GO := &"go"
const RUNNING := &"running"


func _new_timer(step_s: float) -> RefCounted:
	var tuning := RaceTuning.new()
	tuning.countdown_step_s = step_s
	var timer: RefCounted = load(COUNTDOWN_TIMER_PATH).new()
	timer.call("configure", tuning)
	return timer


# ---------------------------------------------------------------------------
# Initial state.
# ---------------------------------------------------------------------------


func test_configure_starts_at_phase_three_with_zero_elapsed() -> void:
	var timer := _new_timer(1.0)

	assert_eq(timer.call("phase"), THREE)
	assert_almost_eq(float(timer.call("elapsed_s")), 0.0, 0.0001)


func test_total_duration_s_is_three_full_steps() -> void:
	var timer := _new_timer(1.5)

	assert_almost_eq(float(timer.call("total_duration_s")), 4.5, 0.0001)


# ---------------------------------------------------------------------------
# Phase transitions at countdown_step_s boundaries -- each boundary is
# INCLUSIVE of the phase it enters (see the class doc's own ruling).
# ---------------------------------------------------------------------------


func test_stays_at_three_for_the_whole_first_step() -> void:
	var timer := _new_timer(1.0)

	assert_eq(timer.call("tick", 0.2), THREE)
	assert_eq(timer.call("tick", 0.2), THREE)
	# Cumulative elapsed now 0.79, still short of the 1.0 boundary.
	assert_eq(timer.call("tick", 0.39), THREE)


func test_reaching_the_first_boundary_exactly_enters_two() -> void:
	var timer := _new_timer(1.0)

	assert_eq(timer.call("tick", 1.0), TWO)


func test_a_tick_landing_just_under_the_first_boundary_stays_three() -> void:
	var timer := _new_timer(1.0)

	assert_eq(timer.call("tick", 0.999), THREE)


func test_reaching_the_second_boundary_exactly_enters_one() -> void:
	var timer := _new_timer(1.0)

	timer.call("tick", 1.0)
	assert_eq(timer.call("tick", 1.0), ONE)


func test_a_tick_landing_just_under_the_second_boundary_stays_two() -> void:
	var timer := _new_timer(1.0)

	timer.call("tick", 1.0)
	assert_eq(timer.call("tick", 0.999), TWO)


func test_reaching_the_third_boundary_exactly_fires_go() -> void:
	var timer := _new_timer(1.0)

	timer.call("tick", 1.0)
	timer.call("tick", 1.0)
	assert_eq(timer.call("tick", 1.0), GO)


func test_a_tick_landing_just_under_the_third_boundary_stays_one() -> void:
	var timer := _new_timer(1.0)

	timer.call("tick", 1.0)
	timer.call("tick", 1.0)
	assert_eq(timer.call("tick", 0.999), ONE)


## A single oversized tick crosses every boundary in one call -- must land
# on &"go" directly, not get stuck part-way through the sequence.
func test_a_single_oversized_tick_jumps_straight_to_go() -> void:
	var timer := _new_timer(1.0)

	assert_eq(timer.call("tick", 100.0), GO)


# ---------------------------------------------------------------------------
# GO is a one-shot edge -- see the class doc's own GO IS A ONE-SHOT EDGE
# section.
# ---------------------------------------------------------------------------


func test_go_is_reported_exactly_once_then_running_forever_after() -> void:
	var timer := _new_timer(1.0)
	timer.call("tick", 1.0)
	timer.call("tick", 1.0)

	assert_eq(timer.call("tick", 1.0), GO, "the boundary-crossing tick must report go")
	assert_eq(
		timer.call("tick", 0.016),
		RUNNING,
		"the very next tick after go must report running"
	)
	assert_eq(timer.call("phase"), RUNNING)
	assert_eq(
		timer.call("tick", 0.016),
		RUNNING,
		"running must be sticky -- every tick after must keep reporting it"
	)
	assert_eq(timer.call("tick", 0.016), RUNNING)


func test_phase_getter_reflects_the_last_ticked_phase_without_re_ticking() -> void:
	var timer := _new_timer(1.0)
	timer.call("tick", 1.0)

	assert_eq(timer.call("phase"), TWO, "phase() must not itself advance the clock")
	assert_eq(timer.call("phase"), TWO)


# ---------------------------------------------------------------------------
# elapsed_s() accessor.
# ---------------------------------------------------------------------------


func test_elapsed_s_accumulates_real_ticked_time() -> void:
	var timer := _new_timer(1.0)

	timer.call("tick", 0.3)
	timer.call("tick", 0.4)

	assert_almost_eq(float(timer.call("elapsed_s")), 0.7, 0.0001)


func test_elapsed_s_keeps_accumulating_even_once_running() -> void:
	var timer := _new_timer(1.0)
	timer.call("tick", 100.0)
	assert_eq(timer.call("phase"), GO)

	timer.call("tick", 1.0)
	timer.call("tick", 1.0)

	# Running ticks are no-ops for elapsed_s too -- the go-tick already
	# folded the whole 100.0 in; nothing after that adds to it.
	assert_almost_eq(float(timer.call("elapsed_s")), 100.0, 0.0001)
