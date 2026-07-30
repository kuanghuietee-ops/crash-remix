class_name SpineFollower
extends RefCounted

## Seam-safe monotonic progress filter (Task 2, CTR R3: AI opponents). Pure
## RefCounted, no Node/scene dependency -- same configure()-then-poll shape
## as lap_validator.gd/drift_state_machine.gd.
##
## This is the documented answer to track_spine.gd's SEAM AMBIGUITY doc
## block, specifically its "CONTINUOUS consumer" bullet: "a progress bar,
## distance-based standings/ranking (future R5) -- must NOT trust
## frame-to-frame deltas of this value near the seam. Either add hysteresis
## ... or, better, rank by (current_lap(), progress_gates())". R3's AI
## needs exactly that continuous distance signal every physics frame (gap
## between karts = difference of two followers' total_progress_m()), so it
## takes the hysteresis branch: this class wraps TrackSpine.
## progress_for_position()'s raw, seam-ambiguous offset into a
## total_progress_m() that only ever grows/shrinks by a plausible per-call
## amount, and never confuses "crossed the seam" with "teleported backward
## almost a full lap".
##
## ALGORITHM. Each update() computes:
##   delta = wrap(raw_progress_m - last_filtered_lap_progress)
## wrapped into (-length/2, +length/2] -- the same wrap that fixes the seam
## ambiguity outright: a raw jump of ~length in either direction (offset
## ~0 <-> ~length_m(), the exact 99%<->0% case track_spine.gd's doc block
## empirically measured) wraps down to the small TRUE delta the physical
## movement actually was, because the two raw values are, by construction,
## the same physical point on the loop. That delta is then clamped to
## +/-max_step_m as a second, independent safety net -- any other
## implausibly large single-frame delta, seam or not, gets rate-limited
## rather than trusted outright -- and only then accumulated into
## total_progress_m(): a plain running sum that never wraps and grows
## across laps. lap_progress_m() is just that sum taken modulo length_m
## for callers that want an on-track position instead of a lap count.
##
## LAST_FILTERED, NOT RAW. The delta above is measured against this
## follower's own last FILTERED lap position (lap_progress_m() as of the
## previous update()), never against the previous raw_progress_m. This is
## what makes it a real rate limiter instead of a one-shot clamp: if raw
## stays pinned at an implausible value for several consecutive calls (a
## sustained bad sample, not just a single-frame seam artifact),
## total_progress_m() ramps toward it by at most max_step_m per call
## instead of recomputing the same oversized delta against stale raw
## every time.
##
## EDGE CASES (pinned by tests/racing/test_spine_follower.gd):
## - configure() with spine_length_m <= 0.0 push_errors and marks the
##   follower invalid; every update() thereafter fails closed, returning
##   0.0 and leaving total_progress_m() untouched, rather than dividing by
##   a zero/negative length.
## - max_step_m <= 0.0 is read as "no clamp" (the wrapped delta passes
##   through unclamped) -- the same 0-means-off convention track_spine.gd
##   itself uses for bake_interval_m/handle_length_factor -- not "clamp to
##   zero movement".
## - configure() only sets the length; it never touches accumulated state.
##   Call reset() explicitly for a fresh total -- the same configure()/
##   tick() split drift_state_machine.gd uses for its own tuning.

const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _length_m: float
var _valid: bool

var _total_progress_m: float
var _last_lap_progress_m: float


func configure(spine_length_m: float) -> void:
	if spine_length_m <= 0.0:
		push_error(
			(
				"SpineFollower.configure: spine_length_m must be > 0.0 "
				+ "(got %s) -- failing closed: update() will return 0.0 "
				+ "until reconfigured with a positive length."
			) % spine_length_m
		)
		_valid = false
		_length_m = 0.0
		return
	_valid = true
	_length_m = spine_length_m


## Seeds total_progress_m() directly to progress_m (a continuous, not
## lap-bounded, value -- reset(250.0) on a 100m loop means "already 2.5
## laps in", matching a resume-mid-race caller) and derives
## lap_progress_m() from it via the same modulo update() uses, so the very
## next update() call's seam wrap has a consistent reference point.
func reset(progress_m: float) -> void:
	_total_progress_m = progress_m
	_last_lap_progress_m = _wrap_to_lap(progress_m) if _valid else 0.0


func update(raw_progress_m: float, max_step_m: float) -> float:
	if not _valid:
		return 0.0
	var delta := _wrap_delta(raw_progress_m - _last_lap_progress_m)
	if max_step_m > 0.0:
		delta = clampf(delta, -max_step_m, max_step_m)
	_total_progress_m += delta
	_last_lap_progress_m = _wrap_to_lap(_total_progress_m)
	return _last_lap_progress_m


## Continuous progress that never wraps and grows across laps -- THE value
## for cross-kart comparison (gap = difference of two followers' totals).
func total_progress_m() -> float:
	return _total_progress_m


## total_progress_m() taken modulo length_m -- an on-track position in
## [0, length_m), the same domain as TrackSpine.progress_for_position().
func lap_progress_m() -> float:
	return _wrap_to_lap(_total_progress_m) if _valid else 0.0


func _wrap_to_lap(progress_m: float) -> float:
	return fposmod(progress_m, _length_m)


## Wraps delta_m into (-length/2, +length/2]: the canonical representative
## of delta_m's residue class that has the smallest magnitude, breaking
## the exact-half tie toward the positive side (see the class doc's
## ALGORITHM section). ScalarMathType.HALF, not a bare 0.5, per this
## codebase's src/racing/**-scoped numeric-literal lint.
func _wrap_delta(delta_m: float) -> float:
	var half := _length_m * ScalarMathType.HALF
	return half - fposmod(half - delta_m, _length_m)
