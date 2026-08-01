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
##
## Launch (launch(scale), Task 1, CTR R7 pads) is JumpPad's own vertical
## impulse -- the SAME v0 = sqrt(2 * g * hop_height_m) kinematic identity
## hop() already uses, scaled by jump_pad_velocity_scale (a caller-supplied
## multiplier, never a raw m/s literal here -- see race_tuning.gd's own doc
## on that field). A launch of scale=1.0 is therefore identical to a plain
## hop(); the peak height an integrated launch reaches is scale^2 *
## hop_height_m (peak height under constant gravity scales with v0
## squared), not scale * hop_height_m -- see test_kart_motor.gd's own
## launch-height test for the worked derivation. Unlike hop_pressed() on
## the controller, launch() carries no grounded/spin-out gate of its own --
## it is an ENVIRONMENTAL effect applied by RaceSession the same
## unconditional way apply_boost() already is (a pad fires regardless of
## whatever the kart's own drift/spin-out state happens to be), not a
## player input edge.

const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _tuning: KartTuning

var _forward_speed_mps: float
var _yaw_degrees: float
var _vertical_speed_mps: float

var _boost_time_remaining_s: float
var _spin_out_remaining_s: float
var _invulnerable_remaining_s: float
var _shield_remaining_s: float

var _speed_scale := 1.0


func configure(kart_tuning: KartTuning) -> void:
	_tuning = kart_tuning
	# Fix-wave LOW-7: a live tuning refresh mid-race (KartController.
	# refresh_tuning() -> this same configure() call, see its own doc) reuses
	# the SAME KartMotor instance -- without resetting this back to its
	# documented 1.0 default (see set_speed_scale()'s own doc), a kart caught
	# mid-rubber-band the instant a tuning edit lands would keep chasing a
	# stale scaled target until its next set_speed_scale() call, instead of
	# configure() actually returning every knob to its authored baseline the
	# way a caller would reasonably expect.
	_speed_scale = 1.0


## Seeds the accumulating yaw heading (see class doc) to an authored value.
## One-time correction for a kart placed onto a spawn transform after
## configure() already ran: _yaw_degrees otherwise always starts at 0.0 with
## no way to tell it a fresh transform's facing should be trusted instead,
## so the very next tick's rotation.y write (see kart_controller.gd) would
## silently snap the kart back to that default heading regardless of where
## it was actually placed. Does not touch forward_speed_mps() or any other
## state -- purely the heading.
func set_yaw_degrees(degrees: float) -> void:
	_yaw_degrees = degrees


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
	# Task 4 (AI rubber-band): scales the auto-throttle target AND the
	# boosted target above identically -- see set_speed_scale()'s own doc --
	# but this multiply happens BEFORE the brake branch below can overwrite
	# target_speed, so a braking/reversing kart's target is never touched by
	# it. A rubber-band ratio has no business making a hard stop/reverse
	# command faster or slower; it only ever governs forward racing pace.
	target_speed *= _speed_scale
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
	_shield_remaining_s = maxf(_shield_remaining_s - delta_s, 0.0)


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
	_shield_remaining_s = maxf(_shield_remaining_s - delta_s, 0.0)


func hop() -> void:
	_vertical_speed_mps = sqrt(
		ScalarMathType.DOUBLE * _tuning.gravity_mps2 * _tuning.hop_height_m
	)


## JumpPad's own entry point -- see this class doc's own Launch paragraph.
func launch(scale: float) -> void:
	_vertical_speed_mps = sqrt(
		ScalarMathType.DOUBLE * _tuning.gravity_mps2 * _tuning.hop_height_m
	) * scale


func add_boost(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var max_boost_s := _tuning.boost_stack_max * _tuning.boost_duration_s
	_boost_time_remaining_s = minf(
		_boost_time_remaining_s + seconds,
		max_boost_s
	)


## Multiplies the auto-throttle target speed (see tick()'s own comment on
## exactly where this applies, and where it deliberately does not) -- Task
## 4's AI rubber-band lever, and the ONLY way an AI kart's pace differs from
## a human's through this same physics path (see ai_kart_agent.gd's class
## doc). Default 1.0 (no scaling) for every kart that never calls this --
## i.e. every human-driven kart, unchanged from before this existed. No
## validation here: AiTuning's own rubber_band_boost_max_ratio/
## rubber_band_drag_max_ratio fields already bound whatever
## AiDriver.decide() can produce (see its class doc's RUBBER BAND section),
## the same "trust the caller" shape add_boost()'s seconds argument already
## has.
func set_speed_scale(ratio: float) -> void:
	_speed_scale = ratio


## Zeros forward AND vertical speed -- Task 4's AI stuck-kart respawn
## teleport (see kart_controller.gd's own reset_speed() proxy doc for the
## full rationale). Yaw and every timer (boost/spin-out/invulnerability) are
## untouched: yaw is seeded separately via set_yaw_degrees(), and a
## teleported-but-not-hit kart has no reason to lose an in-flight boost or
## have its hazard timers disturbed.
func reset_speed() -> void:
	_forward_speed_mps = 0.0
	_vertical_speed_mps = 0.0


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


## Timed "block one hit" flag (R4 Task 4, CTR item loop shield). A fresh
## set_shielded() call REPLACES whatever shield time remained rather than
## stacking -- picking up a second shield mid-window restarts the full
## duration; there is no "stack" concept for a shield the way boost stacks
## via add_boost(). Independent of every other timer here (boost/spin_out/
## invulnerable): a shielded kart can still be mid-boost or mid-spin-out at
## the same time, and RaceSession.register_hit() is the one caller that
## reads is_shielded() to decide whether an incoming hit even reaches
## apply_spin_out() at all (see race_session.gd's own register_hit doc).
func set_shielded(duration_s: float) -> void:
	_shield_remaining_s = duration_s


func is_shielded() -> bool:
	return _shield_remaining_s > 0.0


## Ends the shield immediately, regardless of how much time was left on it.
## RaceSession.register_hit() calls this the instant a hit is BLOCKED (see
## its own doc) -- CTR's shield is "blocks exactly one hit, then it's
## gone", not "blocks every hit until shield_duration_s runs out", so a
## block must consume the remaining window rather than letting it keep
## ticking down and expire on its own.
func consume_shield() -> void:
	_shield_remaining_s = 0.0
