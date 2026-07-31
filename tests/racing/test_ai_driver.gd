extends GutTest

# Task 3 (CTR R3: AI opponents) -- AiDriver is pure logic (RefCounted,
# configure()-then-poll shape, same idiom as drift_state_machine.gd/
# kart_motor.gd/spine_follower.gd). decide(state: Dictionary) -> Dictionary
# is the "virtual thumb": Task 4's AiKartAgent will assemble state from a
# real KartController + TrackSpine + SpineFollower and route the returned
# outputs back onto the same KartController API a human uses. This suite
# drives it entirely with plain FakeState dictionaries -- no scene nodes --
# per the brief's test idiom (see tests/gameplay/test_portal_rules.gd for
# the same Dictionary-in/Dictionary-out shape this mirrors).
#
# See .superpowers/sdd/2026-07-30-ctr-r3-ai-karts/task-3-brief.md and
# docs/superpowers/plans/2026-07-30-ctr-r3-ai-karts.md (Task 3).
#
# Task 5 (CTR R4: AI item use + boxes) -- see
# .superpowers/sdd/2026-07-30-ctr-r4-items/task-5-brief.md. configure()
# gains a third, OPTIONAL item_tuning: ItemTuning parameter (default null) --
# see the "without item_tuning" tests below, which deliberately configure
# WITHOUT it to prove every non-item output keeps working and only the
# missile heuristic (the one heuristic that needs a real ItemTuning value,
# ai_missile_max_target_gap_m) fails closed. Every other test in this file
# configures fully (_new_driver() below now always passes _item too).

const DRIVER_SCRIPT_PATH := "res://src/racing/ai/ai_driver.gd"
const AI_TUNING_PATH := "res://data/tuning/racing/ai.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"
const ITEM_TUNING_PATH := "res://data/tuning/racing/items.tres"

var _ai: AiTuning
var _kart: KartTuning
var _item: ItemTuning


func before_all() -> void:
	_ai = load(AI_TUNING_PATH)
	assert_not_null(_ai, "ai.tres must load -- Task 1 registers it")
	_kart = load(KART_TUNING_PATH)
	assert_not_null(_kart, "kart.tres must load -- Task 1 (R1/R2) registers it")
	_item = load(ITEM_TUNING_PATH)
	assert_not_null(_item, "items.tres must load -- R4 Task 2 registers it")


# ---------------------------------------------------------------------------
# Straight line: no pursuit angle, no lateral error, no curvature -> steer
# almost zero and no brake.
# ---------------------------------------------------------------------------


func test_straight_ahead_gives_near_zero_steer_and_no_brake() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"speed_mps": 10.0,
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": 0.0,
		"lateral_error_m": 0.0,
	}))

	assert_almost_eq(
		float(result.get("steer")),
		0.0,
		0.001,
		"a lookahead point straight ahead with no lateral error must not steer"
	)
	assert_false(bool(result.get("brake")), "well under target speed must not brake")
	assert_false(bool(result.get("hop")), "flat curvature must not trigger a hop")


# ---------------------------------------------------------------------------
# Curve ahead: lookahead point off to one side -> steer sign toward it.
# curvature stays under slide_trigger_curvature so this is isolated from
# the hop/slide-floor behavior exercised separately below.
# ---------------------------------------------------------------------------


func test_curve_ahead_to_the_right_steers_positive() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(4.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature / 2.0,
	}))

	assert_true(
		float(result.get("steer")) > 0.0,
		"a lookahead point to the kart's world-space right must steer positive (right)"
	)


func test_curve_ahead_to_the_left_steers_negative() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(-4.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature / 2.0,
	}))

	assert_true(
		float(result.get("steer")) < 0.0,
		"a lookahead point to the kart's world-space left must steer negative (left)"
	)


# ---------------------------------------------------------------------------
# Lateral error: positive (target to the kart's right) steers toward the
# slot; negative steers the other way. curvature is 0 so the slide floor
# never engages and the lateral term is isolated.
# ---------------------------------------------------------------------------


func test_positive_lateral_error_steers_toward_the_slot_on_the_right() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": 0.0,
		"lateral_error_m": 0.1,
	}))

	# lateral_term = steer_gain * (lateral_error_m / lookahead_distance_m)
	var expected: float = _ai.steer_gain * (0.1 / 10.0)
	assert_almost_eq(float(result.get("steer")), expected, 0.0001)
	assert_true(expected > 0.0, "fixture sanity: expected lateral term must be positive")


func test_negative_lateral_error_steers_toward_the_slot_on_the_left() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": 0.0,
		"lateral_error_m": -0.1,
	}))

	var expected: float = _ai.steer_gain * (-0.1 / 10.0)
	assert_almost_eq(float(result.get("steer")), expected, 0.0001)
	assert_true(expected < 0.0, "fixture sanity: expected lateral term must be negative")


# ---------------------------------------------------------------------------
# Overspeed into a hairpin -> brake.
# ---------------------------------------------------------------------------


func test_overspeed_into_a_hairpin_brakes() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	# target_speed = top_speed * clamp(1 - gain*curvature, floor, 1), floored
	# at a curvature this high -- speed_mps well past target*brake_margin.
	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"speed_mps": _kart.top_speed_mps,
	}))

	var target_speed: float = _kart.top_speed_mps * _ai.corner_speed_floor_ratio
	assert_true(
		_kart.top_speed_mps > target_speed * _ai.brake_margin_ratio,
		"fixture sanity: top speed must exceed the braked target by the margin"
	)
	assert_true(bool(result.get("brake")), "overspeed past target*margin into a hairpin must brake")


# Fix round 1: curvature_ahead is now SIGNED (positive = bends right,
# negative = bends left -- see ai_driver.gd's SIGNED CURVATURE CONTRACT).
# Corner-speed/brake math must read it through absf(), so a left-bending
# hairpin of the same magnitude must brake exactly the same as the
# right-bending one above.
func test_overspeed_into_a_left_bending_hairpin_brakes_the_same_via_absf() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"speed_mps": _kart.top_speed_mps,
	}))

	assert_true(
		bool(result.get("brake")),
		"a left-bending hairpin of equal magnitude must brake identically (absf)"
	)


func test_under_target_speed_does_not_brake() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": 0.0,
		"speed_mps": 1.0,
	}))

	assert_false(bool(result.get("brake")))


# ---------------------------------------------------------------------------
# Tight curvature triggers a hop edge exactly once -- not every tick the
# corner stays sharp, and not just because is_sliding happens to flip true
# (this drives it with is_sliding staying false across every call, so a
# repeat firing could only come from a missing edge-memory guard).
# ---------------------------------------------------------------------------


func test_tight_curvature_triggers_hop_edge_exactly_once() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var straight_ahead_state := _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	})

	var first: Dictionary = driver.call("decide", straight_ahead_state)
	assert_true(bool(first.get("hop")), "curvature past slide_trigger_curvature must arm a hop")

	var second: Dictionary = driver.call("decide", straight_ahead_state)
	assert_false(
		bool(second.get("hop")),
		"the same sharp corner must not re-fire hop every tick (edge memory)"
	)

	var third: Dictionary = driver.call("decide", straight_ahead_state)
	assert_false(bool(third.get("hop")), "hop must stay suppressed while intent is still armed")


func test_hop_does_not_fire_below_slide_trigger_curvature() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature / 2.0,
	}))

	assert_false(bool(result.get("hop")))


func test_hop_does_not_fire_when_already_sliding() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": true,
	}))

	assert_false(
		bool(result.get("hop")),
		"a corner sharp enough to arm intent must not hop again if the FSM already reports sliding"
	)


# Fix round 1: hop's trigger must be magnitude-only (absf(curvature_ahead)),
# so a left-bending corner (negative signed curvature) of the same
# magnitude arms intent and fires hop exactly like a right-bending one.
func test_tight_curvature_triggers_hop_when_bending_left_via_absf() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	}))

	assert_true(
		bool(result.get("hop")),
		"a left-bending corner past the trigger magnitude must arm a hop just like a right-bending one"
	)


# ---------------------------------------------------------------------------
# Hop/slide-min-steer coupling: DriftStateMachine only starts (or sustains)
# a slide when |steer| >= kart.slide_min_steer on the same tick. A hop
# edge fired on a tick where the natural pursuit+lateral steer fell short
# would silently fail to start anything in the real FSM, so the driver must
# bump the steer magnitude up to the floor whenever it intends to hold a
# slide -- on the hop tick itself, and every tick after, for as long as
# curvature_ahead keeps that intent armed.
# ---------------------------------------------------------------------------


# Fix round 1 ([HIGH]): the floor's direction must come from
# curvature_ahead's SIGN, not from the (often ~0 at corner entry, per the
# reviewer's repro) pursuit+lateral steer it's replacing, and not from any
# remembered steer history. A hairpin bending RIGHT (positive signed
# curvature) must floor steer POSITIVE...
func test_hop_tick_on_a_hairpin_bending_right_floors_steer_positive() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": 0.0,
	}))

	assert_true(bool(result.get("hop")))
	assert_almost_eq(
		float(result.get("steer")),
		_kart.slide_min_steer,
		0.0001,
		"a right-bending hairpin must floor steer to +slide_min_steer"
	)


## ...and one bending LEFT (negative signed curvature) must floor steer
## NEGATIVE -- the exact mirror, and the two together are what the old
## "raw steer of ~0" test used to conflate into a single (sign-blind, and
## therefore buggy) case.
func test_hop_tick_on_a_hairpin_bending_left_floors_steer_negative() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": 0.0,
	}))

	assert_true(bool(result.get("hop")))
	assert_almost_eq(
		float(result.get("steer")),
		-_kart.slide_min_steer,
		0.0001,
		"a left-bending hairpin must floor steer to -slide_min_steer"
	)


## The actual reviewer repro: a small NONZERO raw steer whose own sign
## disagrees with the corner's true (curvature) direction -- e.g. the
## lookahead point has drifted very slightly to the right of center
## (raw steer small positive) right as a hard LEFT hairpin starts. The
## floor must still follow curvature (negative), not the raw sign
## (positive) -- this is exactly "keep the pursuit sign only when it
## EXCEEDS the floor already" from the fix-round-1 ruling.
func test_floor_direction_follows_curvature_even_when_a_small_raw_steer_disagrees() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	# lateral_term = steer_gain * (0.1 / 10.0) -- small POSITIVE, well under
	# slide_min_steer (0.25 in kart.tres).
	var raw_would_be: float = _ai.steer_gain * (0.1 / 10.0)
	assert_true(
		raw_would_be > 0.0 and raw_would_be < _kart.slide_min_steer,
		"fixture sanity: raw steer must be small, positive, and under the floor"
	)

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": 0.1,
	}))

	assert_almost_eq(
		float(result.get("steer")),
		-_kart.slide_min_steer,
		0.0001,
		"curvature's LEFT direction must win over the small raw steer's own (positive) sign"
	)


## Symmetric mirror: small NEGATIVE raw steer, RIGHT-bending curvature ->
## floor must still be positive.
func test_floor_direction_follows_curvature_even_when_a_small_raw_steer_disagrees_the_other_way() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": -0.1,
	}))

	assert_almost_eq(
		float(result.get("steer")),
		_kart.slide_min_steer,
		0.0001,
		"curvature's RIGHT direction must win over the small raw steer's own (negative) sign"
	)


## Above-floor raw steer is the one case where curvature must NOT override
## the sign -- "keep the pursuit sign only when it EXCEEDS the floor
## already". A large raw steer opposite the corner's curvature (e.g.
## correcting hard out of a slot on the far side of the track) must pass
## through unchanged, not get clamped onto curvature's side.
func test_floor_leaves_an_already_sufficient_raw_steer_unchanged_even_against_curvature() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	# lateral_term alone = steer_gain * (5.0 / 10.0) = 1.1, comfortably past
	# slide_min_steer (0.25) -- curvature says LEFT (negative), raw steer
	# says strongly RIGHT (positive).
	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": 5.0,
	}))

	assert_true(
		float(result.get("steer")) > 0.0,
		"a raw steer that already clears the floor must keep its own sign, not curvature's"
	)


## History independence: fix round 1 removed the old _last_steer_sign
## memory entirely, so a LEFT-bending episode must have zero effect on a
## later, unrelated RIGHT-bending one's floor direction.
func test_floor_direction_is_independent_of_a_prior_opposite_direction_tick() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var base := {
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"lateral_error_m": 0.0,
	}

	# Episode 1: a LEFT-bending hairpin, hop + floor to -slide_min_steer.
	var left_hop: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": -_ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	})))
	assert_true(bool(left_hop.get("hop")))
	assert_almost_eq(float(left_hop.get("steer")), -_kart.slide_min_steer, 0.0001)

	# Curvature drops to/below the exit threshold -- intent clears, the
	# slide (per the real FSM, simulated here) ends.
	driver.call("decide", _state(_merged(base, {
		"curvature_ahead": _ai.slide_exit_curvature,
		"is_sliding": true,
	})))

	# Episode 2: an unrelated RIGHT-bending hairpin. If any steer-history
	# memory survived, it would still be pointing left from episode 1; the
	# fixed driver must floor this purely from the new curvature sign.
	var right_hop: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	})))
	assert_true(bool(right_hop.get("hop")), "a fresh corner must still arm its own hop edge")
	assert_almost_eq(
		float(right_hop.get("steer")),
		_kart.slide_min_steer,
		0.0001,
		"the new RIGHT-bending corner's floor must not be dragged left by episode 1's history"
	)


func test_steer_floor_stays_enforced_while_intent_remains_armed_across_ticks() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var base := {
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"lateral_error_m": 0.0,
	}

	# Tick 1: curvature past trigger, not yet sliding -> hop + floored steer.
	var tick1: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	})))
	assert_true(bool(tick1.get("hop")))
	assert_almost_eq(float(tick1.get("steer")), _kart.slide_min_steer, 0.0001)

	# Tick 2: the real FSM has now started the slide; curvature still high.
	# No new hop edge, but the floor must still hold the sustain threshold.
	var tick2: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": true,
	})))
	assert_false(bool(tick2.get("hop")))
	assert_almost_eq(float(tick2.get("steer")), _kart.slide_min_steer, 0.0001)

	# Tick 3: curvature drops into the hysteresis band between exit and
	# trigger -- intent must stay armed (neither condition fires), so the
	# floor still holds.
	var midpoint: float = (
		(_ai.slide_trigger_curvature + _ai.slide_exit_curvature) / 2.0
	)
	var tick3: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": midpoint,
		"is_sliding": true,
	})))
	assert_almost_eq(
		float(tick3.get("steer")),
		_kart.slide_min_steer,
		0.0001,
		"the hysteresis band between exit and trigger must keep intent (and the floor) armed"
	)

	# Tick 4: curvature drops to/below slide_exit_curvature -- intent clears
	# and the driver lets steer follow the natural (near-zero) line, which
	# is what allows the real FSM's own sustain check to end the slide.
	var tick4: Dictionary = driver.call("decide", _state(_merged(base, {
		"curvature_ahead": _ai.slide_exit_curvature,
		"is_sliding": true,
	})))
	assert_almost_eq(
		float(tick4.get("steer")),
		0.0,
		0.0001,
		"once curvature drops to slide_exit_curvature the floor must release and steer must follow the natural line"
	)
	assert_false(bool(tick4.get("hop")))


# ---------------------------------------------------------------------------
# boost_tap: only while sliding AND on the rising edge of boost_window_open
# -- never machine-gunned every tick the window stays open, never while not
# sliding, and never when boost_tap_enabled is off.
# ---------------------------------------------------------------------------


func test_boost_tap_fires_on_the_window_open_rising_edge_while_sliding() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var base := _state({"is_sliding": true})

	var closed: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": false})
	)
	assert_false(bool(closed.get("boost_tap")))

	var opened: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": true})
	)
	assert_true(
		bool(opened.get("boost_tap")),
		"the window opening while sliding must fire exactly one tap"
	)

	var still_open: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": true})
	)
	assert_false(
		bool(still_open.get("boost_tap")),
		"the window staying open must not machine-gun repeated taps"
	)


## Fix round 1: the missing stage-2 re-open coverage. A real stacked boost
## sequence is open (tap) -> close (between stages) -> open again (the next
## stage's window) -- the SECOND open must fire its own tap, not stay
## suppressed by the first tap's edge memory.
func test_boost_tap_fires_again_after_the_window_closes_and_reopens_for_the_next_stage() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var base := _state({"is_sliding": true})

	var stage1_open: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": true})
	)
	assert_true(bool(stage1_open.get("boost_tap")), "stage 1's window opening must fire a tap")

	var between_stages_closed: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": false})
	)
	assert_false(bool(between_stages_closed.get("boost_tap")))

	var stage2_open: Dictionary = driver.call(
		"decide", _merged_state(base, {"boost_window_open": true})
	)
	assert_true(
		bool(stage2_open.get("boost_tap")),
		"stage 2's window opening (a fresh rising edge after closing) must fire its own tap"
	)


func test_boost_tap_does_not_fire_when_not_sliding() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"is_sliding": false,
		"boost_window_open": true,
	}))

	assert_false(bool(result.get("boost_tap")))


func test_boost_tap_does_not_fire_when_disabled_in_tuning() -> void:
	var driver := _new_unconfigured_driver()
	if driver == null:
		return
	var disabled_ai: AiTuning = _ai.duplicate()
	disabled_ai.boost_tap_enabled = 0.0
	driver.call("configure", disabled_ai, _kart, _item)

	var result: Dictionary = driver.call("decide", _state({
		"is_sliding": true,
		"boost_window_open": true,
	}))

	assert_false(
		bool(result.get("boost_tap")),
		"boost_tap_enabled = 0.0 must disable tapping even on a valid rising edge"
	)


# ---------------------------------------------------------------------------
# Rubber band: speed_scale formula both directions, capped at the ratio
# extremes, and exactly 1.0 at gap == 0 (continuity between the two
# branches).
# ---------------------------------------------------------------------------


func test_rubber_band_boosts_when_behind_and_caps_at_the_ratio() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var half_gap: Dictionary = driver.call(
		"decide", _state({"band_gap_m": _ai.rubber_band_full_gap_m / 2.0})
	)
	assert_almost_eq(
		float(half_gap.get("speed_scale")),
		1.0 + _ai.rubber_band_boost_max_ratio * 0.5,
		0.0001
	)

	var far_beyond_full_gap: Dictionary = driver.call(
		"decide", _state({"band_gap_m": _ai.rubber_band_full_gap_m * 2.0})
	)
	assert_almost_eq(
		float(far_beyond_full_gap.get("speed_scale")),
		1.0 + _ai.rubber_band_boost_max_ratio,
		0.0001,
		"boost must cap at rubber_band_boost_max_ratio past the full gap"
	)


func test_rubber_band_drags_when_ahead_and_caps_at_the_ratio() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var half_gap: Dictionary = driver.call(
		"decide", _state({"band_gap_m": -_ai.rubber_band_full_gap_m / 2.0})
	)
	assert_almost_eq(
		float(half_gap.get("speed_scale")),
		1.0 - _ai.rubber_band_drag_max_ratio * 0.5,
		0.0001
	)

	var far_beyond_full_gap: Dictionary = driver.call(
		"decide", _state({"band_gap_m": -_ai.rubber_band_full_gap_m * 2.0})
	)
	assert_almost_eq(
		float(far_beyond_full_gap.get("speed_scale")),
		1.0 - _ai.rubber_band_drag_max_ratio,
		0.0001,
		"drag must cap at rubber_band_drag_max_ratio past the full gap"
	)


func test_rubber_band_speed_scale_is_exactly_one_at_zero_gap() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({"band_gap_m": 0.0}))

	assert_eq(
		float(result.get("speed_scale")),
		1.0,
		"gap == 0 must be exactly 1.0 -- the boost and drag branches must agree here"
	)


# ---------------------------------------------------------------------------
# Steer clamp saturation: an enormous pursuit or lateral term must still
# come out within -1..1.
# ---------------------------------------------------------------------------


func test_steer_clamps_to_positive_one_on_a_huge_lateral_error() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -1.0),
		"curvature_ahead": 0.0,
		"lateral_error_m": 100.0,
	}))

	assert_almost_eq(float(result.get("steer")), 1.0, 0.0001)


func test_steer_clamps_to_negative_one_on_a_huge_lateral_error() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -1.0),
		"curvature_ahead": 0.0,
		"lateral_error_m": -100.0,
	}))

	assert_almost_eq(float(result.get("steer")), -1.0, 0.0001)


# ---------------------------------------------------------------------------
# Item use (Task 5, CTR R4 items). One heuristic per held item, per
# ai_driver.gd's own class doc: shield fires immediately; turbo needs a
# straight (|curvature_ahead| below slide_exit_curvature); missile needs a
# target within ai_missile_max_target_gap_m ahead; beaker needs the kart to
# already be leading (band_gap_m < 0.0). All four are additionally gated on
# item_cooldown_ready and produce an EDGE output (own memory, like hop/
# boost_tap) -- see the machine-gun-guard tests below.
# ---------------------------------------------------------------------------


func test_shield_uses_immediately_when_held() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"shield",
	}))

	assert_true(
		bool(result.get("use_item")),
		"R4 keeps it simple: shield is used the instant it is held, no "
		+ "other condition gates it"
	)


func test_use_item_does_not_fire_with_nothing_held() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"none",
	}))

	assert_false(bool(result.get("use_item")))


func test_turbo_uses_below_slide_exit_curvature() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"turbo",
		"curvature_ahead": _ai.slide_exit_curvature / 2.0,
	}))

	assert_true(bool(result.get("use_item")), "a gentle straight must fire the turbo")


func test_turbo_uses_on_a_left_bending_near_straight_via_absf() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"turbo",
		"curvature_ahead": -_ai.slide_exit_curvature / 2.0,
	}))

	assert_true(
		bool(result.get("use_item")),
		"the threshold must read |curvature_ahead| -- a gentle LEFT bend is just as straight"
	)


func test_turbo_does_not_use_at_or_above_slide_exit_curvature() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"turbo",
		"curvature_ahead": _ai.slide_exit_curvature,
	}))

	assert_false(
		bool(result.get("use_item")),
		"'below slide_exit_curvature' is a strict less-than -- AT the threshold must not count"
	)


func test_missile_uses_at_the_target_gap_threshold() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"missile",
		"target_gap_ahead_m": _item.ai_missile_max_target_gap_m,
	}))

	assert_true(
		bool(result.get("use_item")),
		"the brief's own '<=' -- AT the threshold must still fire"
	)


func test_missile_does_not_use_beyond_the_target_gap_threshold() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"missile",
		"target_gap_ahead_m": _item.ai_missile_max_target_gap_m + 1.0,
	}))

	assert_false(bool(result.get("use_item")))


func test_missile_does_not_use_with_no_target_ahead() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"missile",
		"target_gap_ahead_m": INF,
	}))

	assert_false(
		bool(result.get("use_item")),
		"INF (nothing ahead -- e.g. this kart is already in the lead) must never satisfy <="
	)


func test_beaker_uses_when_leading() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"beaker",
		"band_gap_m": -5.0,
	}))

	assert_true(bool(result.get("use_item")))


func test_beaker_does_not_use_when_behind() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"beaker",
		"band_gap_m": 5.0,
	}))

	assert_false(bool(result.get("use_item")))


func test_beaker_does_not_use_when_exactly_tied() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"beaker",
		"band_gap_m": 0.0,
	}))

	assert_false(
		bool(result.get("use_item")),
		"the brief's own strict '< 0.0' -- exactly tied is not leading"
	)


func test_use_item_does_not_fire_when_cooldown_not_ready() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"shield",
		"item_cooldown_ready": false,
	}))

	assert_false(
		bool(result.get("use_item")),
		"an otherwise-satisfied heuristic must still be gated by the cooldown"
	)


func test_use_item_fires_once_then_suppresses_while_the_same_condition_holds() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	# Same Dictionary reused across all three calls -- held_item, the
	# heuristic, and the cooldown gate all stay satisfied the whole time,
	# the same "condition holds for many ticks" shape a long straight or a
	# multi-second cooldown-ready window produces for real.
	var state := _state({"held_item": &"shield"})

	var first: Dictionary = driver.call("decide", state)
	assert_true(bool(first.get("use_item")))

	var second: Dictionary = driver.call("decide", state)
	assert_false(
		bool(second.get("use_item")),
		"own edge memory (like hop/boost_tap) must suppress a repeat fire while "
		+ "the underlying condition is still held true -- 'once per decision, not machine-gun'"
	)

	var third: Dictionary = driver.call("decide", state)
	assert_false(bool(third.get("use_item")))


func test_use_item_rearms_after_the_condition_clears_and_returns() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	var held: Dictionary = driver.call("decide", _state({"held_item": &"shield"}))
	assert_true(bool(held.get("use_item")))

	var cleared: Dictionary = driver.call("decide", _state({"held_item": &"none"}))
	assert_false(bool(cleared.get("use_item")))

	var held_again: Dictionary = driver.call("decide", _state({"held_item": &"shield"}))
	assert_true(
		bool(held_again.get("use_item")),
		"a fresh held item (e.g. a new box pickup after the last one was used "
		+ "and cleared) must be able to fire its own new edge"
	)


func test_missile_never_uses_without_item_tuning_configured() -> void:
	var driver := _new_unconfigured_driver()
	if driver == null:
		return
	# Legacy 2-arg configure() -- item_tuning is optional (default null), the
	# same "graceful per-capability degrade" every other optional Callable in
	# this racing suite already uses (see ai_kart_agent.gd's other_kart_
	# positions_getter). Only the missile heuristic needs a real ItemTuning
	# value (ai_missile_max_target_gap_m); it must fail closed (never fire),
	# not crash, when that was never wired.
	driver.call("configure", _ai, _kart)

	var result: Dictionary = driver.call("decide", _state({
		"held_item": &"missile",
		"target_gap_ahead_m": 0.0,
	}))

	assert_false(bool(result.get("use_item")))


func test_steer_still_works_without_item_tuning_configured() -> void:
	var driver := _new_unconfigured_driver()
	if driver == null:
		return
	driver.call("configure", _ai, _kart)

	var result: Dictionary = driver.call("decide", _state({
		"lookahead_point": Vector3(4.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature / 2.0,
	}))

	assert_true(
		float(result.get("steer")) > 0.0,
		"item_tuning is only required for the missile heuristic -- every other "
		+ "output must keep working when it was never wired"
	)


# ---------------------------------------------------------------------------
# reset(): clears edge memory so a reused driver instance (e.g. after a
# stuck-kart respawn, per Task 4's brief) can re-arm hop/boost edges for a
# state it has technically already seen.
# ---------------------------------------------------------------------------


func test_reset_clears_hop_edge_memory() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var sharp_corner := _state({
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"is_sliding": false,
	})

	var first: Dictionary = driver.call("decide", sharp_corner)
	assert_true(bool(first.get("hop")))
	var second: Dictionary = driver.call("decide", sharp_corner)
	assert_false(bool(second.get("hop")), "fixture sanity: edge memory suppresses the repeat")

	driver.call("reset")

	var after_reset: Dictionary = driver.call("decide", sharp_corner)
	assert_true(
		bool(after_reset.get("hop")),
		"reset() must clear the armed-intent edge memory so the same state can hop again"
	)


func test_reset_clears_boost_tap_edge_memory() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var window_open := _state({"is_sliding": true, "boost_window_open": true})

	var first: Dictionary = driver.call("decide", window_open)
	assert_true(bool(first.get("boost_tap")))
	var second: Dictionary = driver.call("decide", window_open)
	assert_false(bool(second.get("boost_tap")), "fixture sanity: edge memory suppresses the repeat")

	driver.call("reset")

	var after_reset: Dictionary = driver.call("decide", window_open)
	assert_true(
		bool(after_reset.get("boost_tap")),
		"reset() must clear the boost-window edge memory"
	)


func test_reset_clears_use_item_edge_memory() -> void:
	var driver := _new_driver()
	if driver == null:
		return
	var state := _state({"held_item": &"shield"})

	var first: Dictionary = driver.call("decide", state)
	assert_true(bool(first.get("use_item")))
	var second: Dictionary = driver.call("decide", state)
	assert_false(bool(second.get("use_item")), "fixture sanity: edge memory suppresses the repeat")

	driver.call("reset")

	var after_reset: Dictionary = driver.call("decide", state)
	assert_true(
		bool(after_reset.get("use_item")),
		"reset() must clear the use_item edge memory too"
	)


# ---------------------------------------------------------------------------
# Fail-closed: decide() before a successful configure() must not crash on
# a null tuning dereference.
# ---------------------------------------------------------------------------


func test_decide_before_configure_fails_closed_to_a_neutral_output() -> void:
	var driver := _new_unconfigured_driver()
	if driver == null:
		return

	var result: Dictionary = driver.call("decide", _state({}))

	assert_push_error("configure")
	assert_eq(float(result.get("steer")), 0.0)
	assert_eq(bool(result.get("brake")), false)
	assert_eq(bool(result.get("hop")), false)
	assert_eq(bool(result.get("boost_tap")), false)
	assert_eq(float(result.get("speed_scale")), 1.0)
	assert_eq(bool(result.get("use_item")), false)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


## Default, fully-populated FakeState dictionary (straight, stationary,
# no slide/boost/gap) overridden per test by _state()'s overrides arg --
# every test only spells out the keys it actually cares about.
func _default_state() -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"speed_mps": 0.0,
		"is_sliding": false,
		"boost_window_open": false,
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": 0.0,
		"lateral_target_m": 0.0,
		"lateral_error_m": 0.0,
		"band_gap_m": 0.0,
		# Task 5: neutral/"off" defaults -- nothing held (so no heuristic can
		# fire regardless of the other three), no target ahead, but cooldown
		# READY (a gate, not a trigger on its own -- see ai_driver.gd's own
		# class doc) so per-item heuristic tests don't have to remember to
		# open this gate every time; the dedicated cooldown tests below
		# override it closed explicitly.
		"held_item": &"none",
		"target_gap_ahead_m": INF,
		"item_cooldown_ready": true,
	}


func _state(overrides: Dictionary) -> Dictionary:
	return _merged(_default_state(), overrides)


func _merged_state(base_state: Dictionary, overrides: Dictionary) -> Dictionary:
	return _merged(base_state, overrides)


func _merged(base_dict: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := base_dict.duplicate()
	for key in overrides:
		out[key] = overrides[key]
	return out


func _new_unconfigured_driver() -> RefCounted:
	var script: Script = load(DRIVER_SCRIPT_PATH)
	assert_not_null(script, "AiDriver implementation must exist")
	if script == null:
		return null
	return script.new()


func _new_driver() -> RefCounted:
	var driver := _new_unconfigured_driver()
	if driver == null:
		return null
	driver.call("configure", _ai, _kart, _item)
	return driver
