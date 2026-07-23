class_name TouchControls
extends Control

const InputRouterType := preload("res://src/gameplay/input/input_router.gd")
const InputVectorFilterType := preload("res://src/gameplay/input/input_vector_filter.gd")
const MonotonicClockType := preload("res://src/core/monotonic_clock.gd")
const TouchControlLayoutType := preload("res://src/ui/touch_control_layout.gd")

var _router: InputRouterType
var _input_tuning: InputTuning
var _layout: Dictionary = {}
var _layout_override_rect := Rect2()
var _layout_override_dpi := 0.0
var _has_layout_override := false
var _stick_touch := -1
var _stick_center := Vector2.ZERO
var _stick_position := Vector2.ZERO
var _button_actions: Dictionary = {}
var _touch_exclusion_controls: Array[Control] = []
var _last_safe_rect := Rect2()
var _last_dpi: float
var _layout_metrics_poll_elapsed_s := 0.0
var _layout_metrics_poll_count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	set_process(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func configure(router: InputRouterType, input_tuning: InputTuning) -> void:
	_router = router
	_input_tuning = input_tuning
	_layout_metrics_poll_elapsed_s = 0.0
	_recalculate_layout()


func set_layout_override(safe_rect: Rect2, dpi: float) -> void:
	_layout_override_rect = safe_rect
	_layout_override_dpi = dpi
	_has_layout_override = true
	_recalculate_layout()


func set_touch_exclusion_controls(controls: Array) -> void:
	_touch_exclusion_controls.clear()
	for control: Variant in controls:
		if control is Control:
			_touch_exclusion_controls.append(control as Control)


func current_layout() -> Dictionary:
	if _layout.is_empty():
		_recalculate_layout()
	return _layout.duplicate(true)


func stick_touch_index() -> int:
	return _stick_touch


func is_action_flashing(action: StringName) -> bool:
	return _button_actions.values().has(action)


func layout_metrics_poll_count() -> int:
	return _layout_metrics_poll_count


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		handle_touch_event(event)


func handle_touch_event(event: InputEvent) -> void:
	if _router == null or _input_tuning == null or _layout.is_empty():
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and _touch_exclusion_contains(touch_event.position):
			return
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _process(delta_s: float) -> void:
	if _has_layout_override or _input_tuning == null:
		return
	_layout_metrics_poll_elapsed_s += maxf(delta_s, 0.0)
	var interval_s := _input_tuning.layout_metrics_poll_interval_s
	if _layout_metrics_poll_elapsed_s < interval_s:
		return
	_layout_metrics_poll_elapsed_s = fmod(_layout_metrics_poll_elapsed_s, interval_s)
	_layout_metrics_poll_count += 1
	var safe_rect := _viewport_safe_rect()
	var dpi := DisplayServer.screen_get_dpi()
	if safe_rect != _last_safe_rect or not is_equal_approx(dpi, _last_dpi):
		_recalculate_layout()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var action := _action_at(event.position)
		if not action.is_empty():
			_button_actions[event.index] = action
			_router.push_button(action, true, MonotonicClockType.now_s(), InputIntent.SOURCE_TOUCH)
			_tick_haptic()
			queue_redraw()
		elif _stick_touch < 0 and (_layout["stick_region"] as Rect2).has_point(event.position):
			_stick_touch = event.index
			_stick_center = event.position
			_stick_position = event.position
			queue_redraw()
		return

	if _button_actions.has(event.index):
		var action: StringName = _button_actions[event.index]
		_router.push_button(action, false, MonotonicClockType.now_s(), InputIntent.SOURCE_TOUCH)
		_button_actions.erase(event.index)
		queue_redraw()
	elif event.index == _stick_touch:
		_stick_touch = -1
		_stick_center = Vector2.ZERO
		_stick_position = Vector2.ZERO
		_router.push_move(Vector2.ZERO, MonotonicClockType.now_s(), InputIntent.SOURCE_TOUCH)
		queue_redraw()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _stick_touch:
		return
	_stick_position = event.position
	var movement := _stick_value(event.position - _stick_center)
	movement = InputVectorFilterType.apply_corridor_magnet(
		movement,
		_router.corridor_axis(),
		_input_tuning,
		false
	)
	_router.push_move(movement, MonotonicClockType.now_s(), InputIntent.SOURCE_TOUCH)
	queue_redraw()


func _stick_value(deflection_px: Vector2) -> Vector2:
	var pixels_per_mm: float = _layout["pixels_per_mm"]
	var distance_mm := deflection_px.length() / pixels_per_mm
	if distance_mm <= _input_tuning.stick_dead_zone_mm:
		return Vector2.ZERO
	var span_mm := _input_tuning.stick_full_run_mm - _input_tuning.stick_dead_zone_mm
	var magnitude := clampf(
		(distance_mm - _input_tuning.stick_dead_zone_mm) / span_mm,
		0.0,
		1.0
	)
	return deflection_px.normalized() * magnitude


func _action_at(position: Vector2) -> StringName:
	var hit_scale: float = _layout["button_hit_radius_scale"]
	var candidates: Array[Dictionary] = [
		{
			"action": InputIntent.ACTION_JUMP,
			"center": _layout["jump_center"],
			"radius": _layout["jump_radius"],
		},
		{
			"action": InputIntent.ACTION_SPIN,
			"center": _layout["spin_center"],
			"radius": _layout["spin_radius"],
		},
		{
			"action": InputIntent.ACTION_DOWN,
			"center": _layout["down_center"],
			"radius": _layout["down_radius"],
		},
	]
	if _layout.has("phase_center"):
		candidates.append({
			"action": InputIntent.ACTION_PHASE,
			"center": _layout["phase_center"],
			"radius": _layout["phase_radius"],
		})
	var nearest_action := &""
	var nearest_distance := 0.0
	var nearest_radius := 0.0
	for candidate: Dictionary in candidates:
		var center: Vector2 = candidate["center"]
		var radius: float = candidate["radius"]
		var distance := position.distance_to(center)
		if distance > radius * hit_scale:
			continue
		if (
			nearest_action.is_empty()
			or distance * nearest_radius < nearest_distance * radius
		):
			nearest_action = candidate["action"]
			nearest_distance = distance
			nearest_radius = radius
	if not nearest_action.is_empty():
		return nearest_action
	if (_layout["jump_catchall_region"] as Rect2).has_point(position):
		return InputIntent.ACTION_JUMP
	return &""


func _recalculate_layout() -> void:
	if _input_tuning == null:
		return
	var safe_rect: Rect2 = _layout_override_rect if _has_layout_override else _viewport_safe_rect()
	var dpi: float = _layout_override_dpi if _has_layout_override else DisplayServer.screen_get_dpi()
	_layout = TouchControlLayoutType.calculate(safe_rect, dpi, _input_tuning)
	_last_safe_rect = safe_rect
	_last_dpi = dpi
	queue_redraw()


func _viewport_safe_rect() -> Rect2:
	var safe_rect := Rect2(DisplayServer.get_display_safe_area())
	if safe_rect.size.is_zero_approx():
		return get_viewport_rect()
	return safe_rect


func _touch_exclusion_contains(position: Vector2) -> bool:
	for control: Control in _touch_exclusion_controls:
		if (
			is_instance_valid(control)
			and control.is_visible_in_tree()
			and control.get_global_rect().has_point(position)
		):
			return true
	return false


func _on_viewport_size_changed() -> void:
	if not _has_layout_override:
		_recalculate_layout()


func _tick_haptic() -> void:
	if _input_tuning.haptics_enabled:
		Input.vibrate_handheld(_input_tuning.haptic_duration_ms)


func _draw() -> void:
	if _layout.is_empty() or _input_tuning == null:
		return
	var button_color := _input_tuning.control_color
	button_color.a *= _input_tuning.button_opacity
	var stick_color := _input_tuning.control_color
	stick_color.a *= _input_tuning.stick_opacity
	_draw_button(
		_layout["jump_center"],
		_layout["jump_radius"],
		"JUMP",
		_button_color(InputIntent.ACTION_JUMP, button_color)
	)
	_draw_button(
		_layout["spin_center"],
		_layout["spin_radius"],
		"SPIN",
		_button_color(InputIntent.ACTION_SPIN, button_color)
	)
	_draw_button(
		_layout["down_center"],
		_layout["down_radius"],
		"DOWN",
		_button_color(InputIntent.ACTION_DOWN, button_color)
	)
	if _layout.has("phase_center"):
		_draw_button(
			_layout["phase_center"],
			_layout["phase_radius"],
			"PHASE",
			_button_color(InputIntent.ACTION_PHASE, button_color)
		)
	if _stick_touch >= 0:
		var outline_width: float = (
			_input_tuning.control_outline_width_mm * _layout["pixels_per_mm"]
		)
		draw_circle(
			_stick_center,
			_layout["stick_ring_radius"],
			stick_color,
			false,
			outline_width
		)
		var knob_offset := (_stick_position - _stick_center).limit_length(_layout["stick_ring_radius"])
		draw_circle(
			_stick_center + knob_offset,
			_layout["stick_knob_radius"],
			stick_color
		)


func _button_color(action: StringName, resting_color: Color) -> Color:
	if not is_action_flashing(action):
		return resting_color
	var flashing_color := _input_tuning.control_color
	flashing_color.a = 1.0
	return flashing_color


func _draw_button(
	center: Vector2,
	radius: float,
	label: String,
	button_color: Color
) -> void:
	draw_circle(center, radius, button_color)
	var font := ThemeDB.fallback_font
	var font_size := int(round(
		_input_tuning.button_label_height_mm * _layout["pixels_per_mm"]
	))
	var text_size := font.get_string_size(
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	var baseline := center + Vector2(
		-text_size.x / 2.0,
		text_size.y / 4.0
	)
	draw_string(
		font,
		baseline,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		_input_tuning.control_label_color
	)
