extends GutTest

# CTR R6 Task 5 (new items): Bomb is a thin, MOVING Node3D hazard -- see
# bomb.gd's own class doc. Tested here with real physics ticks (add_child_
# autofree + wait_physics_frames), mirroring test_beaker.gd's/test_missile.
# gd's own FakeSession double, since bomb.gd shares the exact same duck-
# typed session/targets_getter contract those two already use.
#
# ARM-DELAY-VS-BLAST-RADIUS PRECISION NOTE: the real shipped tuning (bomb_
# speed_mps=18.0, bomb_blast_radius_m=3.5, bomb_arm_delay_s=0.2, kart.tres's
# own gravity_mps2=24.0) puts a STATIONARY point at the exact launch origin
# just OUTSIDE blast radius (~3.52m) by the very first physics tick at/after
# arming, and the bomb never returns anywhere near that origin afterward
# (constant horizontal velocity carries it tens of metres away by the time
# it falls back to launch height) -- so a literal "self-bomb while standing
# still at the exact spawn point" is NOT reliably reproducible against the
# real production numbers at typical physics tick rates. Tests that need a
# GUARANTEED overlap (arm-delay gating, self-hit, multi-hit, out-of-range
# exclusion) use _tuning_with() to enlarge bomb_blast_radius_m on a COPY of
# the real tuning -- proving the CODE PATH (every candidate kart within
# radius, launcher included, tested only once armed) rather than being a
# hostage to the real numbers' own marginal flight geometry. Tests that
# only care about the flight itself (45-degree launch, real gravity arc,
# real ground-contact timing) use the unmodified real tuning throughout.

const BOMB_SCENE_PATH := "res://scenes/racing/bomb.tscn"
const ITEM_TUNING_PATH := "res://data/tuning/racing/items.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _tuning: ItemTuning
var _kart_tuning: KartTuning


class FakeSession:
	extends RefCounted
	var hit_calls: Array = []

	func register_hit(target: Object) -> StringName:
		hit_calls.append(target)
		return &"spin_out"


func before_all() -> void:
	_tuning = load(ITEM_TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- R4 Task 2 registers it")
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load -- R1/R2 Task 1 registers it")


func test_bomb_scene_loads_and_instantiates_with_a_mesh() -> void:
	assert_true(ResourceLoader.exists(BOMB_SCENE_PATH), "the bomb graybox scene must exist")
	if not ResourceLoader.exists(BOMB_SCENE_PATH):
		return
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	assert_not_null(bomb.get_node_or_null("Mesh"))


# ---------------------------------------------------------------------------
# LAUNCH GEOMETRY: an analytic 45-degree arc (equal horizontal/vertical
# velocity magnitude), no bare angle literal or new tuning field.
# ---------------------------------------------------------------------------


func test_bomb_launch_velocity_splits_evenly_between_horizontal_and_vertical() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	# Identity basis: forward is -Z (Godot convention), so horizontal speed
	# lands entirely on the Z axis and vertical entirely on Y.
	bomb.call(
		"configure", session, launcher, _tuning, _kart_tuning, Callable(self, "_targets_for").bind(launcher)
	)

	var velocity: Vector3 = bomb.get("_velocity")
	assert_almost_eq(
		absf(velocity.z),
		velocity.y,
		0.001,
		"equal-magnitude forward/up components is exactly what makes this a 45-degree launch"
	)
	assert_almost_eq(
		velocity.length(),
		_tuning.bomb_speed_mps,
		0.001,
		"the blended direction must still be normalized to exactly bomb_speed_mps"
	)


func test_bomb_rises_then_falls_under_real_gravity() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure", session, launcher, _tuning, _kart_tuning, Callable(self, "_targets_for").bind(launcher)
	)

	var peak_y := bomb.global_position.y
	var frames_to_peak := int(
		ceil((_tuning.bomb_speed_mps / sqrt(2.0)) / _kart_tuning.gravity_mps2 * float(Engine.physics_ticks_per_second))
	)
	for _frame in range(frames_to_peak):
		await wait_physics_frames(1)
		if not is_instance_valid(bomb):
			break
		peak_y = maxf(peak_y, bomb.global_position.y)

	assert_gt(peak_y, 0.0, "a real ballistic arc must climb above its own launch height")
	if not is_instance_valid(bomb):
		return
	await wait_physics_frames(10)
	if not is_instance_valid(bomb):
		return
	assert_lt(
		bomb.global_position.y,
		peak_y,
		"real gravity must pull the bomb back down off its own peak"
	)


# ---------------------------------------------------------------------------
# ARM DELAY / LAUNCHER IMMUNITY, self-bomb, and multi-hit blast -- all three
# use an enlarged synthetic blast radius (see this file's own PRECISION NOTE).
# ---------------------------------------------------------------------------


func test_bomb_does_not_hit_an_overlapping_kart_before_arming_but_does_hit_it_after() -> void:
	var wide_tuning := _tuning_with({"bomb_blast_radius_m": 50.0})
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var follower := _new_kart_stub(Vector3.ZERO)
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure",
		session,
		launcher,
		wide_tuning,
		_kart_tuning,
		Callable(self, "_targets_for").bind(launcher, follower)
	)

	var margin_ratio := 0.2
	while (
		is_instance_valid(bomb)
		and float(bomb.get("_elapsed_s")) < wide_tuning.bomb_arm_delay_s * (1.0 - margin_ratio)
	):
		await wait_physics_frames(1)

	assert_true(is_instance_valid(bomb), "fixture sanity: the bomb must not have despawned before arming")
	if not is_instance_valid(bomb):
		return
	assert_eq(
		session.hit_calls.size(),
		0,
		"an overlapping kart must not be hit before bomb_arm_delay_s elapses"
	)

	var safety_frames := 60
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_true(session.hit_calls.has(follower), "once armed, an overlapping kart must be hit")
	assert_false(is_instance_valid(bomb), "a bomb must despawn the instant it explodes")


func test_self_bomb_hits_the_launcher_once_armed() -> void:
	var wide_tuning := _tuning_with({"bomb_blast_radius_m": 50.0})
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	# No OTHER kart at all -- the launcher itself is the only candidate,
	# sitting well within the enlarged blast radius the whole time (the
	# classic CTR "blew myself up" case).
	bomb.call(
		"configure",
		session,
		launcher,
		wide_tuning,
		_kart_tuning,
		Callable(self, "_targets_for").bind(launcher)
	)

	var safety_frames := 60
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(
		session.hit_calls.size(),
		1,
		"once armed, a bomb must hit even its own launcher -- classic CTR self-bomb"
	)
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], launcher)


func test_bomb_blast_hits_every_kart_within_radius_in_the_same_explosion() -> void:
	var wide_tuning := _tuning_with({"bomb_blast_radius_m": 50.0})
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var second := _new_kart_stub(Vector3(1.0, 0.0, 1.0))
	var third := _new_kart_stub(Vector3(-1.0, 0.0, -1.0))
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure",
		session,
		launcher,
		wide_tuning,
		_kart_tuning,
		Callable(self, "_targets_for").bind(launcher, second, third)
	)

	var safety_frames := 60
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(
		session.hit_calls.size(),
		3,
		"every kart within the blast radius must be hit in the SAME explosion, not just the first found"
	)
	assert_true(session.hit_calls.has(launcher))
	assert_true(session.hit_calls.has(second))
	assert_true(session.hit_calls.has(third))


func test_bomb_ignores_a_kart_outside_the_blast_radius() -> void:
	var wide_tuning := _tuning_with({"bomb_blast_radius_m": 50.0})
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var far_kart := _new_kart_stub(Vector3(0.0, 0.0, 5000.0))
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure",
		session,
		launcher,
		wide_tuning,
		_kart_tuning,
		Callable(self, "_targets_for").bind(launcher, far_kart)
	)

	var safety_frames := 60
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_true(session.hit_calls.has(launcher), "fixture sanity: the in-range launcher must still be hit")
	assert_false(
		session.hit_calls.has(far_kart),
		"a kart far outside the blast radius must never be hit, even in the same explosion"
	)


# ---------------------------------------------------------------------------
# Ground contact and lifetime -- both use the REAL, unmodified tuning.
# ---------------------------------------------------------------------------


func test_bomb_explodes_on_ground_contact_when_no_kart_is_ever_in_range() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure", session, launcher, _tuning, _kart_tuning, Callable(self, "_targets_for").bind(launcher)
	)

	var safety_frames := int(ceil(_tuning.beaker_lifetime_s * float(Engine.physics_ticks_per_second)))
	var frame_count := 0
	while is_instance_valid(bomb) and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_false(is_instance_valid(bomb), "a bomb with nobody in range must still despawn once it returns to ground height")
	assert_eq(session.hit_calls.size(), 0, "fixture sanity: the launcher was placed far out of blast range")
	var elapsed_s := float(frame_count) / float(Engine.physics_ticks_per_second)
	assert_lt(
		elapsed_s,
		_tuning.beaker_lifetime_s * 0.5,
		"ground contact must fire well before the lifetime safety net -- this is not just a timeout despawn"
	)


func test_bomb_despawns_at_beaker_lifetime_s_if_it_somehow_never_touches_ground_or_a_kart() -> void:
	# bomb_blast_radius_m near-zero AND bomb_speed_mps effectively zero would
	# never move at all, which would hit ground contact instantly (y <=
	# spawn_y is true even standing still) -- instead this fixture disables
	# gravity via a zero-gravity kart tuning copy, so the bomb flies straight
	# and level FOREVER and can only ever be caught by the lifetime cap.
	var level_kart_tuning := _kart_tuning.duplicate(true) as KartTuning
	level_kart_tuning.gravity_mps2 = 0.0
	var tiny_radius_tuning := _tuning_with({"bomb_blast_radius_m": 0.001})
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var bomb := _new_bomb(Vector3.ZERO)
	if bomb == null:
		return
	bomb.call(
		"configure",
		session,
		launcher,
		tiny_radius_tuning,
		level_kart_tuning,
		Callable(self, "_targets_for").bind(launcher)
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(tiny_radius_tuning.beaker_lifetime_s * physics_fps)) + 30
	var frame_count := 0
	while is_instance_valid(bomb) and frame_count < frames_needed:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(session.hit_calls.size(), 0, "fixture sanity: nothing was ever close enough to hit")
	assert_false(
		is_instance_valid(bomb),
		"a bomb that never touches ground or a kart must still despawn at beaker_lifetime_s (reused, no separate bomb_lifetime_s field)"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _targets_for(launcher: CharacterBody3D, second: Variant = null, third: Variant = null) -> Array:
	var result: Array = [{"kart": launcher, "progress": 0.0}]
	if second != null:
		result.append({"kart": second, "progress": 0.0})
	if third != null:
		result.append({"kart": third, "progress": 0.0})
	return result


func _new_bomb(origin: Vector3) -> Node3D:
	assert_true(ResourceLoader.exists(BOMB_SCENE_PATH), "the bomb graybox scene must exist")
	if not ResourceLoader.exists(BOMB_SCENE_PATH):
		return null
	var packed := load(BOMB_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var bomb := packed.instantiate() as Node3D
	assert_not_null(bomb)
	if bomb == null:
		return null
	bomb.position = origin
	add_child_autofree(bomb)
	return bomb


## A minimal, position-only stand-in for a real kart -- see test_missile.gd's
## identical helper doc for why this is sufficient (bomb.gd never calls any
## kart-specific method on a candidate directly).
func _new_kart_stub(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = origin
	add_child_autofree(body)
	return body


func _tuning_with(overrides: Dictionary) -> ItemTuning:
	var copy := _tuning.duplicate(true) as ItemTuning
	for field_name: String in overrides:
		copy.set(field_name, overrides[field_name])
	return copy
