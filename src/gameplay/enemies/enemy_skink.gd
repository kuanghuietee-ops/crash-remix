class_name EnemySkink
extends EnemyBase

var _state_deadline_s: float = -1.0
var _active_started_s: float = -1.0


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
	if (
		behavior_state() == STATE_DORMANT
		and _player_is_inside_trigger(player_position)
	):
		_set_behavior_state(STATE_TELEGRAPH)
		_state_deadline_s = now_s + _enemy_tuning.telegraph_s

	if (
		behavior_state() == STATE_TELEGRAPH
		and now_s >= _state_deadline_s
	):
		_active_started_s = _state_deadline_s
		_state_deadline_s += _enemy_tuning.attack_active_s
		_set_behavior_state(STATE_ACTIVE)
		_set_attack_active(true)

	if behavior_state() == STATE_ACTIVE:
		if now_s >= _state_deadline_s:
			_set_authored_lateral_offset(0.0)
			_set_attack_active(false)
			_set_behavior_state(STATE_COOLDOWN)
			_state_deadline_s += (
				_enemy_tuning.attack_cooldown_s
			)
		else:
			var dart_offset_m := minf(
				_enemy_tuning.patrol_speed_mps
				* (now_s - _active_started_s),
				_enemy_tuning.patrol_span_m
				* ScalarMathType.HALF
			)
			_set_authored_lateral_offset(dart_offset_m)

	if (
		behavior_state() == STATE_COOLDOWN
		and now_s >= _state_deadline_s
	):
		_set_authored_lateral_offset(0.0)
		_set_behavior_state(STATE_DORMANT)
		if _player_is_inside_trigger(player_position):
			_set_behavior_state(STATE_TELEGRAPH)
			_state_deadline_s = (
				now_s + _enemy_tuning.telegraph_s
			)


func delay_timers(duration_s: float) -> void:
	if duration_s <= 0.0:
		return
	if _state_deadline_s >= 0.0:
		_state_deadline_s += duration_s
	if _active_started_s >= 0.0:
		_active_started_s += duration_s


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


func _reset_behavior_state() -> void:
	_state_deadline_s = -1.0
	_active_started_s = -1.0
	_set_behavior_state(STATE_DORMANT)
