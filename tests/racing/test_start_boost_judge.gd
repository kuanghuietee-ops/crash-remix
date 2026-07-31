extends GutTest

# CTR R5 Task 1: StartBoostJudge is pure RefCounted hold-sampling logic
# (configure/sample/verdict poll model) -- see start_boost_judge.gd's own
# class doc (HOLD-SAMPLING MODEL/VERDICT sections) and .superpowers/sdd/
# 2026-07-31-ctr-r5-race-flow/task-1-brief.md.

const JUDGE_PATH := "res://src/racing/flow/start_boost_judge.gd"

const NONE := &"none"
const BOOST := &"boost"
const BOG := &"bog"


func _new_judge(window_s: float) -> RefCounted:
	var tuning := RaceTuning.new()
	tuning.start_boost_window_s = window_s
	var judge: RefCounted = load(JUDGE_PATH).new()
	judge.call("configure", tuning)
	return judge


# ---------------------------------------------------------------------------
# Not held at all -> none.
# ---------------------------------------------------------------------------


func test_never_sampled_held_reads_none_at_verdict() -> void:
	var judge := _new_judge(0.3)

	assert_eq(judge.call("verdict"), NONE)


func test_held_then_released_before_the_final_sample_reads_none() -> void:
	var judge := _new_judge(0.3)

	judge.call("sample", 0.1, true)
	judge.call("sample", 0.1, false)

	assert_eq(
		judge.call("verdict"),
		NONE,
		"HOP not held at the moment verdict() is read must always be none"
	)


# ---------------------------------------------------------------------------
# Held into the window (from within the last start_boost_window_s) -> boost.
# ---------------------------------------------------------------------------


func test_held_starting_inside_the_window_reads_boost() -> void:
	var judge := _new_judge(0.3)

	# 0.1s continuous hold, well inside a 0.3s window.
	judge.call("sample", 0.1, true)

	assert_eq(judge.call("verdict"), BOOST)


func test_held_duration_exactly_at_the_window_edge_reads_boost_inclusive() -> void:
	var judge := _new_judge(0.3)

	# A single sample of exactly the window width (a single float value, not
	# a sum of two -- avoiding any floating-point summation rounding at the
	# boundary itself, which a two-sample 0.2+0.1 would introduce). The
	# boundary instant must still read as inside the window (inclusive, see
	# the class doc's own VERDICT ruling).
	judge.call("sample", 0.3, true)

	assert_eq(judge.call("verdict"), BOOST)


# ---------------------------------------------------------------------------
# Held from earlier than the window start (held too early/too long) -> bog.
# ---------------------------------------------------------------------------


func test_held_starting_earlier_than_the_window_reads_bog() -> void:
	var judge := _new_judge(0.3)

	judge.call("sample", 0.2, true)
	# Cumulative hold now 0.5s, past the 0.3s window.
	judge.call("sample", 0.3, true)

	assert_eq(judge.call("verdict"), BOG)


func test_held_duration_just_past_the_window_edge_reads_bog() -> void:
	var judge := _new_judge(0.3)

	judge.call("sample", 0.301, true)

	assert_eq(judge.call("verdict"), BOG)


# ---------------------------------------------------------------------------
# A release resets the continuous-hold clock -- a fresh press that starts
# inside the window after an earlier, released press must still read boost.
# ---------------------------------------------------------------------------


func test_a_release_resets_the_held_duration_so_a_later_fresh_press_can_still_boost() -> void:
	var judge := _new_judge(0.3)

	# An early press, held well past the window, then released.
	judge.call("sample", 0.5, true)
	judge.call("sample", 0.01, false)
	# A brand-new press starting fresh, well inside the window.
	judge.call("sample", 0.05, true)

	assert_eq(
		judge.call("verdict"),
		BOOST,
		"releasing must reset the continuous-hold clock, not carry the stale duration forward"
	)


func test_a_release_then_re_press_that_started_too_early_still_reads_bog() -> void:
	var judge := _new_judge(0.3)

	judge.call("sample", 0.1, false)
	# Fresh press held for 0.4s total, past the 0.3s window.
	judge.call("sample", 0.2, true)
	judge.call("sample", 0.2, true)

	assert_eq(judge.call("verdict"), BOG)
