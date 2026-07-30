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
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return

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
		return
	kart.position = Vector3(0.0, 0.2, 0.0)
	root.add_child(kart)
	kart.call("configure", _kart_tuning)
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
