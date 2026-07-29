class_name RailCurveBuilder
extends RefCounted


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
		curve.set_point_out(index, out_handle)
		curve.set_point_in(index, -out_handle)
		index += 1
	return curve
