class_name DepthPrediction
extends RefCounted

const JumpKinematicsType := preload("res://src/gameplay/player/jump_kinematics.gd")


static func trajectory_points(
	origin: Vector3,
	initial_velocity: Vector3,
	is_air_spinning: bool,
	move_tuning: MoveTuning,
	depth_tuning: DepthTuning
) -> PackedVector3Array:
	var points := PackedVector3Array([origin])
	var position := origin
	var sample_velocity := initial_velocity
	var elapsed_s := 0.0
	while elapsed_s < depth_tuning.prediction_horizon_s:
		var gravity := JumpKinematicsType.gravity_for_velocity(
			sample_velocity.y,
			is_air_spinning,
			move_tuning
		)
		sample_velocity.y = maxf(
			sample_velocity.y - gravity * depth_tuning.prediction_step_s,
			-move_tuning.maximum_fall_speed_mps
		)
		position += sample_velocity * depth_tuning.prediction_step_s
		points.append(position)
		elapsed_s += depth_tuning.prediction_step_s
	return points


static func first_plane_crossing(
	points: PackedVector3Array,
	plane_height: float
) -> Variant:
	for index in range(1, points.size()):
		var previous := points[index - 1]
		var current := points[index]
		if previous.y < plane_height or current.y > plane_height:
			continue
		var height_span := previous.y - current.y
		if is_zero_approx(height_span):
			return current
		var weight := (previous.y - plane_height) / height_span
		return previous.lerp(current, clampf(weight, 0.0, 1.0))
	return null


static func should_collision_probe(
	point_index: int,
	final_index: int,
	probe_stride: int
) -> bool:
	if point_index <= 0 or final_index <= 0 or point_index > final_index:
		return false
	var resolved_stride := maxi(probe_stride, 1)
	return point_index == final_index or point_index % resolved_stride == 0
