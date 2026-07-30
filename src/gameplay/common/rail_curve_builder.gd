class_name RailCurveBuilder
extends RefCounted

const ScalarMathType := preload("res://src/core/scalar_math.gd")


static func curve_from_markers(
	parent: Node,
	bake_interval_m: float,
	handle_length_factor: float,
	closed: bool = false
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
	var point_count := points.size()
	var last_index := point_count - 1
	# A closed loop needs at least two authored markers to wrap a neighbor
	# relationship around; a single marker (or none) has nothing to close,
	# so it falls back to the same (no-op) handling as the open path below.
	var wraps := closed and point_count > 1
	if wraps:
		# Curve3D has no closed flag -- the standard workaround is to
		# duplicate the first point as the curve's final point, so baking
		# actually draws the segment back from the last marker to the
		# start. Its in-handle is set below to mirror point 0's out-handle,
		# so the tangent direction stays continuous across that seam.
		curve.add_point(points[0])
	var start_index := 0 if wraps else 1
	var stop_index := point_count if wraps else last_index
	var index := start_index
	while index < stop_index:
		# Open curves never touch the first/last marker's handles (index
		# starts at 1 and stops before last_index), so prev/next here are
		# always in-bounds without wrapping. A closed loop walks every
		# marker (0..last_index) instead, and the first/last markers wrap
		# their neighbor to the opposite end of the list -- see the binding
		# interface note: "first point's handle uses last marker as prev,
		# last uses first as next."
		var prev_index := last_index if index == 0 else index - 1
		var next_index := 0 if index == last_index else index + 1
		var out_handle := (
			(points[next_index] - points[prev_index])
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
		# used unchanged. This guard applies identically at the wrap points
		# of a closed loop -- prev_span/next_span are just measured against
		# the wrapped neighbor instead of a linear one.
		var prev_span := points[index].distance_to(points[prev_index])
		var next_span := points[next_index].distance_to(points[index])
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
	if wraps:
		# Mirror point 0's (possibly clamped) out-handle onto the seam's
		# in-handle -- see the "in = -out" pairing above, applied across the
		# seam instead of within a single point since the seam IS point 0
		# geometrically. This is what makes the tangent direction arriving
		# at the seam match the tangent direction leaving the start the
		# first time around, instead of a visible kink at the closure.
		curve.set_point_in(point_count, -curve.get_point_out(0))
	return curve
