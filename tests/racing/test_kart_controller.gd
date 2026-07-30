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


func _spawn_kart_on_floor() -> CharacterBody3D:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null

	var root := Node3D.new()
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
