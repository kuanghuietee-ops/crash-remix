class_name PhaseOneSafeArea
extends Control

const TouchControlsType := preload(
	"res://src/ui/touch_controls.gd"
)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _apply_safe_area() -> void:
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
	var safe_rect: Rect2 = metrics["safe_rect"]
	set_anchor(SIDE_LEFT, 0.0)
	set_anchor(SIDE_TOP, 0.0)
	set_anchor(SIDE_RIGHT, 0.0)
	set_anchor(SIDE_BOTTOM, 0.0)
	offset_left = safe_rect.position.x
	offset_top = safe_rect.position.y
	offset_right = safe_rect.end.x
	offset_bottom = safe_rect.end.y
