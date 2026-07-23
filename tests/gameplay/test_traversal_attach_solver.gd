extends GutTest

const TraversalAttachSolverType := preload(
	"res://src/gameplay/traversal/traversal_attach_solver.gd"
)
const SAMPLE_SCRIPT_PATH := "res://src/gameplay/traversal/traversal_sample.gd"


func test_rail_attach_returns_the_first_contact_sample() -> void:
	# Vector3.BACK is +Z, so the arc's positive z values sit on the rail.
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(0.0, 3.0, 1.0),
		Vector3(0.0, 1.5, 2.0),
		Vector3(0.2, 0.1, 3.0),
	])

	var index: int = TraversalAttachSolverType.solve_rail_attach(
		arc,
		samples,
		0.35
	)

	assert_eq(index, 6, "the first contact is the sample at z=3m")


func test_rail_attach_measures_against_the_whole_arc_segment() -> void:
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		4.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(-1.0, 0.2, 2.0),
		Vector3(1.0, 0.2, 2.0),
	])

	var index: int = TraversalAttachSolverType.solve_rail_attach(
		arc,
		samples,
		0.35
	)

	assert_eq(index, 4, "the segment midpoint passes over the z=2m sample")


func test_rail_attach_prefers_earlier_arc_contact_over_lower_sample_index() -> void:
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(0.2, 0.0, 8.0),
		Vector3(3.0, 0.0, 8.0),
		Vector3(3.0, 0.0, 2.0),
		Vector3(0.1, 0.0, 2.0),
	])

	var index: int = TraversalAttachSolverType.solve_rail_attach(
		arc,
		samples,
		0.35
	)

	assert_eq(
		index,
		16,
		"trajectory reaches z=8 before the lower-index z=2 sample"
	)


func test_rail_attach_orders_multiple_contacts_within_one_arc_segment() -> void:
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var reverse_arc := PackedVector3Array([
		Vector3(0.0, 0.0, 10.0),
		Vector3.ZERO,
	])

	var index: int = TraversalAttachSolverType.solve_rail_attach(
		reverse_arc,
		samples,
		0.35
	)

	assert_eq(index, 20, "the reverse arc reaches z=10 before sample index zero")


func test_rail_attach_misses_when_arc_stays_outside_snap() -> void:
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		10.0,
		0.5
	)
	var arc := PackedVector3Array([
		Vector3(2.0, 3.0, 1.0),
		Vector3(2.0, 1.5, 2.0),
		Vector3(2.0, 0.1, 3.0),
	])

	var index: int = TraversalAttachSolverType.solve_rail_attach(
		arc,
		samples,
		0.35
	)

	assert_eq(index, -1, "an arc 2m off the rail must not attach")


func test_rail_attach_boundary_is_inclusive() -> void:
	var samples: Array[TraversalSample] = [
		_sample(Vector3.ZERO, Vector3.BACK, Vector3.UP),
	]
	var arc := PackedVector3Array([
		Vector3(0.35, 0.0, -1.0),
		Vector3(0.35, 0.0, 1.0),
	])

	assert_eq(
		TraversalAttachSolverType.solve_rail_attach(arc, samples, 0.35),
		0
	)


func test_nearest_sample_index_handles_present_and_empty_samples() -> void:
	var samples: Array[TraversalSample] = _straight_rail(
		Vector3.ZERO,
		Vector3.BACK,
		4.0,
		1.0
	)
	var empty: Array[TraversalSample] = []

	assert_eq(
		TraversalAttachSolverType.nearest_sample_index(
			Vector3(0.0, 0.0, 2.2),
			samples
		),
		2
	)
	assert_eq(
		TraversalAttachSolverType.nearest_sample_index(Vector3.ZERO, empty),
		-1
	)


func test_wall_attach_requires_heading_inside_the_cone() -> void:
	var sample := _sample(Vector3.ZERO, Vector3.BACK, Vector3.RIGHT)

	var inside: bool = TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3.BACK * 6.0,
		sample,
		25.0,
		0.0
	)
	var outside: bool = TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3.RIGHT * 6.0,
		sample,
		25.0,
		0.0
	)

	assert_true(inside, "heading straight along the strip must attach")
	assert_false(outside, "heading 90 degrees off the strip must not attach")


func test_wall_attach_cone_boundary_is_inclusive() -> void:
	var sample := _sample(Vector3.ZERO, Vector3.BACK, Vector3.RIGHT)
	var boundary := (
		Vector3.BACK.rotated(Vector3.UP, deg_to_rad(25.0)) * 6.0
	)
	var just_outside := (
		Vector3.BACK.rotated(Vector3.UP, deg_to_rad(25.1)) * 6.0
	)

	assert_true(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		boundary,
		sample,
		25.0,
		0.0
	))
	assert_false(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		just_outside,
		sample,
		25.0,
		0.0
	))


func test_wall_attach_rejects_below_speed_and_accepts_exact_threshold() -> void:
	var sample := _sample(Vector3.ZERO, Vector3.BACK, Vector3.RIGHT)

	assert_false(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3.BACK * 4.9,
		sample,
		25.0,
		5.0
	))
	assert_true(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3.BACK * 5.0,
		sample,
		25.0,
		5.0
	))


func test_wall_attach_uses_horizontal_heading_and_rejects_zero_heading() -> void:
	var sample := _sample(Vector3.ZERO, Vector3.BACK, Vector3.RIGHT)

	assert_true(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3(0.0, 100.0, 6.0),
		sample,
		25.0,
		0.0
	))
	assert_false(TraversalAttachSolverType.solve_wall_attach(
		Vector3.ZERO,
		Vector3.UP * 100.0,
		sample,
		25.0,
		0.0
	))


func _straight_rail(
	origin: Vector3,
	direction: Vector3,
	length_m: float,
	step_m: float
) -> Array[TraversalSample]:
	var samples: Array[TraversalSample] = []
	var travelled := 0.0
	while travelled <= length_m:
		samples.append(_sample(
			origin + direction.normalized() * travelled,
			direction,
			Vector3.UP,
			travelled
		))
		travelled += step_m
	return samples


func _sample(
	position: Vector3,
	tangent: Vector3,
	normal: Vector3,
	distance_along_m := 0.0
) -> TraversalSample:
	var sample_script: GDScript = load(SAMPLE_SCRIPT_PATH)
	var sample: TraversalSample = sample_script.new()
	sample.position = position
	sample.tangent = tangent.normalized()
	sample.normal = normal.normalized()
	sample.distance_along_m = distance_along_m
	return sample
