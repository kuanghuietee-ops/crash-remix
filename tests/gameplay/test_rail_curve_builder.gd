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


# ---------------------------------------------------------------------------
# Task 6 (CTR racing mode): closed=true wraps handle neighbors around the
# loop and duplicates the first marker as a final seam point (Curve3D has no
# closed flag). Every test below passes closed=true explicitly; the tests
# above never pass a 4th argument at all, proving the new optional parameter
# defaults to false and leaves every existing (platformer) call site's
# behavior byte-for-byte unchanged.
# ---------------------------------------------------------------------------


func _square_loop_parent() -> Node3D:
	return _markers_parent([
		Vector3(0, 0, 0), Vector3(96, 0, 0), Vector3(96, 0, -96), Vector3(0, 0, -96),
	])


func test_closed_loop_appends_seam_point_duplicating_the_first_marker() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _square_loop_parent()
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0, true)
	assert_eq(curve.point_count, 5, "4 markers + 1 duplicated seam point")
	assert_eq(curve.get_point_position(4), curve.get_point_position(0))


func test_closed_loop_baked_length_exceeds_open_polyline() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _square_loop_parent()
	var factor := 1.0 / 6.0
	var open_curve: Curve3D = script.call("curve_from_markers", parent, 0.2, factor)
	var closed_curve: Curve3D = script.call("curve_from_markers", parent, 0.2, factor, true)
	assert_gt(
		closed_curve.get_baked_length(),
		open_curve.get_baked_length(),
		"closing the loop must bake the extra segment back to the start"
	)


func test_closed_loop_seam_in_handle_mirrors_first_point_out_handle() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _square_loop_parent()
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0, true)
	var seam_index := curve.point_count - 1
	assert_eq(curve.get_point_in(seam_index), -curve.get_point_out(0))


func test_closed_loop_first_point_in_handle_mirrors_seam() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _square_loop_parent()
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0, true)
	var seam_index := curve.point_count - 1
	assert_eq(
		curve.get_point_in(0),
		curve.get_point_in(seam_index),
		"point 0 and the seam are the same physical location -- their in-handles must match"
	)


func test_closed_loop_tangent_is_continuous_across_the_seam() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _square_loop_parent()
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0, true)
	var length := curve.get_baked_length()
	var step := 1.0
	var tangent_start := (
		curve.sample_baked(step) - curve.sample_baked(0.0)
	).normalized()
	var tangent_end := (
		curve.sample_baked(length) - curve.sample_baked(length - step)
	).normalized()
	assert_almost_eq(
		tangent_start.x,
		tangent_end.x,
		0.05,
		"no visible kink at the seam: the tangent leaving offset 0 and the "
		+ "tangent arriving at the full baked length must roughly agree"
	)
	assert_almost_eq(tangent_start.z, tangent_end.z, 0.05)


func test_closed_loop_first_and_last_marker_handles_use_wrapped_neighbors() -> void:
	var script: Script = load(BUILDER_PATH)
	var factor := 1.0 / 6.0
	var parent := _markers_parent([
		Vector3.ZERO, Vector3(0, 0, -96), Vector3(-96, 0, -96),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, factor, true)
	# index 0's neighbors wrap: prev = the LAST marker (index 2), next stays
	# marker 1 -- the binding interface's "first point's handle uses last
	# marker as prev".
	var expected_out_0 := (Vector3(0, 0, -96) - Vector3(-96, 0, -96)) * factor
	assert_almost_eq(curve.get_point_out(0).x, expected_out_0.x, 0.0001)
	assert_almost_eq(curve.get_point_out(0).z, expected_out_0.z, 0.0001)
	assert_eq(curve.get_point_in(0), -curve.get_point_out(0))
	# The last marker's neighbors wrap the other way: prev stays marker 1,
	# next wraps to the FIRST marker -- "last uses first as next".
	var expected_out_2 := (Vector3.ZERO - Vector3(0, 0, -96)) * factor
	assert_almost_eq(curve.get_point_out(2).x, expected_out_2.x, 0.0001)
	assert_almost_eq(curve.get_point_out(2).z, expected_out_2.z, 0.0001)
	assert_eq(curve.get_point_in(2), -curve.get_point_out(2))


# CRITICAL-2's non-uniform clamp (see above) must still fire at the wrap
# points of a closed loop, not just at open-curve interior points: a short
# gate-to-start closing segment next to two long straights must not bow the
# rail meters outside the authored loop any more than an interior corner
# would.
func test_closed_loop_clamp_still_applies_at_wrap_points() -> void:
	var script: Script = load(BUILDER_PATH)
	var factor := 1.0 / 6.0
	var parent := _markers_parent([
		Vector3(0, 0, 0), Vector3(96, 0, 0), Vector3(0, 0, 6),
	])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, factor, true)
	var bound := 6.0 * 2.0 * factor
	var naive_out_first := (Vector3(96, 0, 0) - Vector3(0, 0, 6)) * factor
	assert_gt(
		naive_out_first.length(),
		bound,
		"the naive formula must actually overshoot at the wrap, or the test proves nothing"
	)
	assert_lte(curve.get_point_out(0).length(), bound + 0.0001)
	var naive_out_last := (Vector3(0, 0, 0) - Vector3(96, 0, 0)) * factor
	assert_gt(
		naive_out_last.length(),
		bound,
		"the naive formula must actually overshoot at the wrap for the last marker too"
	)
	assert_lte(curve.get_point_out(2).length(), bound + 0.0001)


func test_closed_loop_with_two_markers_does_not_crash() -> void:
	var script: Script = load(BUILDER_PATH)
	var parent := _markers_parent([Vector3.ZERO, Vector3(0, 0, -96)])
	var curve: Curve3D = script.call("curve_from_markers", parent, 0.2, 1.0 / 6.0, true)
	assert_eq(curve.point_count, 3, "2 markers + 1 duplicated seam point")
