class_name EnemyPlant
extends EnemyBase

var _state_deadline_s: float = -1.0


func enemy_kind() -> StringName:
	return &"plant"


func tuning_section() -> StringName:
	return &"enemy_plant"


func accepted_verbs() -> Array[StringName]:
	return [
		VERB_SPIN,
		VERB_SLAM,
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
		_set_behavior_state(STATE_ACTIVE)
		_set_attack_active(true)
		_state_deadline_s += _enemy_tuning.attack_active_s

	if (
		behavior_state() == STATE_ACTIVE
		and now_s >= _state_deadline_s
	):
		_set_attack_active(false)
		_set_behavior_state(STATE_COOLDOWN)
		_state_deadline_s += _enemy_tuning.attack_cooldown_s

	if (
		behavior_state() == STATE_COOLDOWN
		and now_s >= _state_deadline_s
	):
		_set_behavior_state(STATE_DORMANT)
		if _player_is_inside_trigger(player_position):
			_set_behavior_state(STATE_TELEGRAPH)
			_state_deadline_s = (
				now_s + _enemy_tuning.telegraph_s
			)


func delay_timers(duration_s: float) -> void:
	if duration_s > 0.0 and _state_deadline_s >= 0.0:
		_state_deadline_s += duration_s


func resolve_contact(
	verb: StringName,
	now_s: float
) -> Dictionary:
	if is_defeated():
		return _outcome()
	if verb in accepted_verbs():
		return apply_verb(verb, now_s)
	if verb == VERB_JUMP:
		if attack_is_active():
			return _outcome(false, true)
		return _outcome(false, false, true)
	if attack_is_active():
		return _outcome(false, true)
	return _outcome()


func _reset_behavior_state() -> void:
	_state_deadline_s = -1.0
	_set_behavior_state(STATE_DORMANT)
