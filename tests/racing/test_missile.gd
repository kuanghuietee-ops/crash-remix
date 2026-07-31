extends GutTest

# R4 Task 4 (CTR item loop): Missile is a thin Node3D that owns its own
# homing/arm/lifetime/hit-testing state directly -- see missile.gd's own
# class doc. Tested here with real physics ticks (add_child_autofree +
# wait_physics_frames, the same shape test_item_box.gd already uses) and a
# small duck-typed FakeSession double standing in for RaceSession.register_
# hit() -- mirrors racing_input_adapter.gd's own FakeKartController
# precedent for testing a duck-typed collaborator without booting a whole
# scene.

const MISSILE_SCENE_PATH := "res://scenes/racing/missile.tscn"
const TUNING_PATH := "res://data/tuning/racing/items.tres"

var _tuning: ItemTuning


## Records every register_hit() call (the target kart passed in) and always
## returns a fixed outcome -- missile.gd never branches on this return
## value (a hit is a hit, blocked or not, the missile still despawns), so
## the exact outcome returned here is irrelevant to every test in this
## file; only WHICH kart got called, and how many times, matters.
class FakeSession:
	extends RefCounted
	var hit_calls: Array = []

	func register_hit(target: Object) -> StringName:
		hit_calls.append(target)
		return &"spin_out"


func before_all() -> void:
	_tuning = load(TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- Task 2 registers it")


# ---------------------------------------------------------------------------
# Homing: turns toward a locked target and hits it within lifetime.
# ---------------------------------------------------------------------------


func test_homing_missile_turns_toward_and_hits_a_moving_target_ahead_on_a_straight() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	# Target starts a few meters ahead and slightly off-axis so the missile
	# must actually TURN (not just fly straight into it) to connect --
	# proves real pursuit steering, not a straight-line coincidence.
	var target := _new_kart_stub(Vector3(2.0, 0.0, -20.0))
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 0.0, target, 10.0)
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.missile_lifetime_s * physics_fps))
	var step_s := 1.0 / physics_fps
	for _frame_index: int in range(frames_needed):
		if session.hit_calls.size() > 0:
			break
		# Target keeps drifting forward on its own straight line each tick --
		# a real moving target, not a stationary stand-in.
		target.global_position += Vector3(0.0, 0.0, -1.0) * step_s
		await wait_physics_frames(1)

	assert_eq(
		session.hit_calls.size(),
		1,
		"a homing missile must reach and register a hit on its locked target within its own lifetime"
	)
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], target, "the hit must be registered against the locked target")


## Pins the turn-rate CAP itself, directly: a target placed 90 degrees off
## this missile's own launch axis (dead to its right) demands a full
## quarter-turn to face, but a single physics tick may only ever turn it by
## missile_turn_rate_degrees_per_s * delta_s -- proving the steering is a
## bounded-per-tick turn, not an instant snap to face the target.
func test_missile_turn_per_tick_is_capped_at_missile_turn_rate_degrees_per_s() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	# Far to the missile's own right (+X), well beyond hit range -- this
	# test only cares about ONE tick's worth of heading change, never a hit.
	var target := _new_kart_stub(Vector3(1000.0, 0.0, 0.0))
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 0.0, target, 10.0)
	)

	var heading_before_degrees := rad_to_deg(missile.rotation.y)
	await wait_physics_frames(1)
	var heading_after_degrees := rad_to_deg(missile.rotation.y)

	var step_s := 1.0 / float(Engine.physics_ticks_per_second)
	var max_turn_degrees := _tuning.missile_turn_rate_degrees_per_s * step_s
	var turned_degrees := absf(heading_after_degrees - heading_before_degrees)

	assert_gt(turned_degrees, 0.0, "the missile must actually turn toward an off-axis target")
	assert_lte(
		turned_degrees,
		max_turn_degrees + 0.01,
		"a single physics tick must never turn the missile by more than missile_turn_rate_degrees_per_s * delta_s"
	)


func test_missile_with_target_far_off_axis_misses_and_expires_at_lifetime() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	# Directly behind the missile's own launch facing (-Z) and far enough
	# away that neither an instant U-turn nor this missile's own bounded
	# turn rate can close the distance within missile_lifetime_s.
	var target := _new_kart_stub(Vector3(0.0, 0.0, 500.0))
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 0.0, target, 10.0)
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.missile_lifetime_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)

	assert_eq(session.hit_calls.size(), 0, "a target the missile can never turn fast enough to reach must never be hit")
	assert_false(
		is_instance_valid(missile),
		"a missile that never hits anyone must despawn once its own lifetime elapses"
	)


func test_leaderless_missile_with_no_target_ahead_flies_straight() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	# The only other kart in the snapshot is BEHIND the launcher (lower
	# progress) -- the launcher is the leader, so there is nothing to lock.
	var trailing_kart := _new_kart_stub(Vector3(0.0, 0.0, 500.0))
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 10.0, trailing_kart, 0.0)
	)

	var frames := 30
	for _frame_index: int in range(frames):
		await wait_physics_frames(1)

	assert_almost_eq(
		missile.global_position.x,
		0.0,
		0.01,
		"a leaderless missile must fly perfectly straight (no lateral drift) -- default facing is -Z"
	)
	assert_lt(
		missile.global_position.z,
		0.0,
		"a leaderless missile must still travel forward under its own missile_speed_mps"
	)
	assert_eq(session.hit_calls.size(), 0, "fixture sanity: the trailing kart was placed far out of hit range")


# ---------------------------------------------------------------------------
# Arm delay: protects a kart already within hit radius at launch.
# ---------------------------------------------------------------------------


## A target moving in perfect lockstep with the missile's own straight-line
## speed (same velocity, same starting point) stays at ~zero relative
## distance every tick regardless of exactly how many real physics ticks a
## given `wait_physics_frames()` call happens to advance in this headless
## harness -- polling the missile's own internal elapsed-time clock (rather
## than pre-computing a frame count from Engine.physics_ticks_per_second)
## is what actually makes this test's timing robust; a MovingBody stand-in
## just removes "the target fell out of hit range for an unrelated reason"
## as a confound.
## CharacterBody3D, not a plain Node3D -- missile.gd's own configure() reads
## each targets_getter entry's "kart" through a CharacterBody3D-typed local
## (matching every real kart in this codebase), and a mismatched type there
## throws a runtime type error INSIDE configure() that aborts before
## _configured is ever set true, silently leaving this missile permanently
## unconfigured and any polling loop waiting on its own elapsed clock stuck
## forever -- caught empirically while first writing this test.
class MovingBody:
	extends CharacterBody3D
	var velocity_mps: Vector3

	func _physics_process(delta_s: float) -> void:
		global_position += velocity_mps * delta_s


func test_missile_does_not_hit_a_co_located_target_before_arm_delay_elapses() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var target := MovingBody.new()
	target.velocity_mps = Vector3(0.0, 0.0, -1.0) * _tuning.missile_speed_mps
	add_child_autofree(target)
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 0.0, target, 10.0)
	)

	# Poll real physics ticks until this missile's OWN elapsed clock is
	# most of the way toward missile_arm_delay_s but not there yet.
	var margin_ratio := 0.2
	while (
		is_instance_valid(missile)
		and float(missile.get("_elapsed_s")) < _tuning.missile_arm_delay_s * (1.0 - margin_ratio)
	):
		await wait_physics_frames(1)

	assert_true(is_instance_valid(missile), "fixture sanity: the missile must not have despawned before arm delay")
	if not is_instance_valid(missile):
		return
	assert_eq(
		session.hit_calls.size(),
		0,
		"a kart continuously within hit radius must not be hit before missile_arm_delay_s elapses"
	)

	# Now let it finish arming and confirm the same co-located, lockstep
	# target is hit shortly after.
	var safety_frames := 120
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(
		session.hit_calls.size(),
		1,
		"once armed, a kart continuously within hit radius must be hit"
	)
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], target)


func test_missile_never_hits_its_own_launcher_even_once_armed() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var missile := _new_missile(Vector3.ZERO)
	if missile == null:
		return

	# No OTHER kart at all -- the only nearby body is the launcher itself,
	# sitting exactly where the missile spawns for this entire test.
	missile.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, 0.0, null, 0.0)
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.missile_arm_delay_s * physics_fps)) + 10
	for _frame_index: int in range(frames_needed):
		launcher.global_position = missile.global_position
		await wait_physics_frames(1)

	assert_eq(
		session.hit_calls.size(),
		0,
		"a missile must never register a hit against its own launcher, arming or not"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


## Builds the Array[Dictionary] shape targets_getter must return -- see
## missile.gd's own configure() doc. other_kart/other_progress may be null/
## unused (test_missile_never_hits_its_own_launcher_even_once_armed passes
## no second kart at all).
func _targets_for(
	launcher: CharacterBody3D,
	launcher_progress: float,
	other_kart: Variant,
	other_progress: float
) -> Array:
	var result: Array = [{"kart": launcher, "progress": launcher_progress}]
	if other_kart != null:
		result.append({"kart": other_kart, "progress": other_progress})
	return result


func _new_missile(origin: Vector3) -> Node3D:
	assert_true(ResourceLoader.exists(MISSILE_SCENE_PATH), "the missile graybox scene must exist")
	if not ResourceLoader.exists(MISSILE_SCENE_PATH):
		return null
	var packed := load(MISSILE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var missile := packed.instantiate() as Node3D
	assert_not_null(missile)
	if missile == null:
		return null
	missile.position = origin
	add_child_autofree(missile)
	return missile


## A minimal, position-only stand-in for a real kart -- missile.gd never
## calls any kart-specific method on a candidate/launcher directly (only
## reads .global_position, and hands the whole Object to session.
## register_hit()), so a bare CharacterBody3D with no collision shape is
## sufficient here; the real register_hit()/is_shielded()/apply_spin_out
## plumbing is covered separately in test_race_session.gd.
func _new_kart_stub(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = origin
	add_child_autofree(body)
	return body
