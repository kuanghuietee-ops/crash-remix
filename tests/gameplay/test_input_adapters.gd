extends GutTest

const FILTER_SCRIPT_PATH := "res://src/gameplay/input/input_vector_filter.gd"
const ROUTER_SCRIPT_PATH := "res://src/gameplay/input/input_router.gd"
const GAMEPAD_SCRIPT_PATH := "res://src/gameplay/input/gamepad_input.gd"
const TOUCH_SCRIPT_PATH := "res://src/ui/touch_controls.gd"
const LAYOUT_SCRIPT_PATH := "res://src/ui/touch_control_layout.gd"
const SAFE_AREA_SCRIPT_PATH := "res://src/ui/safe_area_control.gd"
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _input_tuning: Resource


func before_all() -> void:
	var catalog: Resource = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_input_tuning = catalog.get("input").duplicate()
		_input_tuning.set("haptics_enabled", false)


func test_corridor_magnet_aligns_inside_cone_but_not_outside() -> void:
	var script: Script = load(FILTER_SCRIPT_PATH)
	assert_not_null(script, "InputVectorFilter implementation must exist")
	if script == null:
		return
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("corridor_magnet_strength", 1.0)
	var inside := Vector2.UP.rotated(deg_to_rad(10.0))
	var outside := Vector2.UP.rotated(deg_to_rad(20.0))

	var aligned: Vector2 = script.call(
		"apply_corridor_magnet", inside, Vector2.UP, tuning, false
	)
	var untouched: Vector2 = script.call(
		"apply_corridor_magnet", outside, Vector2.UP, tuning, false
	)

	assert_almost_eq(aligned.angle_to(Vector2.UP), 0.0, 0.0001)
	assert_almost_eq(untouched.angle_to(outside), 0.0, 0.0001)


func test_screen_corridor_axis_is_converted_to_motor_relative_input() -> void:
	var script: Script = load(FILTER_SCRIPT_PATH)
	assert_not_null(script, "InputVectorFilter implementation must exist")
	if script == null:
		return
	var exposes_conversion := false
	for method: Dictionary in script.get_script_method_list():
		if StringName(method.get("name", &"")) == &"to_corridor_input":
			exposes_conversion = true
			break
	assert_true(
		exposes_conversion,
		"camera-relative stick input needs a named corridor conversion"
	)
	if not exposes_conversion:
		return
	for corridor_axis: Vector2 in [
		Vector2.UP,
		Vector2.RIGHT,
		Vector2(1.0, -1.0).normalized(),
	]:
		var screen_right := Vector2(
			-corridor_axis.y,
			corridor_axis.x
		)
		assert_eq(
			script.call(
				"to_corridor_input",
				corridor_axis * 0.75,
				corridor_axis
			),
			Vector2.UP * 0.75,
			"stick toward the on-screen route must always drive world-forward"
		)
		assert_eq(
			script.call(
				"to_corridor_input",
				screen_right * 0.75,
				corridor_axis
			),
			Vector2.RIGHT * 0.75
		)


func test_router_keeps_held_stick_stable_when_camera_axis_changes() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	if router == null:
		return
	add_child_autofree(router)
	router.call("configure", _input_tuning)
	router.call("set_corridor_axis", Vector2.UP)
	router.call(
		"push_move",
		Vector2.UP,
		1.0,
		InputIntent.SOURCE_TOUCH
	)
	assert_eq(router.get("buffer").call("movement"), Vector2.UP)

	router.call("set_corridor_axis", Vector2.RIGHT)

	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.UP,
		"camera motion alone must never rotate a held movement command"
	)
	router.call(
		"push_move",
		Vector2.UP,
		2.0,
		InputIntent.SOURCE_TOUCH
	)
	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.UP,
		"drag updates must keep the axis captured at gesture start"
	)
	router.call(
		"push_move",
		Vector2.ZERO,
		3.0,
		InputIntent.SOURCE_TOUCH
	)
	router.call(
		"push_move",
		Vector2.RIGHT,
		4.0,
		InputIntent.SOURCE_TOUCH
	)
	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.UP,
		"a new gesture may adopt the camera's settled side-on axis"
	)


func test_router_tracks_held_stick_during_screen_relative_chase() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	if router == null:
		return
	add_child_autofree(router)
	router.call("configure", _input_tuning)
	router.call("set_corridor_axis", Vector2.UP)
	router.call(
		"push_move",
		Vector2.RIGHT,
		1.0,
		InputIntent.SOURCE_TOUCH
	)
	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.RIGHT
	)
	assert_true(
		router.has_method("set_screen_relative_tracking_enabled"),
		"the reversing chase camera needs an explicit live-axis input mode"
	)
	if not router.has_method("set_screen_relative_tracking_enabled"):
		return

	router.call("set_screen_relative_tracking_enabled", true)
	router.call("set_corridor_axis", Vector2.DOWN)

	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.LEFT,
		"a held screen-right gesture must flip its world-relative lateral "
		+ "command when the chase camera reverses"
	)
	router.call("set_screen_relative_tracking_enabled", false)
	router.call("set_corridor_axis", Vector2.UP)
	assert_eq(
		router.get("buffer").call("movement"),
		Vector2.LEFT,
		"ordinary camera motion must become gesture-stable again after chase"
	)


func test_gamepad_disables_magnet_above_configured_magnitude() -> void:
	var script: Script = load(FILTER_SCRIPT_PATH)
	assert_not_null(script, "InputVectorFilter implementation must exist")
	if script == null:
		return
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("corridor_magnet_strength", 1.0)
	var direction := Vector2.UP.rotated(deg_to_rad(10.0))
	var strong_input := direction * 0.8

	var filtered: Vector2 = script.call(
		"apply_corridor_magnet", strong_input, Vector2.UP, tuning, true
	)

	assert_almost_eq(filtered.angle_to(strong_input), 0.0, 0.0001)


func test_touch_layout_uses_physical_millimeters_and_mirrors() -> void:
	var script: Script = load(LAYOUT_SCRIPT_PATH)
	assert_not_null(script, "TouchControlLayout implementation must exist")
	if script == null:
		return
	var safe_rect := Rect2(0.0, 0.0, 1920.0, 1080.0)
	var layout: Dictionary = script.call(
		"calculate",
		safe_rect,
		254.0,
		_input_tuning,
		true
	)
	var mirrored_tuning: Resource = _input_tuning.duplicate()
	mirrored_tuning.set("left_handed_layout", true)
	var mirrored: Dictionary = script.call(
		"calculate", safe_rect, 254.0, mirrored_tuning, true
	)

	assert_eq(layout["jump_radius"], 70.0)
	assert_eq(layout["stick_ring_radius"], 110.0)
	assert_eq(layout["jump_center"], Vector2(1800.0, 960.0))
	assert_eq(mirrored["jump_center"], Vector2(120.0, 960.0))
	assert_true(layout["stick_region"].has_point(Vector2(200.0, 600.0)))
	assert_true(mirrored["stick_region"].has_point(Vector2(1720.0, 600.0)))


func test_native_safe_areas_map_into_tall_and_short_logical_viewports() -> void:
	var touch_script: Script = load(TOUCH_SCRIPT_PATH)
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)
	assert_not_null(touch_script)
	assert_not_null(layout_script)
	if touch_script == null or layout_script == null:
		return
	var exposes_conversion := false
	for method: Dictionary in touch_script.get_script_method_list():
		if method["name"] == &"layout_metrics_in_logical_space":
			exposes_conversion = true
			break
	assert_true(
		exposes_conversion,
		"touch controls must convert native display metrics into logical space"
	)
	if not exposes_conversion:
		return
	var configurations: Array[Dictionary] = [
		{
			"native_safe_rect": Rect2(80.0, 0.0, 3040.0, 1440.0),
			"native_display_size": Vector2(3200.0, 1440.0),
			"native_dpi": 400.0,
			"logical_viewport": Rect2(0.0, 0.0, 2400.0, 1080.0),
			"expected_safe_rect": Rect2(60.0, 0.0, 2280.0, 1080.0),
			"expected_dpi": 300.0,
		},
		{
			"native_safe_rect": Rect2(40.0, 0.0, 1200.0, 720.0),
			"native_display_size": Vector2(1280.0, 720.0),
			"native_dpi": 320.0,
			"logical_viewport": Rect2(0.0, 0.0, 1920.0, 1080.0),
			"expected_safe_rect": Rect2(60.0, 0.0, 1800.0, 1080.0),
			"expected_dpi": 480.0,
		},
	]

	for configuration: Dictionary in configurations:
		var metrics: Dictionary = touch_script.call(
			"layout_metrics_in_logical_space",
			configuration["native_safe_rect"],
			configuration["native_display_size"],
			configuration["native_dpi"],
			configuration["logical_viewport"]
		)
		assert_eq(metrics["safe_rect"], configuration["expected_safe_rect"])
		assert_almost_eq(
			metrics["dpi"],
			configuration["expected_dpi"],
			0.0001
		)
		var layout: Dictionary = layout_script.call(
			"calculate",
			metrics["safe_rect"],
			metrics["dpi"],
			_input_tuning,
			true
		)
		for center_name: String in [
			"jump_center",
			"spin_center",
			"down_center",
			"phase_center",
		]:
			assert_true(
				(configuration["logical_viewport"] as Rect2).has_point(
					layout[center_name]
				),
				"%s must stay inside %s logical viewport"
				% [center_name, configuration["native_display_size"].y]
			)


func test_jump_catchall_width_is_driven_by_input_tuning() -> void:
	var script: Script = load(LAYOUT_SCRIPT_PATH)
	assert_not_null(script, "TouchControlLayout implementation must exist")
	if script == null:
		return
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("jump_catchall_width_ratio", 0.4)

	var layout: Dictionary = script.call(
		"calculate",
		Rect2(0.0, 0.0, 1920.0, 1080.0),
		254.0,
		tuning,
		true
	)

	assert_almost_eq(
		(layout["jump_catchall_region"] as Rect2).size.x,
		768.0,
		0.0001
	)


func test_gamepad_buttons_and_axis_emit_unified_intents() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var gamepad: Node = _new_node(GAMEPAD_SCRIPT_PATH)
	if router == null or gamepad == null:
		return
	add_child_autofree(router)
	add_child_autofree(gamepad)
	router.call("configure", _input_tuning)
	gamepad.call("configure", router, _input_tuning)

	var axis_event := InputEventJoypadMotion.new()
	axis_event.axis = JOY_AXIS_LEFT_X
	axis_event.axis_value = 0.8
	gamepad.call("handle_input", axis_event)
	var jump_event := InputEventJoypadButton.new()
	jump_event.button_index = JOY_BUTTON_A
	jump_event.pressed = true
	gamepad.call("handle_input", jump_event)

	var buffer: RefCounted = router.get("buffer")
	assert_gt(buffer.call("movement").x, 0.0)
	assert_true(buffer.call("is_action_pressed", &"jump"))
	assert_eq(buffer.call("active_source"), &"gamepad")


func test_gamepad_y_emits_phase_intent() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var gamepad: Node = _new_node(GAMEPAD_SCRIPT_PATH)
	if router == null or gamepad == null:
		return
	add_child_autofree(router)
	add_child_autofree(gamepad)
	router.call("configure", _input_tuning)
	gamepad.call("configure", router, _input_tuning)
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_Y
	event.pressed = true

	gamepad.call("handle_input", event)

	assert_true(router.get("buffer").call("is_action_pressed", &"phase"))


func test_phase_button_absent_when_progression_is_locked() -> void:
	var input_tuning: Resource = load(TUNING_PATH).get("input").duplicate(true)
	input_tuning.set("phase_button_unlocked", true)
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)

	var layout: Dictionary = layout_script.call(
		"calculate",
		Rect2(0.0, 0.0, 2400.0, 1080.0),
		400.0,
		input_tuning,
		false
	)

	assert_false(
		layout.has("phase_center"),
		"progression must beat the tuning master flag"
	)
	assert_false(
		layout.has("phase_radius"),
		"locked PHASE must expose no hit target"
	)


func test_phase_button_absent_when_tuning_master_is_locked() -> void:
	var input_tuning: Resource = load(TUNING_PATH).get("input").duplicate(true)
	input_tuning.set("phase_button_unlocked", false)
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)

	var layout: Dictionary = layout_script.call(
		"calculate",
		Rect2(0.0, 0.0, 2400.0, 1080.0),
		400.0,
		input_tuning,
		true
	)

	assert_false(
		layout.has("phase_center"),
		"tuning master flag must hide PHASE"
	)
	assert_false(
		layout.has("phase_radius"),
		"disabled PHASE must expose no hit target"
	)


func test_phase_button_sits_on_the_outer_arc_when_unlocked() -> void:
	var input_tuning: Resource = load(TUNING_PATH).get("input").duplicate(true)
	input_tuning.set("phase_button_unlocked", true)
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)

	var layout: Dictionary = layout_script.call(
		"calculate",
		Rect2(0.0, 0.0, 2400.0, 1080.0),
		400.0,
		input_tuning,
		true
	)

	assert_true(layout.has("phase_center"))
	if not layout.has("phase_center"):
		return
	assert_lt(layout["phase_center"].x, layout["jump_center"].x, "PHASE sits left of JUMP")
	assert_lt(layout["phase_center"].y, layout["jump_center"].y, "PHASE sits above JUMP")
	assert_almost_eq(
		layout["phase_center"].distance_to(layout["jump_center"]),
		input_tuning.get("phase_button_arc_offset_mm") * layout["pixels_per_mm"],
		0.0001
	)
	assert_almost_eq(
		layout["phase_radius"],
		input_tuning.get("phase_button_diameter_mm") * layout["pixels_per_mm"] * 0.5,
		0.0001
	)

	input_tuning.set("left_handed_layout", true)
	var mirrored: Dictionary = layout_script.call(
		"calculate",
		Rect2(0.0, 0.0, 2400.0, 1080.0),
		400.0,
		input_tuning,
		true
	)
	assert_gt(
		mirrored["phase_center"].x,
		mirrored["jump_center"].x,
		"left-handed PHASE mirrors to the right of JUMP"
	)
	assert_lt(
		mirrored["phase_center"].y,
		mirrored["jump_center"].y,
		"mirrored PHASE remains above JUMP"
	)


func test_unlocked_phase_touch_emits_phase_intent() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	var input_tuning: Resource = _input_tuning.duplicate(true)
	input_tuning.set("phase_button_unlocked", true)
	router.call("configure", input_tuning)
	touch.call("configure", router, input_tuning, true)
	touch.call(
		"set_layout_override",
		Rect2(0.0, 0.0, 1920.0, 1080.0),
		254.0
	)
	var layout: Dictionary = touch.call("current_layout")
	assert_true(layout.has("phase_center"))
	if not layout.has("phase_center"):
		return
	var phase_press := InputEventScreenTouch.new()
	phase_press.index = 12
	phase_press.position = layout["phase_center"]
	phase_press.pressed = true

	touch.call("handle_touch_event", phase_press)

	assert_true(router.get("buffer").call("is_action_pressed", &"phase"))
	assert_true(touch.call("is_action_flashing", &"phase"))


func test_gamepad_dpad_emits_discrete_movement_intents() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var gamepad: Node = _new_node(GAMEPAD_SCRIPT_PATH)
	if router == null or gamepad == null:
		return
	add_child_autofree(router)
	add_child_autofree(gamepad)
	router.call("configure", _input_tuning)
	gamepad.call("configure", router, _input_tuning)
	var up_event := InputEventJoypadButton.new()
	up_event.button_index = JOY_BUTTON_DPAD_UP
	up_event.pressed = true

	gamepad.call("handle_input", up_event)

	var buffer: RefCounted = router.get("buffer")
	assert_eq(buffer.call("movement"), Vector2.UP)
	assert_eq(buffer.call("active_source"), InputIntent.SOURCE_GAMEPAD)


func test_gamepad_dpad_is_not_overridden_by_analog_drift() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var gamepad: Node = _new_node(GAMEPAD_SCRIPT_PATH)
	if router == null or gamepad == null:
		return
	add_child_autofree(router)
	add_child_autofree(gamepad)
	router.call("configure", _input_tuning)
	gamepad.call("configure", router, _input_tuning)
	var right_event := InputEventJoypadButton.new()
	right_event.button_index = JOY_BUTTON_DPAD_RIGHT
	right_event.pressed = true
	gamepad.call("handle_input", right_event)
	var drift_event := InputEventJoypadMotion.new()
	drift_event.axis = JOY_AXIS_LEFT_X
	drift_event.axis_value = _input_tuning.gamepad_dead_zone * 0.5

	gamepad.call("handle_input", drift_event)

	var buffer: RefCounted = router.get("buffer")
	assert_eq(buffer.call("movement"), Vector2.RIGHT)
	assert_eq(buffer.call("active_source"), InputIntent.SOURCE_GAMEPAD)


func test_touch_stick_and_button_remain_independent_multitouch() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	router.call("configure", _input_tuning)
	touch.call("configure", router, _input_tuning, true)
	touch.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0), 254.0)
	var layout: Dictionary = touch.call("current_layout")

	var stick_press := InputEventScreenTouch.new()
	stick_press.index = 0
	stick_press.position = Vector2(300.0, 700.0)
	stick_press.pressed = true
	touch.call("handle_touch_event", stick_press)
	var stick_drag := InputEventScreenDrag.new()
	stick_drag.index = 0
	stick_drag.position = Vector2(340.0, 650.0)
	touch.call("handle_touch_event", stick_drag)
	var jump_press := InputEventScreenTouch.new()
	jump_press.index = 1
	jump_press.position = layout["jump_center"]
	jump_press.pressed = true
	touch.call("handle_touch_event", jump_press)

	var buffer: RefCounted = router.get("buffer")
	assert_gt(buffer.call("movement").length(), 0.0)
	assert_true(buffer.call("is_action_pressed", &"jump"))
	assert_eq(touch.call("stick_touch_index"), 0)


func test_touch_button_flashes_only_while_its_finger_is_held() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	router.call("configure", _input_tuning)
	touch.call("configure", router, _input_tuning, true)
	touch.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0), 254.0)
	var layout: Dictionary = touch.call("current_layout")
	var jump_touch := InputEventScreenTouch.new()
	jump_touch.index = 7
	jump_touch.position = layout["jump_center"]
	jump_touch.pressed = true

	touch.call("handle_touch_event", jump_touch)
	assert_true(touch.call("is_action_flashing", InputIntent.ACTION_JUMP))
	assert_false(touch.call("is_action_flashing", InputIntent.ACTION_SPIN))

	jump_touch.pressed = false
	touch.call("handle_touch_event", jump_touch)
	assert_false(touch.call("is_action_flashing", InputIntent.ACTION_JUMP))


func test_touch_ignores_new_contacts_inside_visible_debug_overlays() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	router.call("configure", _input_tuning)
	touch.call("configure", router, _input_tuning, true)
	touch.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0), 254.0)
	var drawer := Control.new()
	drawer.position = Vector2(18.0, 246.0)
	drawer.size = Vector2(922.0, 816.0)
	add_child_autofree(drawer)
	var hud := Control.new()
	hud.position = Vector2(8.0, 8.0)
	hud.size = Vector2(480.0, 190.0)
	add_child_autofree(hud)
	touch.call("set_touch_exclusion_controls", [hud, drawer])
	var drawer_press := InputEventScreenTouch.new()
	drawer_press.index = 8
	drawer_press.position = Vector2(300.0, 700.0)
	drawer_press.pressed = true
	var hud_press := InputEventScreenTouch.new()
	hud_press.index = 9
	hud_press.position = Vector2(100.0, 100.0)
	hud_press.pressed = true

	touch.call("handle_touch_event", drawer_press)
	touch.call("handle_touch_event", hud_press)

	assert_eq(touch.call("stick_touch_index"), -1)
	assert_eq(router.get("buffer").call("movement"), Vector2.ZERO)


func test_touch_overlap_chooses_nearest_button_with_jump_winning_ambiguity() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	router.call("configure", _input_tuning)
	touch.call("configure", router, _input_tuning, true)
	touch.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0), 254.0)
	var overlap_press := InputEventScreenTouch.new()
	overlap_press.index = 9
	overlap_press.position = Vector2(1735.0, 960.0)
	overlap_press.pressed = true

	touch.call("handle_touch_event", overlap_press)

	var buffer: RefCounted = router.get("buffer")
	assert_true(buffer.call("is_action_pressed", InputIntent.ACTION_JUMP))
	assert_false(buffer.call("is_action_pressed", InputIntent.ACTION_SPIN))


func test_touch_recalculates_layout_when_viewport_size_changes() -> void:
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if touch == null:
		return
	add_child_autofree(touch)
	var callback := Callable(touch, "_on_viewport_size_changed")

	assert_true(get_viewport().size_changed.is_connected(callback))
	assert_true(touch.is_processing())


func test_touch_layout_metrics_are_polled_only_at_configured_interval() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("layout_metrics_poll_interval_s", 0.5)
	router.call("configure", tuning)
	touch.call("configure", router, tuning, true)
	touch.set_process(false)
	var initial_count: int = touch.call("layout_metrics_poll_count")

	touch.call("_process", 0.49)
	var before_interval: int = touch.call("layout_metrics_poll_count")
	touch.call("_process", 0.01)

	assert_eq(before_interval, initial_count)
	assert_eq(touch.call("layout_metrics_poll_count"), initial_count + 1)


func test_safe_area_repolls_after_a_flip_that_never_fires_size_changed() -> void:
	var safe_area: Control = _new_node(SAFE_AREA_SCRIPT_PATH)
	if safe_area == null:
		return
	add_child_autofree(safe_area)
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("layout_metrics_poll_interval_s", 0.5)
	safe_area.call("configure", tuning)
	safe_area.set_process(false)

	safe_area.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0))
	safe_area.call("_apply_safe_area")
	assert_eq(safe_area.get("offset_left"), 0.0)
	assert_eq(safe_area.get("offset_right"), 1920.0)

	# A sensor-landscape 180 degree flip moves the notch to the opposite
	# edge without changing the logical viewport size, so no
	# viewport.size_changed signal fires. Only GameRoot's own tuned poll
	# interval should notice.
	safe_area.call("set_layout_override", Rect2(100.0, 0.0, 1820.0, 1080.0))

	safe_area.call("_process", 0.49)
	assert_eq(
		safe_area.get("offset_left"),
		0.0,
		"must not react before the tuned poll interval elapses"
	)

	safe_area.call("_process", 0.01)
	assert_eq(
		safe_area.get("offset_left"),
		100.0,
		"the tuned poll interval must pick up a flip with no resize signal"
	)


func test_safe_area_non_positive_poll_interval_does_not_poison_with_nan() -> void:
	# R7: fmod(x, interval_s) with a non-positive interval_s returns NaN
	# (IEEE 754); every subsequent frame's "elapsed < interval_s" guard
	# then compares against NaN, which is always false, so the throttle
	# silently inverts from "once per tuned interval" into "every frame
	# forever" instead of failing safely. Every reachable production path
	# already rejects this value via TuningService.catalog_is_usable
	# (override load, live debug-drawer edits) -- this proves the polling
	# code defends itself too, for the one path that check doesn't cover
	# (the authored base tuning resource -- see R7's other half).
	var safe_area: Control = _new_node(SAFE_AREA_SCRIPT_PATH)
	if safe_area == null:
		return
	add_child_autofree(safe_area)
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("layout_metrics_poll_interval_s", 0.0)
	safe_area.call("configure", tuning)
	safe_area.set_process(false)

	safe_area.call("set_layout_override", Rect2(0.0, 0.0, 1920.0, 1080.0))
	safe_area.call("_apply_safe_area")

	for _frame in range(3):
		safe_area.call("_process", 0.1)
	assert_false(
		is_nan(safe_area.get("_layout_metrics_poll_elapsed_s")),
		"a non-positive poll interval must not poison elapsed time with NaN"
	)

	# The safe area must still notice a real layout change instead of
	# being silently wedged by the bad interval.
	safe_area.call("set_layout_override", Rect2(100.0, 0.0, 1820.0, 1080.0))
	safe_area.call("_process", 0.1)
	assert_eq(
		safe_area.get("offset_left"),
		100.0,
		"a non-positive poll interval must still poll, not silently stop"
	)


func test_touch_controls_non_positive_poll_interval_does_not_poison_with_nan() -> void:
	var router: Node = _new_node(ROUTER_SCRIPT_PATH)
	var touch: Control = _new_node(TOUCH_SCRIPT_PATH)
	if router == null or touch == null:
		return
	add_child_autofree(router)
	add_child_autofree(touch)
	var tuning: Resource = _input_tuning.duplicate()
	tuning.set("layout_metrics_poll_interval_s", 0.0)
	router.call("configure", tuning)
	touch.call("configure", router, tuning, true)
	touch.set_process(false)

	var initial_count: int = touch.call("layout_metrics_poll_count")
	for _frame in range(3):
		touch.call("_process", 0.1)
	assert_false(
		is_nan(touch.get("_layout_metrics_poll_elapsed_s")),
		"a non-positive poll interval must not poison elapsed time with NaN"
	)
	assert_gt(
		touch.call("layout_metrics_poll_count"),
		initial_count,
		"a non-positive poll interval must still poll, not silently stop"
	)


func test_hud_elements_stay_outside_the_touch_control_occlusion_zones() -> void:
	# R6: the original version of this test only ever checked ONE safe rect
	# (1920x1080). hud.tscn's top-anchored panels are pixel-offset from the
	# safe area's top, while TouchControlLayout's regions start at a HEIGHT
	# RATIO of the safe rect -- the two only avoided overlapping because of
	# that one rect's proportions, not because of any enforced relationship.
	# Sweeping a range of realistic phone safe-rect heights (down to a
	# foldable-hinge-shaped 480px) proves the invariant holds generally, not
	# just at the one aspect ratio a test happened to pick.
	var packed: PackedScene = load(HUD_SCENE_PATH)
	assert_not_null(packed, "hud.tscn must exist")
	if packed == null:
		return
	var hud: Control = packed.instantiate()
	add_child_autofree(hud)
	var safe_area := hud.get_node("SafeArea")
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)

	for safe_height: float in [1080.0, 950.0, 900.0, 850.0, 800.0, 700.0, 600.0, 480.0]:
		var safe_rect := Rect2(0.0, 0.0, 1920.0, safe_height)
		safe_area.call("set_layout_override", safe_rect)
		safe_area.call("_apply_safe_area")
		await wait_process_frames(1)

		var layout: Dictionary = layout_script.call(
			"calculate", safe_rect, 254.0, _input_tuning, true
		)
		# §5.2: left-thumb stick zone and the bottom-right button wedge — the
		# two touch-control regions no HUD element may be drawn over.
		var stick_region: Rect2 = layout["stick_region"]
		var button_zone: Rect2 = layout["jump_catchall_region"]

		for element_path: String in [
			"SafeArea/Stats",
			"SafeArea/RelicTimer",
			"SafeArea/MercyPanel",
			"SafeArea/Pause",
		]:
			var element := hud.get_node(element_path) as Control
			var element_rect := element.get_global_rect()
			assert_false(
				element_rect.intersects(stick_region),
				(
					"%s must not overlap the left-thumb stick zone (§5.2) "
					+ "at safe height %s"
				) % [element_path, safe_height]
			)
			assert_false(
				element_rect.intersects(button_zone),
				(
					"%s must not overlap the right-thumb button zone (§5.2) "
					+ "at safe height %s"
				) % [element_path, safe_height]
			)


func test_hud_reserved_top_px_covers_the_tallest_authored_top_anchored_panel() -> void:
	# R6: hud_reserved_top_px is the tuning-authored floor TouchControlLayout
	# clamps both touch regions' tops to. If hud.tscn ever authors a taller
	# top-anchored panel than this field covers, the two would silently
	# drift apart again -- the same "two independently-tuned numbers with
	# no invariant tying them together" shape as R1 and I17. This test ties
	# them together structurally: it reads the REAL hud.tscn geometry and
	# fails if it ever outgrows the tuned floor, rather than trusting two
	# numbers that merely happen to agree today.
	var packed: PackedScene = load(HUD_SCENE_PATH)
	assert_not_null(packed, "hud.tscn must exist")
	if packed == null:
		return
	var hud: Control = packed.instantiate()
	add_child_autofree(hud)

	var tallest_offset_bottom := 0.0
	for element_path: String in [
		"SafeArea/Stats",
		"SafeArea/RelicTimer",
		"SafeArea/MercyPanel",
		"SafeArea/Pause",
	]:
		var element := hud.get_node(element_path) as Control
		tallest_offset_bottom = maxf(
			tallest_offset_bottom,
			element.offset_bottom
		)

	assert_true(
		_input_tuning.hud_reserved_top_px >= tallest_offset_bottom,
		(
			"hud_reserved_top_px (%s) must cover the tallest authored "
			+ "top-anchored HUD panel (%s), or the touch regions can "
			+ "overlap it again at a short safe height"
		) % [_input_tuning.hud_reserved_top_px, tallest_offset_bottom]
	)


func test_hud_pause_touch_index_clears_when_hud_is_hidden_mid_touch() -> void:
	var packed: PackedScene = load(HUD_SCENE_PATH)
	assert_not_null(packed, "hud.tscn must exist")
	if packed == null:
		return
	var hud: Control = packed.instantiate()
	add_child_autofree(hud)
	await wait_process_frames(1)

	var pause_button := hud.get_node("SafeArea/Pause") as Button
	var touch_position := pause_button.get_global_rect().get_center()

	var press := InputEventScreenTouch.new()
	press.index = 7
	press.position = touch_position
	press.pressed = true
	hud.call("_input", press)

	# The level completes mid-touch; GameRoot's _sync_ui_visibility() hides
	# the HUD for the RESULTS state before the held touch is released.
	hud.visible = false

	var release := InputEventScreenTouch.new()
	release.index = 7
	release.position = touch_position
	release.pressed = false
	hud.call("_input", release)

	hud.visible = true

	# Android reuses touch indices after a lift. A later, unrelated touch
	# far from Pause reuses index 7.
	var unrelated_press := InputEventScreenTouch.new()
	unrelated_press.index = 7
	unrelated_press.position = Vector2(10.0, 10.0)
	unrelated_press.pressed = true
	hud.call("_input", unrelated_press)

	watch_signals(hud)
	var unrelated_release := InputEventScreenTouch.new()
	unrelated_release.index = 7
	unrelated_release.position = Vector2(10.0, 10.0)
	unrelated_release.pressed = false
	hud.call("_input", unrelated_release)

	assert_signal_not_emitted(
		hud,
		"pause_requested",
		(
			"a pause touch abandoned while the HUD was hidden must not "
			+ "hijack an unrelated touch's release once the index is reused"
		)
	)


func _new_node(script_path: String) -> Variant:
	var script: Script = load(script_path)
	assert_not_null(script, script_path + " implementation must exist")
	return script.new() if script != null else null
