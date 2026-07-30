extends GutTest

# Task 6 (CTR racing mode): TrackSpine is a closed Path3D helper built on
# top of the shared RailCurveBuilder's new closed=true support (see
# rail_curve_builder.gd and tests/gameplay/test_rail_curve_builder.gd) --
# progress_for_position()/tangent_at_progress()/is_wrong_way() are what
# Task 7's race session and HUD read every frame. See track_spine.gd's
# class doc and .superpowers/sdd/2026-07-30-ctr-r1-r2-kart-and-circuit/
# task-6-brief.md.

const SPINE_PATH := "res://src/racing/track/track_spine.gd"
const CAMERA_TUNING_PATH := "res://data/tuning/camera.tres"

# An L-shaped closed loop (mirrors the "L-shaped rail, unequal spacing"
# fixture style already used in tests/gameplay/test_camera_rail_controller.
# gd): down the left leg, a step in, then back across the top to close the
# loop. Straight legs everywhere make the polyline-fallback geometry (see
# track_spine.gd's class doc on the pre-configure()/no-tuning build) exact
# to compute by hand, which is what the round-trip and tangent assertions
# below depend on.
const _POINTS: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(0, 0, -100),
	Vector3(50, 0, -100),
	Vector3(50, 0, -50),
	Vector3(100, 0, -50),
	Vector3(100, 0, 0),
]


func _spine_with_markers(points: Array[Vector3]) -> Node3D:
	var spine: Node3D = load(SPINE_PATH).new()
	for point in points:
		var marker := Marker3D.new()
		marker.position = point
		spine.add_child(marker)
	add_child_autofree(spine)
	return spine


# ---------------------------------------------------------------------------
# Progress round-trip: a point authored partway along a straight leg must
# report a closest-offset close to its actual authored distance from the
# start.
# ---------------------------------------------------------------------------


func test_progress_for_position_round_trips_a_point_on_a_straight_leg() -> void:
	var spine := _spine_with_markers(_POINTS)

	# 30m down the first leg (A -> B runs along -Z, length 100).
	var offset: float = spine.call("progress_for_position", Vector3(0, 0, -30))

	assert_almost_eq(offset, 30.0, 0.01)


func test_progress_for_position_round_trips_a_point_past_the_first_corner() -> void:
	var spine := _spine_with_markers(_POINTS)

	# 20m along the second leg (B -> C, length 50): 100 (leg 1) + 20.
	var offset: float = spine.call("progress_for_position", Vector3(20, 0, -100))

	assert_almost_eq(offset, 120.0, 0.01)


# ---------------------------------------------------------------------------
# Tangent direction on a straight section.
# ---------------------------------------------------------------------------


func test_tangent_at_progress_points_along_the_straight_leg() -> void:
	var spine := _spine_with_markers(_POINTS)

	var tangent: Vector3 = spine.call("tangent_at_progress", 30.0)

	assert_true(
		tangent.is_equal_approx(Vector3(0, 0, -1)),
		"expected (0,0,-1) along leg A->B, got %s" % tangent
	)


# ---------------------------------------------------------------------------
# Wrong-way flag: sign flips with the direction of travel.
# ---------------------------------------------------------------------------


func test_is_wrong_way_false_when_moving_with_the_tangent() -> void:
	var spine := _spine_with_markers(_POINTS)

	var forward_velocity := Vector3(0, 0, -5)

	assert_false(spine.call("is_wrong_way", forward_velocity, 30.0))


func test_is_wrong_way_true_when_moving_against_the_tangent() -> void:
	var spine := _spine_with_markers(_POINTS)

	var backward_velocity := Vector3(0, 0, 5)

	assert_true(spine.call("is_wrong_way", backward_velocity, 30.0))


# ---------------------------------------------------------------------------
# length_m(): the closed loop's baked length must include the closing
# segment back to the start, not just the authored legs.
# ---------------------------------------------------------------------------


func test_length_m_includes_the_closing_segment_back_to_the_start() -> void:
	var spine := _spine_with_markers(_POINTS)

	var perimeter := (
		_POINTS[0].distance_to(_POINTS[1])
		+ _POINTS[1].distance_to(_POINTS[2])
		+ _POINTS[2].distance_to(_POINTS[3])
		+ _POINTS[3].distance_to(_POINTS[4])
		+ _POINTS[4].distance_to(_POINTS[5])
		+ _POINTS[5].distance_to(_POINTS[0])
	)

	assert_almost_eq(float(spine.call("length_m")), perimeter, 0.01)


# ---------------------------------------------------------------------------
# configure(): mirrors camera_rail_controller.gd's
# test_configure_after_ready_rebuilds_the_rail_with_real_tuning -- _ready()
# always fires before Task 7's session can call configure(), building a
# zero-handle polyline fallback first; configure() must then actually
# reshape the curve with the real tuning, not silently keep the fallback.
# ---------------------------------------------------------------------------


func test_configure_after_ready_rebuilds_with_real_camera_tuning() -> void:
	var camera_tuning: CameraTuning = load(CAMERA_TUNING_PATH)
	assert_not_null(camera_tuning, "camera.tres must load")
	if camera_tuning == null:
		return

	var spine: Node3D = load(SPINE_PATH).new()
	for point in _POINTS:
		var marker := Marker3D.new()
		marker.position = point
		spine.add_child(marker)
	# Entering the tree fires _ready() with no tuning configured yet,
	# reproducing the real add-before-configure scene order.
	add_child_autofree(spine)

	var path := spine as Path3D
	assert_not_null(path.curve, "the pre-configure _ready() build must run")
	assert_eq(
		path.curve.get_point_out(1),
		Vector3.ZERO,
		"before configure(), the fallback build has zero-length handles"
	)

	spine.call("configure", camera_tuning)

	assert_false(
		path.curve.get_point_out(1).is_zero_approx(),
		"configure() must reshape the curve with the real tuning's "
		+ "rail_handle_length_factor, not keep the flat fallback"
	)
