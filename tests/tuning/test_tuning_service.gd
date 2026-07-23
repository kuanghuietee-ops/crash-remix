extends GutTest

const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const SERVICE_SCRIPT_PATH := "res://src/tuning/tuning_service.gd"
const TEST_OVERRIDE_PATH := "user://test_sandbox/tuning_override.tres"


func before_each() -> void:
	_remove_test_override()


func after_each() -> void:
	_remove_test_override()


func test_authored_catalog_loads_all_typed_resources() -> void:
	var catalog: Resource = load(BASE_CATALOG_PATH)
	assert_not_null(catalog, "The authored tuning catalog must load")
	if catalog == null:
		return

	assert_eq(_global_class_name(catalog), "GameplayTuning")
	assert_eq(_global_class_name(catalog.get("move")), "MoveTuning")
	assert_eq(_global_class_name(catalog.get("input")), "InputTuning")
	assert_eq(_global_class_name(catalog.get("camera")), "CameraTuning")
	assert_eq(_global_class_name(catalog.get("depth")), "DepthTuning")


func test_authored_values_form_valid_phase_zero_contract() -> void:
	var catalog: Resource = load(BASE_CATALOG_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return

	var move: Resource = catalog.get("move")
	var input_tuning: Resource = catalog.get("input")
	assert_gt(move.get("run_speed_mps"), move.get("crawl_speed_mps"))
	assert_gt(move.get("jump_full_height_m"), move.get("jump_tap_height_m"))
	assert_gt(move.get("high_jump_height_m"), move.get("jump_full_height_m"))
	assert_gt(move.get("double_jump_height_m"), 0.0)
	assert_gt(move.get("double_jump_tap_height_m"), 0.0)
	assert_lt(
		move.get("double_jump_tap_height_m"),
		move.get("double_jump_height_m")
	)
	assert_gt(move.get("spin_radius_m"), 0.0)
	assert_gt(move.get("spin_active_s"), 0.0)
	assert_gt(move.get("slide_distance_m"), 0.0)
	assert_gt(move.get("slide_duration_s"), 0.0)
	assert_gt(move.get("slide_jump_distance_m"), move.get("slide_distance_m"))
	assert_gt(move.get("slide_jump_height_m"), 0.0)
	assert_between(move.get("hurtbox_visual_ratio"), 0.7, 0.75)
	assert_gte(move.get("attack_visual_ratio"), 1.0)
	assert_lte(move.get("respawn_delay_s"), 2.0)
	assert_gt(input_tuning.get("jump_buffer_s"), 0.0)
	assert_gt(input_tuning.get("coyote_time_s"), 0.0)
	assert_gt(input_tuning.get("action_buffer_s"), 0.0)
	assert_lt(
		input_tuning.get("minimum_hop_release_s"),
		input_tuning.get("full_jump_hold_s")
	)
	assert_gt(input_tuning.get("layout_metrics_poll_interval_s"), 0.0)


func test_effective_catalog_is_detached_and_reports_every_authored_path() -> void:
	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return

	assert_eq(service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH), OK)
	var effective_catalog: Resource = service.get("catalog")
	var authored_catalog: Resource = load(BASE_CATALOG_PATH)
	assert_not_same(effective_catalog, authored_catalog)
	assert_not_same(effective_catalog.get("move"), authored_catalog.get("move"))

	var loaded_paths: PackedStringArray = service.call("get_loaded_resource_paths")
	assert_has(loaded_paths, BASE_CATALOG_PATH)
	assert_has(loaded_paths, "res://data/tuning/move.tres")
	assert_has(loaded_paths, "res://data/tuning/input.tres")
	assert_has(loaded_paths, "res://data/tuning/camera.tres")
	assert_has(loaded_paths, "res://data/tuning/depth.tres")


func test_fingerprint_changes_when_an_effective_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return

	var fingerprint_before: String = service.call("fingerprint")
	var move: Resource = service.get("catalog").get("move")
	move.set("gravity_mps2", move.get("gravity_mps2") + 1.0)
	var fingerprint_after: String = service.call("fingerprint")
	assert_ne(fingerprint_after, fingerprint_before)
	assert_eq(fingerprint_before.length(), 64)
	assert_eq(fingerprint_after.length(), 64)


func test_override_round_trip_persists_values_and_fingerprint() -> void:
	var original: RefCounted = _loaded_service()
	if original == null:
		return

	var base_fingerprint: String = original.call("fingerprint")
	var move: Resource = original.get("catalog").get("move")
	move.set("gravity_mps2", 37.5)
	var edited_fingerprint: String = original.call("fingerprint")
	assert_eq(original.call("save_override", TEST_OVERRIDE_PATH), OK)
	assert_true(original.get("override_active"))

	var restored: RefCounted = _new_service()
	assert_not_null(restored)
	if restored == null:
		return
	assert_eq(restored.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH), OK)
	assert_true(restored.get("override_active"))
	assert_eq(restored.get("catalog").get("move").get("gravity_mps2"), 37.5)
	assert_eq(restored.call("fingerprint"), edited_fingerprint)
	assert_ne(restored.call("fingerprint"), base_fingerprint)
	assert_has(restored.call("get_loaded_resource_paths"), TEST_OVERRIDE_PATH)


func test_invalid_override_falls_back_to_authored_catalog_and_reports_rejection() -> void:
	assert_eq(ResourceSaver.save(Resource.new(), TEST_OVERRIDE_PATH), OK)
	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return

	assert_eq(service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH), OK)
	assert_not_null(service.get("catalog"))
	assert_false(service.get("override_active"))
	assert_true(service.get("override_rejected"))
	assert_false(service.call("get_loaded_resource_paths").has(TEST_OVERRIDE_PATH))


func test_layout_critical_override_values_are_rejected_before_replacing_authored() -> void:
	var source: RefCounted = _loaded_service()
	if source == null:
		return
	var invalid_override: GameplayTuning = source.get("catalog")
	invalid_override.input.millimeters_per_inch = 0.0
	invalid_override.input.control_scale = 0.0
	assert_eq(ResourceSaver.save(invalid_override, TEST_OVERRIDE_PATH), OK)
	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return

	assert_eq(service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH), OK)

	assert_true(service.get("override_rejected"))
	assert_false(service.get("override_active"))
	assert_gt(service.get("catalog").get("input").get("millimeters_per_inch"), 0.0)
	assert_gt(service.get("catalog").get("input").get("control_scale"), 0.0)


func test_playability_critical_soft_brick_values_are_rejected() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog: GameplayTuning = service.get("catalog")
	var invalid_values: Array[Array] = [
		[catalog.move, &"maximum_fall_speed_mps", 0.0],
		[catalog.move, &"respawn_floor_y_m", 1.0],
		[catalog.move, &"double_jump_tap_height_m", 0.0],
		[catalog.input, &"jump_buffer_s", -0.01],
		[catalog.input, &"action_buffer_s", -0.01],
		[catalog.input, &"coyote_time_s", -0.01],
		[catalog.input, &"layout_metrics_poll_interval_s", 0.0],
	]

	for invalid_value: Array in invalid_values:
		var resource := invalid_value[0] as Resource
		var property_name := invalid_value[1] as StringName
		var original_value: Variant = resource.get(property_name)
		resource.set(property_name, invalid_value[2])
		assert_false(
			service.call("catalog_is_usable"),
			"%s must reject %s" % [property_name, invalid_value[2]]
		)
		resource.set(property_name, original_value)

	assert_true(service.call("catalog_is_usable"))


func test_reset_to_authored_deletes_override_and_restores_baseline() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	service.get("catalog").get("move").set("gravity_mps2", 37.5)
	assert_eq(service.call("save_override", TEST_OVERRIDE_PATH), OK)
	assert_true(FileAccess.file_exists(TEST_OVERRIDE_PATH))
	assert_has(service.call("get_loaded_resource_paths"), TEST_OVERRIDE_PATH)

	assert_eq(service.call("reset_to_authored"), OK)

	assert_false(FileAccess.file_exists(TEST_OVERRIDE_PATH))
	assert_false(service.get("override_active"))
	assert_false(service.get("override_rejected"))
	assert_eq(
		service.get("catalog").get("move").get("gravity_mps2"),
		authored.move.gravity_mps2
	)
	assert_false(service.call("get_loaded_resource_paths").has(TEST_OVERRIDE_PATH))


func _loaded_service() -> RefCounted:
	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return null
	assert_eq(service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH), OK)
	return service


func _new_service() -> RefCounted:
	var service_script: Script = load(SERVICE_SCRIPT_PATH)
	if service_script == null:
		return null
	return service_script.new()


func _global_class_name(resource: Resource) -> String:
	if resource == null or resource.get_script() == null:
		return ""
	return resource.get_script().get_global_name()


func _remove_test_override() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_OVERRIDE_PATH)
	if FileAccess.file_exists(TEST_OVERRIDE_PATH):
		DirAccess.remove_absolute(absolute_path)
