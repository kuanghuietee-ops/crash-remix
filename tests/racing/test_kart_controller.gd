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

var _kart_tuning: KartTuning


func before_all() -> void:
	_kart_tuning = load(TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load — Task 1 registers it")


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


## origin offsets the whole floor+kart fixture so multiple fixtures spawned
## in the same test (e.g. a same-direction-vs-counter-steer A/B comparison)
## don't share a global position and collide with each other.
func _spawn_kart_on_floor(origin: Vector3 = Vector3.ZERO) -> CharacterBody3D:
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
	kart.call("configure", _kart_tuning)
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
