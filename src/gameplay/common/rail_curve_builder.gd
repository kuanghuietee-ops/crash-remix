class_name RailCurveBuilder
extends RefCounted

const ScalarMathType := preload("res://src/core/scalar_math.gd")


static func curve_from_markers(
	parent: Node,
	bake_interval_m: float,
	handle_length_factor: float
) -> Curve3D:
	var curve := Curve3D.new()
	if bake_interval_m > 0.0:
		curve.bake_interval = bake_interval_m
	var points: Array[Vector3] = []
	if parent != null:
		for marker: Node in parent.get_children():
			if marker is Marker3D:
				points.append((marker as Marker3D).position)
	for point in points:
		curve.add_point(point)
	var index := 1
	while index < points.size() - 1:
		var out_handle := (
			(points[index + 1] - points[index - 1])
			* handle_length_factor
		)
		# Non-uniform Catmull-Rom overshoot guard: when the neighboring spans
		# are very unequal (e.g. a 96m straight run next to a 6m arc slice),
		# the naive handle above can be longer than the short span itself,
		# bowing the baked curve well outside the authored points. Cap the
		# handle's length at min(prev_span, next_span) * 2 * factor -- the
		# standard non-uniform bound -- while keeping its direction. When
		# the spans are equal this never fires: |p[i+1]-p[i-1]| <=
		# prev_span + next_span = 2*L by the triangle inequality, so the
		# naive handle is already within the bound and the formula above is
		# used unchanged.
		var prev_span := points[index].distance_to(points[index - 1])
		var next_span := points[index + 1].distance_to(points[index])
		var max_length := (
			minf(prev_span, next_span)
			* ScalarMathType.DOUBLE
			* handle_length_factor
		)
		var handle_length := out_handle.length()
		if handle_length > max_length and handle_length > 0.0:
			out_handle = out_handle * (max_length / handle_length)
		curve.set_point_out(index, out_handle)
		curve.set_point_in(index, -out_handle)
		index += 1
	return curve
