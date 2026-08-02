extends GutTest

const SERVICE_SCRIPT_PATH := "res://src/tuning/tuning_service.gd"
const DEBUG_SCENE_PATH := "res://scenes/debug/tuning_debug_ui.tscn"
const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const LEVEL_META_PATH := "res://data/tuning/levels/n_sanity_beach.tres"
const SPEED_CLASS_PATH := "res://data/tuning/racing/classes/speed.tres"
const TEST_OVERRIDE_PATH := "user://test_sandbox/debug_ui_override.tres"


func before_each() -> void:
	_remove_override()


func after_each() -> void:
	_remove_override()


func test_hud_dumps_full_fingerprint_and_every_authored_path() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var summary: String = ui.call("summary_text")

	assert_string_contains(summary, service.call("fingerprint"))
	for path: String in service.call("get_loaded_resource_paths"):
		assert_string_contains(summary, path)
	assert_false(ui.call("override_watermark_visible"))
	assert_gt(ui.call("drawer_property_count"), 20)


func test_debug_drawer_renders_every_runtime_economy_field() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var rows := ui.get_node(
		"Drawer/Margin/VBox/Scroll/Rows"
	) as VBoxContainer
	var rendered_sections: Array[String] = []
	var rendered_economy_fields: Array[StringName] = []
	var inside_economy := false
	for child: Control in rows.get_children():
		if child is Label:
			var section_title := (child as Label).text
			rendered_sections.append(section_title)
			inside_economy = section_title == "ECONOMY"
		elif inside_economy and child is HBoxContainer:
			var field_label := child.get_child(0) as Label
			assert_not_null(field_label)
			assert_true(child.get_child(1) is HSlider)
			assert_true(child.get_child(2) is SpinBox)
			if field_label != null:
				rendered_economy_fields.append(
					StringName(field_label.text)
				)

	for section_title: String in [
		"WALL_RUN",
		"GRIND",
		"SWING",
		"PHASE",
		"ECONOMY",
	]:
		assert_has(rendered_sections, section_title)

	var expected_economy_fields: Array[StringName] = []
	var economy := service.get("catalog").get("economy") as Resource
	assert_not_null(economy)
	if economy == null:
		return
	for property_info: Dictionary in economy.get_property_list():
		if (
			int(property_info["usage"])
			& PROPERTY_USAGE_SCRIPT_VARIABLE
			and property_info["name"] != &"checkpoint_spacing_limit_s"
		):
			var field_name: StringName = property_info["name"]
			var field_type: int = property_info["type"]
			if field_type == TYPE_VECTOR3:
				for component_name: String in ["x", "y", "z"]:
					expected_economy_fields.append(
						StringName(
							String(field_name) + "." + component_name
						)
					)
			elif field_type == TYPE_COLOR:
				for component_name: String in ["r", "g", "b", "a"]:
					expected_economy_fields.append(
						StringName(
							String(field_name) + "." + component_name
						)
					)
			else:
				expected_economy_fields.append(field_name)
	expected_economy_fields.sort()
	rendered_economy_fields.sort()
	assert_gt(expected_economy_fields.size(), 0)
	assert_eq(
		rendered_economy_fields,
		expected_economy_fields,
		"every runtime economy field must have a real slider row"
	)


func test_debug_drawer_renders_all_enemy_sections_and_fields() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var expected_fields := [
		&"patrol_speed_mps",
		&"patrol_span_m",
		&"turn_pause_s",
		&"telegraph_s",
		&"attack_active_s",
		&"attack_cooldown_s",
		&"trigger_range_m",
	]
	for section_name: StringName in [
		&"enemy_crab",
		&"enemy_skink",
		&"enemy_plant",
	]:
		var resource := service.get("catalog").get(
			section_name
		) as Resource
		assert_not_null(
			resource,
			"%s must reach the live drawer catalog" % section_name
		)
		if resource == null:
			continue
		for property_name: StringName in expected_fields:
			assert_true(
				ui.call(
					"drawer_has_control",
					section_name,
					property_name
				),
				"%s.%s must have a live debug control"
				% [section_name, property_name]
			)


func test_hud_reports_loaded_level_meta() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]
	var meta := load(LEVEL_META_PATH) as Resource
	assert_not_null(meta)
	if meta == null:
		return

	ui.call("report_level_meta", meta)

	assert_string_contains(ui.call("summary_text"), LEVEL_META_PATH)
	assert_string_contains(
		ui.call("summary_text"),
		String(meta.call("fingerprint")).left(12)
	)


## CTR R8 Task 1 fix round 1 (reviewer [IMPORTANT]): the DriverClass
## counterpart to test_hud_reports_loaded_level_meta above -- see
## TuningDebugUI.report_driver_classes()'s own doc for why this is the
## operator-visible half of DriverClass.fingerprint() (a unit test on the
## resource alone proves the hash CAN move, not that an operator editing a
## class .tres on-device would ever SEE it move -- this test proves the
## latter).
func test_hud_reports_loaded_driver_classes() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]
	var speed_class := load(SPEED_CLASS_PATH) as DriverClass
	assert_not_null(speed_class)
	if speed_class == null:
		return
	var driver_classes: Array[DriverClass] = [speed_class]

	ui.call("report_driver_classes", driver_classes)

	assert_string_contains(ui.call("summary_text"), SPEED_CLASS_PATH)
	assert_string_contains(
		ui.call("summary_text"),
		speed_class.fingerprint().left(12)
	)


## The literal "fingerprint moves when a class value changes" checklist
## item, proven at the debug-HUD boundary rather than only on the bare
## resource (test_driver_class.gd's own test_driver_class_fingerprint_
## moves_when_a_multiplier_changes already proves the bare-resource half).
func test_hud_driver_class_report_moves_when_a_multiplier_changes() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]
	var loaded := load(SPEED_CLASS_PATH) as DriverClass
	assert_not_null(loaded)
	if loaded == null:
		return
	var driver_class := loaded.duplicate() as DriverClass
	var driver_classes: Array[DriverClass] = [driver_class]

	ui.call("report_driver_classes", driver_classes)
	var before: String = ui.call("summary_text")

	driver_class.top_speed_mult = 1.5
	ui.call("report_driver_classes", driver_classes)

	assert_ne(
		ui.call("summary_text"),
		before,
		"an edited driver class's own fingerprint never reaches the debug HUD summary"
	)
	assert_string_contains(
		ui.call("summary_text"),
		driver_class.fingerprint().left(12)
	)


func test_live_edit_moves_fingerprint_and_override_survives_reload() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var before: String = service.call("fingerprint")

	assert_eq(ui.call("set_live_value", &"move", &"gravity_mps2", 37.5), OK)
	var edited: String = service.call("fingerprint")
	assert_ne(edited, before)
	assert_string_contains(ui.call("summary_text"), edited)
	assert_eq(ui.call("save_override"), OK)
	assert_true(ui.call("override_watermark_visible"))
	assert_true(FileAccess.file_exists(TEST_OVERRIDE_PATH))

	var restored: RefCounted = load(SERVICE_SCRIPT_PATH).new()
	assert_eq(
		restored.call("load_from_paths", BASE_TUNING_PATH, TEST_OVERRIDE_PATH),
		OK
	)
	assert_eq(restored.get("catalog").get("move").get("gravity_mps2"), 37.5)
	assert_eq(restored.call("fingerprint"), edited)


func test_drawer_can_be_opened_without_covering_persistent_hud() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]

	ui.call("set_drawer_open", true)

	assert_true(ui.call("drawer_is_open"))
	assert_true(ui.call("hud_is_visible"))


func test_drawer_edits_vector_and_color_resource_values() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var camera_offset := Vector3(2.0, 8.0, 11.0)
	var landable_color := Color(0.1, 0.8, 0.25, 0.9)

	assert_true(ui.call("drawer_has_control", &"camera", &"default_offset"))
	assert_true(ui.call("drawer_has_control", &"depth", &"landable_color"))
	assert_eq(
		ui.call("set_live_value", &"camera", &"default_offset", camera_offset),
		OK
	)
	assert_eq(
		ui.call("set_live_value", &"depth", &"landable_color", landable_color),
		OK
	)
	assert_eq(service.get("catalog").get("camera").get("default_offset"), camera_offset)
	assert_eq(service.get("catalog").get("depth").get("landable_color"), landable_color)


func test_drawer_excludes_physical_constants_and_does_not_poll_fingerprint() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]

	assert_false(ui.call("drawer_has_control", &"input", &"millimeters_per_inch"))
	assert_false(ui.call("drawer_has_control", &"input", &"fallback_dpi"))
	assert_false(ui.call("drawer_has_control", &"input", &"control_scale"))
	assert_false(ui.call("drawer_has_control", &"input", &"bounce_timing_s"))
	assert_false(ui.call("drawer_has_control", &"input", &"touch_response_target_s"))
	assert_false(ui.call("drawer_has_control", &"input", &"touch_response_hard_fail_s"))
	assert_false(ui.call(
		"drawer_has_control",
		&"input",
		&"layout_metrics_poll_interval_s"
	))
	assert_false(ui.call(
		"drawer_has_control",
		&"camera",
		&"minimum_jump_depression_degrees"
	))
	assert_false(ui.call(
		"drawer_has_control",
		&"economy",
		&"checkpoint_spacing_limit_s"
	))
	assert_false(ui.is_processing())


func test_rebuilding_drawer_replaces_rows_immediately() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]
	var initial_row_count: int = ui.call("drawer_row_count")

	assert_eq(ui.call("reset_to_authored"), OK)

	assert_eq(ui.call("drawer_row_count"), initial_row_count)
	await get_tree().process_frame


func test_reset_to_authored_recovers_saved_override_in_place() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var authored: GameplayTuning = load(BASE_TUNING_PATH)
	assert_eq(ui.call("set_live_value", &"move", &"gravity_mps2", 37.5), OK)
	assert_eq(ui.call("save_override"), OK)

	assert_eq(ui.call("reset_to_authored"), OK)

	assert_false(FileAccess.file_exists(TEST_OVERRIDE_PATH))
	assert_false(ui.call("override_watermark_visible"))
	assert_eq(
		service.get("catalog").get("move").get("gravity_mps2"),
		authored.move.gravity_mps2
	)
	await get_tree().process_frame


func test_rejected_override_is_visible_and_reset_control_is_available() -> void:
	assert_eq(ResourceSaver.save(Resource.new(), TEST_OVERRIDE_PATH), OK)
	var setup := _new_ui()
	if setup.is_empty():
		return
	var ui: Control = setup["ui"]
	var watermark := ui.get_node("HUD/Margin/VBox/Header/OverrideActive") as Label

	assert_true(ui.call("override_watermark_visible"))
	assert_eq(watermark.text, "OVERRIDE REJECTED")
	assert_true(ui.has_node("Drawer/Margin/VBox/Footer/Reset"))


func test_live_drawer_rejects_values_that_would_break_runtime_math() -> void:
	var setup := _new_ui()
	if setup.is_empty():
		return
	var service: RefCounted = setup["service"]
	var ui: Control = setup["ui"]
	var original_step: float = (
		service.get("catalog").get("depth").get("prediction_step_s")
	)

	assert_eq(
		ui.call("set_live_value", &"depth", &"prediction_step_s", 0.0),
		ERR_INVALID_DATA
	)
	assert_eq(
		service.get("catalog").get("depth").get("prediction_step_s"),
		original_step
	)


func _new_ui() -> Dictionary:
	var service_script: Script = load(SERVICE_SCRIPT_PATH)
	var packed: PackedScene = load(DEBUG_SCENE_PATH)
	assert_not_null(service_script)
	assert_not_null(packed, "Tuning debug UI scene must exist")
	if service_script == null or packed == null:
		return {}
	var service: RefCounted = service_script.new()
	assert_eq(
		service.call("load_from_paths", BASE_TUNING_PATH, TEST_OVERRIDE_PATH),
		OK
	)
	var ui: Control = packed.instantiate()
	add_child_autofree(ui)
	ui.call("configure", service, TEST_OVERRIDE_PATH)
	return {"service": service, "ui": ui}


func _remove_override() -> void:
	if FileAccess.file_exists(TEST_OVERRIDE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_OVERRIDE_PATH))
