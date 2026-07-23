extends GutTest


func test_engine_feature_version_is_pinned_to_godot_4_7() -> void:
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features",
		PackedStringArray()
	)
	assert_true(features.has("4.7"), "Project features must declare Godot 4.7")


func test_mobile_renderer_is_selected() -> void:
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"mobile"
	)
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"mobile"
	)


func test_jolt_runs_at_sixty_hz_with_interpolation() -> void:
	assert_eq(
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		"Jolt Physics"
	)
	assert_eq(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),
		60
	)
	assert_true(
		ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"3D physics interpolation must be enabled"
	)


func test_mobile_window_is_landscape_and_touch_events_are_independent() -> void:
	assert_eq(
		ProjectSettings.get_setting("display/window/handheld/orientation"),
		DisplayServer.SCREEN_SENSOR_LANDSCAPE
	)
	assert_false(
		ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")
	)
	assert_false(
		ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse")
	)
