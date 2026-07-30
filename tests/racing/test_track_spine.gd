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


# ---------------------------------------------------------------------------
# point_at_progress(): Task 4 (CTR R3: AI opponents) addition -- AiKartAgent
# needs a global-space "where on the spine is progress X" sample for its
# lookahead point, its own lateral-offset centerline reference, and the
# stuck-respawn teleport target (see ai_kart_agent.gd's class doc). Mirrors
# tangent_at_progress()'s existing local-to-global transform shape.
# ---------------------------------------------------------------------------


func test_point_at_progress_round_trips_a_point_on_a_straight_leg() -> void:
	var spine := _spine_with_markers(_POINTS)

	var point: Vector3 = spine.call("point_at_progress", 30.0)

	assert_true(
		point.is_equal_approx(Vector3(0, 0, -30)),
		"expected (0,0,-30) 30m down leg A->B, got %s" % point
	)


func test_point_at_progress_wraps_progress_past_the_closing_seam() -> void:
	var spine := _spine_with_markers(_POINTS)
	var length: float = spine.call("length_m")
	assert_almost_eq(length, 400.0, 0.01, "fixture sanity: perimeter must be 400m")

	# 10m past a full lap must read the same as 10m into the first leg.
	var wrapped_point: Vector3 = spine.call("point_at_progress", length + 10.0)
	var direct_point: Vector3 = spine.call("point_at_progress", 10.0)

	assert_true(
		wrapped_point.is_equal_approx(direct_point),
		"progress past length_m() must wrap via fposmod on this closed loop"
	)


# ---------------------------------------------------------------------------
# curvature_at_progress(): Task 4 (CTR R3: AI opponents) addition, SIGNED per
# ai_driver.gd's SIGNED CURVATURE CONTRACT (binding on this producer):
#   magnitude = tangent_now.angle_to(tangent_ahead) / sample_span_m   (>= 0)
#   sign      = -signf(tangent_now.cross(tangent_ahead).y)
# tangent_now = spine tangent at progress_m, tangent_ahead = spine tangent at
# progress_m + sample_span_m (order matters -- cross() is anti-commutative).
# ---------------------------------------------------------------------------


func test_curvature_at_progress_reports_signed_value_on_a_right_bending_corner() -> void:
	# Corner B (offset 100): leg A->B tangent (0,0,-1) turns into leg B->C
	# tangent (1,0,0) -- the exact vectors from ai_driver.gd's own worked
	# example, which that class doc derives as a RIGHTWARD bend (positive).
	var spine := _spine_with_markers(_POINTS)
	var sample_span_m := 20.0

	var curvature: float = spine.call("curvature_at_progress", 90.0, sample_span_m)

	var expected_magnitude: float = (PI / 2.0) / sample_span_m
	assert_almost_eq(
		curvature,
		expected_magnitude,
		0.01,
		"a 90-degree corner over a 20m span must read +(pi/2)/20 -- positive because it bends right"
	)


func test_curvature_at_progress_reports_signed_value_on_a_left_bending_corner() -> void:
	# The same L-shaped loop walked in REVERSE turns every corner the other
	# way -- corner E (reversed offset 50): leg F->E tangent (0,0,-1) turns
	# into leg E->D tangent (-1,0,0), a LEFTWARD bend (negative).
	var reversed_points := _POINTS.duplicate()
	reversed_points.reverse()
	var spine := _spine_with_markers(reversed_points)
	var sample_span_m := 20.0

	var curvature: float = spine.call("curvature_at_progress", 40.0, sample_span_m)

	var expected_magnitude: float = (PI / 2.0) / sample_span_m
	assert_almost_eq(
		curvature,
		-expected_magnitude,
		0.01,
		"the same corner shape walked in reverse must read negative -- it now bends left"
	)


func test_curvature_at_progress_wraps_the_ahead_sample_past_the_seam() -> void:
	# progress_m=390 sits on the closing leg F->A (10m before the seam);
	# progress_m+span=410 must wrap to 10.0 (10m into leg A->B), NOT clamp at
	# length_m() -- clamping would read the tangent arriving at the seam (leg
	# F->A's own direction) instead of the true wrapped sample.
	var spine := _spine_with_markers(_POINTS)
	var length: float = spine.call("length_m")
	assert_almost_eq(length, 400.0, 0.01, "fixture sanity")
	var sample_span_m := 20.0

	var tangent_now: Vector3 = spine.call("tangent_at_progress", 390.0)
	var tangent_wrapped_ahead: Vector3 = spine.call("tangent_at_progress", 10.0)
	var tangent_clamped_ahead: Vector3 = spine.call("tangent_at_progress", 410.0)
	assert_false(
		tangent_clamped_ahead.is_equal_approx(tangent_wrapped_ahead),
		"fixture sanity: the clamped-at-seam tangent must differ from the "
		+ "properly wrapped one, or this test cannot distinguish wrap from clamp"
	)
	var expected_magnitude := tangent_now.angle_to(tangent_wrapped_ahead) / sample_span_m
	var expected_sign := -signf(tangent_now.cross(tangent_wrapped_ahead).y)

	var curvature: float = spine.call("curvature_at_progress", 390.0, sample_span_m)

	assert_almost_eq(absf(curvature), expected_magnitude, 0.01)
	assert_almost_eq(signf(curvature), expected_sign, 0.01)


func test_curvature_at_progress_is_near_zero_on_a_straight_leg() -> void:
	var spine := _spine_with_markers(_POINTS)

	var curvature: float = spine.call("curvature_at_progress", 30.0, 10.0)

	assert_almost_eq(curvature, 0.0, 0.001, "a straight leg must have ~zero curvature")


func test_curvature_at_progress_fails_closed_on_a_non_positive_sample_span() -> void:
	var spine := _spine_with_markers(_POINTS)

	assert_almost_eq(float(spine.call("curvature_at_progress", 30.0, 0.0)), 0.0, 0.0001)
	assert_almost_eq(float(spine.call("curvature_at_progress", 30.0, -5.0)), 0.0, 0.0001)


# ---------------------------------------------------------------------------
# curvature_at_progress() on the real graybox loop: pins the sign against a
# corner whose bend direction is known from the authored marker geometry
# itself (see ai_kart_agent.gd's class doc for the same corner reasoned
# through in full) -- an independent check that the SIGNED CURVATURE
# CONTRACT lands correctly on the real, shipped track, not just a synthetic
# fixture.
# ---------------------------------------------------------------------------


func test_curvature_at_progress_matches_the_known_bend_on_the_real_graybox_loop() -> void:
	const GRAYBOX_LOOP_PATH := "res://scenes/racing/track_graybox_loop.tscn"
	const CAMERA_TUNING_PATH_LOCAL := "res://data/tuning/camera.tres"
	assert_true(
		ResourceLoader.exists(GRAYBOX_LOOP_PATH),
		"the graybox loop scene must exist"
	)
	if not ResourceLoader.exists(GRAYBOX_LOOP_PATH):
		return
	var track := (load(GRAYBOX_LOOP_PATH) as PackedScene).instantiate()
	add_child_autofree(track)
	var spine := track.get_node("Spine")
	var camera_tuning: CameraTuning = load(CAMERA_TUNING_PATH_LOCAL)
	spine.call("configure", camera_tuning)

	# EastTurnA(50,-17.32) sits inside the East turn -- the corner that
	# carries the south straight (kart travels +X, per race_session.gd's own
	# "the spawn tangent faces +X (south straight)" comment) around to the
	# north straight (-X) via a sweep through positive Z. Sampling from this
	# marker's own progress (rather than the kart's spawn point, which sits
	# on the wraparound leg just before the seam and would need extra
	# bookkeeping to locate the turn from) isolates the sign check from the
	# seam entirely.
	var east_turn_progress: float = spine.call(
		"progress_for_position", Vector3(50.0, 0.0, -17.3205)
	)
	var sample_span_m := 15.0
	var curvature: float = spine.call(
		"curvature_at_progress", east_turn_progress, sample_span_m
	)

	assert_gt(
		curvature,
		0.0,
		(
			"the East turn (south straight -> east apex -> north straight) "
			+ "must read as a RIGHT-bending corner (positive curvature) -- "
			+ "got %s"
		) % curvature
	)
