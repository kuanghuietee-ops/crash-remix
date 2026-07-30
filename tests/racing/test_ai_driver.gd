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

const DRIVER_SCRIPT_PATH := "res://src/racing/ai/ai_driver.gd"
const AI_TUNING_PATH := "res://data/tuning/racing/ai.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _ai: AiTuning
var _kart: KartTuning


func before_all() -> void:
	_ai = load(AI_TUNING_PATH)
	assert_not_null(_ai, "ai.tres must load -- Task 1 registers it")
	_kart = load(KART_TUNING_PATH)
	assert_not_null(_kart, "kart.tres must load -- Task 1 (R1/R2) registers it")


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


# ---------------------------------------------------------------------------
# Hop/slide-min-steer coupling: DriftStateMachine only starts (or sustains)
# a slide when |steer| >= kart.slide_min_steer on the same tick. A hop
# edge fired on a tick where the natural pursuit+lateral steer fell short
# would silently fail to start anything in the real FSM, so the driver must
# bump the steer magnitude up to the floor whenever it intends to hold a
# slide -- on the hop tick itself, and every tick after, for as long as
# curvature_ahead keeps that intent armed.
# ---------------------------------------------------------------------------


func test_hop_tick_forces_steer_to_slide_min_steer_when_raw_steer_is_zero() -> void:
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
		"raw steer of ~0 on a hop tick must be floored up to slide_min_steer"
	)


func test_hop_tick_floors_a_small_positive_steer_preserving_its_sign() -> void:
	var driver := _new_driver()
	if driver == null:
		return

	# lateral_term = steer_gain * (0.1 / 10.0), comfortably below
	# slide_min_steer (0.25 in kart.tres) but not zero -- the floor must
	# preserve the sign it already had, not fall back to a default.
	var result: Dictionary = driver.call("decide", _state({
		"position": Vector3.ZERO,
		"forward": Vector3(0.0, 0.0, -1.0),
		"lookahead_point": Vector3(0.0, 0.0, -10.0),
		"curvature_ahead": _ai.slide_trigger_curvature * 2.0,
		"lateral_error_m": 0.1,
	}))

	var raw_would_be: float = _ai.steer_gain * (0.1 / 10.0)
	assert_true(
		raw_would_be < _kart.slide_min_steer,
		"fixture sanity: raw steer must fall short of the floor"
	)
	assert_almost_eq(float(result.get("steer")), _kart.slide_min_steer, 0.0001)


func test_hop_tick_floors_a_small_negative_steer_preserving_its_sign() -> void:
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

	assert_almost_eq(float(result.get("steer")), -_kart.slide_min_steer, 0.0001)


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
	driver.call("configure", disabled_ai, _kart)

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
	driver.call("configure", _ai, _kart)
	return driver
