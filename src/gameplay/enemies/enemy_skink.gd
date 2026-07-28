class_name EnemySkink
extends EnemyBase

var _state_deadline_s: float = -1.0
var _lateral_offset_m: float = 0.0
var _last_logic_s: float = -1.0


func _ready() -> void:
	super._ready()
	var visual_driver := _visual_driver()
	if (
		visual_driver != null
		and visual_driver.has_signal(&"defeat_finished")
		and not visual_driver.is_connected(
			&"defeat_finished",
			_on_defeat_visual_finished
		)
	):
		visual_driver.connect(
			&"defeat_finished",
			_on_defeat_visual_finished
		)
	_sync_visual_state()


func enemy_kind() -> StringName:
	return &"skink"


func tuning_section() -> StringName:
	return &"enemy_skink"


func accepted_verbs() -> Array[StringName]:
	return [
		VERB_SPIN,
		VERB_JUMP,
	]


func advance_logic(
	now_s: float,
	player_position: Vector3
) -> void:
	if is_defeated() or _enemy_tuning == null:
		return
	var movement_elapsed_s := _movement_elapsed_s(now_s)
	var entered_active := false
	var entered_cooldown := false
	if (
		behavior_state() == STATE_DORMANT
		and _player_is_inside_corridor_trigger(player_position)
	):
		_set_behavior_state(STATE_TELEGRAPH)
		_state_deadline_s = now_s + _enemy_tuning.telegraph_s

	if (
		behavior_state() == STATE_TELEGRAPH
		and now_s >= _state_deadline_s
	):
		_state_deadline_s += _enemy_tuning.attack_active_s
		_set_behavior_state(STATE_ACTIVE)
		_set_attack_active(true)
		entered_active = true

	if behavior_state() == STATE_ACTIVE:
		if not entered_active:
			_lateral_offset_m = minf(
				_lateral_offset_m
					+ _enemy_tuning.patrol_speed_mps
					* movement_elapsed_s,
				_dart_distance_m()
			)
			_set_authored_lateral_offset(_lateral_offset_m)
		if now_s >= _state_deadline_s:
			_set_attack_active(false)
			_set_behavior_state(STATE_COOLDOWN)
			_state_deadline_s += (
				_enemy_tuning.attack_cooldown_s
			)
			entered_cooldown = true

	if behavior_state() == STATE_COOLDOWN:
		if not entered_cooldown:
			_lateral_offset_m = maxf(
				_lateral_offset_m
					- _enemy_tuning.patrol_speed_mps
					* movement_elapsed_s,
				0.0
			)
			_set_authored_lateral_offset(_lateral_offset_m)
		if (
			now_s >= _state_deadline_s
			and is_zero_approx(_lateral_offset_m)
		):
			_set_authored_lateral_offset(0.0)
			_set_behavior_state(STATE_DORMANT)
			if _player_is_inside_corridor_trigger(
				player_position
			):
				_set_behavior_state(STATE_TELEGRAPH)
				_state_deadline_s = (
					now_s + _enemy_tuning.telegraph_s
				)


func delay_timers(duration_s: float) -> void:
	if duration_s <= 0.0:
		return
	if _state_deadline_s >= 0.0:
		_state_deadline_s += duration_s
	if _last_logic_s >= 0.0:
		_last_logic_s += duration_s


func resolve_contact(
	verb: StringName,
	now_s: float
) -> Dictionary:
	var result := super.resolve_contact(verb, now_s)
	if (
		verb == VERB_JUMP
		and bool(result["enemy_defeated"])
	):
		result["player_bounce"] = true
	return result


func _player_is_inside_corridor_trigger(
	player_position: Vector3
) -> bool:
	var authored_spawn := authored_spawn_transform()
	var corridor_forward := (
		authored_spawn.basis.z.normalized()
	)
	var player_delta := player_position - authored_spawn.origin
	var forward_offset_m := player_delta.dot(corridor_forward)
	var forward_distance_m := absf(
		forward_offset_m
	)
	var lateral_distance_m := (
		player_delta
			- corridor_forward * forward_offset_m
	).length()
	return (
		forward_distance_m <= _enemy_tuning.trigger_range_m
		and lateral_distance_m
			<= _enemy_tuning.trigger_lateral_m
	)


func _dart_distance_m() -> float:
	return _enemy_tuning.patrol_span_m


func _movement_elapsed_s(now_s: float) -> float:
	if _last_logic_s < 0.0:
		_last_logic_s = now_s
		return 0.0
	if now_s <= _last_logic_s:
		return 0.0
	var elapsed_s := minf(
		now_s - _last_logic_s,
		get_physics_process_delta_time()
	)
	_last_logic_s = now_s
	return elapsed_s


func _reset_behavior_state() -> void:
	_state_deadline_s = -1.0
	_lateral_offset_m = 0.0
	_last_logic_s = -1.0
	_set_behavior_state(STATE_DORMANT)


func _set_behavior_state(state: StringName) -> void:
	super._set_behavior_state(state)
	_sync_visual_state()


func _set_defeated(defeated: bool) -> void:
	super._set_defeated(defeated)
	var visual_driver := _visual_driver()
	if visual_driver == null:
		return
	if defeated:
		visible = true
		if visual_driver.has_method("play_defeat"):
			visual_driver.call("play_defeat")
	elif visual_driver.has_method("reset_visual"):
		visual_driver.call("reset_visual")


func _sync_visual_state() -> void:
	var visual_driver := _visual_driver()
	if (
		visual_driver != null
		and visual_driver.has_method("set_behavior_state")
	):
		visual_driver.call(
			"set_behavior_state",
			behavior_state()
		)


func _visual_driver() -> Node:
	return get_node_or_null("VisualDriver")


func _on_defeat_visual_finished() -> void:
	if is_defeated():
		visible = false
