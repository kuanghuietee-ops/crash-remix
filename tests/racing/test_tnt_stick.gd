extends GutTest

# CTR R6 Task 5 (new items): TntStick is a two-phase (&"grounded" then
# &"attached") thin Node3D hazard -- see tnt_stick.gd's own class doc.
# Tested here with real physics ticks (add_child_autofree + wait_physics_
# frames), mirroring test_beaker.gd's own FakeSession double for the
# grounded phase's shared beaker_* tuning fields, and using a duck-typed
# FakeHoppableKart double (a real CharacterBody3D declaring the exact same
# hop_pressed_edge/boost_tap_edge signal names and hop_pressed()/boost_tap()
# methods KartController does) for most of the attached phase's shake-off
# mechanism -- proving REAL hop presses route through the real signal-based
# wiring, not a private counter poked directly. test_kart_controller.gd's
# own hop_pressed_edge/boost_tap_edge tests prove the PRODUCER side (a real
# KartController really emits each); this file proves the CONSUMER side
# (tnt_stick.gd really connects to and decrements from both).
#
# Fix round 1 (reviewer [HIGH]): the double above is not enough to prove the
# one case that actually broke -- a REAL player mashing hop through the REAL
# RacingInputAdapter while already sliding. RacingInputAdapter.apply_hop_
# pressed() routes that press to boost_tap(), never hop_pressed(), a
# decision only a REAL KartController + DriftStateMachine pair can make
# correctly (a double cannot fake is_sliding() transitions credibly without
# re-implementing the drift FSM). The REAL-ADAPTER ROUTING section below
# uses a real, physically-grounded kart.tscn instance and the real
# RacingInputAdapter for exactly this reason.

const TNT_STICK_SCENE_PATH := "res://scenes/racing/tnt_stick.tscn"
const TUNING_PATH := "res://data/tuning/racing/items.tres"
const KART_SCENE_PATH := "res://scenes/racing/kart.tscn"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _tuning: ItemTuning
var _kart_tuning: KartTuning


class FakeSession:
	extends RefCounted
	var hit_calls: Array = []

	func register_hit(target: Object) -> StringName:
		hit_calls.append(target)
		return &"spin_out"


## Real Godot signals + hop_pressed()/boost_tap() methods under the SAME
## names KartController uses -- see this file's own class doc. is_sliding()
## is a plain settable stub (not a real drift FSM), fine for every test that
## drives this double directly by calling hop_pressed()/boost_tap() itself;
## the one thing a stub CANNOT credibly stand in for is a real adapter
## routing decision made FROM a real is_sliding() transition, which is
## exactly why the REAL-ADAPTER ROUTING section below uses a real kart
## instead of this double.
class FakeHoppableKart:
	extends CharacterBody3D
	signal hop_pressed_edge
	signal boost_tap_edge

	func hop_pressed() -> void:
		hop_pressed_edge.emit()

	func boost_tap() -> StringName:
		boost_tap_edge.emit()
		return &"ignored"

	func is_sliding() -> bool:
		return false


func before_all() -> void:
	_tuning = load(TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- R4 Task 2 registers it")
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load -- R1/R2 Task 1 registers it")


func test_tnt_stick_scene_loads_and_instantiates_with_a_mesh() -> void:
	assert_true(ResourceLoader.exists(TNT_STICK_SCENE_PATH), "the tnt_stick graybox scene must exist")
	if not ResourceLoader.exists(TNT_STICK_SCENE_PATH):
		return
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return
	assert_not_null(stick.get_node_or_null("Mesh"))


func test_tnt_stick_starts_grounded() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return
	stick.call("configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher))
	assert_eq(stick.call("phase"), &"grounded")


func test_tnt_stick_never_moves_while_grounded_with_nobody_nearby() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var stick := _new_tnt_stick(Vector3(3.0, 0.0, -7.0))
	if stick == null:
		return
	stick.call("configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher))

	var origin := stick.global_position
	await wait_physics_frames(30)

	assert_eq(stick.call("phase"), &"grounded", "fixture sanity: the far-away launcher must never trigger an attach")
	assert_almost_eq(stick.global_position.x, origin.x, 0.0001)
	assert_almost_eq(stick.global_position.z, origin.z, 0.0001)


# ---------------------------------------------------------------------------
# GROUNDED phase: arm delay gates the attach (reuses beaker_arm_delay_s/
# beaker_hit_radius_m -- see tnt_stick.gd's own class doc).
# ---------------------------------------------------------------------------


func test_tnt_stick_does_not_attach_before_arming_but_does_attach_once_armed() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var victim := _new_hoppable_kart(Vector3.ZERO)
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return
	stick.call(
		"configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher, victim)
	)

	var margin_ratio := 0.2
	while (
		is_instance_valid(stick)
		and float(stick.get("_elapsed_s")) < _tuning.beaker_arm_delay_s * (1.0 - margin_ratio)
	):
		await wait_physics_frames(1)

	assert_eq(stick.call("phase"), &"grounded", "must not attach before beaker_arm_delay_s elapses")

	var safety_frames := 60
	var frame_count := 0
	while stick.call("phase") == &"grounded" and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(stick.call("phase"), &"attached", "once armed, an overlapping kart must trigger an attach")
	assert_eq(stick.get("_attached_kart"), victim)


func test_tnt_stick_attaches_to_the_launcher_too_once_armed() -> void:
	var session := FakeSession.new()
	var launcher := _new_hoppable_kart(Vector3.ZERO)
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return
	# No OTHER kart at all -- the launcher itself is the only candidate,
	# sitting exactly on the stick the whole time (drove back into their
	# own dropped TNT).
	stick.call("configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher))

	var safety_frames := 60
	var frame_count := 0
	while stick.call("phase") == &"grounded" and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(
		stick.call("phase"),
		&"attached",
		"once armed, a TNT stick must attach to even its own launcher"
	)
	assert_eq(stick.get("_attached_kart"), launcher)


func test_tnt_stick_despawns_at_beaker_lifetime_s_if_never_contacted() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return
	stick.call("configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher))

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.beaker_lifetime_s * physics_fps)) + 30
	var frame_count := 0
	while is_instance_valid(stick) and frame_count < frames_needed:
		await wait_physics_frames(1)
		frame_count += 1

	assert_eq(session.hit_calls.size(), 0, "fixture sanity: the launcher was placed far out of hit range")
	assert_false(
		is_instance_valid(stick),
		"a TNT stick that never attaches to anyone must despawn at its own (reused) beaker_lifetime_s"
	)


# ---------------------------------------------------------------------------
# ATTACHED phase: follows the victim, fuse hits, shake-off escapes clean.
# ---------------------------------------------------------------------------


func test_tnt_stick_follows_the_attached_kart_every_tick() -> void:
	var fixture := await _attached_fixture()
	if fixture.is_empty():
		return
	var stick: Node3D = fixture["stick"]
	var victim: CharacterBody3D = fixture["victim"]

	victim.global_position = Vector3(12.0, 0.0, -8.0)
	await wait_physics_frames(1)

	assert_almost_eq(stick.global_position.x, victim.global_position.x, 0.0001)
	assert_almost_eq(stick.global_position.z, victim.global_position.z, 0.0001)


func test_tnt_stick_fuse_expiry_hits_the_victim_and_despawns() -> void:
	var fixture := await _attached_fixture()
	if fixture.is_empty():
		return
	var session: FakeSession = fixture["session"]
	var stick: Node3D = fixture["stick"]
	var victim: CharacterBody3D = fixture["victim"]

	# No shaking at all -- the fuse alone must be sufficient.
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.tnt_fuse_s * physics_fps)) + 5
	var frame_count := 0
	while is_instance_valid(stick) and frame_count < frames_needed:
		await wait_physics_frames(1)
		frame_count += 1

	assert_false(is_instance_valid(stick), "the stick must despawn once its own fuse expires")
	assert_eq(session.hit_calls.size(), 1, "fuse expiry must register exactly one hit")
	if session.hit_calls.size() > 0:
		assert_eq(session.hit_calls[0], victim)


func test_shaking_off_the_full_tuned_hop_count_before_the_fuse_despawns_harmlessly() -> void:
	var fixture := await _attached_fixture()
	if fixture.is_empty():
		return
	var session: FakeSession = fixture["session"]
	var stick: Node3D = fixture["stick"]
	var victim: CharacterBody3D = fixture["victim"]

	var shake_count := roundi(_tuning.tnt_shake_hops)
	assert_gt(shake_count, 0, "fixture sanity: the real tuning must author a positive shake count")
	for _hop_index in range(shake_count):
		victim.call("hop_pressed")
	await wait_physics_frames(1)

	assert_false(
		is_instance_valid(stick),
		"the full tuned hop count, all landed well before the fuse, must shake the stick off"
	)
	assert_eq(session.hit_calls.size(), 0, "a successful shake-off must never register a hit")


func test_shaking_off_one_hop_short_of_the_tuned_count_still_lets_the_fuse_hit() -> void:
	var fixture := await _attached_fixture()
	if fixture.is_empty():
		return
	var session: FakeSession = fixture["session"]
	var stick: Node3D = fixture["stick"]
	var victim: CharacterBody3D = fixture["victim"]

	var shake_count := roundi(_tuning.tnt_shake_hops)
	for _hop_index in range(shake_count - 1):
		victim.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(is_instance_valid(stick), "fixture sanity: one hop short of the tuned count must not shake it off yet")

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_tuning.tnt_fuse_s * physics_fps)) + 5
	var frame_count := 0
	while is_instance_valid(stick) and frame_count < frames_needed:
		await wait_physics_frames(1)
		frame_count += 1

	assert_false(is_instance_valid(stick))
	assert_eq(
		session.hit_calls.size(),
		1,
		"one hop short of the tuned shake count must still let the fuse hit the victim"
	)


func test_hop_presses_before_attachment_do_not_pre_arm_the_shake_counter() -> void:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var victim := _new_hoppable_kart(Vector3(0.0, 0.0, 500.0))
	var stick := _new_tnt_stick(Vector3(0.0, 0.0, 500.0))
	if stick == null:
		return
	# Mash hop many times BEFORE this stick has even been configured/armed --
	# the connection is only made at the instant of attach (_attach_to()), so
	# these earlier presses must have no effect on the shake budget once a
	# real attach eventually happens.
	var shake_count := roundi(_tuning.tnt_shake_hops)
	for _hop_index in range(shake_count * 2):
		victim.call("hop_pressed")

	stick.call(
		"configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher, victim)
	)
	var safety_frames := 60
	var frame_count := 0
	while stick.call("phase") == &"grounded" and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1
	assert_eq(stick.call("phase"), &"attached", "fixture sanity: the attach must still happen normally")

	assert_eq(
		int(stick.get("_shake_hops_remaining")),
		shake_count,
		"pre-attach hop presses must never have been counted -- the shake budget starts fresh at attach"
	)


## Fix round 1 (reviewer [HIGH]): proves the two signals are TRULY
## interchangeable toward the same budget, not just independently wired --
## alternates real hop_pressed()/boost_tap() calls on the same double.
func test_shake_off_counts_boost_tap_edge_presses_the_same_as_hop_pressed_edge() -> void:
	var fixture := await _attached_fixture()
	if fixture.is_empty():
		return
	var session: FakeSession = fixture["session"]
	var stick: Node3D = fixture["stick"]
	var victim: CharacterBody3D = fixture["victim"]

	var shake_count := roundi(_tuning.tnt_shake_hops)
	assert_gt(shake_count, 1, "fixture sanity: the real tuning must author more than one shake hop to alternate across")
	for hop_index in range(shake_count):
		if hop_index % 2 == 0:
			victim.call("hop_pressed")
		else:
			victim.call("boost_tap")
	await wait_physics_frames(1)

	assert_false(
		is_instance_valid(stick),
		"boost_tap_edge presses must count toward shake-off exactly like hop_pressed_edge presses"
	)
	assert_eq(session.hit_calls.size(), 0, "a successful shake-off must never register a hit")


# ---------------------------------------------------------------------------
# Fix round 1 (reviewer [HIGH]): REAL-ADAPTER ROUTING. Not the duck-typed
# FakeHoppableKart double above -- a REAL kart.tscn instance driven through
# a REAL DriftStateMachine into a REAL slide, then real presses routed
# through the REAL RacingInputAdapter.apply_hop_pressed(), the exact
# production call path a human's touch/gamepad HOP press takes (see race_
# session.gd's own _route_input()). This is what actually proves the bug is
# fixed: a double's own is_sliding() stub cannot credibly stand in for a
# real adapter ROUTING DECISION made from real drift-FSM state.
# ---------------------------------------------------------------------------


func test_shake_off_through_the_real_adapter_works_while_the_victim_is_sliding() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before arming a slide")

	# Arm a real slide (steer past threshold, then a grounded hop press --
	# same sequence test_kart_controller.gd's own slide-arming tests use),
	# then let it settle so a still-in-flight hop arc can't be mistaken for
	# the slide itself having ended.
	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(60)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside, and stay inside, a real slide")

	var setup := await _attach_stick_to_real_kart(kart)
	if setup.is_empty():
		return
	var session: FakeSession = setup["session"]
	var stick: Node3D = setup["stick"]
	assert_true(
		kart.call("is_sliding"),
		"fixture sanity: the victim must still be sliding once the real TNT stick has attached"
	)

	# Real presses through the REAL adapter -- every one of these routes to
	# boost_tap(), never hop_pressed(), because is_sliding() reads true (see
	# racing_input_adapter.gd's own apply_hop_pressed()). This is the exact
	# call this bug made unreachable before the fix.
	var adapter := RacingInputAdapter.new()
	var shake_count := roundi(_tuning.tnt_shake_hops)
	for _hop_index in range(shake_count):
		adapter.apply_hop_pressed(kart)
	await wait_physics_frames(1)

	assert_false(
		is_instance_valid(stick),
		"real adapter presses while sliding (routed to boost_tap()) must still shake the stick off"
	)
	assert_eq(session.hit_calls.size(), 0, "a successful shake-off must never register a hit")


## The non-sliding half of the same real-adapter path -- every press here
## routes to hop_pressed() instead, the branch that already worked before
## this fix; proven again here through the REAL adapter (not just the
## double) so both branches of apply_hop_pressed() are covered by the same
## rigor.
func test_shake_off_through_the_real_adapter_works_while_the_victim_is_not_sliding() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	await wait_physics_frames(10)
	assert_false(bool(kart.call("is_sliding")), "fixture sanity: a freshly-settled kart must not be sliding")

	var setup := await _attach_stick_to_real_kart(kart)
	if setup.is_empty():
		return
	var session: FakeSession = setup["session"]
	var stick: Node3D = setup["stick"]

	var adapter := RacingInputAdapter.new()
	var shake_count := roundi(_tuning.tnt_shake_hops)
	for _hop_index in range(shake_count):
		adapter.apply_hop_pressed(kart)
	await wait_physics_frames(1)

	assert_false(
		is_instance_valid(stick),
		"real adapter presses while NOT sliding (routed to hop_pressed()) must shake the stick off"
	)
	assert_eq(session.hit_calls.size(), 0, "a successful shake-off must never register a hit")


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _targets_for(launcher: CharacterBody3D, victim: Variant = null) -> Array:
	var result: Array = [{"kart": launcher, "progress": 0.0}]
	if victim != null:
		result.append({"kart": victim, "progress": 0.0})
	return result


func _new_tnt_stick(origin: Vector3) -> Node3D:
	assert_true(ResourceLoader.exists(TNT_STICK_SCENE_PATH), "the tnt_stick graybox scene must exist")
	if not ResourceLoader.exists(TNT_STICK_SCENE_PATH):
		return null
	var packed := load(TNT_STICK_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var stick := packed.instantiate() as Node3D
	assert_not_null(stick)
	if stick == null:
		return null
	stick.position = origin
	add_child_autofree(stick)
	return stick


func _new_kart_stub(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = origin
	add_child_autofree(body)
	return body


func _new_hoppable_kart(origin: Vector3) -> CharacterBody3D:
	var body := FakeHoppableKart.new()
	body.position = origin
	add_child_autofree(body)
	return body


## Boots a session/launcher/victim/stick and drives it all the way to
## &"attached" -- the shared setup every ATTACHED-phase test below needs.
## Returns {} (empty) if any fixture step failed, matching every other
## helper's own "if x == null: return" early-out shape one level up.
func _attached_fixture() -> Dictionary:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var victim := _new_hoppable_kart(Vector3.ZERO)
	var stick := _new_tnt_stick(Vector3.ZERO)
	if stick == null:
		return {}
	stick.call(
		"configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher, victim)
	)

	var safety_frames := 60
	var frame_count := 0
	while stick.call("phase") == &"grounded" and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1
	assert_eq(stick.call("phase"), &"attached", "fixture sanity: the attach must succeed")
	if stick.call("phase") != &"attached":
		return {}

	return {"session": session, "launcher": launcher, "victim": victim, "stick": stick}


## A real, physically-grounded kart.tscn instance -- see this file's own
## REAL-ADAPTER ROUTING doc for why the fix-round-1 tests need one instead
## of FakeHoppableKart. Mirrors test_kart_controller.gd's own _spawn_kart_
## on_floor() helper exactly (same floor size/offset/settle-drop shape).
func _spawn_kart_on_floor(origin: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed, "the kart graybox scene must exist")
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


## Attaches a real TNT stick to the given REAL kart (already positioned
## wherever the caller wants, e.g. mid-slide on a real floor) -- the shared
## setup the REAL-ADAPTER ROUTING tests need, distinct from _attached_
## fixture() above which always builds its own FakeHoppableKart double.
##
## Freezes the victim's own _physics_process for the arm-delay window:
## every real kart auto-throttles forward under its own _physics_process
## even at zero steer, which would otherwise drive it clean away from this
## STATIC drop point before beaker_arm_delay_s (real tuning: 0.7s, tens of
## physics ticks) ever elapses. Left frozen afterward, deliberately not
## re-enabled -- apply_hop_pressed()/hop_pressed()/boost_tap() are all
## plain method calls, never gated on _physics_process being active, so the
## shake-off mechanism under test needs no further ticking from the kart at
## all once attached.
func _attach_stick_to_real_kart(victim: CharacterBody3D) -> Dictionary:
	var session := FakeSession.new()
	var launcher := _new_kart_stub(Vector3(0.0, 0.0, 1000.0))
	var stick := _new_tnt_stick(victim.global_position)
	if stick == null:
		return {}
	victim.set_physics_process(false)
	stick.call(
		"configure", session, launcher, _tuning, Callable(self, "_targets_for").bind(launcher, victim)
	)

	var safety_frames := 60
	var frame_count := 0
	while stick.call("phase") == &"grounded" and frame_count < safety_frames:
		await wait_physics_frames(1)
		frame_count += 1
	assert_eq(stick.call("phase"), &"attached", "fixture sanity: the attach to the real kart must succeed")
	if stick.call("phase") != &"attached":
		return {}

	return {"session": session, "launcher": launcher, "stick": stick}
