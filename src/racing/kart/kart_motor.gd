class_name KartMotor
extends RefCounted

## Pure-logic CTR-style kart velocity/yaw motor (Task 3). Mirrors
## drift_state_machine.gd's poll idiom (configure once, tick(...) once per
## physics frame, discrete event calls for hop/boost/spin-out, getters read
## state back) -- no Node deps, fully headless-testable. The controller owns
## grounded detection and move_and_slide; this motor only produces the
## numbers that feed CharacterBody3D.velocity.
##
## Forward speed is a single signed scalar (positive = forward, negative =
## reverse) that always chases a target under move_toward, so it can never
## overshoot: accel_mps2 while climbing toward a higher target under power,
## coast_drag_mps2 when current speed exceeds the target without braking
## (e.g. bleeding off a boost as it expires), brake_mps2 for the whole
## brake-then-reverse sweep down to -reverse_speed_mps (there is no separate
## reverse-accel tuning field, so one rate governs both halves of that
## sweep). Throttle is auto-on: with no brake and no boost the target is
## simply top_speed_mps, so an idle kart with zero steer still accelerates.
##
## Yaw is a single accumulating heading in degrees. Steer authority falls
## off linearly with current speed by steer_speed_falloff (full authority at
## rest, steer_rate_degrees_per_s * (1 - steer_speed_falloff) at or past top
## speed). While sliding, yaw additionally gains slide_yaw_bonus_degrees_per_s
## toward the locked slide_direction every tick regardless of steer; steer
## input INTO that same direction stacks the ordinary full-authority steer
## term on top (CTR lets you sharpen a drift), while steer AGAINST it swaps
## steer_rate_degrees_per_s for the (typically smaller) tuned
## slide_counter_yaw_degrees_per_s in that same falloff-scaled formula --
## a straight rate substitution, not a separate model. Velocity is the PS1-
## simple arcade model named in the brief: forward(yaw) * speed, no separate
## grip/slip vector -- the drift *look* is entirely the yaw bonus (plus
## camera framing, out of scope here).
##
## A spin-out (apply_spin_out()) zeroes ALL yaw authority -- both steer and
## the slide bonus -- for spin_out_duration_s; forward speed keeps
## integrating normally (a player can still throttle/brake out of one), it
## just took a one-time multiplicative dump by spin_out_speed_keep_ratio at
## the moment of impact. invulnerable_after_hit_s runs as its own
## independent timer (kart.tres authors it longer than the spin than the
## spin itself), tracked separately so a caller can't accidentally conflate
## "still spinning" with "still safe from another hit".
##
## Boost is a single accruable "time remaining" budget: add_boost(seconds)
## (the controller polls DriftStateMachine.consume_boost() every physics
## tick per the Task 3 contract and forwards whatever comes back, most
## ticks 0) stacks onto it, capped at boost_stack_max * boost_duration_s so
## a caller can never bank more than a full stack's worth queued at once.
## While any boost time remains the forward-speed target becomes
## top_speed_mps + boost_speed_bonus_mps; the remaining budget decays by
## delta_s every tick using the value already on hand at the start of that
## tick, so a boost that still has time left this frame still gets a
## boosted target this frame (fires immediately, same frame, per the
## contract) even though it may reach zero by the end of it.
##
## Hop (hop()) is a discrete vertical impulse sized to reach hop_height_m
## under gravity_mps2 (v0 = sqrt(2 * g * h), the same kinematic identity
## src/gameplay/player/jump_kinematics.gd uses for the platformer jump).
## Gravity integration itself happens here too, every tick, keyed off the
## grounded flag the controller reads from is_on_floor(): grounded clears
## any residual downward speed, airborne integrates -gravity_mps2 per
## second. This keeps hop fully headless-testable by ticking with
## grounded=false and summing vertical_speed_mps() * delta_s in the caller.

const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _tuning: KartTuning

var _forward_speed_mps: float
var _yaw_degrees: float
var _vertical_speed_mps: float

var _boost_time_remaining_s: float
var _spin_out_remaining_s: float
var _invulnerable_remaining_s: float


func configure(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning


func tick(
	delta_s: float,
	steer: float,
	brake: bool,
	grounded: bool,
	sliding: bool,
	slide_direction: int
) -> void:
	var target_speed := _tuning.top_speed_mps
	if _boost_time_remaining_s > 0.0:
		target_speed = _tuning.top_speed_mps + _tuning.boost_speed_bonus_mps
	if brake:
		target_speed = -_tuning.reverse_speed_mps

	var rate := _tuning.accel_mps2
	if brake:
		rate = _tuning.brake_mps2
	elif _forward_speed_mps > target_speed:
		rate = _tuning.coast_drag_mps2

	_forward_speed_mps = move_toward(
		_forward_speed_mps,
		target_speed,
		rate * delta_s
	)

	var speed_ratio := clampf(
		absf(_forward_speed_mps) / _tuning.top_speed_mps,
		0.0,
		1.0
	)
	var falloff_scale := 1.0 - speed_ratio * _tuning.steer_speed_falloff

	var yaw_rate := 0.0
	if _spin_out_remaining_s <= 0.0:
		if sliding:
			yaw_rate = (
				float(slide_direction) * _tuning.slide_yaw_bonus_degrees_per_s
			)
			if not is_zero_approx(steer):
				var steer_sign := signf(steer)
				if steer_sign == float(slide_direction):
					yaw_rate += (
						steer
						* _tuning.steer_rate_degrees_per_s
						* falloff_scale
					)
				else:
					yaw_rate += (
						steer
						* _tuning.slide_counter_yaw_degrees_per_s
						* falloff_scale
					)
		else:
			yaw_rate = steer * _tuning.steer_rate_degrees_per_s * falloff_scale
	# Single sign-conversion point (operator-reported control bug, R1 racing
	# APK: stick right turned the kart left, stick left turned it right).
	# Every term above (plain steer, the slide's bonus toward slide_direction,
	# steering-with vs counter-steering) is built as if positive steer /
	# positive slide_direction should mean "positive yaw", but Godot's
	# rotation about +Y is CCW-positive: Vector3.FORWARD.rotated(Vector3.UP,
	# +angle) sweeps the facing vector toward -X, which is the kart's own
	# LEFT (identity basis has +X as right -- see velocity() below, which
	# uses this exact same FORWARD.rotated(UP, yaw) convention). So positive
	# steer (stick right) must produce a NEGATIVE yaw delta, not positive --
	# negating the whole accumulated yaw_rate right here, in the one place it
	# turns into a yaw delta, fixes every contributing term at once without
	# touching the relative-sign relationships (steer-vs-slide_direction
	# selection, bonus direction, falloff) computed above.
	_yaw_degrees -= yaw_rate * delta_s

	if grounded:
		if _vertical_speed_mps < 0.0:
			_vertical_speed_mps = 0.0
	else:
		_vertical_speed_mps -= _tuning.gravity_mps2 * delta_s

	_boost_time_remaining_s = maxf(_boost_time_remaining_s - delta_s, 0.0)
	_spin_out_remaining_s = maxf(_spin_out_remaining_s - delta_s, 0.0)
	_invulnerable_remaining_s = maxf(_invulnerable_remaining_s - delta_s, 0.0)


## Decelerates the CURRENT forward speed toward a full stop at brake_mps2,
## and holds there -- unlike tick()'s ordinary brake branch, whose target is
## -reverse_speed_mps (so a continuously-applied brake eventually creeps
## into reverse). Fix round (H2): KartController calls this every tick
## instead of tick() once set_run_active(false) freezes the kart after a
## race finishes, so a kart still coasting at the finish line visually
## rolls to a stop -- not a hard snap to zero, and not an auto-throttle
## creep back up to speed once it gets there.
##
## Vertical/gravity integration and the boost/spin-out/invulnerability
## timers still run exactly like tick() (a kart that finishes mid-air must
## still settle onto the floor, and no timer should get stuck non-zero
## forever); yaw is untouched entirely -- the controller has already zeroed
## steer and cancelled any slide before calling this, so there is nothing
## here that should still be turning the kart.
func decelerate_to_stop(delta_s: float, grounded: bool) -> void:
	_forward_speed_mps = move_toward(
		_forward_speed_mps,
		0.0,
		_tuning.brake_mps2 * delta_s
	)
	if grounded:
		if _vertical_speed_mps < 0.0:
			_vertical_speed_mps = 0.0
	else:
		_vertical_speed_mps -= _tuning.gravity_mps2 * delta_s
	_boost_time_remaining_s = maxf(_boost_time_remaining_s - delta_s, 0.0)
	_spin_out_remaining_s = maxf(_spin_out_remaining_s - delta_s, 0.0)
	_invulnerable_remaining_s = maxf(_invulnerable_remaining_s - delta_s, 0.0)


func hop() -> void:
	_vertical_speed_mps = sqrt(
		ScalarMathType.DOUBLE * _tuning.gravity_mps2 * _tuning.hop_height_m
	)


func add_boost(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var max_boost_s := _tuning.boost_stack_max * _tuning.boost_duration_s
	_boost_time_remaining_s = minf(
		_boost_time_remaining_s + seconds,
		max_boost_s
	)


func apply_spin_out() -> void:
	_forward_speed_mps *= _tuning.spin_out_speed_keep_ratio
	_spin_out_remaining_s = _tuning.spin_out_duration_s
	_invulnerable_remaining_s = _tuning.invulnerable_after_hit_s


func forward_speed_mps() -> float:
	return _forward_speed_mps


func speed_mps() -> float:
	return absf(_forward_speed_mps)


func yaw_degrees() -> float:
	return _yaw_degrees


func vertical_speed_mps() -> float:
	return _vertical_speed_mps


func velocity() -> Vector3:
	return (
		Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(_yaw_degrees))
		* _forward_speed_mps
	)


func is_boosting() -> bool:
	return _boost_time_remaining_s > 0.0


func boost_time_remaining_s() -> float:
	return _boost_time_remaining_s


func is_spinning_out() -> bool:
	return _spin_out_remaining_s > 0.0


func is_invulnerable() -> bool:
	return _invulnerable_remaining_s > 0.0
