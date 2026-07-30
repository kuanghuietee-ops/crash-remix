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


## origin offsets the whole floor+kart fixture so multiple fixtures spawned
## in the same test (e.g. a same-direction-vs-counter-steer A/B comparison)
## don't share a global position and collide with each other. item_tuning
## (R4 Task 3) is OPTIONAL and defaults to null -- every pre-existing call
## site in this file that only ever passed origin keeps configuring the
## kart with no item tuning, exactly the same "an omitted item_tuning is a
## documented no-op" contract kart_controller.gd's own configure() itself
## establishes.
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
