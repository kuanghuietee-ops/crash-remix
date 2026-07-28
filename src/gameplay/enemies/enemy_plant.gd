class_name EnemyPlant
extends EnemyBase

var _state_deadline_s: float = -1.0


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
