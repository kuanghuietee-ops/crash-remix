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

# CRITICAL-2: a 96m span next to a 6m span makes the naive Catmull-Rom
# handle (p[i+1]-p[i-1])*factor explode to ~17m -- more than double the
# length of the short 6m segment it's supposed to shape -- and the rail
# bows meters outside the authored arc. The standard non-uniform fix caps
# the handle length at min(prev_span, next_span) * 2 * factor, keeping the
# same direction.
func test_unequal_spacing_handle_is_clamped_to_the_shorter_span() -> void:
	var script: Script = load(BUILDER_PATH)
	var factor := 1.0 / 6.0
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(0, 0, -102),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, factor)
	var naive_out := (Vector3(0, 0, -102) - Vector3.ZERO) * factor
	assert_gt(
		naive_out.length(),
		6.0 * 2.0 * factor,
		"the naive formula must actually overshoot for this fixture, or the test proves nothing"
	)
	var out_handle := curve.get_point_out(1)
	assert_lte(
		out_handle.length(),
		6.0 * 2.0 * factor + 0.0001,
		"handle length must be capped at min(prev_span, next_span) * 2 * factor"
	)
	assert_eq(curve.get_point_in(1), -out_handle)


# The clamp must never fire when the naive handle is already inside the
# bound -- straight runs keep producing a straight rail.
func test_straight_markers_stay_straight_with_clamp_active() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(0, 0, -192),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	var expected_out := (Vector3(0, 0, -192) - Vector3.ZERO) * (1.0 / 6.0)
	assert_almost_eq(curve.get_point_out(1).x, expected_out.x, 0.0001)
	assert_almost_eq(curve.get_point_out(1).z, expected_out.z, 0.0001)


# Equal (but non-collinear) spans never need clamping either -- the naive
# handle's magnitude is bounded by prev_len+next_len via the triangle
# inequality, which never exceeds 2*L*factor when prev_len == next_len == L.
# This is the formula's existing behavior and must be unchanged.
func test_equal_span_corner_reduces_to_the_original_formula() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(-96, 0, -96),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0)
	var expected_out := (Vector3(-96, 0, -96) - Vector3.ZERO) * (1.0 / 6.0)
	assert_almost_eq(curve.get_point_out(1).x, expected_out.x, 0.0001)
	assert_almost_eq(curve.get_point_out(1).z, expected_out.z, 0.0001)
