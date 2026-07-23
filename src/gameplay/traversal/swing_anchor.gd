class_name SwingAnchor
extends Node3D

const ANCHOR_GROUP := &"swing_anchor"
const SwingPendulumType := preload(
	"res://src/gameplay/traversal/swing_pendulum.gd"
)
const ScalarMathType := preload("res://src/core/scalar_math.gd")

@export var swing_tuning: SwingTuning


func _ready() -> void:
	add_to_group(ANCHOR_GROUP)
	refresh_tuning(swing_tuning)


func refresh_tuning(next_swing_tuning: SwingTuning) -> void:
	swing_tuning = next_swing_tuning
	if swing_tuning == null:
		return
	var rope_mesh := get_node_or_null(
		"RopePivot/RopeMesh"
	) as MeshInstance3D
	if rope_mesh != null:
		rope_mesh.position.y = (
			-swing_tuning.rope_length_m * ScalarMathType.HALF
		)
		rope_mesh.scale.y = swing_tuning.rope_length_m
	var handle := get_node_or_null("RopePivot/Handle") as Node3D
	if handle != null:
		handle.position.y = -swing_tuning.rope_length_m


func can_catch(
	world_position: Vector3,
	catch_radius_m: float,
	active_tuning: SwingTuning
) -> bool:
	if active_tuning == null or catch_radius_m <= 0.0:
		return false
	return (
		world_position.distance_to(catch_position(active_tuning))
		<= catch_radius_m
	)


func catch_position(active_tuning: SwingTuning) -> Vector3:
	return position_for(0.0, active_tuning)


func position_for(
	angle_rad: float,
	active_tuning: SwingTuning
) -> Vector3:
	return to_global(
		SwingPendulumType.position_offset(angle_rad, active_tuning)
	)


func angle_for(world_position: Vector3) -> float:
	var local_offset := to_local(world_position)
	if local_offset.is_zero_approx():
		return 0.0
	return atan2(
		local_offset.dot(Vector3.FORWARD),
		local_offset.dot(Vector3.DOWN)
	)


func angular_velocity_for(
	world_velocity_value: Vector3,
	angle_rad: float,
	active_tuning: SwingTuning
) -> float:
	if active_tuning == null or active_tuning.rope_length_m <= 0.0:
		return 0.0
	var local_velocity := (
		global_basis.orthonormalized().inverse()
		* world_velocity_value
	)
	var tangent := (
		Vector3.UP * sin(angle_rad)
		+ Vector3.FORWARD * cos(angle_rad)
	).normalized()
	return local_velocity.dot(tangent) / active_tuning.rope_length_m


func world_velocity(local_velocity: Vector3) -> Vector3:
	return global_basis.orthonormalized() * local_velocity


func set_rope_angle(angle_rad: float) -> void:
	var rope_pivot := get_node_or_null("RopePivot") as Node3D
	if rope_pivot != null:
		rope_pivot.rotation.x = angle_rad


func reset_rope_visual() -> void:
	set_rope_angle(0.0)
