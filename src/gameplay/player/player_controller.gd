class_name PlayerController
extends CharacterBody3D

signal state_changed(previous_state: StringName, state: StringName)
signal spin_changed(active: bool)
signal movement_impulse_applied(impulse: StringName)
signal hit_received(fatal: bool)
signal body_slam_impacted
signal respawn_started
signal respawned
signal mask_state_changed(
	mask_count: int,
	invincible_until_s: float
)

const PlayerStateMachineType := preload("res://src/gameplay/player/player_state_machine.gd")
const PlayerFrameDecisionType := preload("res://src/gameplay/player/player_frame_decision.gd")
const PlayerMotorType := preload("res://src/gameplay/player/player_motor.gd")
const JumpKinematicsType := preload("res://src/gameplay/player/jump_kinematics.gd")
const LandingAssistType := preload("res://src/gameplay/depth/landing_assist.gd")
const DepthPredictionType := preload("res://src/gameplay/depth/depth_prediction.gd")
const TraversalAttachSolverType := preload(
	"res://src/gameplay/traversal/traversal_attach_solver.gd"
)
const TraversalRailType := preload(
	"res://src/gameplay/traversal/traversal_rail.gd"
)
const WallRunStripType := preload(
	"res://src/gameplay/traversal/wall_run_strip.gd"
)
const SwingPendulumType := preload(
	"res://src/gameplay/traversal/swing_pendulum.gd"
)
const SwingAnchorType := preload(
	"res://src/gameplay/traversal/swing_anchor.gd"
)
const MonotonicClockType := preload("res://src/core/monotonic_clock.gd")
const ScalarMathType := preload("res://src/core/scalar_math.gd")

const DAMAGE_SOURCE_GROUP := &"player_damage_source"

@export var ride_visual_offset := Vector3.ZERO

var _move_tuning: MoveTuning
var _input_tuning: InputTuning
var _depth_tuning: DepthTuning
var _wall_run_tuning: WallRunTuning
var _grind_tuning: GrindTuning
var _swing_tuning: SwingTuning
var _economy_tuning: EconomyTuning
var _hog_tuning: HogTuning
var _intents: InputIntentBuffer
var _phase_enabled: bool
var _state_machine: PlayerStateMachineType = PlayerStateMachineType.new()
var _collision_shape: CollisionShape3D
var _hurtbox_area: Area3D
var _visual_root: Node3D
var _spin_visual_pivot: Node3D
var _spin_area: Area3D
var _slam_area: Area3D
var _corridor_forward := Vector3.FORWARD
var _chase_auto_run_remaining_s: float
var _ride_mounted: bool
var _spawn_transform := Transform3D.IDENTITY
var _last_state := &""
var _last_spin_active: bool
var _fall_apex_y: float
var _respawn_due_s := -1.0
var _mask_count: int
var _invincible_until_s := -1.0
var _active_jump_tap_height_m := 0.0
var _traversal_neighbour_available: bool
var _active_rail: TraversalRailType
var _rail_hop_target: TraversalRailType
var _rail_attach_blocked: TraversalRailType
var _active_rail_distance_m: float
var _grind_speed_mps: float
var _active_wall_strip: WallRunStripType
var _wall_attach_blocked: WallRunStripType
var _active_wall_sample: TraversalSample
var _active_swing_anchor: SwingAnchorType
var _swing_attach_blocked: SwingAnchorType
var _swing_angle_rad: float
var _swing_angular_velocity: float
var _bounce_window_active: bool
var _bounce_contact_s: float
var _bounce_target_apex_y: float


func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_hurtbox_area = get_node_or_null("Hurtbox") as Area3D
	_visual_root = get_node_or_null("Visual") as Node3D
	_spin_visual_pivot = get_node_or_null("Visual/SpinPivot") as Node3D
	_spin_area = get_node_or_null("SpinArea") as Area3D
	_slam_area = get_node_or_null("SlamArea") as Area3D
	if _hurtbox_area != null:
		_hurtbox_area.area_entered.connect(
			_on_hurtbox_area_entered
		)
		_hurtbox_area.body_entered.connect(
			_on_hurtbox_body_entered
		)
	_spawn_transform = global_transform
	_fall_apex_y = global_position.y
	_apply_character_dimensions(_state_machine.state)
	_apply_motion_mode(_state_machine.state)


func configure(
	move_tuning: MoveTuning,
	input_tuning: InputTuning,
	depth_tuning: DepthTuning,
	wall_run_tuning: WallRunTuning,
	grind_tuning: GrindTuning,
	swing_tuning: SwingTuning,
	intents: InputIntentBuffer,
	economy_tuning: EconomyTuning,
	phase_enabled: bool,
	hog_tuning: HogTuning
) -> void:
	_move_tuning = move_tuning
	_input_tuning = input_tuning
	_depth_tuning = depth_tuning
	_wall_run_tuning = wall_run_tuning
	_grind_tuning = grind_tuning
	_swing_tuning = swing_tuning
	_economy_tuning = economy_tuning
	_hog_tuning = hog_tuning
	_phase_enabled = phase_enabled
	if is_instance_valid(_active_swing_anchor):
		_active_swing_anchor.refresh_tuning(_swing_tuning)
	_intents = intents
	_chase_auto_run_remaining_s = 0.0
	_clear_bounce_timing_window()
	_active_jump_tap_height_m = _move_tuning.jump_tap_height_m
	floor_snap_length = _move_tuning.floor_snap_length_m
	floor_max_angle = deg_to_rad(_move_tuning.floor_max_angle_degrees)
	_apply_character_dimensions(_state_machine.state)
	_apply_motion_mode(_state_machine.state)


func set_corridor_forward(forward: Vector3) -> void:
	var horizontal_forward := Vector3(forward.x, 0.0, forward.z)
	if not horizontal_forward.is_zero_approx():
		_corridor_forward = horizontal_forward.normalized()


func set_chase_auto_run_duration(duration_s: float) -> void:
	_chase_auto_run_remaining_s = maxf(duration_s, 0.0)


func mount_hog() -> void:
	if _hog_tuning == null:
		return
	_ride_mounted = true
	_chase_auto_run_remaining_s = 0.0
	_clear_rail_state()
	_clear_wall_run_state()
	_clear_swing_state()
	_clear_bounce_timing_window()
	_state_machine.enter_ride(MonotonicClockType.now_s())
	_apply_character_dimensions(_state_machine.state)
	_apply_motion_mode(_state_machine.state)
	_emit_state_changes(
		_state_machine.state,
		_state_machine.is_spinning
	)


func dismount_hog() -> void:
	if not _ride_mounted:
		return
	_ride_mounted = false
	_state_machine.exit_ride(
		MonotonicClockType.now_s(),
		is_on_floor()
	)
	_apply_character_dimensions(_state_machine.state)
	_apply_motion_mode(_state_machine.state)
	_emit_state_changes(
		_state_machine.state,
		_state_machine.is_spinning
	)


func is_hog_mounted() -> bool:
	return _ride_mounted


func set_spawn_transform(spawn_transform: Transform3D) -> void:
	_spawn_transform = spawn_transform


func grant_mask(now_s: float) -> bool:
	if (
		_economy_tuning == null
		or _economy_tuning.mask_stack_maximum <= 0
	):
		return false
	if _mask_count < _economy_tuning.mask_stack_maximum:
		_mask_count += 1
		_invincible_until_s = -1.0
		_emit_mask_state()
		return false
	_invincible_until_s = (
		now_s
		+ _economy_tuning.invincibility_duration_s
	)
	_emit_mask_state()
	return true


func mask_count() -> int:
	return _mask_count


func is_invincible(now_s: float) -> bool:
	return (
		_economy_tuning != null
		and _invincible_until_s >= 0.0
		and now_s < _invincible_until_s
	)


func invincibility_remaining_s(now_s: float) -> float:
	if not is_invincible(now_s):
		return 0.0
	return _invincible_until_s - now_s


func delay_invincibility(duration_s: float) -> void:
	if duration_s <= 0.0 or _invincible_until_s < 0.0:
		return
	_invincible_until_s += duration_s
	_emit_mask_state()


func receive_hit(now_s: float) -> bool:
	if is_invincible(now_s):
		return false
	if is_respawning():
		return false
	if _invincible_until_s >= 0.0:
		_invincible_until_s = -1.0
	if _mask_count > 0:
		_mask_count -= 1
		_invincible_until_s = (
			now_s
			+ _economy_tuning.mask_hit_invulnerability_s
		)
		_emit_mask_state()
		hit_received.emit(false)
		return false
	request_respawn(now_s)
	hit_received.emit(true)
	return true


func _on_hurtbox_area_entered(area: Area3D) -> void:
	_receive_contact_hit(area)


func _on_hurtbox_body_entered(body: Node3D) -> void:
	_receive_contact_hit(body)


func _receive_contact_hit(source: Node) -> void:
	if not source.is_in_group(DAMAGE_SOURCE_GROUP):
		return
	receive_hit(MonotonicClockType.now_s())


func clear_masks() -> void:
	if _mask_count == 0 and _invincible_until_s < 0.0:
		return
	_mask_count = 0
	_invincible_until_s = -1.0
	_emit_mask_state()


func _emit_mask_state() -> void:
	mask_state_changed.emit(
		_mask_count,
		_invincible_until_s
	)


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
		grounded
		and not PlayerMotorType.uses_spline_motion(_state_machine.state)
	):
		_rail_attach_blocked = null
		_rail_hop_target = null
		_wall_attach_blocked = null
		_swing_attach_blocked = null
	_update_rail_neighbour_context()
	_apply_late_bounce_press(now_s)
	var phase_press := _intents.consume_pressed(
		InputIntent.ACTION_PHASE,
		now_s,
		_input_tuning.action_buffer_s
	)
	if (
		not _ride_mounted
		and _phase_enabled
		and _input_tuning.phase_button_unlocked
		and phase_press != null
	):
		PhaseState.request_toggle(now_s)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var decision: PlayerFrameDecisionType = _state_machine.step(
		now_s,
		grounded,
		horizontal_speed,
		_intents,
		_move_tuning,
		_input_tuning,
		_traversal_neighbour_available
	)
	var movement_input := _intents.movement()
	if _chase_auto_run_remaining_s > 0.0:
		movement_input.y = -1.0
		_chase_auto_run_remaining_s = maxf(
			_chase_auto_run_remaining_s - maxf(delta_s, 0.0),
			0.0
		)
	var next_horizontal := PlayerMotorType.horizontal_velocity(
		velocity,
		movement_input,
		decision.state,
		delta_s,
		_corridor_forward,
		_move_tuning,
		_hog_tuning
	)
	velocity.x = next_horizontal.x
	velocity.z = next_horizontal.z
	_apply_motion_mode(decision.state)
	_apply_vertical_physics(grounded, delta_s)
	if decision.impulse != PlayerFrameDecisionType.IMPULSE_NONE:
		if decision.impulse == PlayerFrameDecisionType.IMPULSE_RAIL_HOP:
			_apply_rail_hop()
		elif decision.impulse == PlayerFrameDecisionType.IMPULSE_RAIL_EXIT:
			_apply_rail_exit()
		elif decision.impulse == PlayerFrameDecisionType.IMPULSE_WALL_DETACH:
			_apply_wall_detach()
		elif decision.impulse == PlayerFrameDecisionType.IMPULSE_SWING_RELEASE:
			_apply_swing_release()
		else:
			velocity = PlayerMotorType.impulse_velocity(
				decision.impulse,
				velocity,
				_corridor_forward,
				_move_tuning,
				_hog_tuning
			)
		var tap_height_m := tap_height_for_impulse(
			decision.impulse,
			_move_tuning,
			_hog_tuning
		)
		if decision.impulse != PlayerFrameDecisionType.IMPULSE_BODY_SLAM:
			_active_jump_tap_height_m = tap_height_m
	_apply_jump_release(now_s)
	if (
		decision.previous_state == PlayerStateMachineType.STATE_WALL_RUN
		and decision.state != PlayerStateMachineType.STATE_WALL_RUN
		and decision.impulse != PlayerFrameDecisionType.IMPULSE_WALL_DETACH
	):
		_finish_wall_run()
	if decision.state == PlayerStateMachineType.STATE_GRIND:
		_advance_grind_motion(delta_s, now_s)
		decision.state = _state_machine.state
	elif decision.state == PlayerStateMachineType.STATE_WALL_RUN:
		_advance_wall_run_motion(delta_s, now_s)
		decision.state = _state_machine.state
	elif decision.state == PlayerStateMachineType.STATE_SWING:
		_advance_swing_motion(delta_s)
	_track_fall_apex(grounded)
	_apply_character_dimensions(decision.state)
	_apply_spin_visual(delta_s)
	_apply_body_slam_attack(decision)
	_emit_state_changes(decision.state, _state_machine.is_spinning)
	if decision.impulse != PlayerFrameDecisionType.IMPULSE_NONE:
		movement_impulse_applied.emit(decision.impulse)
	return decision


func current_state() -> StringName:
	return _state_machine.state


func consume_bounce_contact_intent(now_s: float) -> bool:
	if _intents == null or _input_tuning == null:
		return false
	if _intents.is_action_pressed(InputIntent.ACTION_JUMP):
		_intents.consume_pressed(
			InputIntent.ACTION_JUMP,
			now_s,
			_input_tuning.bounce_timing_s
		)
		return true
	return (
		_intents.consume_pressed(
			InputIntent.ACTION_JUMP,
			now_s,
			_input_tuning.bounce_timing_s
		)
		!= null
	)


func begin_bounce_timing_window(
	contact_s: float,
	launched_high: bool
) -> void:
	_clear_bounce_timing_window()
	if (
		launched_high
		or _input_tuning == null
		or _economy_tuning == null
		or _move_tuning == null
		or _input_tuning.bounce_timing_s <= 0.0
	):
		return
	_bounce_window_active = true
	_bounce_contact_s = contact_s
	_bounce_target_apex_y = (
		global_position.y
		+ _economy_tuning.bounce_launch_height_m
	)


func traversal_camera_context() -> Dictionary:
	var context_position := (
		global_position
		if is_inside_tree()
		else position
	)
	var context := {
		&"state": _state_machine.state,
		&"tangent": Vector3.ZERO,
		&"normal": Vector3.ZERO,
		&"position": context_position,
	}
	if (
		_state_machine.state == PlayerStateMachineType.STATE_GRIND
		and is_instance_valid(_active_rail)
	):
		var rail_sample: TraversalSample = _active_rail.sample_at_distance(
			_active_rail_distance_m
		)
		if rail_sample != null:
			context[&"tangent"] = rail_sample.tangent
			context[&"normal"] = rail_sample.normal
			context[&"position"] = rail_sample.position
	elif (
		_state_machine.state == PlayerStateMachineType.STATE_WALL_RUN
		and _active_wall_sample != null
	):
		context[&"tangent"] = _active_wall_sample.tangent
		context[&"normal"] = _active_wall_sample.normal
		context[&"position"] = _active_wall_sample.position
	elif (
		_state_machine.state == PlayerStateMachineType.STATE_SWING
		and is_instance_valid(_active_swing_anchor)
	):
		var anchor_basis := (
			_active_swing_anchor.global_basis.orthonormalized()
		)
		context[&"tangent"] = (
			anchor_basis * Vector3.FORWARD
		).normalized()
		context[&"normal"] = (
			anchor_basis * Vector3.RIGHT
		).normalized()
		context[&"position"] = (
			_active_swing_anchor.catch_position(_swing_tuning)
			if _swing_tuning != null
			else _active_swing_anchor.global_position
		)
	return context


func landing_prediction_context() -> Dictionary:
	var context_position := (
		global_position
		if is_inside_tree()
		else position
	)
	var prediction_velocity := velocity
	if (
		_state_machine.state == PlayerStateMachineType.STATE_WALL_RUN
		and _active_wall_sample != null
	):
		prediction_velocity = _wall_detach_velocity_for(
			_active_wall_sample
		)
	elif _state_machine.state == PlayerStateMachineType.STATE_SWING:
		prediction_velocity = _current_swing_release_velocity()
	return {
		&"state": _state_machine.state,
		&"origin": context_position,
		&"velocity": prediction_velocity,
		&"spinning": _state_machine.is_spinning,
	}


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
	move_tuning: MoveTuning,
	hog_tuning: HogTuning
) -> float:
	match impulse:
		PlayerFrameDecisionType.IMPULSE_DOUBLE_JUMP:
			return move_tuning.double_jump_tap_height_m
		PlayerFrameDecisionType.IMPULSE_JUMP:
			return move_tuning.jump_tap_height_m
		PlayerFrameDecisionType.IMPULSE_RIDE_JUMP:
			if hog_tuning != null:
				return hog_tuning.hog_jump_height_m
	return 0.0


func try_edge_landing_nudge() -> bool:
	if (
		_input_tuning == null
		or _move_tuning == null
		or not is_inside_tree()
		or PlayerMotorType.uses_spline_motion(_state_machine.state)
	):
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
		or PlayerMotorType.uses_spline_motion(_state_machine.state)
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
	respawn_started.emit()
	global_transform = _spawn_transform
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_respawn_due_s = -1.0
	_clear_rail_state()
	_clear_wall_run_state()
	_clear_swing_state()
	_clear_bounce_timing_window()
	_state_machine = PlayerStateMachineType.new()
	if _ride_mounted and _hog_tuning != null:
		_state_machine.enter_ride(
			MonotonicClockType.now_s()
		)
	_last_state = &""
	_last_spin_active = false
	_fall_apex_y = global_position.y
	if _move_tuning != null:
		_active_jump_tap_height_m = _move_tuning.jump_tap_height_m
	if _intents != null:
		_intents.clear()
	_apply_character_dimensions(_state_machine.state)
	_apply_motion_mode(_state_machine.state)
	if _spin_visual_pivot != null:
		_spin_visual_pivot.rotation.y = 0.0
	respawned.emit()


func _apply_late_bounce_press(now_s: float) -> void:
	if not _bounce_window_active:
		return
	var contact_age_s := now_s - _bounce_contact_s
	if (
		contact_age_s > _input_tuning.bounce_timing_s
		and not is_equal_approx(
			contact_age_s,
			_input_tuning.bounce_timing_s
		)
	):
		_clear_bounce_timing_window()
		return
	var press := _intents.consume_pressed(
		InputIntent.ACTION_JUMP,
		now_s,
		_input_tuning.bounce_timing_s
	)
	if press == null:
		return
	if (
		press.timestamp_s < _bounce_contact_s
		and not is_equal_approx(
			press.timestamp_s,
			_bounce_contact_s
		)
	):
		return
	var remaining_height_m := maxf(
		_bounce_target_apex_y - global_position.y,
		0.0
	)
	velocity.y = maxf(
		velocity.y,
		JumpKinematicsType.upward_speed_for_height(
			remaining_height_m,
			_move_tuning
		)
	)
	_active_jump_tap_height_m = 0.0
	_clear_bounce_timing_window()


func _clear_bounce_timing_window() -> void:
	_bounce_window_active = false


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
	_try_automatic_rail_attach(now_s)
	_try_automatic_wall_attach(now_s)
	_try_automatic_swing_catch(now_s)
	advance_logic(now_s, is_on_floor(), delta_s, _corridor_forward)
	if (
		not PlayerMotorType.uses_spline_motion(_state_machine.state)
		and not is_on_floor()
		and velocity.y <= 0.0
	):
		try_soft_landing_assist()
		try_edge_landing_nudge()
	move_and_slide()
	_reproject_active_rail()
	_reproject_active_wall()
	_reproject_active_swing()
	if global_position.y < _move_tuning.respawn_floor_y_m:
		request_respawn(now_s)


func try_rail_attach(
	arc_points: PackedVector3Array,
	now_s: float
) -> bool:
	if (
		_grind_tuning == null
		or not is_inside_tree()
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return false
	var merged_samples: Array[TraversalSample] = []
	var sample_rails: Array[TraversalRailType] = []
	for candidate: Node in get_tree().get_nodes_in_group(
		TraversalRailType.RAIL_GROUP
	):
		if not candidate is TraversalRailType:
			continue
		var rail := candidate as TraversalRailType
		if rail == _rail_attach_blocked:
			continue
		for sample: TraversalSample in rail.samples():
			merged_samples.append(sample)
			sample_rails.append(rail)
	var sample_index := TraversalAttachSolverType.solve_rail_attach(
		arc_points,
		merged_samples,
		_grind_tuning.attach_snap_m
	)
	if sample_index < 0:
		return false
	var sample := merged_samples[sample_index]
	var rail := sample_rails[sample_index]
	_active_rail = rail
	_active_rail_distance_m = sample.distance_along_m
	_grind_speed_mps = maxf(velocity.dot(sample.tangent), 0.0)
	_rail_hop_target = null
	_rail_attach_blocked = null
	_state_machine.enter_grind(now_s)
	global_position = sample.position
	velocity = Vector3.ZERO
	_apply_grind_bank()
	_apply_motion_mode(_state_machine.state)
	reset_physics_interpolation()
	return true


func _try_automatic_rail_attach(now_s: float) -> void:
	if (
		_move_tuning == null
		or _depth_tuning == null
		or is_on_floor()
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return
	var arc_points := DepthPredictionType.trajectory_points(
		global_position,
		velocity,
		_state_machine.is_spinning,
		_move_tuning,
		_depth_tuning
	)
	try_rail_attach(arc_points, now_s)


func try_wall_attach(
	strip: WallRunStripType,
	now_s: float
) -> bool:
	if (
		_wall_run_tuning == null
		or not is_inside_tree()
		or not is_instance_valid(strip)
		or strip == _wall_attach_blocked
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return false
	var sample: TraversalSample = strip.sample_at(global_position)
	if sample == null:
		return false
	var held_position := (
		sample.position
		+ sample.normal * _wall_run_tuning.surface_stick_distance_m
	)
	if (
		global_position.distance_to(held_position)
		> _wall_run_tuning.surface_stick_distance_m
	):
		return false
	if not TraversalAttachSolverType.solve_wall_attach(
		global_position,
		velocity,
		sample,
		_wall_run_tuning.attach_cone_degrees,
		_wall_run_tuning.minimum_entry_speed_mps
	):
		return false
	var vertical_speed_mps := velocity.y
	var run_direction := _horizontal_direction(sample.tangent)
	_active_wall_strip = strip
	_active_wall_sample = sample
	_wall_attach_blocked = null
	_state_machine.enter_wall_run(
		now_s,
		_wall_run_tuning.maximum_duration_s
	)
	global_position = held_position
	velocity = run_direction * _wall_run_tuning.run_speed_mps
	velocity.y = vertical_speed_mps
	_apply_motion_mode(_state_machine.state)
	reset_physics_interpolation()
	return true


func _try_automatic_wall_attach(now_s: float) -> void:
	if (
		_wall_run_tuning == null
		or is_on_floor()
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return
	for candidate: Node in get_tree().get_nodes_in_group(
		WallRunStripType.STRIP_GROUP
	):
		if (
			candidate is WallRunStripType
			and try_wall_attach(candidate as WallRunStripType, now_s)
		):
			return


func try_swing_catch(
	anchor: SwingAnchorType,
	now_s: float
) -> bool:
	if (
		_swing_tuning == null
		or _swing_tuning.rope_length_m <= 0.0
		or not is_inside_tree()
		or not is_instance_valid(anchor)
		or anchor == _swing_attach_blocked
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return false
	anchor.refresh_tuning(_swing_tuning)
	var is_chain_transfer := is_instance_valid(_swing_attach_blocked)
	var catch_radius_m := (
		_swing_tuning.transfer_catch_radius_m
		if is_chain_transfer
		else _swing_tuning.catch_radius_m
	)
	if not anchor.can_catch(
		global_position,
		catch_radius_m,
		_swing_tuning
	):
		return false
	var angle_rad := anchor.angle_for(global_position)
	var maximum_angular_speed := (
		_swing_tuning.maximum_speed_mps
		/ _swing_tuning.rope_length_m
	)
	var angular_velocity := clampf(
		anchor.angular_velocity_for(
			velocity,
			angle_rad,
			_swing_tuning
		),
		-maximum_angular_speed,
		maximum_angular_speed
	)
	var catch_speed_mps := (
		absf(angular_velocity) * _swing_tuning.rope_length_m
	)
	if catch_speed_mps < _swing_tuning.minimum_catch_speed_mps:
		if (
			not is_chain_transfer
			or catch_speed_mps
			< _swing_tuning.transfer_minimum_catch_speed_mps
		):
			return false
		angular_velocity = (
			signf(angular_velocity)
			* _swing_tuning.minimum_catch_speed_mps
			/ _swing_tuning.rope_length_m
		)
	_active_swing_anchor = anchor
	_swing_attach_blocked = null
	_swing_angle_rad = angle_rad
	_swing_angular_velocity = angular_velocity
	_state_machine.enter_swing(now_s)
	global_position = anchor.position_for(angle_rad, _swing_tuning)
	velocity = Vector3.ZERO
	anchor.set_rope_angle(angle_rad)
	_apply_motion_mode(_state_machine.state)
	reset_physics_interpolation()
	return true


func _try_automatic_swing_catch(now_s: float) -> void:
	if (
		_swing_tuning == null
		or is_on_floor()
		or _state_machine.state != PlayerStateMachineType.STATE_AIRBORNE
	):
		return
	for candidate: Node in get_tree().get_nodes_in_group(
		SwingAnchorType.ANCHOR_GROUP
	):
		if (
			candidate is SwingAnchorType
			and try_swing_catch(candidate as SwingAnchorType, now_s)
		):
			return


func _update_rail_neighbour_context() -> void:
	_traversal_neighbour_available = false
	if not is_instance_valid(_active_rail) or _intents == null:
		return
	var direction := _lateral_direction(_intents.movement().x)
	if direction == 0:
		return
	_traversal_neighbour_available = (
		_active_rail.parallel_neighbor(direction) != null
	)


func _advance_grind_motion(delta_s: float, now_s: float) -> void:
	if (
		not is_instance_valid(_active_rail)
		or _grind_tuning == null
		or delta_s <= 0.0
	):
		return
	var rail_length_m := _active_rail.length_m()
	if _active_rail_distance_m >= rail_length_m:
		_finish_grind(now_s)
		return
	_grind_speed_mps = move_toward(
		_grind_speed_mps,
		_grind_tuning.speed_mps,
		_grind_tuning.acceleration_mps2 * delta_s
	)
	_active_rail_distance_m = minf(
		_active_rail_distance_m + _grind_speed_mps * delta_s,
		rail_length_m
	)
	var target_sample: TraversalSample = _active_rail.sample_at_distance(
		_active_rail_distance_m
	)
	if target_sample == null:
		_finish_grind(now_s)
		return
	velocity = (target_sample.position - global_position) / delta_s
	_apply_grind_bank()


func _finish_grind(now_s: float) -> void:
	_state_machine.enter_airborne(now_s)
	_apply_rail_exit()
	_apply_motion_mode(_state_machine.state)


func _advance_wall_run_motion(delta_s: float, now_s: float) -> void:
	if (
		not is_instance_valid(_active_wall_strip)
		or _wall_run_tuning == null
		or _move_tuning == null
	):
		return
	var sample: TraversalSample = _active_wall_strip.sample_at(
		global_position
	)
	if sample == null:
		_state_machine.enter_airborne(now_s)
		_finish_wall_run()
		_apply_motion_mode(_state_machine.state)
		return
	_active_wall_sample = sample
	var strip_length_m := _active_wall_strip.length_m()
	var step_distance_m := (
		_wall_run_tuning.run_speed_mps * maxf(delta_s, 0.0)
	)
	if sample.distance_along_m + step_distance_m >= strip_length_m:
		var end_sample: TraversalSample = (
			_active_wall_strip.sample_at_distance(strip_length_m)
		)
		if end_sample != null:
			_active_wall_sample = end_sample
			global_position = (
				end_sample.position
				+ end_sample.normal
				* _wall_run_tuning.surface_stick_distance_m
			)
			reset_physics_interpolation()
		_state_machine.enter_airborne(now_s)
		_apply_wall_detach()
		_apply_motion_mode(_state_machine.state)
		return
	var run_direction := _horizontal_direction(sample.tangent)
	velocity.x = run_direction.x * _wall_run_tuning.run_speed_mps
	velocity.z = run_direction.z * _wall_run_tuning.run_speed_mps
	if delta_s > 0.0:
		velocity.y = maxf(
			velocity.y
			- _move_tuning.gravity_mps2
			* _wall_run_tuning.gravity_multiplier
			* delta_s,
			-_move_tuning.maximum_fall_speed_mps
		)


func _apply_wall_detach() -> void:
	if (
		not is_instance_valid(_active_wall_strip)
		or _wall_run_tuning == null
		or _move_tuning == null
	):
		return
	var departed_strip := _active_wall_strip
	var sample := _active_wall_sample
	if sample == null:
		sample = departed_strip.sample_at(global_position)
	if sample == null:
		_finish_wall_run()
		return
	velocity = _wall_detach_velocity_for(sample)
	_wall_attach_blocked = departed_strip
	_active_wall_strip = null
	_active_wall_sample = null


func _wall_detach_velocity_for(sample: TraversalSample) -> Vector3:
	if (
		sample == null
		or _wall_run_tuning == null
		or _move_tuning == null
	):
		return velocity
	var run_direction := _horizontal_direction(sample.tangent)
	var outward_direction := _horizontal_direction(sample.normal)
	var detach_velocity := (
		run_direction * _wall_run_tuning.run_speed_mps
		+ outward_direction * _wall_run_tuning.detach_outward_speed_mps
	)
	detach_velocity.y = JumpKinematicsType.upward_speed_for_height(
		_wall_run_tuning.detach_height_m,
		_move_tuning
	)
	return detach_velocity


func _finish_wall_run() -> void:
	if is_instance_valid(_active_wall_strip):
		_wall_attach_blocked = _active_wall_strip
	_active_wall_strip = null
	_active_wall_sample = null


func _advance_swing_motion(delta_s: float) -> void:
	if (
		not is_instance_valid(_active_swing_anchor)
		or _swing_tuning == null
		or _move_tuning == null
		or delta_s <= 0.0
	):
		return
	_active_swing_anchor.refresh_tuning(_swing_tuning)
	var next_state := SwingPendulumType.step(
		_swing_angle_rad,
		_swing_angular_velocity,
		delta_s,
		_swing_tuning,
		_move_tuning.gravity_mps2
	)
	_swing_angle_rad = next_state["angle_rad"]
	_swing_angular_velocity = next_state["angular_velocity"]
	var target_position := _active_swing_anchor.position_for(
		_swing_angle_rad,
		_swing_tuning
	)
	velocity = (target_position - global_position) / delta_s
	_active_swing_anchor.set_rope_angle(_swing_angle_rad)


func _apply_swing_release() -> void:
	if (
		not is_instance_valid(_active_swing_anchor)
		or _swing_tuning == null
	):
		return
	var departed_anchor := _active_swing_anchor
	velocity = _current_swing_release_velocity()
	departed_anchor.reset_rope_visual()
	_swing_attach_blocked = departed_anchor
	_active_swing_anchor = null
	_swing_angle_rad = 0.0
	_swing_angular_velocity = 0.0


func _current_swing_release_velocity() -> Vector3:
	if (
		not is_instance_valid(_active_swing_anchor)
		or _swing_tuning == null
	):
		return velocity
	var local_velocity := SwingPendulumType.release_velocity(
		_swing_angle_rad,
		_swing_angular_velocity,
		_swing_tuning
	)
	return _active_swing_anchor.world_velocity(local_velocity)


func _apply_rail_hop() -> void:
	if not is_instance_valid(_active_rail):
		return
	var departed_rail := _active_rail
	var direction := _lateral_direction(_intents.movement().x)
	var neighbor := departed_rail.parallel_neighbor(direction)
	if neighbor == null:
		_apply_rail_exit()
		return
	var current_sample: TraversalSample = departed_rail.sample_at_distance(
		_active_rail_distance_m
	)
	var neighbor_sample: TraversalSample = neighbor.sample_at_distance(
		minf(_active_rail_distance_m, neighbor.length_m())
	)
	if current_sample == null or neighbor_sample == null:
		_apply_rail_exit()
		return
	var forward := _horizontal_direction(current_sample.tangent)
	var lateral := neighbor_sample.position - current_sample.position
	lateral.y = 0.0
	lateral -= forward * lateral.dot(forward)
	if lateral.is_zero_approx():
		lateral = _corridor_right() * float(direction)
	var lateral_speed_mps := JumpKinematicsType.horizontal_speed_for_jump(
		_grind_tuning.hop_lateral_distance_m,
		_grind_tuning.hop_height_m,
		_move_tuning
	)
	velocity = (
		forward * _grind_speed_mps
		+ lateral.normalized() * lateral_speed_mps
	)
	velocity.y = JumpKinematicsType.upward_speed_for_height(
		_grind_tuning.hop_height_m,
		_move_tuning
	)
	_rail_hop_target = neighbor
	_rail_attach_blocked = departed_rail
	_active_rail = null
	_reset_grind_bank()
	reset_physics_interpolation()


func _apply_rail_exit() -> void:
	if not is_instance_valid(_active_rail):
		return
	var departed_rail := _active_rail
	var sample: TraversalSample = departed_rail.sample_at_distance(
		_active_rail_distance_m
	)
	var forward := (
		_horizontal_direction(sample.tangent)
		if sample != null
		else _horizontal_direction(_corridor_forward)
	)
	velocity = forward * _grind_tuning.exit_forward_speed_mps
	velocity.y = JumpKinematicsType.upward_speed_for_height(
		_grind_tuning.hop_height_m,
		_move_tuning
	)
	_rail_attach_blocked = departed_rail
	_rail_hop_target = null
	_active_rail = null
	_reset_grind_bank()


func _reproject_active_rail() -> void:
	if (
		_state_machine.state == PlayerStateMachineType.STATE_GRIND
		and is_instance_valid(_active_rail)
	):
		_active_rail_distance_m = _active_rail.closest_distance_m(
			global_position
		)


func _reproject_active_wall() -> void:
	if (
		_state_machine.state != PlayerStateMachineType.STATE_WALL_RUN
		or not is_instance_valid(_active_wall_strip)
		or _wall_run_tuning == null
	):
		return
	var sample: TraversalSample = _active_wall_strip.sample_at(
		global_position
	)
	if sample == null:
		return
	var current_distance_m := (
		global_position - sample.position
	).dot(sample.normal)
	global_position += (
		sample.normal
		* (
			_wall_run_tuning.surface_stick_distance_m
			- current_distance_m
		)
	)
	_active_wall_sample = sample


func _reproject_active_swing() -> void:
	if (
		_state_machine.state == PlayerStateMachineType.STATE_SWING
		and is_instance_valid(_active_swing_anchor)
		and _swing_tuning != null
	):
		global_position = _active_swing_anchor.position_for(
			_swing_angle_rad,
			_swing_tuning
		)


func _apply_grind_bank() -> void:
	if _visual_root != null and _grind_tuning != null:
		_visual_root.rotation.z = deg_to_rad(_grind_tuning.bank_degrees)


func _reset_grind_bank() -> void:
	if _visual_root != null:
		_visual_root.rotation.z = 0.0


func _clear_rail_state() -> void:
	_active_rail = null
	_rail_hop_target = null
	_rail_attach_blocked = null
	_active_rail_distance_m = 0.0
	_grind_speed_mps = 0.0
	_traversal_neighbour_available = false
	_reset_grind_bank()


func _clear_wall_run_state() -> void:
	_active_wall_strip = null
	_wall_attach_blocked = null
	_active_wall_sample = null


func _clear_swing_state() -> void:
	if is_instance_valid(_active_swing_anchor):
		_active_swing_anchor.reset_rope_visual()
	_active_swing_anchor = null
	_swing_attach_blocked = null
	_swing_angle_rad = 0.0
	_swing_angular_velocity = 0.0


func _lateral_direction(input_x: float) -> int:
	if input_x < 0.0:
		return -1
	if input_x > 0.0:
		return 1
	return 0


func _horizontal_direction(direction: Vector3) -> Vector3:
	var horizontal := Vector3(direction.x, 0.0, direction.z).normalized()
	return horizontal if not horizontal.is_zero_approx() else _corridor_forward


func _corridor_right() -> Vector3:
	return _horizontal_direction(_corridor_forward).cross(Vector3.UP).normalized()


func _apply_vertical_physics(grounded: bool, delta_s: float) -> void:
	if PlayerMotorType.uses_spline_motion(_state_machine.state):
		return
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


func _apply_motion_mode(state: StringName) -> void:
	motion_mode = (
		MOTION_MODE_FLOATING
		if PlayerMotorType.uses_spline_motion(state)
		else MOTION_MODE_GROUNDED
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
		_visual_root.scale = Vector3.ONE
		_visual_root.position = Vector3.ZERO
		if state == PlayerStateMachineType.STATE_RIDE:
			_visual_root.position = ride_visual_offset
		_visual_root.position.y += (
			_move_tuning.player_height_m * ScalarMathType.HALF
		)
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
