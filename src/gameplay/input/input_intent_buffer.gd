class_name InputIntentBuffer
extends RefCounted

var _movement := Vector2.ZERO
var _active_source := &""
var _pressed: Dictionary = {}
var _pressed_at: Dictionary = {}
var _last_hold_durations: Dictionary = {}
var _press_queues: Dictionary = {}
var _release_queues: Dictionary = {}


func push(intent: InputIntent) -> void:
	if intent == null:
		return
	_active_source = intent.source
	if intent.is_movement:
		_movement = intent.movement_value.limit_length(1.0)
		return

	if intent.pressed:
		if not is_action_pressed(intent.action):
			_queue_for(_press_queues, intent.action).append(intent)
			_pressed_at[intent.action] = intent.timestamp_s
		_pressed[intent.action] = true
		return

	if is_action_pressed(intent.action):
		var pressed_timestamp: float = _pressed_at.get(intent.action, intent.timestamp_s)
		_last_hold_durations[intent.action] = maxf(
			intent.timestamp_s - pressed_timestamp,
			0.0
		)
		_queue_for(_release_queues, intent.action).append(intent)
	_pressed[intent.action] = false


func movement() -> Vector2:
	return _movement


func active_source() -> StringName:
	return _active_source


func is_action_pressed(action: StringName) -> bool:
	return _pressed.get(action, false)


func pressed_duration(action: StringName, now_s: float) -> float:
	if not is_action_pressed(action):
		return 0.0
	return maxf(now_s - float(_pressed_at.get(action, now_s)), 0.0)


func last_hold_duration(action: StringName) -> float:
	return float(_last_hold_durations.get(action, 0.0))


func has_buffered_pressed(action: StringName, now_s: float, window_s: float) -> bool:
	_prune(_press_queues, action, now_s, window_s)
	return not _queue_for(_press_queues, action).is_empty()


func consume_pressed(action: StringName, now_s: float, window_s: float) -> InputIntent:
	return _consume(_press_queues, action, now_s, window_s)


func consume_released(action: StringName, now_s: float, window_s: float) -> InputIntent:
	return _consume(_release_queues, action, now_s, window_s)


func prune_expired(now_s: float, window_s: float) -> void:
	for action: StringName in _press_queues.keys():
		_prune(_press_queues, action, now_s, window_s)
	for action: StringName in _release_queues.keys():
		_prune(_release_queues, action, now_s, window_s)


func clear() -> void:
	_movement = Vector2.ZERO
	_active_source = &""
	_pressed.clear()
	_pressed_at.clear()
	_last_hold_durations.clear()
	_press_queues.clear()
	_release_queues.clear()


func _consume(
	queues: Dictionary,
	action: StringName,
	now_s: float,
	window_s: float
) -> InputIntent:
	_prune(queues, action, now_s, window_s)
	var queue := _queue_for(queues, action)
	if queue.is_empty():
		return null
	return queue.pop_front()


func _prune(
	queues: Dictionary,
	action: StringName,
	now_s: float,
	window_s: float
) -> void:
	var queue := _queue_for(queues, action)
	while not queue.is_empty():
		var intent: InputIntent = queue.front()
		var age_s := now_s - intent.timestamp_s
		if age_s < window_s or is_equal_approx(age_s, window_s):
			return
		queue.pop_front()


func _queue_for(queues: Dictionary, action: StringName) -> Array:
	if not queues.has(action):
		queues[action] = []
	return queues[action]
