extends GutTest

# Task 2 (CTR R3: AI opponents) -- SpineFollower is pure RefCounted
# hysteresis-filter logic (configure/reset/update poll model, same shape as
# lap_validator.gd/drift_state_machine.gd) that turns TrackSpine.
# progress_for_position()'s seam-ambiguous raw offset into a continuous,
# monotonic-per-frame total_progress_m() -- the documented answer to
# track_spine.gd's SEAM AMBIGUITY doc block's "CONTINUOUS consumer" bullet.
# See spine_follower.gd's class doc and .superpowers/sdd/
# 2026-07-30-ctr-r3-ai-karts/task-2-brief.md.

const FOLLOWER_SCRIPT_PATH := "res://src/racing/track/spine_follower.gd"

# A 100m closed loop is used throughout: easy-to-hand-verify arithmetic
# (half = 50), and large enough that "near the seam" (offsets close to 0 or
# close to 100) and "mid-track" (offsets far from both) are unambiguous.
const _LENGTH_M := 100.0


# ---------------------------------------------------------------------------
# Baseline: forward progress away from the seam accumulates plainly.
# ---------------------------------------------------------------------------


func test_forward_progress_away_from_the_seam_accumulates_total() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 10.0)

	var out1: float = follower.call("update", 15.0, 10.0)
	assert_almost_eq(out1, 15.0, 0.001)
	assert_almost_eq(follower.call("total_progress_m"), 15.0, 0.001)

	var out2: float = follower.call("update", 20.0, 10.0)
	assert_almost_eq(out2, 20.0, 0.001)
	assert_almost_eq(follower.call("total_progress_m"), 20.0, 0.001)


# ---------------------------------------------------------------------------
# (a) Forward crossing of the seam continues total upward by the small true
# delta -- must NOT read as a ~length jump backward.
# ---------------------------------------------------------------------------


func test_forward_crossing_of_the_seam_continues_total_upward() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 99.9)

	# True forward movement of 0.15m: 99.9 -> 100.0 (seam) -> 0.05.
	var filtered: float = follower.call("update", 0.05, 10.0)

	assert_almost_eq(
		follower.call("total_progress_m"),
		100.05,
		0.001,
		"seam crossing must continue total upward by the true delta"
	)
	assert_almost_eq(
		filtered,
		0.05,
		0.001,
		"update() must return the new lap progress (total mod length)"
	)
	assert_true(
		float(follower.call("total_progress_m")) > 99.9,
		"forward seam crossing must never read as a jump back toward 0"
	)


# ---------------------------------------------------------------------------
# (b) The documented ambiguity jump (raw leaps ~99%<->~0% for a sub-meter
# true move, either direction) is filtered to <= max_step -- see
# track_spine.gd's SEAM AMBIGUITY doc block for the empirical numbers this
# mirrors (offset flipping 0.0 -> ~399.95 of a ~400m loop for a ~5cm move).
# ---------------------------------------------------------------------------


func test_seam_ambiguity_flip_high_to_low_is_bounded_by_max_step() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 0.0)

	# Ambiguity flip: raw reads 99.95 (near the top) right after a sample
	# that read 0.0 (near the bottom) -- same physical corner, ~0.05m of
	# true movement, not the ~100m the raw numbers suggest.
	follower.call("update", 99.95, 1.0)

	var applied: float = float(follower.call("total_progress_m")) - 0.0
	assert_true(
		absf(applied) <= 1.0,
		"seam ambiguity flip must be filtered to <= max_step_m, got delta %s"
		% applied
	)
	assert_true(
		absf(applied) < _LENGTH_M * 0.5,
		"must never be misread as a near-half-lap (or near-full-lap) jump"
	)


func test_seam_ambiguity_flip_low_to_high_is_bounded_by_max_step() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 0.05)

	# Reverse-direction ambiguity flip: raw reads 99.97 (near the top)
	# right after a sample that read 0.05 (near the bottom) -- ~0.08m of
	# true BACKWARD movement across the seam.
	follower.call("update", 99.97, 1.0)

	var applied: float = float(follower.call("total_progress_m")) - 0.05
	assert_true(
		absf(applied) <= 1.0,
		"reverse seam ambiguity flip must be filtered to <= max_step_m, got delta %s"
		% applied
	)
	assert_true(
		applied < 0.0,
		"this flip represents true backward movement and must decrease total"
	)


# ---------------------------------------------------------------------------
# (c) Reverse driving decreases total.
# ---------------------------------------------------------------------------


func test_reverse_driving_decreases_total() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 50.0)

	var out1: float = follower.call("update", 49.5, 5.0)
	assert_almost_eq(out1, 49.5, 0.001)
	assert_almost_eq(follower.call("total_progress_m"), 49.5, 0.001)

	var out2: float = follower.call("update", 49.0, 5.0)
	assert_almost_eq(out2, 49.0, 0.001)
	assert_true(out2 < out1, "reverse driving must keep decreasing total")


# ---------------------------------------------------------------------------
# (d) Three full laps accumulate total to ~3x length.
# ---------------------------------------------------------------------------


func test_three_full_laps_accumulate_total_to_three_times_length() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 0.0)

	# Each lap: 10 forward steps of 10m each, the last of which is the raw
	# seam wrap (90 -> 0.0) that represents the true final 10m of the lap.
	var raws: Array[float] = [
		10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 0.0
	]
	var lap := 0
	while lap < 3:
		for raw in raws:
			follower.call("update", raw, 50.0)
		lap += 1

	assert_almost_eq(
		follower.call("total_progress_m"),
		300.0,
		0.01,
		"3 laps of a 100m loop must accumulate to ~300m of continuous total"
	)
	assert_almost_eq(
		follower.call("lap_progress_m"),
		0.0,
		0.01,
		"lap_progress_m must be total mod length"
	)


# ---------------------------------------------------------------------------
# (e) Zero/negative-length guard: fail closed.
# ---------------------------------------------------------------------------


func test_configure_with_zero_length_pushes_error_and_fails_closed() -> void:
	var follower := _new_unconfigured_follower()
	if follower == null:
		return
	follower.call("configure", 0.0)

	assert_push_error("spine_length_m")

	var result: float = follower.call("update", 5.0, 1.0)
	assert_eq(
		result,
		0.0,
		"update() must fail closed to 0.0 with a non-positive configured length"
	)
	assert_eq(
		follower.call("total_progress_m"),
		0.0,
		"total must not accumulate while the follower is invalid"
	)


func test_configure_with_negative_length_pushes_error_and_fails_closed() -> void:
	var follower := _new_unconfigured_follower()
	if follower == null:
		return
	follower.call("configure", -5.0)

	assert_push_error("spine_length_m")

	var result: float = follower.call("update", 5.0, 1.0)
	assert_eq(result, 0.0)
	assert_eq(follower.call("lap_progress_m"), 0.0)


# ---------------------------------------------------------------------------
# (f) max_step_m <= 0 is treated as unclamped (documented choice).
# ---------------------------------------------------------------------------


func test_max_step_zero_is_treated_as_unclamped() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 0.0)

	var out: float = follower.call("update", 40.0, 0.0)

	assert_almost_eq(
		out,
		40.0,
		0.001,
		"max_step_m <= 0.0 must mean unclamped, not clamp-to-zero-movement"
	)
	assert_almost_eq(follower.call("total_progress_m"), 40.0, 0.001)


func test_max_step_negative_is_treated_as_unclamped() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 0.0)

	var out: float = follower.call("update", 40.0, -1.0)

	assert_almost_eq(out, 40.0, 0.001)
	assert_almost_eq(follower.call("total_progress_m"), 40.0, 0.001)


func test_max_step_clamps_a_plain_large_forward_delta() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 10.0)

	# 30m of raw forward movement in one call, capped to a 5m/step budget.
	var out: float = follower.call("update", 40.0, 5.0)

	assert_almost_eq(out, 15.0, 0.001)
	assert_almost_eq(follower.call("total_progress_m"), 15.0, 0.001)


# ---------------------------------------------------------------------------
# General contract: reset(), lap_progress_m() == total mod length, and
# update()'s return value matches lap_progress_m() after the call.
# ---------------------------------------------------------------------------


func test_reset_seeds_total_and_derives_lap_progress_by_modulo() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return

	# A resume-mid-race seed past one full lap length.
	follower.call("reset", 250.0)

	assert_almost_eq(follower.call("total_progress_m"), 250.0, 0.001)
	assert_almost_eq(follower.call("lap_progress_m"), 50.0, 0.001)


func test_update_return_value_matches_lap_progress_after_the_call() -> void:
	var follower := _new_follower(_LENGTH_M)
	if follower == null:
		return
	follower.call("reset", 95.0)

	var out: float = follower.call("update", 97.0, 10.0)
	var lap_progress: float = follower.call("lap_progress_m")

	assert_almost_eq(out, lap_progress, 0.0001)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_unconfigured_follower() -> RefCounted:
	var script: Script = load(FOLLOWER_SCRIPT_PATH)
	assert_not_null(script, "SpineFollower implementation must exist")
	if script == null:
		return null
	return script.new()


func _new_follower(spine_length_m: float) -> RefCounted:
	var follower := _new_unconfigured_follower()
	if follower == null:
		return null
	follower.call("configure", spine_length_m)
	return follower
