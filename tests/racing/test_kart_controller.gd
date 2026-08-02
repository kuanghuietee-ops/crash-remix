extends GutTest

# Task 3 (CTR racing mode): a thin scene-level check that the real
# scenes/racing/kart.tscn graybox settles on a floor and drives forward
# under its own auto-on throttle with no steer input, the same way
# tests/integration/test_island_slice.gd proves the real player scene
# settles on authored floor (test_real_scene_spawn_stays_on_authored_floor_
# without_death) and tests/gameplay/test_depth_prediction.gd builds a
# throwaway StaticBody3D floor for a physics-driven fixture.

const KART_SCENE_PATH := "res://scenes/racing/kart.tscn"
const TUNING_PATH := "res://data/tuning/racing/kart.tres"
const ITEM_TUNING_PATH := "res://data/tuning/racing/items.tres"

## CTR R6 Task 5: a minimal signal-connect target proving KartController.
## hop_pressed_edge really fires per real hop_pressed() call -- see the
## signal's own doc on kart_controller.gd. tnt_stick.gd's own tests reuse
## this exact "duck-typed double exposing the identical signal name" shape
## one layer further out (against a fake victim, not a real KartController).
class HopPressedEdgeWatcher:
	extends RefCounted
	var call_count: int = 0

	func _on_hop_pressed_edge() -> void:
		call_count += 1

var _kart_tuning: KartTuning
var _item_tuning: ItemTuning


func before_all() -> void:
	_kart_tuning = load(TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load — Task 1 registers it")
	_item_tuning = load(ITEM_TUNING_PATH)
	assert_not_null(_item_tuning, "items.tres must load — Task 2 registers it")


func test_kart_scene_settles_grounded_and_drives_forward_with_zero_steer() -> void:
	assert_true(
		ResourceLoader.exists(KART_SCENE_PATH),
		"the kart graybox scene must exist"
	)
	if not ResourceLoader.exists(KART_SCENE_PATH):
		return
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("steer", 0.0)

	await wait_physics_frames(90)

	assert_true(
		kart.is_on_floor(),
		"the real kart must settle on a floor under gravity with no input"
	)
	assert_gt(
		float(kart.call("speed_mps")),
		0.0,
		"throttle is auto-on: zero steer must still drive the kart forward"
	)
	assert_lt(
		kart.global_position.z,
		0.0,
		"forward is -Z; the kart must have actually travelled that way"
	)


## Operator-reported control bug (device, R1 racing APK): steering was
## INVERTED -- stick left turned the kart right, stick right turned it
## left. The Task 7 reviewer flagged that every existing steer/yaw sign
## test (test_kart_motor.gd's steer-rate/slide-bonus formulas,
## test_counter_steering_while_sliding_reaches_the_counter_yaw_rate below,
## and test_kart_camera.gd's drift-yaw-flip test) is RELATIVE ONLY -- each
## checks that steer(+1) vs steer(-1), or slide_direction 1 vs -1, produce
## opposite-signed yaw/heading changes, never which absolute WORLD side
## either one turns toward. A perfectly self-consistent 180-degree-mirrored
## implementation passes every one of those. This test pins the missing
## absolute polarity: the kart spawns facing -Z (Godot's FORWARD, per
## test_kart_scene_settles_grounded_and_drives_forward_with_zero_steer's own
## "forward is -Z" comment above); steering RIGHT (stick x=+1, the exact
## value RacingInputAdapter.apply_move forwards straight through from a
## right-deflected stick -- see test_racing_input_adapter.gd's
## test_steer_maps_stick_x_directly_to_controller_steer, which proves the
## adapter does no negation of its own) must turn the kart's facing and
## velocity toward world +X, and steering LEFT (stick x=-1) toward world -X.
func test_steering_right_turns_toward_world_positive_x_not_negative() -> void:
	var right_kart := _spawn_kart_on_floor(Vector3.ZERO)
	var left_kart := _spawn_kart_on_floor(Vector3(100.0, 0.0, 0.0))
	if right_kart == null or left_kart == null:
		return

	await wait_physics_frames(10)
	assert_true(right_kart.is_on_floor(), "fixture setup must be grounded before steering")
	assert_true(left_kart.is_on_floor(), "fixture setup must be grounded before steering")

	right_kart.call("steer", 1.0)
	left_kart.call("steer", -1.0)

	await wait_physics_frames(30)

	var right_forward: Vector3 = -right_kart.global_transform.basis.z
	var left_forward: Vector3 = -left_kart.global_transform.basis.z

	assert_gt(
		right_forward.x,
		0.05,
		(
			"stick RIGHT (steer(+1)) must turn the kart's facing toward world "
			+ "+X -- got forward=%s (x=%s). A negative x here means steering "
			+ "right is turning the kart LEFT (the reported device bug)."
		) % [right_forward, right_forward.x]
	)
	assert_lt(
		left_forward.x,
		-0.05,
		(
			"stick LEFT (steer(-1)) must turn the kart's facing toward world "
			+ "-X -- got forward=%s (x=%s)."
		) % [left_forward, left_forward.x]
	)
	assert_gt(
		right_kart.velocity.x,
		0.0,
		"steering right must also give the kart's actual velocity a positive X component"
	)
	assert_lt(
		left_kart.velocity.x,
		0.0,
		"steering left must also give the kart's actual velocity a negative X component"
	)


func test_hop_press_while_sliding_adds_no_vertical_impulse() -> void:
	# Fix round 1: RacingInputAdapter now routes every hop press that
	# arrives while already sliding to boost_tap() instead of
	# hop_pressed() (see racing_input_adapter.gd), so this guard is never
	# exercised through that path in production -- this proves the
	# defense-in-depth guard on KartController itself: even a direct
	# hop_pressed() call while already sliding must not add a hop-height
	# vertical impulse.
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return

	# Let the kart settle onto the floor from its small spawn drop before
	# arming a slide -- DriftStateMachine only starts a slide on a tick
	# where grounded already reads true.
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	# Start a slide: steer past threshold, then a grounded hop press. This
	# press's own hop impulse is expected and out of scope here.
	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	# Let the initial hop's own vertical arc fully settle back onto the
	# floor before probing the guard, so residual hop-arc velocity from
	# starting the slide can't be mistaken for a second impulse.
	await wait_physics_frames(60)
	assert_true(
		kart.is_on_floor(),
		"fixture setup must be back on the floor before probing the guard"
	)
	assert_true(kart.call("is_sliding"), "the slide must still be active (steer is unchanged)")

	kart.call("hop_pressed")
	await wait_physics_frames(1)

	assert_almost_eq(
		kart.velocity.y,
		0.0,
		0.05,
		"a hop press while already grounded AND sliding must not add a vertical impulse"
	)


func test_counter_steering_while_sliding_reaches_the_counter_yaw_rate() -> void:
	# Fix round 2 (orchestrator ruling): counter-steering (full deflection
	# AGAINST the locked slide direction) must now SUSTAIN the slide
	# (drift_state_machine.gd's magnitude-only sustain check) and drive
	# KartMotor's counter-yaw branch (slide_counter_yaw_degrees_per_s) --
	# previously unreachable end to end, because round 1's sign-based
	# sustain ended the slide the instant you counter-steered, so this
	# branch was only ever exercised by a unit test feeding KartMotor
	# sliding/slide_direction by hand, never through real input.
	#
	# Proof, through the REAL DriftStateMachine + REAL KartMotor wired
	# together by KartController (not a motor-level test supplying
	# sliding/slide_direction manually): two karts start an identical
	# slide steering the SAME way, then diverge -- one keeps steering with
	# the locked direction (full authority, steer_rate_degrees_per_s), the
	# other counter-steers (the smaller slide_counter_yaw_degrees_per_s).
	# Steer never affects forward speed (only brake/boost do), so both
	# karts share an IDENTICAL speed -- and therefore falloff -- trajectory
	# throughout; the only possible source of a heading-change difference
	# is which yaw-rate branch the real pipeline actually reached.
	var same_direction_kart := _spawn_kart_on_floor(Vector3.ZERO)
	var counter_steer_kart := _spawn_kart_on_floor(Vector3(100.0, 0.0, 0.0))
	if same_direction_kart == null or counter_steer_kart == null:
		return

	await wait_physics_frames(10)
	assert_true(same_direction_kart.is_on_floor())
	assert_true(counter_steer_kart.is_on_floor())

	# Start both slides steering positive (locks slide_direction to 1 on both).
	same_direction_kart.call("steer", _kart_tuning.slide_min_steer)
	same_direction_kart.call("hop_pressed")
	counter_steer_kart.call("steer", _kart_tuning.slide_min_steer)
	counter_steer_kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(same_direction_kart.call("is_sliding"), "fixture setup must land inside a slide")
	assert_true(counter_steer_kart.call("is_sliding"), "fixture setup must land inside a slide")

	# Diverge: one keeps steering the SAME way, the other flips to full
	# opposite deflection (a counter-steer).
	same_direction_kart.call("steer", 1.0)
	counter_steer_kart.call("steer", -1.0)
	assert_true(
		counter_steer_kart.call("is_sliding"),
		"counter-steering must sustain the slide, not end it"
	)
	var same_direction_velocity_before: Vector3 = same_direction_kart.velocity
	var counter_steer_velocity_before: Vector3 = counter_steer_kart.velocity

	await wait_physics_frames(20)

	assert_true(
		counter_steer_kart.call("is_sliding"),
		"the counter-steered slide must still be active after ticking"
	)
	var same_direction_turn_degrees := _horizontal_heading_change_degrees(
		same_direction_velocity_before,
		same_direction_kart.velocity
	)
	var counter_steer_turn_degrees := _horizontal_heading_change_degrees(
		counter_steer_velocity_before,
		counter_steer_kart.velocity
	)

	assert_gt(
		counter_steer_turn_degrees,
		0.0,
		"counter-steering must still turn the kart (via the tuned counter "
		+ "rate) -- zero here would mean the branch never fired at all"
	)
	assert_gt(
		same_direction_turn_degrees,
		counter_steer_turn_degrees,
		(
			"steering WITH the locked slide direction (steer_rate_degrees_per_s = %s) "
			+ "must turn faster than counter-steering AGAINST it "
			+ "(slide_counter_yaw_degrees_per_s = %s) -- the counter-yaw branch must "
			+ "be reachable through the real FSM+motor pipeline, not just in isolation"
		) % [_kart_tuning.steer_rate_degrees_per_s, _kart_tuning.slide_counter_yaw_degrees_per_s]
	)


## Fix round 1 (KartCamera review): slide_direction() must proxy straight
## through to the real DriftStateMachine the controller already owns and
## wires every tick, the same way is_sliding()/speed_mps() do.
func test_slide_direction_proxies_the_locked_drift_direction() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	kart.call("steer", -_kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	assert_eq(
		int(kart.call("slide_direction")),
		-1,
		"steering negative past the threshold must lock slide_direction to -1"
	)


## Fix round 1 (KartCamera review): the Task 3 gap the review caught -- the
## controller computed yaw inside KartMotor (used for velocity()) but never
## wrote it back onto its own CharacterBody3D transform, so a chase camera
## reading the body's facing basis (rather than velocity, which a slide's
## counter-steer or a spin-out can point somewhere else -- see
## kart_camera.gd) would never see the kart actually turn. Proves both that
## the body visibly yaws over ticks AND that its basis stays numerically
## consistent with the motor's own yaw state, not just "some" rotation.
func test_body_rotation_tracks_motor_yaw_while_steering() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before steering")

	kart.call("steer", 1.0)
	await wait_physics_frames(30)

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	var motor_yaw_degrees: float = motor.call("yaw_degrees")
	assert_gt(
		absf(motor_yaw_degrees),
		1.0,
		"steering for 30 ticks must have visibly turned the motor's own yaw"
	)

	var expected_forward: Vector3 = Vector3.FORWARD.rotated(
		Vector3.UP,
		deg_to_rad(motor_yaw_degrees)
	)
	var actual_forward: Vector3 = -kart.global_transform.basis.z
	assert_almost_eq(
		actual_forward.angle_to(expected_forward),
		0.0,
		0.01,
		"the body's facing basis must match the motor's yaw state, not stay parked"
	)


# ---------------------------------------------------------------------------
# Task 4 (CTR R3: AI opponents) controller hooks: set_speed_scale()/
# boost_window_open()/reset_speed() are thin proxies onto the real
# KartMotor/DriftStateMachine this controller already owns and wires every
# tick -- the same "proxy straight through" shape is_sliding()/speed_mps()/
# slide_direction() already use.
# ---------------------------------------------------------------------------


func test_set_speed_scale_reaches_the_real_motor_and_changes_its_target() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("steer", 0.0)
	var ratio := 1.0 + _kart_tuning.boost_speed_bonus_mps / _kart_tuning.top_speed_mps
	kart.call("set_speed_scale", ratio)

	await wait_physics_frames(120)

	assert_gt(
		float(kart.call("speed_mps")),
		_kart_tuning.top_speed_mps,
		"set_speed_scale() must reach the real motor and raise its target above the plain top_speed_mps"
	)


func test_boost_window_open_proxies_the_real_drift_fsm() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	assert_false(
		bool(kart.call("boost_window_open")),
		"a kart that never started a slide must never report an open boost window"
	)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")
	assert_false(
		bool(kart.call("boost_window_open")),
		"the window must not already be open the instant a slide starts"
	)

	await wait_physics_frames(int(ceil(_kart_tuning.boost_window_open_s * float(Engine.physics_ticks_per_second))) + 2)

	assert_true(
		bool(kart.call("boost_window_open")),
		"the real DriftStateMachine's window must report open once boost_window_open_s has elapsed"
	)


# ---------------------------------------------------------------------------
# Task 1 (CTR R6, circuit polish): boost_stage()/is_boosting() are thin
# proxies onto the real DriftStateMachine/KartMotor this controller already
# owns and ticks every frame -- mirrors slide_direction()/boost_window_
# open()'s own identical proxy shape one section up. kart_fx.gd (the new
# FX driver) is their first real caller.
# ---------------------------------------------------------------------------


func test_boost_stage_proxies_the_real_drift_fsm_and_advances_on_a_real_tap() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	assert_eq(
		int(kart.call("boost_stage")),
		0,
		"a kart that never started a slide must report boost stage 0"
	)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")
	assert_eq(int(kart.call("boost_stage")), 0, "a fresh slide must start at stage 0")

	await wait_physics_frames(
		int(ceil(_kart_tuning.boost_window_open_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_eq(
		String(kart.call("boost_tap")),
		"fired",
		"fixture setup: the tap must land inside the window and actually fire"
	)

	assert_eq(
		int(kart.call("boost_stage")),
		1,
		"boost_stage() must reach the real DriftStateMachine and reflect a fired tap"
	)


func test_is_boosting_proxies_the_real_motor_and_reaches_zero_when_boost_decays() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	assert_false(
		bool(kart.call("is_boosting")),
		"a fresh kart must not report boosting"
	)

	kart.call("apply_boost", 0.2)
	assert_true(
		bool(kart.call("is_boosting")),
		"is_boosting() must reach the real motor's accrued boost time immediately"
	)

	await wait_physics_frames(
		int(ceil(0.2 * float(Engine.physics_ticks_per_second))) + 3
	)
	assert_false(
		bool(kart.call("is_boosting")),
		"is_boosting() must report false once the accrued boost time has fully decayed"
	)


## Task 1 (CTR R7 pads): JumpPad's own entry point -- a thin, unconditional
## pass-through onto the real motor's launch(), mirrors apply_boost()'s own
## reach-the-motor proof (test_is_boosting_proxies_the_real_motor_and_
## reaches_zero_when_boost_decays immediately above) but for vertical_speed_
## mps instead of boost time. The scaled kinematic math itself is test_kart_
## motor.gd's own job (test_launch_speed_matches_the_scaled_kinematic_
## identity) -- this proves only that the controller actually forwards.
func test_launch_reaches_the_real_motor_vertical_speed() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_almost_eq(
		float(motor.call("vertical_speed_mps")),
		0.0,
		0.01,
		"fixture sanity: a settled kart must have no residual vertical speed"
	)

	kart.call("launch", 2.2)

	assert_gt(
		float(motor.call("vertical_speed_mps")),
		0.0,
		"launch() must reach the real motor and give it upward vertical speed immediately"
	)


func test_reset_speed_zeroes_forward_and_vertical_speed_and_body_velocity() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("steer", 0.0)
	await wait_physics_frames(30)
	assert_gt(
		float(kart.call("speed_mps")),
		0.0,
		"fixture setup: the kart must really be moving before reset_speed() is called"
	)

	kart.call("reset_speed")

	assert_almost_eq(
		float(kart.call("speed_mps")),
		0.0,
		0.0001,
		"reset_speed() must zero the real motor's forward speed"
	)
	assert_almost_eq(
		kart.velocity.length(),
		0.0,
		0.0001,
		"reset_speed() must also zero the body's own CharacterBody3D.velocity"
	)


# ---------------------------------------------------------------------------
# R4 Task 1 (striking the design spec's Recorded debts #1, R4-BINDING): a
# spin-out landing mid-slide must force-end the drift FSM, not just zero the
# motor's yaw authority; boost_tap()/hop_pressed() must be gated on the
# motor's spin-out state for its whole spin_out_duration_s; recovery must be
# automatic once the stun's own timer expires; invulnerable_after_hit_s must
# keep running as its own independent window throughout.
# ---------------------------------------------------------------------------


func test_apply_spin_out_mid_slide_ends_the_slide_and_zeroes_accrued_boost() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	await wait_physics_frames(
		int(ceil(_kart_tuning.boost_window_open_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_eq(
		String(kart.call("boost_tap")),
		"fired",
		"fixture setup: the tap must land inside the window and actually accrue boost"
	)

	kart.call("apply_spin_out")

	assert_false(
		kart.call("is_sliding"),
		"a spin-out landing mid-slide must end the slide immediately -- the "
		+ "camera's drift bias (which only applies while is_sliding() is "
		+ "true, see kart_camera.gd) clears the same tick as a result"
	)

	var drift: RefCounted = kart.get("_drift")
	assert_not_null(drift, "the controller must still own its private drift FSM")
	if drift == null:
		return
	assert_eq(
		int(drift.call("boost_stage")),
		0,
		"the spin-out must forfeit the accrued boost stage, not just end the slide"
	)
	assert_eq(
		float(drift.call("consume_boost")),
		0.0,
		"any boost accrued before the spin-out must have been zeroed, not merely left orphaned for the next poll"
	)


## Proves the gate lives on the CONTROLLER (checking KartMotor.is_spinning_
## out() before ever calling DriftStateMachine.boost_tap()), not merely
## inherited from the FSM's own pre-existing "not sliding" early-return --
## the motor is spun out directly here while the drift FSM is left mid-slide
## and inside its own open boost window, which would otherwise fire.
func test_boost_tap_is_gated_at_the_controller_even_while_the_drift_fsm_would_otherwise_fire() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before starting a slide")

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	await wait_physics_frames(
		int(ceil(_kart_tuning.boost_window_open_s * float(Engine.physics_ticks_per_second))) + 2
	)

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	motor.call("apply_spin_out")
	assert_true(bool(motor.call("is_spinning_out")), "fixture setup: the motor must be spinning out")
	assert_true(
		kart.call("is_sliding"),
		"fixture setup: only the motor was hit directly here, so the drift FSM must still report sliding"
	)

	assert_eq(
		String(kart.call("boost_tap")),
		"ignored",
		"the controller must gate boost_tap() on the motor's spin-out state "
		+ "even though the drift FSM's own window would otherwise fire"
	)


func test_hop_pressed_during_spin_out_no_ops_and_does_not_arm_a_slide() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before probing the guard")

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	motor.call("apply_spin_out")
	assert_true(bool(motor.call("is_spinning_out")), "fixture setup: the motor must be spinning out")

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)

	assert_false(
		kart.call("is_sliding"),
		"a hop press during a spin-out stun must not arm a new slide"
	)
	assert_almost_eq(
		kart.velocity.y,
		0.0,
		0.05,
		"a hop press during a spin-out stun must not add a vertical impulse either"
	)


## CTR R6 Task 5: hop_pressed_edge is the "clean signal" tnt_stick.gd's own
## shake-off mechanism connects to (see kart_controller.gd's own doc on the
## signal declaration) -- proven directly against the real production
## script here; tnt_stick.gd's own tests then prove the CONSUMER side
## (connecting to it, decrementing a shake counter) against a duck-typed
## double exposing the identical signal name.
func test_hop_pressed_emits_the_hop_pressed_edge_signal() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var watcher := HopPressedEdgeWatcher.new()
	kart.connect("hop_pressed_edge", Callable(watcher, "_on_hop_pressed_edge"))

	kart.call("hop_pressed")
	kart.call("hop_pressed")

	assert_eq(watcher.call_count, 2, "every real hop_pressed() call must fire its own edge")


## See the class doc's own signal doc: the edge fires UNCONDITIONALLY, even
## when the spin-out guard immediately below it turns the rest of the call
## into a no-op -- a real physical button press happened either way, and
## tnt_stick.gd's own shake-off must not silently discard mashes that happen
## to land during a stun.
func test_hop_pressed_edge_still_fires_during_a_spin_out_stun() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	motor.call("apply_spin_out")
	assert_true(bool(motor.call("is_spinning_out")), "fixture setup: the motor must be spinning out")

	var watcher := HopPressedEdgeWatcher.new()
	kart.connect("hop_pressed_edge", Callable(watcher, "_on_hop_pressed_edge"))
	kart.call("hop_pressed")

	assert_eq(watcher.call_count, 1, "the edge must still fire even though the stun guard no-ops the rest of the call")


## A hop can latch _hop_held=true BEFORE a slide actually starts (steer
## hasn't crossed slide_min_steer yet) -- DriftStateMachine.cancel_slide()
## is a documented no-op when nothing is sliding, so calling it alone after
## a hit landing in this exact window would leave that latch standing; the
## very next tick steer crosses the threshold would then arm a slide DURING
## the stun with no fresh hop_pressed() edge at all. apply_spin_out() must
## also force-clear the latch unconditionally via hop_released(), the same
## pairing set_run_active(false) already uses for the identical reason.
func test_apply_spin_out_before_a_slide_starts_still_clears_a_pending_hop_latch() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before probing the guard")

	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_false(
		kart.call("is_sliding"),
		"fixture setup: steer below threshold must not have started a slide yet"
	)

	kart.call("apply_spin_out")

	kart.call("steer", _kart_tuning.slide_min_steer)
	await wait_physics_frames(1)

	assert_false(
		kart.call("is_sliding"),
		"a hop latch armed before the hit must not survive apply_spin_out() "
		+ "to arm a slide off stale state during the stun"
	)


func test_control_is_restored_after_spin_out_duration_elapses() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before probing the guard")

	kart.call("apply_spin_out")
	assert_true(kart.call("is_spinning_out"), "fixture setup: the controller proxy must report spinning out")

	await wait_physics_frames(
		int(ceil(_kart_tuning.spin_out_duration_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_false(
		kart.call("is_spinning_out"),
		"the stun must have ended by its own authored spin_out_duration_s"
	)

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	var yaw_before: float = float(motor.call("yaw_degrees"))
	kart.call("steer", 1.0)
	await wait_physics_frames(20)
	var yaw_after: float = float(motor.call("yaw_degrees"))
	assert_gt(
		absf(yaw_after - yaw_before),
		1.0,
		"steering after the stun ends must visibly turn the kart again -- "
		+ "proves yaw authority is really back, not just that the timer expired"
	)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(
		kart.call("is_sliding"),
		"a hop press after the stun ends must be able to arm a slide again"
	)


func test_invulnerability_outlasts_spin_out_through_the_controller() -> void:
	# Mirrors test_kart_motor.gd's test_spin_out_and_invulnerability_run_as_
	# independent_timers, but pinned through the real controller (is_
	# spinning_out()/is_invulnerable() proxies) rather than the motor
	# directly, per the R4 Task 1 brief's own "invulnerable window still
	# independent" requirement.
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before probing the guard")

	kart.call("apply_spin_out")

	await wait_physics_frames(
		int(ceil(_kart_tuning.spin_out_duration_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_false(
		kart.call("is_spinning_out"),
		"the spin itself must have ended at its own authored duration"
	)
	assert_true(
		kart.call("is_invulnerable"),
		(
			"invulnerability (authored longer, kart.tres: %s vs %s) must "
			+ "outlast the spin"
		) % [_kart_tuning.invulnerable_after_hit_s, _kart_tuning.spin_out_duration_s]
	)


# ---------------------------------------------------------------------------
# R4 Task 4 (CTR item loop): set_shielded()/is_shielded()/consume_shield()
# proxy straight onto the real KartMotor's own timed shield flag -- mirrors
# is_invulnerable()'s own proxy shape one section up.
# ---------------------------------------------------------------------------


func test_a_fresh_kart_is_not_shielded() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	assert_false(kart.call("is_shielded"))


func test_set_shielded_reaches_the_real_motor() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("set_shielded", _item_tuning.shield_duration_s)
	assert_true(kart.call("is_shielded"))


func test_consume_shield_reaches_the_real_motor() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("set_shielded", _item_tuning.shield_duration_s)
	assert_true(kart.call("is_shielded"), "fixture setup: the shield must be up before consuming it")

	kart.call("consume_shield")

	assert_false(kart.call("is_shielded"), "consume_shield() must reach the real motor and end the shield")


func test_kart_scene_wires_a_blob_shadow_node() -> void:
	assert_true(ResourceLoader.exists(KART_SCENE_PATH))
	if not ResourceLoader.exists(KART_SCENE_PATH):
		return
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var kart := packed.instantiate() as Node3D
	add_child_autofree(kart)

	var blob := kart.get_node_or_null("BlobShadow")

	assert_not_null(blob, "kart.tscn must instance scenes/props/blob_shadow.tscn")
	assert_true(
		blob != null and blob.has_method("configure"),
		"the BlobShadow instance must be the real reusable prop, not a stand-in"
	)


# ---------------------------------------------------------------------------
# Task 3 (CTR R6, circuit polish): kart mesh swap (graybox box -> the real
# generated glb) + the character-mount/body-tint API. See kart_controller.gd's
# own class doc section for the design (NODE LOOKUP NOT @onready, no physics
# from the character, no explicit yaw sync needed).
# ---------------------------------------------------------------------------

const CRASH_MODEL_PATH := "res://assets/models/characters/SK_crash.glb"
const LAB_ASSISTANT_MODEL_PATH := "res://assets/models/enemies/SK_lab_assistant.glb"
const SEAT_ANIMATION_CLIP := &"A_crash_hog_ride"
const SEAT_POSE_TUNING_PATH := "res://data/tuning/racing/seat_pose.tres"


func test_kart_scene_has_the_real_mesh_and_no_character_by_default() -> void:
	assert_true(ResourceLoader.exists(KART_SCENE_PATH))
	if not ResourceLoader.exists(KART_SCENE_PATH):
		return
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var kart := packed.instantiate() as Node3D
	add_child_autofree(kart)

	var visual := kart.get_node_or_null("Visual")
	assert_not_null(visual, "kart.tscn must still carry a Visual node")
	if visual == null:
		return
	var mesh_instances: Array = visual.find_children("*", "MeshInstance3D", true, false)
	if visual is MeshInstance3D:
		mesh_instances.append(visual)
	assert_gt(
		mesh_instances.size(),
		0,
		"the graybox box mesh must have been replaced by the generated kart glb"
	)
	if not mesh_instances.is_empty():
		var mesh := (mesh_instances[0] as MeshInstance3D).mesh
		assert_not_null(mesh, "the instanced kart model must carry a real mesh")
		if mesh != null:
			assert_gt(
				mesh.get_surface_count(),
				0,
				"the budget-linted kart mesh must have at least one surface"
			)

	assert_not_null(
		kart.get_node_or_null("SeatMount"),
		"kart.tscn must author a SeatMount marker for mount_character() to seat onto"
	)
	assert_null(
		kart.call("mounted_character"),
		"kart.tscn ships with NO character by default -- RaceSession decides who rides"
	)


func test_mount_character_seats_the_given_scene_with_no_physics_body() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", crash_scene)

	assert_not_null(mounted, "mount_character() must return the instantiated character")
	assert_eq(
		kart.call("mounted_character"),
		mounted,
		"mounted_character() must expose the same node just mounted"
	)
	if mounted == null:
		return
	assert_eq(
		mounted.get_parent(),
		kart.get_node("SeatMount"),
		"the character must be parented under the kart's own SeatMount, not Visual or the kart root"
	)
	assert_false(
		mounted is PhysicsBody3D,
		"the mounted character must carry no physics body of its own -- visual only"
	)


func test_mount_character_plays_the_seated_ride_clip_when_the_model_has_one() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(mounted)
	if mounted == null:
		return

	var animation_players := mounted.find_children("*", "AnimationPlayer", true, false)
	assert_eq(animation_players.size(), 1, "the Crash model must carry exactly one AnimationPlayer")
	if animation_players.size() != 1:
		return
	var animation_player := animation_players[0] as AnimationPlayer
	assert_eq(
		animation_player.current_animation,
		String(SEAT_ANIMATION_CLIP),
		"mounting Crash on a kart must play the same seated-riding clip Hog Wild already uses"
	)


## The lab assistant model has no seated-riding clip of its own (its only
## animation is a walk cycle) -- mount_character() must still succeed and
## must not error or fight a nonexistent clip. R6 device-test fix ("the
## opponent character should sit down just like Crash, not standing on the
## car"): it no longer leaves the model at its imported standing rest pose
## -- see _apply_static_seat_pose()'s own doc and the dedicated tests below
## for the actual seated-pose assertions this comment used to wave off.
func test_mount_character_on_a_model_without_a_seated_clip_does_not_error() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var lab_assistant_scene := load(LAB_ASSISTANT_MODEL_PATH) as PackedScene
	assert_not_null(lab_assistant_scene)
	if lab_assistant_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", lab_assistant_scene)

	assert_not_null(mounted, "mounting a model with no seated clip must still succeed")
	if mounted == null:
		return
	var animation_players := mounted.find_children("*", "AnimationPlayer", true, false)
	if animation_players.size() == 1:
		var animation_player := animation_players[0] as AnimationPlayer
		assert_false(
			animation_player.has_animation(SEAT_ANIMATION_CLIP),
			"fixture sanity: the lab assistant must genuinely lack the seated clip"
		)


## R6 device-test fix (operator: "the opponent character should sit down
## just like Crash, not standing on the car"). The lab assistant glb has no
## seated clip (see the test immediately above), so mount_character() now
## falls back to a static Skeleton3D bone-pose override -- see kart_
## controller.gd's own _apply_static_seat_pose() and data/tuning/racing/
## seat_pose.tres's own SeatPoseTuning doc for where the pose values come
## from. This pins the hip and knee bones actually landing away from their
## imported rest rotation -- the minimum bar for "seated, not standing".
func test_mount_character_on_a_model_without_a_seated_clip_bends_hips_and_knees() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var lab_assistant_scene := load(LAB_ASSISTANT_MODEL_PATH) as PackedScene
	assert_not_null(lab_assistant_scene)
	if lab_assistant_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", lab_assistant_scene)
	assert_not_null(mounted)
	if mounted == null:
		return

	var skeleton := _find_skeleton(mounted)
	assert_not_null(skeleton, "fixture setup: the lab assistant must carry a Skeleton3D")
	if skeleton == null:
		return

	for bone_name in [
		"DEF-thigh.L", "DEF-thigh.R", "DEF-shin.L", "DEF-shin.R"
	]:
		var bone_index := skeleton.find_bone(bone_name)
		assert_ne(bone_index, -1, "fixture setup: %s must exist on the rig" % bone_name)
		if bone_index == -1:
			continue
		var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
		var pose_rotation := skeleton.get_bone_pose_rotation(bone_index)
		assert_false(
			pose_rotation.is_equal_approx(rest_rotation),
			(
				"%s must be posed away from its imported rest rotation -- "
				+ "got rest=%s pose=%s"
			) % [bone_name, rest_rotation, pose_rotation]
		)


## Same fixture as above, but pins the exact pose values against the real
## data/tuning/racing/seat_pose.tres -- not just "different from rest", the
## real authored seated-pose data actually reached the skeleton.
func test_mount_character_on_a_model_without_a_seated_clip_applies_the_tuned_pose_values() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var lab_assistant_scene := load(LAB_ASSISTANT_MODEL_PATH) as PackedScene
	assert_not_null(lab_assistant_scene)
	if lab_assistant_scene == null:
		return
	var seat_pose: Resource = load(SEAT_POSE_TUNING_PATH)
	assert_not_null(seat_pose, "fixture setup: seat_pose.tres must load")
	if seat_pose == null:
		return

	var mounted: Node3D = kart.call("mount_character", lab_assistant_scene)
	assert_not_null(mounted)
	if mounted == null:
		return
	var skeleton := _find_skeleton(mounted)
	assert_not_null(skeleton)
	if skeleton == null:
		return

	var expected_by_bone := {
		"DEF-thigh.L": seat_pose.thigh_l_pose,
		"DEF-thigh.R": seat_pose.thigh_r_pose,
		"DEF-shin.L": seat_pose.shin_l_pose,
		"DEF-shin.R": seat_pose.shin_r_pose,
		"DEF-upper_arm.L": seat_pose.upper_arm_l_pose,
		"DEF-upper_arm.R": seat_pose.upper_arm_r_pose,
		"DEF-forearm.L": seat_pose.forearm_l_pose,
		"DEF-forearm.R": seat_pose.forearm_r_pose,
	}
	for bone_name: String in expected_by_bone:
		var bone_index := skeleton.find_bone(bone_name)
		assert_ne(bone_index, -1, "fixture setup: %s must exist on the rig" % bone_name)
		if bone_index == -1:
			continue
		var expected: Quaternion = expected_by_bone[bone_name]
		var actual := skeleton.get_bone_pose_rotation(bone_index)
		assert_true(
			actual.is_equal_approx(expected),
			(
				"%s pose must match seat_pose.tres -- expected=%s got=%s"
			) % [bone_name, expected, actual]
		)


## R6 device-test fix: "lower the model so the pelvis sits on the
## SeatMount" -- see _apply_static_seat_pose()'s own doc. Bounded, not
## pinned to one exact value: the check that matters here is "near the
## seat", not a specific millimeter (that's what the tuned-pose-values test
## above is for on the rotations; pelvis_drop_m is comparatively coarse
## visual data by its own doc).
func test_mount_character_on_a_model_without_a_seated_clip_lowers_the_pelvis_to_seat_height() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var lab_assistant_scene := load(LAB_ASSISTANT_MODEL_PATH) as PackedScene
	assert_not_null(lab_assistant_scene)
	if lab_assistant_scene == null:
		return
	var seat_mount := kart.get_node("SeatMount") as Node3D
	assert_not_null(seat_mount)
	if seat_mount == null:
		return

	var mounted: Node3D = kart.call("mount_character", lab_assistant_scene)
	assert_not_null(mounted)
	if mounted == null:
		return
	var skeleton := _find_skeleton(mounted)
	assert_not_null(skeleton)
	if skeleton == null:
		return

	var pelvis_index := skeleton.find_bone("DEF-spine")
	assert_ne(pelvis_index, -1, "fixture setup: DEF-spine (pelvis proxy) must exist on the rig")
	if pelvis_index == -1:
		return
	var pelvis_global_y := (
		skeleton.global_transform * skeleton.get_bone_global_pose(pelvis_index)
	).origin.y
	var seat_y := seat_mount.global_position.y
	var height_above_seat := pelvis_global_y - seat_y
	assert_true(
		height_above_seat > -0.1 and height_above_seat < 0.75,
		(
			"the mounted assistant's pelvis must land close to seat height, "
			+ "not floating at full standing hip height nor sunk through the "
			+ "kart -- seat_y=%s pelvis_y=%s (height_above_seat=%s)"
		) % [seat_y, pelvis_global_y, height_above_seat]
	)


## Binding contract: the static seat-pose fallback is for models with NO
## seated clip only -- Crash keeps his existing A_crash_hog_ride animation
## path completely untouched (own doc: "Crash keeps his existing seated
## animation, untouched"). mount_character() never lowers Crash's own
## position.y or overrides his skeleton's bone poses; the animation player
## owns his pose entirely, the same as before this fix wave.
func test_mount_character_on_crash_never_applies_the_static_seat_pose_fallback() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(mounted)
	if mounted == null:
		return

	assert_eq(
		mounted.position.y,
		0.0,
		"Crash's own path must never apply the lab-assistant-only pelvis_drop_m offset"
	)


func test_mount_character_replaces_a_previously_mounted_character() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	var lab_assistant_scene := load(LAB_ASSISTANT_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	assert_not_null(lab_assistant_scene)
	if crash_scene == null or lab_assistant_scene == null:
		return

	var first: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(first)
	var second: Node3D = kart.call("mount_character", lab_assistant_scene)
	# unmount_character() (called internally by mount_character() before
	# seating the new one) uses queue_free(), Godot's own recommended
	# deferred-free -- the freed node stays is_instance_valid() == true until
	# the next frame's deferred-call queue actually runs it.
	await wait_physics_frames(1)

	assert_not_null(second)
	assert_ne(second, first, "a second mount must be a fresh instance, not the same node")
	assert_false(
		is_instance_valid(first),
		"the previously mounted character must be freed, not left orphaned in the tree"
	)
	assert_eq(kart.call("mounted_character"), second)


func test_unmount_character_clears_the_seat_and_is_safe_to_call_when_empty() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("unmount_character")
	assert_null(kart.call("mounted_character"), "unmounting an empty seat must stay a harmless no-op")

	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return
	var mounted: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(mounted)

	kart.call("unmount_character")
	# queue_free() is deferred -- see the identical wait in test_mount_
	# character_replaces_a_previously_mounted_character's own doc.
	await wait_physics_frames(1)

	assert_null(kart.call("mounted_character"))
	assert_false(is_instance_valid(mounted), "unmount_character() must actually free the node")


## R8 Task 5 (characters/select/classes): DriverEntry.seat_scale/seat_
## offset (driver_entry.gd's own doc) exist to fit an oversized driver like
## Papu into the kart's own seat -- apply_seat_fit() is the method that
## actually applies them, called by RaceSession right after mount_
## character() (the same "mount, then adjust" two-call shape apply_body_
## tint() already establishes for the tint).
func test_apply_seat_fit_scales_and_offsets_the_mounted_character() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return
	var mounted: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(mounted)
	if mounted == null:
		return
	var position_before_fit := mounted.position

	kart.call("apply_seat_fit", 0.62, Vector3(0.0, -0.3, 0.05))

	assert_eq(
		mounted.scale,
		Vector3.ONE * 0.62,
		"apply_seat_fit() must uniformly scale the mounted character's own Node3D"
	)
	assert_eq(
		mounted.position,
		position_before_fit + Vector3(0.0, -0.3, 0.05),
		"apply_seat_fit() must ADD its offset to whatever position mount_character() already set"
	)


func test_apply_seat_fit_is_a_safe_no_op_when_nothing_is_mounted() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return

	# Must not error with no character mounted -- mirrors unmount_
	# character()'s own "harmless no-op when nothing is mounted" contract.
	kart.call("apply_seat_fit", 0.62, Vector3(0.0, -0.3, 0.05))

	assert_null(kart.call("mounted_character"))


## R8 Task 5 (characters/select/classes): the fit the brief itself demands
## proven -- "kart visual not clipped, head above cowl" -- against REAL
## numbers from the REAL mounted scene using papu.tres's own authored seat_
## scale/seat_offset, not assumed from the authoring math.
##
## Deliberately does NOT read MeshInstance3D.get_aabb() on the mounted
## Papu -- proven unreliable during authoring: querying it at two different
## points within the SAME playing animation returned byte-identical AABBs,
## meaning Godot is not folding the live skeletal pose into that value for
## this skinned mesh. Bone world positions (skeleton.get_bone_global_pose(),
## the same technique test_mount_character_on_a_model_without_a_seated_
## clip_lowers_the_pelvis_to_seat_height already uses for the lab
## assistant's own fallback pose) DO reflect the live pose, so this test
## reads those instead: headdress (his tallest silhouette point that is not
## the fixed-in-place feather ornament) against the kart's own real Visual-
## mesh AABB for "above the cowl", and hand span against the kart's own
## real half-width for "not clipped".
func test_papu_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var papu_entry: DriverEntry = load("res://data/racing/drivers/papu.tres")
	assert_not_null(papu_entry, "fixture setup: papu.tres must load")
	if papu_entry == null:
		return
	var papu_scene := load(papu_entry.character_scene_path) as PackedScene
	assert_not_null(papu_scene, "fixture setup: papu.tres's own character_scene_path must resolve")
	if papu_scene == null:
		return

	var mounted: Node3D = kart.call("mount_character", papu_scene)
	assert_not_null(mounted)
	if mounted == null:
		return
	kart.call("apply_seat_fit", papu_entry.seat_scale, papu_entry.seat_offset)

	# AnimationPlayer.play() (called inside mount_character() above) samples
	# its first frame on the NEXT process tick, not synchronously -- see
	# this test's own class doc. Two physics frames is the same margin
	# test_mount_character_replaces_a_previously_mounted_character's own
	# queue_free() wait already uses for a different deferred-engine-step
	# reason.
	await wait_physics_frames(2)

	var skeleton := _find_skeleton(mounted)
	assert_not_null(skeleton, "fixture setup: the seated Papu model must carry a Skeleton3D")
	if skeleton == null:
		return

	var kart_visual := kart.get_node("Visual") as Node3D
	var kart_body_aabb := _combined_mesh_aabb_world(kart_visual)

	var headdress_index := skeleton.find_bone("headdress")
	var hand_l_index := skeleton.find_bone("hand.L")
	var hand_r_index := skeleton.find_bone("hand.R")
	var foot_l_index := skeleton.find_bone("foot.L")
	assert_ne(headdress_index, -1, "fixture setup: headdress bone must exist on Papu's own rig")
	assert_ne(hand_l_index, -1, "fixture setup: hand.L bone must exist on Papu's own rig")
	assert_ne(hand_r_index, -1, "fixture setup: hand.R bone must exist on Papu's own rig")
	assert_ne(foot_l_index, -1, "fixture setup: foot.L bone must exist on Papu's own rig")
	if headdress_index == -1 or hand_l_index == -1 or hand_r_index == -1 or foot_l_index == -1:
		return

	var headdress_world := _bone_global_position(skeleton, headdress_index)
	var hand_l_world := _bone_global_position(skeleton, hand_l_index)
	var hand_r_world := _bone_global_position(skeleton, hand_r_index)
	var foot_l_world := _bone_global_position(skeleton, foot_l_index)

	var kart_top_y := kart_body_aabb.position.y + kart_body_aabb.size.y
	assert_gt(
		headdress_world.y,
		kart_top_y,
		(
			"Papu's own headdress must clear the kart's own real Visual-mesh "
			+ "AABB top (the cowl) -- headdress_y=%s kart_top_y=%s"
		) % [headdress_world.y, kart_top_y]
	)
	# Bounded above too -- a future scale regression that towers absurdly
	# high must fail this the same way a clipped one would, not just "more
	# clearance is always fine".
	assert_lt(
		headdress_world.y,
		kart_top_y + 1.5,
		(
			"Papu's own headdress cleared the cowl by more than 1.5m -- "
			+ "likely an un-authored scale regression, not a deliberately "
			+ "huge driver -- headdress_y=%s kart_top_y=%s"
		) % [headdress_world.y, kart_top_y]
	)

	var kart_min_x := kart_body_aabb.position.x
	var kart_max_x := kart_body_aabb.position.x + kart_body_aabb.size.x
	assert_true(
		hand_l_world.x >= kart_min_x and hand_l_world.x <= kart_max_x,
		(
			"Papu's own left hand must stay within the kart's own real "
			+ "Visual-mesh AABB width, not clipped out past the body -- "
			+ "hand_l_x=%s kart_x_range=[%s, %s]"
		) % [hand_l_world.x, kart_min_x, kart_max_x]
	)
	assert_true(
		hand_r_world.x >= kart_min_x and hand_r_world.x <= kart_max_x,
		(
			"Papu's own right hand must stay within the kart's own real "
			+ "Visual-mesh AABB width, not clipped out past the body -- "
			+ "hand_r_x=%s kart_x_range=[%s, %s]"
		) % [hand_r_world.x, kart_min_x, kart_max_x]
	)

	# Grounded, not floating well above the seat nor sunk through the
	# kart's own floor (y=0, the same floor _spawn_kart_on_floor()'s own
	# StaticBody3D sits just under -- see that helper's own doc).
	assert_true(
		foot_l_world.y > -0.1 and foot_l_world.y < kart_top_y,
		(
			"Papu's own feet must rest somewhere between the kart's own "
			+ "floor and its cowl top, not sunk through the floor nor "
			+ "floating above the cowl -- foot_l_y=%s kart_top_y=%s"
		) % [foot_l_world.y, kart_top_y]
	)


func test_apply_body_tint_overrides_the_visual_meshes_with_the_given_color() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var tint := Color(0.2, 0.45, 0.86, 1.0)

	kart.call("apply_body_tint", tint)

	var visual := kart.get_node("Visual")
	var mesh_instances: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	if visual is MeshInstance3D:
		mesh_instances.append(visual)
	assert_gt(mesh_instances.size(), 0, "fixture sanity: the kart model must carry at least one mesh")
	for node: Node in mesh_instances:
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.material_override as StandardMaterial3D
		assert_not_null(
			material,
			"apply_body_tint() must set a StandardMaterial3D material_override on every mesh instance"
		)
		if material == null:
			continue
		assert_eq(material.albedo_color, tint)
		assert_true(
			material.vertex_color_use_as_albedo,
			"the override must multiply the mesh's own painted vertex colour, not replace it flatly"
		)


## Two different apply_body_tint() calls (the shape RaceSession uses once per
## AI slot) must leave two INDEPENDENT karts with two DIFFERENT colours --
## proves the override is per-instance, not a shared sub-resource every kart
## silently repaints together (the exact hazard kart_fx.gd's own class doc
## warns about for kart.tscn's embedded ParticleProcessMaterial).
func test_apply_body_tint_is_independent_per_kart_instance() -> void:
	var red_kart := _spawn_kart_on_floor(Vector3.ZERO)
	var blue_kart := _spawn_kart_on_floor(Vector3(100.0, 0.0, 0.0))
	if red_kart == null or blue_kart == null:
		return
	var red := Color(0.86, 0.22, 0.16, 1.0)
	var blue := Color(0.2, 0.45, 0.86, 1.0)

	red_kart.call("apply_body_tint", red)
	blue_kart.call("apply_body_tint", blue)

	var red_material := (
		red_kart.get_node("Visual").find_children("*", "MeshInstance3D", true, false)[0]
		as MeshInstance3D
	).material_override as StandardMaterial3D
	var blue_material := (
		blue_kart.get_node("Visual").find_children("*", "MeshInstance3D", true, false)[0]
		as MeshInstance3D
	).material_override as StandardMaterial3D
	assert_not_null(red_material)
	assert_not_null(blue_material)
	if red_material == null or blue_material == null:
		return
	assert_eq(red_material.albedo_color, red)
	assert_eq(blue_material.albedo_color, blue)


## The design brief's own "animation driver non-interference" requirement:
## the mounted character must yaw together with the kart body, never lag or
## diverge from it, with NO explicit facing-sync code of any kind (see
## mount_character()'s own YAW doc for why this holds by construction --
## the character is a plain scene-graph descendant of this kart's own
## CharacterBody3D). Proven through real steering + real physics ticks, not
## asserted from the parenting alone.
func test_mounted_character_yaws_together_with_the_kart_body_while_steering() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var crash_scene := load(CRASH_MODEL_PATH) as PackedScene
	assert_not_null(crash_scene)
	if crash_scene == null:
		return
	var mounted: Node3D = kart.call("mount_character", crash_scene)
	assert_not_null(mounted)
	if mounted == null:
		return

	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before steering")

	# mount_character() sets a fixed LOCAL rotation.y = PI on the character
	# itself (the "-Y-forward-in-Blender" orientation fix, see that method's
	# own doc) -- so the character's WORLD yaw sits at a constant offset from
	# the kart body's own world yaw, never numerically equal to it. What
	# "yaws together, no fighting" actually means is that the two CHANGE by
	# the same amount tick over tick -- captured here as the delta before vs.
	# after steering, for both the kart body and the mounted character.
	var kart_yaw_before: float = kart.global_transform.basis.get_euler().y
	var character_yaw_before: float = mounted.global_transform.basis.get_euler().y

	kart.call("steer", 1.0)
	await wait_physics_frames(30)

	var kart_yaw_after: float = kart.global_transform.basis.get_euler().y
	var character_yaw_after: float = mounted.global_transform.basis.get_euler().y
	var kart_delta := wrapf(kart_yaw_after - kart_yaw_before, -PI, PI)
	var character_delta := wrapf(character_yaw_after - character_yaw_before, -PI, PI)

	assert_gt(
		absf(kart_delta),
		0.01,
		"fixture setup: the kart body must have visibly yawed by now"
	)
	assert_almost_eq(
		character_delta,
		kart_delta,
		0.001,
		"the mounted character's world yaw must change by exactly the kart body's own yaw delta, every tick"
	)


# ---------------------------------------------------------------------------
# R4 Task 3 (CTR item loop): the real per-kart ItemSlot -- configure()/
# refresh_tuning() thread item_tuning through (optionally, see
# _spawn_kart_on_floor()'s own doc), use_item() now delegates to the real
# slot instead of the Task-2 stub's hardcoded &"none", item_slot() exposes
# it, and _physics_process ticks it every frame the kart is run_active.
# ---------------------------------------------------------------------------


func test_configure_without_item_tuning_still_compiles_and_use_item_stays_none() -> void:
	# Backward compatibility: every OTHER test in this file spawns a kart
	# with no item_tuning at all (the optional param's default null) --
	# this pins that use_item() degrades to a harmless permanent &"none"
	# rather than erroring, since the ItemSlot never gets configure()d.
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	assert_eq(kart.call("use_item"), &"none")
	assert_eq(int(kart.call("item_use_count")), 1, "the call counter must still increment")


func test_item_slot_accessor_exposes_the_real_configured_slot() -> void:
	var kart := _spawn_kart_on_floor(Vector3.ZERO, _item_tuning)
	if kart == null:
		return
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot, "item_slot() must expose the controller's own real ItemSlot")
	if slot == null:
		return
	assert_eq(slot.call("state"), &"empty", "a freshly configured slot must start empty")


func test_use_item_returns_none_when_nothing_is_held() -> void:
	var kart := _spawn_kart_on_floor(Vector3.ZERO, _item_tuning)
	if kart == null:
		return
	assert_eq(
		kart.call("use_item"),
		&"none",
		"use_item() must return none before any roll has landed"
	)


## Drives a real roll through the real slot (start_roll() directly on the
## slot this controller owns, exactly the way race_session.gd's own box
## pickup routing will call it in this same task) and real physics ticks
## (proving _physics_process actually calls ItemSlot.tick(), not just that
## the slot works in isolation -- that is test_item_slot.gd's job) to prove
## use_item() hands back the real rolled item and clears it.
func test_use_item_returns_the_rolled_item_once_the_roll_lands_and_then_clears_it() -> void:
	var kart := _spawn_kart_on_floor(Vector3.ZERO, _item_tuning)
	if kart == null:
		return
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), &"rolling", "fixture setup: the roll must have started")

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_item_tuning.roulette_duration_s * physics_fps)) + 2
	await wait_physics_frames(frames_needed)

	assert_eq(
		slot.call("state"),
		&"held",
		"real _physics_process ticks must have advanced the real slot to held"
	)

	var used: StringName = kart.call("use_item")

	assert_eq(used, &"missile", "rng_value=0.0 must roll the first item, missile")
	assert_eq(
		int(kart.call("item_use_count")),
		1,
		"the call counter must still increment on a real, successful use"
	)
	assert_eq(
		kart.call("use_item"),
		&"none",
		"a second use_item() call must not hand out the same item again"
	)


## Run-active gating: the item roulette must not advance while a kart is
## frozen (RaceSession freezes every kart at the finish line via set_run_
## active(false), see race_session.gd's own _finish_race()) -- mirrors how
## the drift FSM/motor tick above it in _physics_process are already gated
## the same way.
func test_item_slot_does_not_advance_while_the_kart_is_not_run_active() -> void:
	var kart := _spawn_kart_on_floor(Vector3.ZERO, _item_tuning)
	if kart == null:
		return
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	kart.call("set_run_active", false)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_item_tuning.roulette_duration_s * physics_fps)) + 2
	await wait_physics_frames(frames_needed)

	assert_eq(
		slot.call("state"),
		&"rolling",
		"a frozen kart's own item roll must not advance, even past roulette_duration_s worth of real ticks"
	)


## Live tuning refresh (M2 fix-wave counterpart for items): mirrors test_
## refresh_tuning_reapplies_a_live_kart_tuning_value_to_the_motor's own
## "shrink/change a tuning value, prove the NEXT tick already reads the new
## one" shape, applied to the item slot instead of the motor.
func test_refresh_tuning_reaches_the_real_item_slot() -> void:
	var kart := _spawn_kart_on_floor(Vector3.ZERO, _item_tuning)
	if kart == null:
		return
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), &"rolling", "fixture setup: the roll must have started")

	# Far smaller than even a single real physics tick's own delta_s (at a
	# default 60 physics ticks/second, ~0.0167s) -- so ANY tick at all after
	# the refresh lands the roll, unlike the STALE (1.2s) duration this
	# fixture's own start_roll() began under, which two ticks could never
	# reach on its own (proving the refresh, not just that time passed).
	var shrunk_tuning: ItemTuning = _item_tuning.duplicate(true)
	shrunk_tuning.roulette_duration_s = 0.001

	kart.call("refresh_tuning", _kart_tuning, shrunk_tuning)
	await wait_physics_frames(2)

	assert_eq(
		slot.call("state"),
		&"held",
		(
			"refresh_tuning() must reach the real ItemSlot this controller "
			+ "owns -- with the stale (longer) roulette_duration_s still in "
			+ "effect, two ticks would not be enough to land the roll"
		)
	)


## ---------------------------------------------------------------------------
## CTR R7 Task 2: kart-to-kart contact. Real move_and_slide() collisions
## between two real kart.tscn instances sharing one physics world -- see
## _spawn_kart_pair()'s own doc for why two _spawn_kart_on_floor() fixtures
## at different origins already collide with each other with no extra
## wiring. Direction convention pinned by kart_motor.gd's own sign-
## conversion doc: yaw=-90 faces +X, yaw=+90 faces -X (Vector3.FORWARD.
## rotated(UP, +angle) sweeps toward -X).
## ---------------------------------------------------------------------------


## Two karts approaching head-on along world X (yaw=-90/+90, see this
## section's own doc), starting far enough apart that BOTH must cross real
## distance under their own auto-throttle before the collision -- proves
## the mechanic end to end (real move_and_slide() collision -> duck-checked
## collider -> receive_bump() crossing into the OTHER kart's own
## KartController instance), not just that the pure-logic motor decay
## works in isolation (test_kart_motor.gd already covers that). Samples
## EVERY tick rather than a single snapshot at the end, because the bump is
## a decaying impulse (see kart_motor.gd's own apply_bump() doc) that can
## legitimately have decayed back toward zero again by any single later
## instant -- a snapshot at a fixed tick count would be flaky by
## construction.
func test_two_karts_colliding_at_speed_separate_laterally_and_symmetrically() -> void:
	var karts := _spawn_kart_pair(Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)
	kart_b.call("set_yaw_degrees", 90.0)

	var motor_a: RefCounted = kart_a.get("_motor")
	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_a)
	assert_not_null(motor_b)
	if motor_a == null or motor_b == null:
		return

	var max_bump_a := 0.0
	var max_bump_b := 0.0
	var opposite_direction_observed := false
	var comparable_magnitude_observed := false
	for _tick_index: int in range(240):
		await wait_physics_frames(1)
		var bump_a: Vector3 = motor_a.call("lateral_bump_mps")
		var bump_b: Vector3 = motor_b.call("lateral_bump_mps")
		max_bump_a = maxf(max_bump_a, bump_a.length())
		max_bump_b = maxf(max_bump_b, bump_b.length())
		if not bump_a.is_zero_approx() and not bump_b.is_zero_approx():
			if bump_a.dot(bump_b) < 0.0:
				opposite_direction_observed = true
			if absf(bump_a.length() - bump_b.length()) < 0.75:
				comparable_magnitude_observed = true

	assert_gt(max_bump_a, 0.0, "kart A must have received a real lateral bump from the collision")
	assert_gt(max_bump_b, 0.0, "kart B must have received a real lateral bump from the collision")
	assert_true(
		opposite_direction_observed,
		"the two karts' bumps must point away from each other, not the same way"
	)
	assert_true(
		comparable_magnitude_observed,
		"both karts must receive a comparable magnitude -- a SYMMETRIC separation"
	)
	assert_lte(
		max_bump_a,
		_kart_tuning.bump_lateral_cap_mps + 0.01,
		"kart A's bump must never exceed the authored cap"
	)
	assert_lte(
		max_bump_b,
		_kart_tuning.bump_lateral_cap_mps + 0.01,
		"kart B's bump must never exceed the authored cap"
	)


## An absurdly high approach speed (white-boxed, far beyond anything
## reachable under authored top_speed_mps/boost) deliberately makes
## relative_speed * bump_impulse_scale blow WAY past bump_lateral_cap_mps --
## a capped observation here proves the cap actually clamps, not merely
## that ordinary racing speeds never happen to reach it.
func test_bump_magnitude_is_capped_even_at_extreme_relative_speed() -> void:
	var karts := _spawn_kart_pair(Vector3(-0.8, 0.0, 0.0), Vector3(0.8, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)

	var motor_a: RefCounted = kart_a.get("_motor")
	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_a)
	if motor_a == null:
		return
	motor_a.set("_forward_speed_mps", _kart_tuning.top_speed_mps * 50.0)

	var max_bump_a := 0.0
	var max_bump_b := 0.0
	for _tick_index: int in range(60):
		await wait_physics_frames(1)
		max_bump_a = maxf(max_bump_a, (motor_a.call("lateral_bump_mps") as Vector3).length())
		max_bump_b = maxf(max_bump_b, (motor_b.call("lateral_bump_mps") as Vector3).length())

	assert_gt(max_bump_a, 0.0, "fixture sanity: an extreme-speed collision must still register a bump")
	assert_lte(
		max_bump_a,
		_kart_tuning.bump_lateral_cap_mps + 0.01,
		"kart A's bump must be capped even at an extreme relative speed"
	)
	assert_lte(
		max_bump_b,
		_kart_tuning.bump_lateral_cap_mps + 0.01,
		"kart B's bump must be capped even at an extreme relative speed"
	)


## The same proven head-on approach geometry as test_two_karts_colliding_
## at_speed_separate_laterally_and_symmetrically above (real contact is
## already confirmed to occur there), but with BOTH karts' own forward
## speed re-pinned to a small creep value before each wait (white-boxed --
## a plain accel-from-rest approach cannot hold a low relative speed long
## enough to actually reach contact, since auto-throttle keeps climbing
## toward top_speed_mps regardless of how slowly either kart started).
##
## GUT's own wait_physics_frames(1) (see addons/gut/awaiter.gd's own
## _on_tree_physics_frame()/_end_wait(): it waits until elapsed_frames >
## requested, i.e. STRICTLY more than 1) actually elapses TWO physics
## ticks per call, not one -- confirmed by direct measurement while
## building this test (a single re-pin followed by exactly 2*accel_mps2*
## one tick's delta_s of unclamped climb). creep_speed_mps is therefore
## picked so even the WORST case -- two full unclamped accel ticks between
## re-pins, on BOTH karts -- keeps the combined relative closing speed
## under bump_min_relative_speed_mps with real margin:
## 2 * (creep_speed_mps + 2 * accel_mps2 / physics_ticks_per_second) must
## stay comfortably below 1.5.
func test_below_min_relative_speed_produces_no_impulse() -> void:
	var karts := _spawn_kart_pair(Vector3(-1.5, 0.0, 0.0), Vector3(1.5, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)
	kart_b.call("set_yaw_degrees", 90.0)

	var motor_a: RefCounted = kart_a.get("_motor")
	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_a)
	assert_not_null(motor_b)
	if motor_a == null or motor_b == null:
		return

	var creep_speed_mps := 0.05
	var worst_case_per_kart_mps := creep_speed_mps + (
		2.0 * _kart_tuning.accel_mps2 / float(Engine.physics_ticks_per_second)
	)
	assert_lt(
		2.0 * worst_case_per_kart_mps,
		_kart_tuning.bump_min_relative_speed_mps,
		"fixture sanity: the worst-case creep speed must stay under the authored gate"
	)

	var contact_observed := false
	for _tick_index: int in range(300):
		motor_a.set("_forward_speed_mps", creep_speed_mps)
		motor_b.set("_forward_speed_mps", creep_speed_mps)
		await wait_physics_frames(1)
		if kart_a.get_slide_collision_count() > 0:
			contact_observed = true
		var bump_a: Vector3 = motor_a.call("lateral_bump_mps")
		var bump_b: Vector3 = motor_b.call("lateral_bump_mps")
		assert_true(
			bump_a.is_zero_approx(),
			"a slow-creep contact must stay below bump_min_relative_speed_mps"
		)
		assert_true(
			bump_b.is_zero_approx(),
			"a slow-creep contact must stay below bump_min_relative_speed_mps"
		)

	assert_true(
		contact_observed,
		"fixture sanity: the two karts must actually have touched during the run"
	)


## Kart A stays active and drives toward kart B, which is frozen (set_run_
## active(false)) and parked stationary in A's path -- the realistic shape
## of the mechanic's own constraint (a kart parked at the finish line must
## not react to incoming traffic). Proves BOTH halves of "neither give nor
## receive" in one real physics run: B's own _process_kart_bumps() never
## runs while frozen (B GIVES nothing, structurally -- see kart_controller.
## gd's own doc), and A's own detection DOES try to hand B a bump via
## receive_bump(), which B's own guard must reject (B RECEIVES nothing) --
## while A itself, still active, is free to keep reacting normally
## (asserted via the fixture-sanity check below, so this test cannot pass
## vacuously by nothing ever touching at all).
func test_frozen_kart_neither_gives_nor_receives_a_bump() -> void:
	var karts := _spawn_kart_pair(Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)
	kart_b.call("set_run_active", false)

	var motor_a: RefCounted = kart_a.get("_motor")
	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_a)
	assert_not_null(motor_b)
	if motor_a == null or motor_b == null:
		return

	var kart_a_ever_bumped := false
	for _tick_index: int in range(180):
		await wait_physics_frames(1)
		var bump_b: Vector3 = motor_b.call("lateral_bump_mps")
		assert_true(bump_b.is_zero_approx(), "a frozen kart must never receive a bump")
		if not (motor_a.call("lateral_bump_mps") as Vector3).is_zero_approx():
			kart_a_ever_bumped = true

	assert_true(
		kart_a_ever_bumped,
		"fixture sanity: the still-active kart must have actually made contact with the frozen one"
	)


## Direct unit check on receive_bump()'s own guard clause (see that
## method's own doc) -- no physics simulation, no approach geometry,
## isolates exactly the one line of logic the physics-based test above
## exercises only indirectly. source_instance_id is a required argument
## (FIX ROUND 1 -- see receive_bump()'s own doc for why it is not
## defaulted); this direct unit call has no real "other kart" instance to
## pass, so it uses 0 (never a real Godot instance id) as an inert
## placeholder -- the dedup dictionary write it produces is irrelevant
## here since this test never calls _process_kart_bumps() to consult it.
func test_frozen_kart_rejects_a_direct_receive_bump_call() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	kart.call("set_run_active", false)
	kart.call("receive_bump", Vector3(5.0, 0.0, 0.0), 0)

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	var lateral: Vector3 = motor.call("lateral_bump_mps")
	assert_true(
		lateral.is_zero_approx(),
		"a frozen kart must reject an incoming receive_bump() call, regardless of who calls it"
	)


## _process_kart_bumps()'s own doc states the mechanic is deliberately
## independent of hit/hazard state: a bump is a physical shove, not a hit,
## so is_invulnerable() must never gate it (contrast register_hit()'s own
## item-damage path, which invulnerability DOES block). Proven directly,
## not just by the absence of an is_invulnerable() check in the source:
## kart B's own motor is forced invulnerable for the whole run (white-
## boxed -- mirrors this file's own _forward_speed_mps re-pin precedent
## above), and must still receive a real, non-zero lateral bump from kart
## A's real collision.
func test_invulnerable_kart_still_receives_a_bump() -> void:
	var karts := _spawn_kart_pair(Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)
	kart_b.call("set_yaw_degrees", 90.0)

	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_b)
	if motor_b == null:
		return
	motor_b.set("_invulnerable_remaining_s", 999.0)

	var kart_b_ever_bumped := false
	for _tick_index: int in range(240):
		await wait_physics_frames(1)
		assert_true(
			bool(kart_b.call("is_invulnerable")),
			"fixture sanity: kart B must stay invulnerable for the whole run"
		)
		if not (motor_b.call("lateral_bump_mps") as Vector3).is_zero_approx():
			kart_b_ever_bumped = true

	assert_true(
		kart_b_ever_bumped,
		"an invulnerable kart must still receive a bump -- invulnerability blocks hits, not shoves"
	)


## FIX ROUND 1 (Task 2 review, same-tick double-detection). Both karts held
## at a fixed, MODERATE forward speed (white-boxed re-pin every iteration --
## mirrors test_below_min_relative_speed_produces_no_impulse's own creep-
## speed technique above), starting close enough together (same ±1.5m
## geometry that test already proves produces real, repeated contact) to
## stay overlapped/touching for many consecutive physics ticks -- the exact
## "sustained overlap" shape the review flagged. Two independent
## regressions are asserted every sample:
##
## (1) PROPORTIONAL, NOT SATURATED: the true combined closing speed here is
## small and known (2 * creep_speed_mps, give or take drift -- see the
## fixture-sanity assert below), so a CORRECT impulse must land well under
## the cap. The old bug -- reading an already-applied bump back through
## velocity() instead of the bump-free commanded_velocity_without_bump_mps()
## -- would compound tick after tick under sustained overlap and pin the
## observed magnitude at bump_lateral_cap_mps regardless of this slow true
## speed; asserting max_observed stays under 0.75 * the cap gives real
## margin above the correct expected range and real margin below a
## saturated one.
##
## (2) ONE PAIR PER TICK: bump_count() deltas (see that method's own doc)
## are summed across BOTH karts and compared against the number of REAL
## physics ticks elapsed between samples -- read directly via Engine.get_
## physics_frames(), not assumed from loop-iteration count, because GUT's
## own wait_physics_frames(1) (see test_below_min_relative_speed_produces_
## no_impulse's own doc) elapses more than one real tick per call. A
## correct implementation increments the COMBINED total by at most 1 per
## real tick (only the first detector counts, per _bumped_by_tick's own
## dedup); the old same-tick double-detection bug would let both karts'
## own independent detection increment their own count for the identical
## contact, doubling that rate.
func test_sustained_overlap_stays_proportional_and_dedups_to_one_pair_per_tick() -> void:
	var karts := _spawn_kart_pair(Vector3(-1.5, 0.0, 0.0), Vector3(1.5, 0.0, 0.0))
	if karts.is_empty():
		return
	var kart_a: CharacterBody3D = karts[0]
	var kart_b: CharacterBody3D = karts[1]
	kart_a.call("set_yaw_degrees", -90.0)
	kart_b.call("set_yaw_degrees", 90.0)

	var motor_a: RefCounted = kart_a.get("_motor")
	var motor_b: RefCounted = kart_b.get("_motor")
	assert_not_null(motor_a)
	assert_not_null(motor_b)
	if motor_a == null or motor_b == null:
		return

	var creep_speed_mps := 1.2
	# Fixture sanity: even accounting for the worst-case drift between
	# re-pins (2 full unclamped accel ticks per kart, the same bound test_
	# below_min_relative_speed_produces_no_impulse's own doc derives), the
	# TRUE combined closing speed here must clear the gate with real margin
	# -- proving any observed impulse is a real, gated response, not noise.
	var worst_case_per_kart_mps := creep_speed_mps + (
		2.0 * _kart_tuning.accel_mps2 / float(Engine.physics_ticks_per_second)
	)
	assert_gt(
		2.0 * creep_speed_mps,
		_kart_tuning.bump_min_relative_speed_mps,
		"fixture sanity: the chosen creep speed must clear the gate with margin"
	)
	assert_lt(
		2.0 * worst_case_per_kart_mps * _kart_tuning.bump_impulse_scale,
		_kart_tuning.bump_lateral_cap_mps * 0.75,
		"fixture sanity: even worst-case drift must stay well clear of the cap under correct behavior"
	)

	var max_observed_magnitude := 0.0
	var prev_tick := Engine.get_physics_frames()
	var prev_bump_count_a := int(kart_a.call("bump_count"))
	var prev_bump_count_b := int(kart_b.call("bump_count"))
	for _tick_index: int in range(200):
		motor_a.set("_forward_speed_mps", creep_speed_mps)
		motor_b.set("_forward_speed_mps", creep_speed_mps)
		await wait_physics_frames(1)

		var now_tick := Engine.get_physics_frames()
		var real_ticks_elapsed := now_tick - prev_tick
		prev_tick = now_tick

		var bump_count_a := int(kart_a.call("bump_count"))
		var bump_count_b := int(kart_b.call("bump_count"))
		var combined_delta := (
			(bump_count_a - prev_bump_count_a) + (bump_count_b - prev_bump_count_b)
		)
		assert_lte(
			combined_delta,
			real_ticks_elapsed,
			"at most one impulse pair may fire per REAL physics tick, not per contact"
		)
		prev_bump_count_a = bump_count_a
		prev_bump_count_b = bump_count_b

		max_observed_magnitude = maxf(
			max_observed_magnitude,
			(motor_a.call("lateral_bump_mps") as Vector3).length()
		)
		max_observed_magnitude = maxf(
			max_observed_magnitude,
			(motor_b.call("lateral_bump_mps") as Vector3).length()
		)

	assert_gt(
		max_observed_magnitude,
		0.0,
		"fixture sanity: the sustained-overlap scenario must actually produce real contact"
	)
	assert_lt(
		max_observed_magnitude,
		_kart_tuning.bump_lateral_cap_mps * 0.75,
		"a slow, sustained contact must stay proportional to the TRUE closing speed, not saturate at the cap"
	)


## Two _spawn_kart_on_floor() fixtures at different origins, reused as-is --
## see that helper's own doc: multiple fixtures spawned in the same test
## already share one physics world and collide with each other with no
## extra wiring, which is exactly what these tests need (a real two-kart
## contact, not a mocked one).
func _spawn_kart_pair(origin_a: Vector3, origin_b: Vector3) -> Array:
	var kart_a := _spawn_kart_on_floor(origin_a)
	var kart_b := _spawn_kart_on_floor(origin_b)
	if kart_a == null or kart_b == null:
		return []
	return [kart_a, kart_b]


## origin offsets the whole floor+kart fixture so multiple fixtures spawned
## in the same test (e.g. a same-direction-vs-counter-steer A/B comparison)
## don't share a global position and collide with each other. item_tuning
## (R4 Task 3) is OPTIONAL and defaults to null -- every pre-existing call
## site in this file that only ever passed origin keeps configuring the
## kart with no item tuning, exactly the same "an omitted item_tuning is a
## documented no-op" contract kart_controller.gd's own configure() itself
## establishes.
## Shared lookup for the mount_character() seat-pose tests above: every
## character glb (SK_crash.glb, SK_lab_assistant.glb) wraps its Skeleton3D
## one level under the mounted root (RIG_*/Skeleton3D -- see this file's own
## dump of both rigs during the R6 fix wave), so a plain find_children scan
## is enough; returns null (with no assertion of its own) if the fixture
## itself is broken, matching this file's existing "if x == null: return"
## early-out shape at every call site.
func _find_skeleton(mounted: Node3D) -> Skeleton3D:
	var skeletons := mounted.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		return null
	return skeletons[0] as Skeleton3D


## R8 Task 5's own mounted-fit test: get_bone_global_pose() returns a
## transform relative to the Skeleton3D node itself, not the world --
## composing it with skeleton.global_transform is the documented way to
## get a real world-space bone position, the same composition test_mount_
## character_on_a_model_without_a_seated_clip_lowers_the_pelvis_to_seat_
## height already does inline for a single bone; this is that same one-
## liner, named, for a test that needs it for four different bones.
func _bone_global_position(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


## R8 Task 5's own mounted-fit test: a real world-space AABB for the kart's
## OWN Visual subtree, corner-by-corner through every MeshInstance3D's own
## global_transform. Safe here specifically because the kart's Visual is a
## plain STATIC (non-skinned) mesh -- unlike the mounted CHARACTER's own
## MeshInstance3D.get_aabb() (see the mounted-fit test's own doc for why
## that one is unreliable for a posed, skinned mesh), a static mesh's
## get_aabb() genuinely is its real, unchanging local-space bounds, so
## transforming its 8 corners through the current world transform is exact.
func _combined_mesh_aabb_world(node: Node3D) -> AABB:
	var result := AABB()
	var has_any := false
	for mesh_instance: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local_aabb := mesh_instance.get_aabb()
		var world_xform := mesh_instance.global_transform
		for corner_index in range(8):
			var corner := Vector3(
				local_aabb.position.x + (local_aabb.size.x if (corner_index & 1) else 0.0),
				local_aabb.position.y + (local_aabb.size.y if (corner_index & 2) else 0.0),
				local_aabb.position.z + (local_aabb.size.z if (corner_index & 4) else 0.0)
			)
			var world_corner := world_xform * corner
			if not has_any:
				result = AABB(world_corner, Vector3.ZERO)
				has_any = true
			else:
				result = result.expand(world_corner)
	return result


func _spawn_kart_on_floor(
	origin: Vector3 = Vector3.ZERO, item_tuning: ItemTuning = null
) -> CharacterBody3D:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null

	var root := Node3D.new()
	root.position = origin
	add_child_autofree(root)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor)

	var kart := packed.instantiate() as CharacterBody3D
	assert_not_null(kart)
	if kart == null:
		return null
	kart.position = Vector3(0.0, 0.2, 0.0)
	root.add_child(kart)
	kart.call("configure", _kart_tuning, item_tuning)
	return kart


## Unsigned heading change in degrees between two horizontal velocity
## vectors -- robust to which way either one points, so it works as a pure
## "how much did this kart turn" magnitude regardless of sign convention.
func _horizontal_heading_change_degrees(before: Vector3, after: Vector3) -> float:
	var before_direction := Vector3(before.x, 0.0, before.z)
	var after_direction := Vector3(after.x, 0.0, after.z)
	if before_direction.is_zero_approx() or after_direction.is_zero_approx():
		return 0.0
	return rad_to_deg(before_direction.angle_to(after_direction))
