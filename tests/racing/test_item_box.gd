extends GutTest

# R4 Task 3 (CTR item loop): ItemBox is a self-contained Area3D pickup --
# hides + starts its own box_respawn_s countdown on a kart entering it, then
# reappears -- see item_box.gd's own class doc. Mirrors test_checkpoint_
# gate.gd's "load the raw script, prove the node-level contract" shape for
# the monitoring-defaults test, and test_kart_controller.gd's "spawn a real
# body, let real physics detect the overlap" shape for the pickup/respawn
# cycle tests.

const BOX_SCRIPT_PATH := "res://src/racing/items/item_box.gd"
const BOX_SCENE_PATH := "res://scenes/racing/item_box.tscn"
const TUNING_PATH := "res://data/tuning/racing/items.tres"

var _tuning: ItemTuning


func before_all() -> void:
	_tuning = load(TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- Task 2 registers it")


# ---------------------------------------------------------------------------
# Monitoring defaults (mirrors test_checkpoint_gate.gd exactly).
# ---------------------------------------------------------------------------


func test_box_forces_monitoring_on_and_monitorable_off() -> void:
	var box: Area3D = load(BOX_SCRIPT_PATH).new()
	box.monitoring = false
	box.monitorable = true
	add_child_autofree(box)

	assert_true(box.monitoring, "_ready() must force monitoring on")
	assert_false(box.monitorable, "_ready() must force monitorable off")


func test_box_is_active_by_default() -> void:
	var box: Area3D = load(BOX_SCRIPT_PATH).new()
	add_child_autofree(box)
	assert_true(bool(box.call("is_active")))


# ---------------------------------------------------------------------------
# Scene wiring.
# ---------------------------------------------------------------------------


func test_box_scene_loads_and_instantiates_with_collision_and_mesh() -> void:
	assert_true(ResourceLoader.exists(BOX_SCENE_PATH), "the item box graybox scene must exist")
	if not ResourceLoader.exists(BOX_SCENE_PATH):
		return
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	assert_not_null(box.get_node_or_null("CollisionShape3D"))
	assert_not_null(box.get_node_or_null("Mesh"))


func test_configure_applies_box_pickup_radius_m_to_the_pickup_shape() -> void:
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	box.call("configure", _tuning)

	var collision := box.get_node("CollisionShape3D") as CollisionShape3D
	var sphere := collision.shape as SphereShape3D
	assert_not_null(sphere, "the pickup shape must be (and stay) a SphereShape3D")
	if sphere == null:
		return
	assert_almost_eq(sphere.radius, _tuning.box_pickup_radius_m, 0.0001)


## Regression lock: configure() must never mutate the SHARED sub-resource
## every ItemBox instance of this PackedScene starts out pointing at (see
## item_box.gd's own configure() doc) -- a second, unconfigured box's own
## shape must be unaffected by a first box's configure() call.
func test_configure_does_not_leak_the_radius_into_a_different_box_instance() -> void:
	var configured_box := _new_box(Vector3.ZERO)
	var other_box := _new_box(Vector3(50.0, 0.0, 0.0))
	if configured_box == null or other_box == null:
		return
	var other_collision := other_box.get_node("CollisionShape3D") as CollisionShape3D
	var other_sphere := other_collision.shape as SphereShape3D
	assert_not_null(other_sphere)
	if other_sphere == null:
		return
	var original_radius := other_sphere.radius

	configured_box.call("configure", _tuning)

	assert_almost_eq(
		other_sphere.radius,
		original_radius,
		0.0001,
		"configuring one box must not resize a DIFFERENT box's own pickup shape"
	)


# ---------------------------------------------------------------------------
# Real-physics pickup + respawn cycle.
# ---------------------------------------------------------------------------


## Regression lock for a real bug caught while building this suite: a
## ground-level box's own box_pickup_radius_m-sized SphereShape3D reaches
## into the floor/walls beneath it, which -- like every graybox StaticBody3D
## in this repo's own track scenes -- set no explicit collision_layer and so
## default to Godot's own layer 1, the exact same layer a plain mask=1
## filter would also match. See item_box.gd's own class doc BODY FILTER
## section: collision_mask = 4 (kart-only bit 3) exists specifically so a
## body on the plain environment layer alone can never trigger a pickup,
## even sitting well inside the box's own radius.
func test_a_body_on_the_plain_environment_layer_never_triggers_a_pickup() -> void:
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	box.call("configure", _tuning)

	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 10.0, 10.0)
	collision.shape = shape
	floor_body.add_child(collision)
	# collision_layer left at Godot's own CollisionObject3D default (1) --
	# deliberately unset, exactly like every graybox floor/wall StaticBody3D
	# in track_graybox_loop.tscn/track_sanity_shores.tscn.
	add_child_autofree(floor_body)

	await wait_physics_frames(5)

	assert_true(
		bool(box.call("is_active")),
		"a body on the plain environment layer (no kart bit) must never trigger a pickup"
	)


func test_kart_entering_the_box_hides_it_and_marks_it_inactive() -> void:
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	box.call("configure", _tuning)
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_true(bool(box.call("is_active")), "fixture setup: the box must start active")

	kart.global_position = box.global_position
	await wait_physics_frames(2)

	assert_false(bool(box.call("is_active")), "a kart pickup must mark the box inactive")
	assert_false(box.visible, "a picked-up box must hide its own visual")
	assert_false(box.monitoring, "a picked-up box must stop monitoring further overlaps")


func test_box_stays_inactive_before_box_respawn_s_elapses() -> void:
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	box.call("configure", _tuning)
	var kart := _new_kart_body(box.global_position)
	await wait_physics_frames(2)
	assert_false(bool(box.call("is_active")), "fixture setup: the pickup must have registered")

	# Move the kart well clear so it can never re-trigger a pickup while
	# this test waits out most of the countdown.
	kart.global_position = Vector3(500.0, 0.0, 0.0)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 5
	var frames_short_of_respawn := int(floor(_tuning.box_respawn_s * physics_fps)) - margin_frames
	assert_gt(frames_short_of_respawn, 0, "fixture sanity: box_respawn_s must be several frames long")
	if frames_short_of_respawn <= 0:
		return
	await wait_physics_frames(frames_short_of_respawn)

	assert_false(bool(box.call("is_active")), "must not reappear before box_respawn_s has elapsed")


func test_box_reappears_after_box_respawn_s_elapses() -> void:
	var box := _new_box(Vector3.ZERO)
	if box == null:
		return
	box.call("configure", _tuning)
	var kart := _new_kart_body(box.global_position)
	await wait_physics_frames(2)
	assert_false(bool(box.call("is_active")), "fixture setup: the pickup must have registered")

	# Move the kart well clear before the countdown finishes -- see item_box.
	# gd's own class doc for why a kart still parked on the pickup at the
	# exact moment it reappears is a separate, deliberately accepted edge
	# case this test does not need to also exercise.
	kart.global_position = Vector3(500.0, 0.0, 0.0)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 5
	var frames_needed := int(ceil(_tuning.box_respawn_s * physics_fps)) + margin_frames
	await wait_physics_frames(frames_needed)

	assert_true(bool(box.call("is_active")), "must reappear once box_respawn_s has elapsed")
	assert_true(box.visible, "a reappeared box must show its visual again")
	assert_true(box.monitoring, "a reappeared box must resume monitoring for the next pickup")


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_box(origin: Vector3) -> Area3D:
	var packed := load(BOX_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var box := packed.instantiate() as Area3D
	assert_not_null(box)
	if box == null:
		return null
	# LOCAL position, set BEFORE add_child_autofree -- see _new_kart_body's
	# own doc for why: this box is parented directly under this GutTest
	# instance with no intervening Node3D transform, so local position and
	# global position coincide here, and setting it before the node enters
	# the tree means the physics server never registers this Area3D at the
	# (0,0,0) default for even one frame before it "moves" to origin.
	box.position = origin
	add_child_autofree(box)
	return box


## A minimal stand-in for kart.tscn's own CharacterBody3D -- collision_layer
## = 5 to match kart.tscn exactly (see kart.tscn's own [node name="Kart"]
## and item_box.gd's own class doc BODY FILTER section for why bit 3/value
## 4 specifically, not just bit 1): item_box.tscn's own collision_mask = 4
## only detects bodies carrying that bit, which the real graybox floor/
## walls (plain Godot defaults, collision_layer = 1) never do -- a fixture
## kart body without bit 3 would never be detected by the box at all. No
## motor/controller needed: an Area3D detects any overlapping body by its
## current transform each physics step.
##
## POSITION SET BEFORE add_child_autofree (LOCAL position, not global,
## exactly like _new_box() above -- discovered empirically while chasing a
## flaky false pickup): a CharacterBody3D added to the tree at its (0,0,0)
## default and repositioned only AFTER can still register a transient
## body_entered against a box already sitting at the origin -- Godot/Jolt
## can queue the overlap event from that one-instant default placement for
## delivery on a LATER physics frame, well after this fixture's own
## global_position write has already moved it away, permanently (and
## incorrectly) marking the box picked-up. Setting position first means the
## body's very first tree-entry transform is already its intended one, so
## there is no (0,0,0) instant to spuriously overlap during.
func _new_kart_body(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 5
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 0.6, 2.0)
	collision.shape = shape
	body.add_child(collision)
	body.position = origin
	add_child_autofree(body)
	return body
