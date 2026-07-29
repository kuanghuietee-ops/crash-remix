extends GutTest

const BUILDER_PATH := "res://src/gameplay/common/rail_curve_builder.gd"

func _markers_parent(points: Array[Vector3]) -> Node3D:
	var parent := Node3D.new()
	for point in points:
		var marker := Marker3D.new()
		marker.position = point
		parent.add_child(marker)
	add_child_autofree(parent)
	return parent

func test_straight_markers_stay_straight() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(0, 0, -192),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	assert_eq(curve.point_count, 3)
	var mid := curve.sample_baked(curve.get_baked_length() / 2.0)
	assert_almost_eq(mid.x, 0.0, 0.0001)

func test_corner_markers_get_catmull_rom_handles() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(-96, 0, -96),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	var expected_out := (Vector3(-96, 0, -96) - Vector3.ZERO) * (1.0 / 6.0)
	assert_almost_eq(curve.get_point_out(1).x, expected_out.x, 0.0001)
	assert_almost_eq(curve.get_point_out(1).z, expected_out.z, 0.0001)
	assert_eq(curve.get_point_in(1), -curve.get_point_out(1))
	assert_eq(curve.get_point_out(0), Vector3.ZERO)
