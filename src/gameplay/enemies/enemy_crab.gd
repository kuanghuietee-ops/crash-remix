class_name EnemyCrab
extends EnemyBase

var _patrol_direction: float = 1.0
var _lateral_offset_m: float = 0.0
var _last_logic_s: float = -1.0
var _turn_pause_until_s: float = -1.0


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
	_sync_visual_patrol()


func enemy_kind() -> StringName:
	return &"crab"


func tuning_section() -> StringName:
	return &"enemy_crab"


func accepted_verbs() -> Array[StringName]:
	return [
		VERB_SPIN,
		VERB_JUMP,
		VERB_SLIDE,
		VERB_SLAM,
	]


func advance_logic(
	now_s: float,
	_player_position: Vector3
) -> void:
	if is_defeated() or _enemy_tuning == null:
		return
	if _last_logic_s < 0.0:
		_last_logic_s = now_s
		return
	if now_s <= _last_logic_s:
		return
	if behavior_state() == STATE_TURN_PAUSE:
		if now_s < _turn_pause_until_s:
			return
		_last_logic_s = _turn_pause_until_s
		_set_behavior_state(STATE_PATROL)

	var elapsed_s := now_s - _last_logic_s
	var half_span_m := (
		_enemy_tuning.patrol_span_m
		* ScalarMathType.HALF
	)
	var next_offset_m := (
		_lateral_offset_m
		+ _patrol_direction
		* _enemy_tuning.patrol_speed_mps
		* elapsed_s
	)
	if absf(next_offset_m) >= half_span_m:
		_lateral_offset_m = (
			half_span_m
			* _patrol_direction
		)
		_patrol_direction *= -1.0
		_set_behavior_state(STATE_TURN_PAUSE)
		_turn_pause_until_s = (
			now_s + _enemy_tuning.turn_pause_s
		)
	else:
		_lateral_offset_m = next_offset_m
	_last_logic_s = now_s
	_set_authored_lateral_offset(_lateral_offset_m)


func delay_timers(duration_s: float) -> void:
	if duration_s <= 0.0:
		return
	if _last_logic_s >= 0.0:
		_last_logic_s += duration_s
	if _turn_pause_until_s >= 0.0:
		_turn_pause_until_s += duration_s


func resolve_contact(
	verb: StringName,
	now_s: float
) -> Dictionary:
	var result := super.resolve_contact(verb, now_s)
	if bool(result["player_hit"]):
		var visual_driver := _visual_driver()
		if (
			visual_driver != null
			and visual_driver.has_method("play_attack")
		):
			visual_driver.call("play_attack")
	if (
		verb == VERB_JUMP
		and bool(result["enemy_defeated"])
	):
		result["player_bounce"] = true
	return result


func _reset_behavior_state() -> void:
	_patrol_direction = 1.0
	_lateral_offset_m = 0.0
	_last_logic_s = -1.0
	_turn_pause_until_s = -1.0
	_set_behavior_state(STATE_PATROL)


func _set_behavior_state(state: StringName) -> void:
	super._set_behavior_state(state)
	_sync_visual_patrol()


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


func _sync_visual_patrol() -> void:
	var visual_driver := _visual_driver()
	if (
		visual_driver != null
		and visual_driver.has_method("set_patrolling")
	):
		visual_driver.call(
			"set_patrolling",
			behavior_state() == STATE_PATROL
		)


func _visual_driver() -> Node:
	return get_node_or_null("VisualDriver")


func _on_defeat_visual_finished() -> void:
	if is_defeated():
		visible = false
