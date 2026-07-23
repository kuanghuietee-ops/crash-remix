extends GutTest

const INTENT_SCRIPT_PATH := "res://src/gameplay/input/input_intent.gd"
const BUFFER_SCRIPT_PATH := "res://src/gameplay/input/input_intent_buffer.gd"


func test_pressed_intent_is_consumed_inside_buffer_window() -> void:
	var buffer: RefCounted = _new_buffer()
	if buffer == null:
		return
	buffer.call("push", _button_intent(&"jump", true, 1.0, &"touch"))

	var consumed: RefCounted = buffer.call("consume_pressed", &"jump", 1.12, 0.12)

	assert_not_null(consumed)
	assert_eq(consumed.get("timestamp_s"), 1.0)
	assert_null(buffer.call("consume_pressed", &"jump", 1.12, 0.12))


func test_pressed_intent_expires_after_buffer_window() -> void:
	var buffer: RefCounted = _new_buffer()
	if buffer == null:
		return
	buffer.call("push", _button_intent(&"jump", true, 2.0, &"touch"))

	assert_null(buffer.call("consume_pressed", &"jump", 2.121, 0.12))


func test_release_records_hold_duration() -> void:
	var buffer: RefCounted = _new_buffer()
	if buffer == null:
		return
	buffer.call("push", _button_intent(&"jump", true, 3.0, &"gamepad"))
	buffer.call("push", _button_intent(&"jump", false, 3.22, &"gamepad"))

	assert_false(buffer.call("is_action_pressed", &"jump"))
	assert_almost_eq(buffer.call("last_hold_duration", &"jump"), 0.22, 0.0001)
	assert_not_null(buffer.call("consume_released", &"jump", 3.3, 0.15))


func test_movement_intent_updates_vector_and_active_source() -> void:
	var buffer: RefCounted = _new_buffer()
	if buffer == null:
		return
	var intent: RefCounted = _movement_intent(Vector2(0.25, -0.75), 4.0, &"touch")

	buffer.call("push", intent)

	assert_eq(buffer.call("movement"), Vector2(0.25, -0.75))
	assert_eq(buffer.call("active_source"), &"touch")


func test_prune_expired_discards_unconsumed_release_intents_for_every_action() -> void:
	var buffer: RefCounted = _new_buffer()
	if buffer == null:
		return
	buffer.call("push", _button_intent(&"spin", true, 5.0, &"touch"))
	buffer.call("push", _button_intent(&"spin", false, 5.01, &"touch"))
	buffer.call("push", _button_intent(&"down", true, 5.02, &"touch"))
	buffer.call("push", _button_intent(&"down", false, 5.03, &"touch"))

	buffer.call("prune_expired", 5.5, 0.15)

	assert_null(buffer.call("consume_released", &"spin", 5.5, 1.0))
	assert_null(buffer.call("consume_released", &"down", 5.5, 1.0))


func _new_buffer() -> RefCounted:
	var script: Script = load(BUFFER_SCRIPT_PATH)
	assert_not_null(script, "InputIntentBuffer implementation must exist")
	return script.new() if script != null else null


func _button_intent(
	action: StringName,
	pressed: bool,
	timestamp_s: float,
	source: StringName
) -> RefCounted:
	var script: Script = load(INTENT_SCRIPT_PATH)
	assert_not_null(script, "InputIntent implementation must exist")
	return script.call("button", action, pressed, timestamp_s, source) if script != null else null


func _movement_intent(value: Vector2, timestamp_s: float, source: StringName) -> RefCounted:
	var script: Script = load(INTENT_SCRIPT_PATH)
	assert_not_null(script, "InputIntent implementation must exist")
	return script.call("move", value, timestamp_s, source) if script != null else null
