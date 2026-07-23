class_name PlayerController
extends CharacterBody3D

signal state_changed(previous_state: StringName, state: StringName)
signal spin_changed(active: bool)
signal body_slam_impacted
signal respawned

const PlayerStateMachineType := preload("res://src/gameplay/player/player_state_machine.gd")
const PlayerFrameDecisionType := preload("res://src/gameplay/player/player_frame_decision.gd")
const PlayerMotorType := preload("res://src/gameplay/player/player_motor.gd")
const JumpKinematicsType := preload("res://src/gameplay/player/jump_kinematics.gd")
const LandingAssistType := preload("res://src/gameplay/depth/landing_assist.gd")
const MonotonicClockType := preload("res://src/core/monotonic_clock.gd")
const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _move_tuning: MoveTuning
var _input_tuning: InputTuning
var _depth_tuning: DepthTuning
var _intents: InputIntentBuffer
var _state_machine: PlayerStateMachineType = PlayerStateMachineType.new()
var _collision_shape: CollisionShape3D
var _hurtbox_area: Area3D
var _visual_root: Node3D
var _spin_visual_pivot: Node3D
var _spin_area: Area3D
var _slam_area: Area3D
var _corridor_forward := Vector3.FORWARD
var _spawn_transform := Transform3D.IDENTITY
var _last_state := &""
var _last_spin_active: bool
var _fall_apex_y: float
var _respawn_due_s := -1.0
var _active_jump_tap_height_m := 0.0


func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_hurtbox_area = get_node_or_null("Hurtbox") as Area3D
	_visual_root = get_node_or_null("Visual") as Node3D
	_spin_visual_pivot = get_node_or_null("Visual/SpinPivot") as Node3D
	_spin_area = get_node_or_null("SpinArea") as Area3D
	_slam_area = get_node_or_null("SlamArea") as Area3D
	_spawn_transform = global_transform
	_fall_apex_y = global_position.y
	_apply_character_dimensions(_state_machine.state)


func configure(
	move_tuning: MoveTuning,
	input_tuning: InputTuning,
	depth_tuning: DepthTuning,
	intents: InputIntentBuffer
) -> void:
	_move_tuning = move_tuning
	_input_tuning = input_tuning
	_depth_tuning = depth_tuning
	_intents = intents
	_active_jump_tap_height_m = _move_tuning.jump_tap_height_m
	floor_snap_length = _move_tuning.floor_snap_length_m
	floor_max_angle = deg_to_rad(_move_tuning.floor_max_angle_degrees)
	_apply_character_dimensions(_state_machine.state)


func set_corridor_forward(forward: Vector3) -> void:
	var horizontal_forward := Vector3(forward.x, 0.0, forward.z)
	if not horizontal_forward.is_zero_approx():
		_corridor_forward = horizontal_forward.normalized()


func set_spawn_transform(spawn_transform: Transform3D) -> void:
	_spawn_transform = spawn_transform


func advance_logic(
	now_s: float,
	grounded: bool,
	delta_s: float,
	forward: Vector3
) -> PlayerFrameDecisionType:
	if _move_tuning == null or _input_tuning == null or _intents == null:
		return null

	set_corridor_forward(forward)
	if (
		_intents.consume_pressed(
			InputIntent.ACTION_PHASE,
			now_s,
			_input_tuning.action_buffer_s
		)
		!= null
	):
		PhaseState.request_toggle(now_s)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var decision: PlayerFrameDecisionType = _state_machine.step(
		now_s,
		grounded,
		horizontal_speed,
		_intents,
		_move_tuning,
		_input_tuning
	)
	var next_horizontal := PlayerMotorType.horizontal_velocity(
		velocity,
		_intents.movement(),
		decision.state,
		delta_s,
		_corridor_forward,
		_move_tuning
	)
	velocity.x = next_horizontal.x
	velocity.z = next_horizontal.z
	_apply_vertical_physics(grounded, delta_s)
	if decision.impulse != PlayerFrameDecisionType.IMPULSE_NONE:
		velocity = PlayerMotorType.impulse_velocity(
			decision.impulse,
			velocity,
			_corridor_forward,
			_move_tuning
		)
		var tap_height_m := tap_height_for_impulse(
			decision.impulse,
			_move_tuning
		)
		if decision.impulse != PlayerFrameDecisionType.IMPULSE_BODY_SLAM:
			_active_jump_tap_height_m = tap_height_m
	_apply_jump_release(now_s)
	_track_fall_apex(grounded)
	_apply_character_dimensions(decision.state)
	_apply_spin_visual(delta_s)
	_apply_body_slam_attack(decision)
	_emit_state_changes(decision.state, _state_machine.is_spinning)
	return decision


func current_state() -> StringName:
	return _state_machine.state


func is_spinning() -> bool:
	return _state_machine.is_spinning


static func edge_nudge_directions(
	corridor_forward: Vector3,
	horizontal_travel: Vector3
) -> Array[Vector3]:
	var forward := Vector3(
		corridor_forward.x,
		0.0,
		corridor_forward.z
	).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var directions: Array[Vector3] = [
		right,
		-right,
		forward,
		-forward,
		(right + forward).normalized(),
		(right - forward).normalized(),
		(-right + forward).normalized(),
		(-right - forward).normalized(),
	]
	var travel := Vector3(
		horizontal_travel.x,
		0.0,
		horizontal_travel.z
	).normalized()
	if not travel.is_zero_approx():
		var recovery_direction := -travel
		directions.sort_custom(
			func(first: Vector3, second: Vector3) -> bool:
				return (
					first.dot(recovery_direction)
					> second.dot(recovery_direction)
				)
		)
	return directions


static func tap_height_for_impulse(
	impulse: StringName,
	move_tuning: MoveTuning
) -> float:
	match impulse:
		PlayerFrameDecisionType.IMPULSE_DOUBLE_JUMP:
			return move_tuning.double_jump_tap_height_m
		PlayerFrameDecisionType.IMPULSE_JUMP:
			return move_tuning.jump_tap_height_m
	return 0.0


func try_edge_landing_nudge() -> bool:
	if _input_tuning == null or _move_tuning == null or not is_inside_tree():
		return false
	if not _safe_floor_probe(Vector3.ZERO).is_empty():
		return false
	var horizontal_travel := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_travel.is_zero_approx() and _intents != null:
		horizontal_travel = _movement_world_direction(_intents.movement())
	var directions := edge_nudge_directions(
		_corridor_forward,
		horizontal_travel
	)
	for direction: Vector3 in directions:
		var offset := direction * _input_tuning.edge_landing_nudge_m
		if _safe_floor_probe(offset).is_empty():
			continue
		if test_move(global_transform, offset):
			continue
		global_position += offset
		reset_physics_interpolation()
		return true
	return false


func try_soft_landing_assist() -> bool:
	if (
		_depth_tuning == null
		or _intents == null
		or not is_inside_tree()
		or velocity.y >= 0.0
	):
		return false
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var input_direction := _movement_world_direction(_intents.movement())
	var aimed_direction := input_direction
	if aimed_direction.is_zero_approx():
		aimed_direction = horizontal.normalized()
	if aimed_direction.is_zero_approx():
		return false
	if not _landing_assist_floor_probe(Vector3.ZERO).is_empty():
		return false

	var correction := aimed_direction.normalized()
	var probe_offset := correction * _depth_tuning.landing_assist_edge_distance_m
	var hit := _landing_assist_floor_probe(probe_offset)
	if hit.is_empty():
		return false
	var surface_position: Vector3 = hit["position"]
	var total_fall_m := _fall_apex_y - surface_position.y
	if total_fall_m <= 0.0:
		return false
	var fallen_m := _fall_apex_y - global_position.y
	var fall_progress := clampf(fallen_m / total_fall_m, 0.0, 1.0)
	var adjusted := LandingAssistType.adjusted_horizontal_velocity(
		horizontal,
		correction,
		input_direction,
		fall_progress,
		_intents.active_source(),
		_depth_tuning
	)
	if (adjusted - horizontal).is_zero_approx():
		return false
	velocity.x = adjusted.x
	velocity.z = adjusted.z
	return true


func respawn() -> void:
	global_transform = _spawn_transform
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_respawn_due_s = -1.0
	_state_machine = PlayerStateMachineType.new()
	_last_state = &""
	_last_spin_active = false
	_fall_apex_y = global_position.y
	if _move_tuning != null:
		_active_jump_tap_height_m = _move_tuning.jump_tap_height_m
	if _intents != null:
		_intents.clear()
	_apply_character_dimensions(_state_machine.state)
	if _spin_visual_pivot != null:
		_spin_visual_pivot.rotation.y = 0.0
	respawned.emit()


func request_respawn(now_s: float) -> void:
	if _move_tuning == null or is_respawning():
		return
	_respawn_due_s = now_s + _move_tuning.respawn_delay_s
	velocity = Vector3.ZERO


func is_respawning() -> bool:
	return _respawn_due_s >= 0.0


func advance_respawn(now_s: float) -> bool:
	if not is_respawning() or now_s < _respawn_due_s:
		return false
	respawn()
	return true


func _physics_process(delta_s: float) -> void:
	if _move_tuning == null or _input_tuning == null or _intents == null:
		return
	var now_s := MonotonicClockType.now_s()
	if advance_respawn(now_s) or is_respawning():
		return
	advance_logic(now_s, is_on_floor(), delta_s, _corridor_forward)
	if not is_on_floor() and velocity.y <= 0.0:
		try_soft_landing_assist()
		try_edge_landing_nudge()
	move_and_slide()
	if global_position.y < _move_tuning.respawn_floor_y_m:
		request_respawn(now_s)


func _apply_vertical_physics(grounded: bool, delta_s: float) -> void:
	if grounded and velocity.y < 0.0:
		velocity.y = 0.0
	if grounded:
		return
	var gravity := JumpKinematicsType.gravity_for_velocity(
		velocity.y,
		_state_machine.is_spinning,
		_move_tuning
	)
	velocity.y = maxf(
		velocity.y - gravity * delta_s,
		-_move_tuning.maximum_fall_speed_mps
	)


func _apply_jump_release(now_s: float) -> void:
	var released := _intents.consume_released(
		InputIntent.ACTION_JUMP,
		now_s,
		_input_tuning.action_buffer_s
	)
	if released == null:
		return
	velocity.y = JumpKinematicsType.velocity_after_release(
		velocity.y,
		_intents.last_hold_duration(InputIntent.ACTION_JUMP),
		_active_jump_tap_height_m,
		_move_tuning,
		_input_tuning
	)


func _apply_character_dimensions(state: StringName) -> void:
	if _move_tuning == null:
		return
	var crouched := (
		state == PlayerStateMachineType.STATE_CROUCHED
		or state == PlayerStateMachineType.STATE_SLIDING
	)
	var visual_height := _move_tuning.player_height_m
	if crouched:
		visual_height *= _move_tuning.crouch_hurtbox_height_ratio
	var half_height := visual_height * ScalarMathType.HALF
	if _collision_shape != null and _collision_shape.shape is CylinderShape3D:
		var cylinder := _collision_shape.shape as CylinderShape3D
		cylinder.height = visual_height
		cylinder.radius = _move_tuning.collision_radius_m
		_collision_shape.position.y = half_height
	if _hurtbox_area != null:
		var hurtbox_shape_node := (
			_hurtbox_area.get_node_or_null("CollisionShape3D")
			as CollisionShape3D
		)
		if (
			hurtbox_shape_node != null
			and hurtbox_shape_node.shape is CylinderShape3D
		):
			var hurtbox_shape := hurtbox_shape_node.shape as CylinderShape3D
			hurtbox_shape.height = (
				visual_height * _move_tuning.hurtbox_visual_ratio
			)
			hurtbox_shape.radius = (
				_move_tuning.collision_radius_m
				* _move_tuning.hurtbox_visual_ratio
			)
			hurtbox_shape_node.position.y = half_height
	if _visual_root != null:
		_visual_root.scale.y = visual_height / _move_tuning.player_height_m
		_visual_root.position.y = visual_height * ScalarMathType.HALF
	if _spin_area != null:
		var spin_shape_node := _spin_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if spin_shape_node != null and spin_shape_node.shape is SphereShape3D:
			(spin_shape_node.shape as SphereShape3D).radius = (
				_move_tuning.spin_radius_m * _move_tuning.attack_visual_ratio
			)
			spin_shape_node.position.y = visual_height * ScalarMathType.HALF
	if _slam_area != null:
		var slam_shape_node := _slam_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if slam_shape_node != null and slam_shape_node.shape is SphereShape3D:
			(slam_shape_node.shape as SphereShape3D).radius = (
				_move_tuning.body_slam_shockwave_radius_m
			)


func _apply_body_slam_attack(decision: PlayerFrameDecisionType) -> void:
	if _slam_area == null:
		return
	_slam_area.monitoring = (
		decision.state == PlayerStateMachineType.STATE_SLAM_RECOVERY
	)
	if (
		decision.landed
		and decision.previous_state == PlayerStateMachineType.STATE_BODY_SLAM
	):
		body_slam_impacted.emit()


func _apply_spin_visual(delta_s: float) -> void:
	if (
		_spin_visual_pivot == null
		or not _state_machine.is_spinning
		or _move_tuning.spin_active_s <= 0.0
	):
		return
	_spin_visual_pivot.rotate_y(
		TAU * maxf(delta_s, 0.0) / _move_tuning.spin_active_s
	)


func _emit_state_changes(state: StringName, spinning: bool) -> void:
	if state != _last_state:
		state_changed.emit(_last_state, state)
		_last_state = state
	if spinning != _last_spin_active:
		spin_changed.emit(spinning)
		_last_spin_active = spinning
		if not spinning and _spin_visual_pivot != null:
			_spin_visual_pivot.rotation.y = 0.0
		if _spin_area != null:
			_spin_area.set_deferred("monitoring", spinning)


func _track_fall_apex(grounded: bool) -> void:
	if grounded:
		_fall_apex_y = global_position.y
	elif velocity.y >= 0.0:
		_fall_apex_y = maxf(_fall_apex_y, global_position.y)


func _movement_world_direction(input_vector: Vector2) -> Vector3:
	var forward := Vector3(_corridor_forward.x, 0.0, _corridor_forward.z).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var direction := right * input_vector.x - forward * input_vector.y
	return direction.normalized()


func _safe_floor_probe(horizontal_offset: Vector3) -> Dictionary:
	var probe_origin := (
		global_position
		+ horizontal_offset
		+ Vector3.UP * _move_tuning.floor_snap_length_m
	)
	var probe_end := (
		global_position
		+ horizontal_offset
		+ Vector3.DOWN * _move_tuning.floor_snap_length_m
	)
	var query := PhysicsRayQueryParameters3D.create(probe_origin, probe_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var surface_normal: Vector3 = hit["normal"]
	var minimum_up_dot := cos(deg_to_rad(_move_tuning.floor_max_angle_degrees))
	if surface_normal.dot(Vector3.UP) < minimum_up_dot:
		return {}
	var collider: Object = hit["collider"]
	if collider is Node and (collider as Node).is_in_group("hazard"):
		return {}
	return hit


func _landing_assist_floor_probe(horizontal_offset: Vector3) -> Dictionary:
	var probe_origin := (
		global_position
		+ horizontal_offset
		+ Vector3.UP * _move_tuning.floor_snap_length_m
	)
	var probe_end := LandingAssistType.probe_end(
		probe_origin,
		_depth_tuning
	)
	var query := PhysicsRayQueryParameters3D.create(probe_origin, probe_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var surface_normal: Vector3 = hit["normal"]
	var minimum_up_dot := cos(deg_to_rad(_move_tuning.floor_max_angle_degrees))
	if surface_normal.dot(Vector3.UP) < minimum_up_dot:
		return {}
	var collider: Object = hit["collider"]
	if collider is Node and (collider as Node).is_in_group("hazard"):
		return {}
	return hit
