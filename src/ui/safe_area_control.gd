class_name PhaseOneSafeArea
extends Control

const TouchControlsType := preload(
	"res://src/ui/touch_controls.gd"
)

var _input_tuning: InputTuning
var _layout_metrics_poll_elapsed_s := 0.0
var _last_safe_rect := Rect2()
var _layout_override_rect := Rect2()
var _has_layout_override := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func configure(input_tuning: InputTuning) -> void:
	_input_tuning = input_tuning
	_layout_metrics_poll_elapsed_s = 0.0


func set_layout_override(safe_rect: Rect2) -> void:
	_layout_override_rect = safe_rect
	_has_layout_override = true


func _process(delta_s: float) -> void:
	if _input_tuning == null:
		return
	_layout_metrics_poll_elapsed_s += maxf(delta_s, 0.0)
	var interval_s := _input_tuning.layout_metrics_poll_interval_s
	if _layout_metrics_poll_elapsed_s < interval_s:
		return
	_layout_metrics_poll_elapsed_s = fmod(_layout_metrics_poll_elapsed_s, interval_s)
	if _current_safe_rect() != _last_safe_rect:
		_apply_safe_area()


func _apply_safe_area() -> void:
	var safe_rect := _current_safe_rect()
	set_anchor(SIDE_LEFT, 0.0)
	set_anchor(SIDE_TOP, 0.0)
	set_anchor(SIDE_RIGHT, 0.0)
	set_anchor(SIDE_BOTTOM, 0.0)
	offset_left = safe_rect.position.x
	offset_top = safe_rect.position.y
	offset_right = safe_rect.end.x
	offset_bottom = safe_rect.end.y
	_last_safe_rect = safe_rect


func _current_safe_rect() -> Rect2:
	if _has_layout_override:
		return _layout_override_rect
	var screen_index := DisplayServer.window_get_current_screen()
	var native_safe_rect := Rect2(
		DisplayServer.get_display_safe_area()
	)
	native_safe_rect.position -= Vector2(
		DisplayServer.screen_get_position(screen_index)
	)
	var metrics := TouchControlsType.layout_metrics_in_logical_space(
		native_safe_rect,
		Vector2(DisplayServer.screen_get_size(screen_index)),
		DisplayServer.screen_get_dpi(screen_index),
		get_viewport_rect()
	)
	return metrics["safe_rect"]
