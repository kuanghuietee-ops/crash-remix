extends GutTest

# Task 3 (CTR racing mode): KartMotor is pure logic (RefCounted, poll model
# mirroring DriftStateMachine -- configure/tick push state forward, discrete
# hop()/add_boost()/apply_spin_out() calls are events, getters read state
# back). See docs/superpowers/plans/2026-07-30-ctr-r1-r2-kart-and-circuit.md
# task 3 and .superpowers/sdd/2026-07-30-ctr-r1-r2-kart-and-circuit/
# task-3-brief.md.

const MOTOR_SCRIPT_PATH := "res://src/racing/kart/kart_motor.gd"
const TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _kart: KartTuning


func before_all() -> void:
	_kart = load(TUNING_PATH)
	assert_not_null(_kart, "kart.tres must load — Task 1 registers it")


# ---------------------------------------------------------------------------
# Forward speed: accel asymptote, brake-then-reverse, coast drag.
# ---------------------------------------------------------------------------


func test_accel_asymptotes_to_top_speed_without_overshoot() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	var max_speed_seen := 0.0
	var elapsed_s := 0.0
	var step_s := 0.05
	while elapsed_s < 5.0:
		motor.call("tick", step_s, 0.0, false, false, false, 0)
		max_speed_seen = maxf(
			max_speed_seen,
			float(motor.call("forward_speed_mps"))
		)
		elapsed_s += step_s

	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		_kart.top_speed_mps,
		0.0001,
		"throttle is auto-on, so an idle kart must climb to top speed"
	)
	assert_lte(
		max_speed_seen,
		_kart.top_speed_mps + 0.0001,
		"move_toward must never let accel overshoot top speed"
	)


func test_brake_decelerates_then_reverses_to_authored_reverse_speed() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.set("_forward_speed_mps", _kart.top_speed_mps)
	var elapsed_s := 0.0
	var step_s := 0.05
	while elapsed_s < 5.0:
		motor.call("tick", step_s, 0.0, true, false, false, 0)
		elapsed_s += step_s

	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		-_kart.reverse_speed_mps,
		0.0001,
		"holding brake long enough must settle at -reverse_speed_mps"
	)


func test_coast_drag_bleeds_off_excess_speed_toward_top_speed() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	# Above top speed with no brake and no boost active -- the only way to
	# reach this state honestly is a boost that has since expired, but
	# forcing it directly isolates the coast_drag_mps2 path from boost decay
	# timing.
	motor.set(
		"_forward_speed_mps",
		_kart.top_speed_mps + _kart.boost_speed_bonus_mps
	)
	var elapsed_s := 0.0
	var step_s := 0.05
	while elapsed_s < 5.0:
		motor.call("tick", step_s, 0.0, false, false, false, 0)
		elapsed_s += step_s

	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		_kart.top_speed_mps,
		0.0001,
		"excess speed with no brake/boost must bleed off via coast_drag_mps2"
	)


func test_grounded_landing_clears_downward_vertical_speed() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.set("_vertical_speed_mps", -5.0)

	motor.call("tick", 0.1, 0.0, false, true, false, 0)

	assert_eq(
		float(motor.call("vertical_speed_mps")),
		0.0,
		"landing must clear residual downward speed, not carry it forward"
	)


# ---------------------------------------------------------------------------
# Yaw: steer falloff with speed, at rest / half / top speed.
# ---------------------------------------------------------------------------


func test_steer_rate_falls_off_with_speed_at_rest_half_and_top() -> void:
	for speed_fraction: float in [0.0, 0.5, 1.0]:
		var motor := _new_motor()
		if motor == null:
			return
		motor.set(
			"_forward_speed_mps",
			_kart.top_speed_mps * speed_fraction
		)
		var steer_value := 1.0
		var step_s := 0.02

		motor.call("tick", step_s, steer_value, false, false, false, 0)

		var resulting_speed := float(motor.call("forward_speed_mps"))
		var speed_ratio: float = clampf(
			absf(resulting_speed) / _kart.top_speed_mps,
			0.0,
			1.0
		)
		var expected_falloff := 1.0 - speed_ratio * _kart.steer_speed_falloff
		# Negated (world-space steering-polarity fix): positive steer (stick
		# right) must produce a NEGATIVE yaw delta under Godot's CCW-positive
		# rotation about +Y -- see kart_motor.gd's single sign-conversion
		# comment. This test only ever pinned the RELATIVE falloff-vs-speed
		# shape, not an absolute sign; test_kart_controller.gd's
		# test_steering_right_turns_toward_world_positive_x_not_negative pins
		# the absolute polarity end to end.
		var expected_yaw_rate := -(
			steer_value * _kart.steer_rate_degrees_per_s * expected_falloff
		)
		var measured_yaw_rate := (
			float(motor.call("yaw_degrees")) / step_s
		)

		assert_almost_eq(
			measured_yaw_rate,
			expected_yaw_rate,
			0.001,
			"steer falloff mismatch at speed_fraction=%s" % speed_fraction
		)


func test_zero_speed_uses_full_steer_authority() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	# A tick from a dead stop also integrates accel_mps2 * step_s of fresh
	# forward speed (throttle is auto-on), so falloff is computed from that
	# post-integration speed, not a frozen zero -- a small enough step keeps
	# that drift negligible against a correspondingly tight tolerance while
	# still pinning "at rest" to (within noise) full authority.
	var step_s := 0.0001

	motor.call("tick", step_s, 1.0, false, false, false, 0)

	# Negated (world-space steering-polarity fix, see kart_motor.gd):
	# steer(+1) yields a negative yaw rate now -- this test only pins that
	# falloff doesn't shrink the MAGNITUDE at rest, not the sign.
	assert_almost_eq(
		float(motor.call("yaw_degrees")) / step_s,
		-_kart.steer_rate_degrees_per_s,
		0.01,
		"at rest, falloff must not meaningfully reduce steer authority"
	)


# ---------------------------------------------------------------------------
# Slide yaw: bonus toward locked direction, full authority into it,
# counter-steer substitution against it.
# ---------------------------------------------------------------------------


func test_slide_adds_yaw_bonus_toward_locked_direction_with_no_steer() -> void:
	for slide_direction: int in [1, -1]:
		var motor := _new_motor()
		if motor == null:
			return
		var step_s := 0.02

		motor.call("tick", step_s, 0.0, false, false, true, slide_direction)

		# Negated (world-space steering-polarity fix, see kart_motor.gd): the
		# slide bonus must push yaw FURTHER INTO the locked direction under the
		# corrected convention, so slide_direction=+1 (a rightward-locked slide)
		# now adds a NEGATIVE yaw rate (turns right), not positive.
		assert_almost_eq(
			float(motor.call("yaw_degrees")) / step_s,
			-float(slide_direction) * _kart.slide_yaw_bonus_degrees_per_s,
			0.001,
			"slide_direction=%s" % slide_direction
		)


func test_steering_into_slide_direction_adds_full_authority_on_top_of_bonus() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	var step_s := 0.02
	var slide_direction := 1

	motor.call("tick", step_s, 1.0, false, false, true, slide_direction)

	var resulting_speed := float(motor.call("forward_speed_mps"))
	var speed_ratio: float = clampf(
		absf(resulting_speed) / _kart.top_speed_mps,
		0.0,
		1.0
	)
	var falloff_scale := 1.0 - speed_ratio * _kart.steer_speed_falloff
	# Negated (world-space steering-polarity fix, see kart_motor.gd): both
	# the bonus-toward-slide_direction term and the steer-into-direction
	# term go through the same single sign-conversion point, so the whole
	# sum flips together -- steering into a rightward-locked slide
	# (slide_direction=1, steer=1.0) now stacks a NEGATIVE (rightward) rate.
	var expected := -(
		float(slide_direction) * _kart.slide_yaw_bonus_degrees_per_s
		+ 1.0 * _kart.steer_rate_degrees_per_s * falloff_scale
	)

	assert_almost_eq(
		float(motor.call("yaw_degrees")) / step_s,
		expected,
		0.001,
		"steering into the locked slide direction must stack full authority"
	)


func test_counter_steering_uses_slide_counter_yaw_rate_instead() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	var step_s := 0.02
	var slide_direction := 1

	motor.call("tick", step_s, -1.0, false, false, true, slide_direction)

	var resulting_speed := float(motor.call("forward_speed_mps"))
	var speed_ratio: float = clampf(
		absf(resulting_speed) / _kart.top_speed_mps,
		0.0,
		1.0
	)
	var falloff_scale := 1.0 - speed_ratio * _kart.steer_speed_falloff
	# Negated (world-space steering-polarity fix, see kart_motor.gd): same
	# single sign-conversion point as above flips this sum too.
	var expected := -(
		float(slide_direction) * _kart.slide_yaw_bonus_degrees_per_s
		+ (-1.0) * _kart.slide_counter_yaw_degrees_per_s * falloff_scale
	)

	assert_almost_eq(
		float(motor.call("yaw_degrees")) / step_s,
		expected,
		0.001,
		(
			"counter-steering must substitute slide_counter_yaw_degrees_per_s "
			+ "for steer_rate_degrees_per_s, not merely reduce it"
		)
	)


# ---------------------------------------------------------------------------
# Boost: raises target speed, decays, stacks with a cap.
# ---------------------------------------------------------------------------


func test_boost_raises_target_speed_above_top_speed() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.set("_forward_speed_mps", _kart.top_speed_mps)
	motor.call("add_boost", _kart.boost_duration_s)

	var elapsed_s := 0.0
	var step_s := 0.01
	# Convergence time to the boosted target is boost_speed_bonus_mps /
	# accel_mps2, well inside boost_duration_s for the authored kart.tres.
	while elapsed_s < 0.4:
		motor.call("tick", step_s, 0.0, false, false, false, 0)
		elapsed_s += step_s

	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		_kart.top_speed_mps + _kart.boost_speed_bonus_mps,
		0.001,
		"an active boost must raise the forward-speed target"
	)
	assert_true(bool(motor.call("is_boosting")))


func test_boost_decays_by_delta_each_tick_and_expires() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.call("add_boost", _kart.boost_duration_s)

	motor.call("tick", _kart.boost_duration_s * 0.5, 0.0, false, false, false, 0)
	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		_kart.boost_duration_s * 0.5,
		0.0001,
		"boost time must decay by exactly delta_s each tick"
	)
	assert_true(bool(motor.call("is_boosting")))

	motor.call("tick", _kart.boost_duration_s * 0.5, 0.0, false, false, false, 0)
	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		0.0,
		0.0001
	)
	assert_false(
		bool(motor.call("is_boosting")),
		"boost time reaching zero must end the boosted target"
	)


func test_boost_target_still_applies_the_same_tick_it_reaches_zero() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.set("_forward_speed_mps", _kart.top_speed_mps)
	motor.call("add_boost", 0.01)

	# The contract: a boost that still has time remaining at the START of a
	# tick still applies its boosted target for that whole tick, even though
	# the tick's own delta_s exhausts it before the tick ends.
	motor.call("tick", 0.01, 0.0, false, false, false, 0)

	var expected_boosted_speed := (
		_kart.top_speed_mps
		+ minf(_kart.accel_mps2 * 0.01, _kart.boost_speed_bonus_mps)
	)
	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		expected_boosted_speed,
		0.0001,
		"a boost active at tick-start must still apply that same tick"
	)
	assert_false(bool(motor.call("is_boosting")))


func test_add_boost_stacks_and_caps_at_stack_max_times_duration() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	var stack_max := roundi(_kart.boost_stack_max)
	for _stack_index: int in range(stack_max + 2):
		motor.call("add_boost", _kart.boost_duration_s)

	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		_kart.boost_duration_s * _kart.boost_stack_max,
		0.0001,
		"accrued boost must cap at boost_stack_max stacks, not grow unbounded"
	)


func test_add_boost_ignores_non_positive_seconds() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.call("add_boost", 0.0)
	motor.call("add_boost", -1.0)

	assert_eq(float(motor.call("boost_time_remaining_s")), 0.0)
	assert_false(bool(motor.call("is_boosting")))


# ---------------------------------------------------------------------------
# Spin-out: one-time speed dump, zeroed steer authority, independent
# invulnerability window.
# ---------------------------------------------------------------------------


func test_spin_out_dumps_speed_once_by_keep_ratio() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.set("_forward_speed_mps", _kart.top_speed_mps)

	motor.call("apply_spin_out")

	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		_kart.top_speed_mps * _kart.spin_out_speed_keep_ratio,
		0.0001
	)
	assert_true(bool(motor.call("is_spinning_out")))
	assert_true(bool(motor.call("is_invulnerable")))


func test_spin_out_zeroes_steer_authority_for_its_full_duration() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.call("apply_spin_out")

	var elapsed_s := 0.0
	var step_s := 0.05
	while elapsed_s < _kart.spin_out_duration_s:
		motor.call("tick", step_s, 1.0, false, true, true, 1)
		elapsed_s += step_s

	assert_eq(
		float(motor.call("yaw_degrees")),
		0.0,
		"steer and slide yaw bonus must both be suppressed through the spin"
	)
	assert_false(bool(motor.call("is_spinning_out")))


func test_spin_out_and_invulnerability_run_as_independent_timers() -> void:
	# kart.tres authors these to different lengths (spin_out_duration_s
	# 1.2s vs invulnerable_after_hit_s 1.5s) specifically so an
	# implementation cannot get away with reusing one field for both.
	assert_ne(
		_kart.spin_out_duration_s,
		_kart.invulnerable_after_hit_s,
		"fixture assumption: kart.tres must author these durations distinctly"
	)
	var motor := _new_motor()
	if motor == null:
		return
	motor.call("apply_spin_out")

	motor.call("tick", _kart.spin_out_duration_s, 0.0, false, false, false, 0)
	assert_false(
		bool(motor.call("is_spinning_out")),
		"spin-out itself must have ended at its own authored duration"
	)
	assert_true(
		bool(motor.call("is_invulnerable")),
		"invulnerability must outlast the spin when authored longer"
	)

	var remaining_s := _kart.invulnerable_after_hit_s - _kart.spin_out_duration_s
	motor.call("tick", remaining_s, 0.0, false, false, false, 0)
	assert_false(
		bool(motor.call("is_invulnerable")),
		"invulnerability must end at its own authored duration"
	)


# ---------------------------------------------------------------------------
# Hop: vertical impulse reaches hop_height_m under gravity_mps2.
# ---------------------------------------------------------------------------


func test_hop_launch_speed_matches_kinematic_identity() -> void:
	var motor := _new_motor()
	if motor == null:
		return

	motor.call("hop")

	var expected_speed := sqrt(
		2.0 * _kart.gravity_mps2 * _kart.hop_height_m
	)
	assert_almost_eq(
		float(motor.call("vertical_speed_mps")),
		expected_speed,
		0.0001
	)


func test_hop_reaches_authored_height_under_gravity_within_tolerance() -> void:
	var motor := _new_motor()
	if motor == null:
		return
	motor.call("hop")

	var height_m := 0.0
	var peak_height_m := 0.0
	var step_s := 0.001
	# 1s comfortably covers the ~0.45s hang time this kart.tres produces;
	# peak_height_m only ever tracks the maximum reached, so continuing to
	# integrate past the apex (and even past re-crossing zero) is harmless.
	for _step_index: int in range(1000):
		var speed_before := float(motor.call("vertical_speed_mps"))
		height_m += speed_before * step_s
		peak_height_m = maxf(peak_height_m, height_m)
		motor.call("tick", step_s, 0.0, false, false, false, 0)

	assert_almost_eq(
		peak_height_m,
		_kart.hop_height_m,
		0.01,
		"the hop's integrated peak height must match hop_height_m"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_motor() -> RefCounted:
	var script: Script = load(MOTOR_SCRIPT_PATH)
	assert_not_null(script, "KartMotor implementation must exist")
	if script == null:
		return null
	var motor: RefCounted = script.new()
	motor.call("configure", _kart)
	return motor
