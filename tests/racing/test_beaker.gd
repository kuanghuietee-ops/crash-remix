extends GutTest

# R4 Task 4 (CTR item loop): Beaker is a thin, STATIC Node3D hazard -- see
# beaker.gd's own class doc. Tested here with real physics ticks (add_
# child_autofree + wait_physics_frames, mirroring test_missile.gd's own
# FakeSession double, since beaker.gd shares the exact same duck-typed
# session/targets_getter contract missile.gd uses).

const BEAKER_SCENE_PATH := "res://scenes/racing/beaker.tscn"
const TUNING_PATH := "res://data/tuning/racing/items.tres"

var _tuning: ItemTuning


class FakeSession:
	extends RefCounted
	var hit_calls: Array = []

	func register_hit(target: Object) -> StringName:
		hit_calls.append(target)
		return &"spin_out"


func before_all() -> void:
	_tuning = load(TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- Task 2 registers it")


func test_beaker_scene_loads_and_instantiates_with_a_mesh() -> void:
	assert_true(ResourceLoader.exists(BEAKER_SCENE_PATH), "the beaker graybox scene must exist")
	if not ResourceLoader.exists(BEAKER_SCENE_PATH):
		return
	var beaker := _new_beaker(Vector3.ZERO)
	if beaker == null:
		return
	assert_not_null(beaker.get_node_or_null("Mesh"))


func test_beaker_never_moves_once_configured() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 100.0))
	var beaker := _new_beaker(Vector3(3.0, 0.0, -7.0))
	if beaker == null:
		return

	beaker.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher)
	)

	var origin := beaker.global_position
	await wait_physics_frames(30)

	assert_almost_eq(beaker.global_position.x, origin.x, 0.0001)
	assert_almost_eq(beaker.global_position.y, origin.y, 0.0001)
	assert_almost_eq(beaker.global_position.z, origin.z, 0.0001)


# ---------------------------------------------------------------------------
# Arm delay: no hit test runs against ANYONE until beaker_arm_delay_s.
# ---------------------------------------------------------------------------


func test_beaker_does_not_hit_a_nearby_kart_before_arming_but_does_hit_it_after() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 100.0))
	var follower := _new_kart_stub(Vector3.ZERO)
	var beaker := _new_beaker(Vector3.ZERO)
	if beaker == null:
		return

	beaker.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher, follower)
	)

	# Poll the beaker's own internal clock (see test_missile.gd's identical
	# rationale for why a frame-count is not trusted directly in this
	# harness) until it is most of the way toward arming but not yet there.
	var margin_ratio := 0.2
	while (
		is_instance_valid(beaker)
		and float(beaker.get("_elapsed_s")) < _tuning.beaker_arm_delay_s * (1.0 - margin_ratio)
	):
		await wait_physics_frames(1)

	assert_true(is_instance_valid(beaker), "fixture sanity: the beaker must not have despawned before arming")
	if not is_instance_valid(beaker):
		return
	assert_eq(
		session.hit_calls.size(),
		0,
		"a kart within hit radius must not be hit before beaker_arm_delay_s elapses"
	)

	var safety_frames := 60
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(session.hit_calls.size(), 1, "once armed, a kart within hit radius must be hit")
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], follower)
	assert_false(is_instance_valid(beaker), "a beaker must despawn the instant it hits someone")


func test_self_beaker_hits_the_launcher_once_armed() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3.ZERO)
	var beaker := _new_beaker(Vector3.ZERO)
	if beaker == null:
		return

	# No OTHER kart at all -- the launcher itself is the only nearby body,
	# sitting exactly on the beaker for this whole test (the classic
	# CTR "drove back over your own dropped beaker" case).
	beaker.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher)
	)

	var safety_frames := 120
	var frame_count := 0
	while session.hit_calls.size() == 0 and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(
		session.hit_calls.size(),
		1,
		"once armed, a beaker must hit even its own launcher -- classic CTR self-beaker"
	)
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], launcher)


# ---------------------------------------------------------------------------
# Lifetime expiry.
# ---------------------------------------------------------------------------


func test_beaker_despawns_at_its_own_lifetime_with_no_hit() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var beaker := _new_beaker(Vector3.ZERO)
	if beaker == null:
		return

	# No other kart at all, and the launcher is placed far out of hit
	# range -- nothing should ever be hit, so this beaker must despawn
	# purely from its own beaker_lifetime_s timer.
	beaker.call(
		"configure",
		session,
		launcher,
		_tuning,
		Callable(self, "_targets_for").bind(launcher)
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	# A generous frame count with margin, mirroring item_box.gd's own
	# respawn-timing test convention -- this loop only needs to prove
	# eventual despawn, not pin an exact tick.
	var frames_needed := int(ceil(_tuning.beaker_lifetime_s * physics_fps)) + 30
	var frame_count := 0
	while is_instance_valid(beaker) and frame_count < frames_needed:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(session.hit_calls.size(), 0, "fixture sanity: the launcher was placed far out of hit range")
	assert_false(is_instance_valid(beaker), "a beaker that never hits anyone must despawn at its own beaker_lifetime_s")


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


## Builds the Array[Dictionary] shape targets_getter must return -- see
## beaker.gd's own configure() doc. "progress" is never read by beaker.gd
## (see its own class doc's "spatial distance, not SpineFollower totals"
## rule), so a fixed placeholder is fine here.
func _targets_for(launcher: CharacterBody3D, follower: Variant = null) -> Array:
	var result: Array = [{"kart": launcher, "progress": 0.0}]
	if follower != null:
		result.append({"kart": follower, "progress": 0.0})
	return result


func _new_beaker(origin: Vector3) -> Node3D:
	assert_true(ResourceLoader.exists(BEAKER_SCENE_PATH), "the beaker graybox scene must exist")
	if not ResourceLoader.exists(BEAKER_SCENE_PATH):
		return null
	var packed := load(BEAKER_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var beaker := packed.instantiate() as Node3D
	assert_not_null(beaker)
	if beaker == null:
		return null
	beaker.position = origin
	add_child_autofree(beaker)
	return beaker


## A minimal, position-only stand-in for a real kart -- see test_missile.gd's
## identical helper doc for why this is sufficient (beaker.gd never calls
## any kart-specific method on a candidate directly).
func _new_kart_stub(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = origin
	add_child_autofree(body)
	return body
