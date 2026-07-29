extends GutTest

# Task 7 (turns-camera-difficulty plan): the three reusable corner-arc
# segments. Local frame for every scene: entry heading -Z at the origin.
# Geometry is the eighth/quarter arc described in
# docs/superpowers/plans/2026-07-29-turns-camera-difficulty.md Task 7.

const CORNER_LEFT_90_PATH := "res://scenes/segments/corner_left_90.tscn"
const SWERVE_LEFT_45_PATH := "res://scenes/segments/swerve_left_45.tscn"
const SWERVE_RIGHT_45_PATH := "res://scenes/segments/swerve_right_45.tscn"
const POSITION_TOLERANCE_M := 0.01

const ARC_RADIUS_M := 12.0
const CORNER_LEFT_90_EXIT := Vector3(-12.0, 0.0, -12.0)
const CORNER_LEFT_90_MID_30 := Vector3(-1.607695, 0.0, -6.0)
const CORNER_LEFT_90_MID_60 := Vector3(-6.0, 0.0, -10.392305)
const SWERVE_LEFT_45_EXIT := Vector3(-3.514719, 0.0, -8.485281)
const SWERVE_LEFT_45_MID_15 := Vector3(-0.408886, 0.0, -3.105829)
const SWERVE_LEFT_45_MID_30 := Vector3(-1.607695, 0.0, -6.0)
const SWERVE_RIGHT_45_EXIT := Vector3(3.514719, 0.0, -8.485281)
const SWERVE_RIGHT_45_MID_15 := Vector3(0.408886, 0.0, -3.105829)
const SWERVE_RIGHT_45_MID_30 := Vector3(1.607695, 0.0, -6.0)


func test_corner_left_90_spine_and_floor() -> void:
	var scene := _instantiate(CORNER_LEFT_90_PATH)
	if scene == null:
		return
	add_child_autofree(scene)

	_assert_spine(scene, Vector3.ZERO, CORNER_LEFT_90_EXIT)
	_assert_marker_on_arc(
		scene, "Spine/Mid30", CORNER_LEFT_90_MID_30, Vector3(-12, 0, 0)
	)
	_assert_marker_on_arc(
		scene, "Spine/Mid60", CORNER_LEFT_90_MID_60, Vector3(-12, 0, 0)
	)
	_assert_floor_slab_count(scene, 6)


func test_swerve_left_45_spine_and_floor() -> void:
	var scene := _instantiate(SWERVE_LEFT_45_PATH)
	if scene == null:
		return
	add_child_autofree(scene)

	_assert_spine(scene, Vector3.ZERO, SWERVE_LEFT_45_EXIT)
	_assert_marker_on_arc(
		scene, "Spine/Mid15", SWERVE_LEFT_45_MID_15, Vector3(-12, 0, 0)
	)
	_assert_marker_on_arc(
		scene, "Spine/Mid30", SWERVE_LEFT_45_MID_30, Vector3(-12, 0, 0)
	)
	_assert_floor_slab_count(scene, 3)


func test_swerve_right_45_spine_and_floor() -> void:
	var scene := _instantiate(SWERVE_RIGHT_45_PATH)
	if scene == null:
		return
	add_child_autofree(scene)

	_assert_spine(scene, Vector3.ZERO, SWERVE_RIGHT_45_EXIT)
	_assert_marker_on_arc(
		scene, "Spine/Mid15", SWERVE_RIGHT_45_MID_15, Vector3(12, 0, 0)
	)
	_assert_marker_on_arc(
		scene, "Spine/Mid30", SWERVE_RIGHT_45_MID_30, Vector3(12, 0, 0)
	)
	_assert_floor_slab_count(scene, 3)


func test_all_three_scenes_carry_a_default_camera_region() -> void:
	for path: String in [
		CORNER_LEFT_90_PATH, SWERVE_LEFT_45_PATH, SWERVE_RIGHT_45_PATH
	]:
		var scene := _instantiate(path)
		if scene == null:
			continue
		add_child_autofree(scene)
		var region := scene.get_node_or_null("CameraRegion") as Area3D
		assert_not_null(region, "%s must carry a CameraRegion" % path)
		if region == null:
			continue
		assert_eq(region.get("camera_mode"), &"default", path)
		assert_true(
			region.get_node_or_null("CollisionShape3D") is CollisionShape3D,
			path
		)


func _assert_spine(scene: Node, entry_local: Vector3, exit_local: Vector3) -> void:
	var entry := scene.get_node_or_null("Spine/Entry") as Marker3D
	var exit_marker := scene.get_node_or_null("Spine/Exit") as Marker3D
	assert_not_null(entry, "%s must have Spine/Entry" % scene.scene_file_path)
	assert_not_null(exit_marker, "%s must have Spine/Exit" % scene.scene_file_path)
	if entry == null or exit_marker == null:
		return
	_assert_vector3_near(
		entry.position, entry_local, POSITION_TOLERANCE_M, "Spine/Entry"
	)
	_assert_vector3_near(
		exit_marker.position, exit_local, POSITION_TOLERANCE_M, "Spine/Exit"
	)


func _assert_marker_on_arc(
	scene: Node,
	node_path: String,
	expected_local: Vector3,
	arc_center_local: Vector3
) -> void:
	var marker := scene.get_node_or_null(node_path) as Marker3D
	assert_not_null(marker, "%s missing %s" % [scene.scene_file_path, node_path])
	if marker == null:
		return
	_assert_vector3_near(
		marker.position, expected_local, POSITION_TOLERANCE_M, node_path
	)
	assert_almost_eq(
		marker.position.distance_to(arc_center_local),
		ARC_RADIUS_M,
		POSITION_TOLERANCE_M,
		"%s must sit on the arc centerline" % node_path
	)


func _assert_floor_slab_count(scene: Node, expected_minimum: int) -> void:
	var slabs: Array[Node] = scene.find_children(
		"*", "StaticBody3D", true, false
	)
	var graybox_slabs: Array[Node] = []
	for slab: Node in slabs:
		if slab is GrayboxPlatform:
			graybox_slabs.append(slab)
	assert_gte(
		graybox_slabs.size(),
		1,
		"%s must have at least one floor slab" % scene.scene_file_path
	)
	assert_eq(
		graybox_slabs.size(),
		expected_minimum,
		"%s authored slab count" % scene.scene_file_path
	)


func _assert_vector3_near(
	actual: Vector3, expected: Vector3, tolerance: float, label: String
) -> void:
	assert_almost_eq(actual.x, expected.x, tolerance, label + " x")
	assert_almost_eq(actual.y, expected.y, tolerance, label + " y")
	assert_almost_eq(actual.z, expected.z, tolerance, label + " z")


func _instantiate(path: String) -> Node:
	var packed: PackedScene = load(path)
	assert_not_null(packed, path + " must load")
	return packed.instantiate() if packed != null else null
