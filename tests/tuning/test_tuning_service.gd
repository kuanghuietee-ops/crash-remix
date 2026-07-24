extends GutTest

const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const SERVICE_SCRIPT_PATH := "res://src/tuning/tuning_service.gd"
const TEST_OVERRIDE_PATH := "user://test_sandbox/tuning_override.tres"
const PHASE0_INPUT_OVERRIDE_PATH := (
	"res://tests/fixtures/phase0_input_override_all_sections.tres"
)
# Frozen at the field shape understood when cohort migration was introduced.
# A later field belongs in LEGACY_FIELD_GROUPS_BY_SECTION, not in this baseline.
const PHASE0_BASELINE_FIELDS_BY_SECTION := {
	&"move": [
		&"player_height_m",
		&"collision_radius_m",
		&"floor_snap_length_m",
		&"floor_max_angle_degrees",
		&"crouch_hurtbox_height_ratio",
		&"hurtbox_visual_ratio",
		&"attack_visual_ratio",
		&"run_speed_mps",
		&"run_time_to_speed_s",
		&"stop_time_s",
		&"crawl_speed_mps",
		&"gravity_mps2",
		&"jump_full_height_m",
		&"jump_tap_height_m",
		&"double_jump_height_m",
		&"double_jump_tap_height_m",
		&"high_jump_height_m",
		&"fall_gravity_multiplier",
		&"apex_gravity_multiplier",
		&"apex_velocity_threshold_mps",
		&"maximum_fall_speed_mps",
		&"spin_radius_m",
		&"spin_active_s",
		&"air_spin_gravity_multiplier",
		&"slide_distance_m",
		&"slide_duration_s",
		&"slide_minimum_speed_mps",
		&"slide_jump_distance_m",
		&"slide_jump_height_m",
		&"body_slam_speed_mps",
		&"body_slam_shockwave_radius_m",
		&"body_slam_recovery_s",
		&"respawn_delay_s",
		&"respawn_floor_y_m",
	],
	&"input": [
		&"jump_buffer_s",
		&"coyote_time_s",
		&"action_buffer_s",
		&"minimum_hop_release_s",
		&"full_jump_hold_s",
		&"edge_landing_nudge_m",
		&"bounce_timing_s",
		&"touch_response_target_s",
		&"touch_response_hard_fail_s",
		&"millimeters_per_inch",
		&"fallback_dpi",
		&"stick_region_width_ratio",
		&"stick_region_top_exclusion_ratio",
		&"stick_ring_diameter_mm",
		&"stick_knob_diameter_mm",
		&"stick_opacity",
		&"stick_dead_zone_mm",
		&"stick_full_run_mm",
		&"corridor_magnet_cone_degrees",
		&"corridor_magnet_strength",
		&"gamepad_magnet_disable_magnitude",
		&"gamepad_dead_zone",
		&"jump_button_diameter_mm",
		&"spin_button_diameter_mm",
		&"down_button_diameter_mm",
		&"jump_button_edge_x_mm",
		&"jump_button_edge_y_mm",
		&"spin_button_edge_x_mm",
		&"down_button_above_jump_mm",
		&"button_hit_radius_scale",
		&"jump_catchall_width_ratio",
		&"jump_catchall_top_ratio",
		&"button_opacity",
		&"button_label_height_mm",
		&"control_outline_width_mm",
		&"control_color",
		&"control_label_color",
		&"haptic_duration_ms",
		&"haptics_enabled",
		&"left_handed_layout",
		&"control_scale",
		&"layout_metrics_poll_interval_s",
	],
	&"camera": [
		&"field_of_view_degrees",
		&"rail_bake_interval_m",
		&"rail_follow_speed_mps",
		&"region_blend_s",
		&"look_ahead_m",
		&"look_at_height_m",
		&"player_screen_left_bias_m",
		&"default_offset",
		&"close_offset",
		&"side_on_offset",
		&"grind_offset",
		&"wall_run_offset",
		&"swing_offset",
		&"wall_run_bank_degrees",
		&"minimum_jump_depression_degrees",
	],
	&"depth": [
		&"shadow_diameter_m",
		&"shadow_opacity",
		&"shadow_ray_length_m",
		&"shadow_ray_origin_offset_m",
		&"shadow_surface_offset_m",
		&"prediction_step_s",
		&"prediction_horizon_s",
		&"collision_probe_radius_m",
		&"collision_probe_stride",
		&"ring_outer_radius_m",
		&"ring_inner_radius_m",
		&"ring_surface_offset_m",
		&"landable_color",
		&"hazard_color",
		&"rail_predicted_color",
		&"landing_assist_last_fall_ratio",
		&"landing_assist_edge_distance_m",
		&"landing_assist_probe_depth_m",
		&"landing_assist_touch_strength",
		&"landing_assist_gamepad_strength",
	],
	&"wall_run": [
		&"attach_cone_degrees",
		&"minimum_entry_speed_mps",
		&"surface_stick_distance_m",
		&"run_speed_mps",
		&"maximum_duration_s",
		&"gravity_multiplier",
		&"detach_outward_speed_mps",
		&"detach_height_m",
	],
	&"grind": [
		&"attach_snap_m",
		&"speed_mps",
		&"acceleration_mps2",
		&"bank_degrees",
		&"hop_lateral_distance_m",
		&"hop_height_m",
		&"exit_forward_speed_mps",
	],
	&"swing": [
		&"catch_radius_m",
		&"rope_length_m",
		&"gravity_scale",
		&"maximum_speed_mps",
		&"damping_per_s",
		&"release_boost_mps",
	],
	&"phase": [
		&"retoggle_cooldown_s",
		&"ghost_opacity",
		&"ghost_outline_width_m",
	],
	&"economy": [
		&"wumpa_per_standard_crate",
		&"wumpa_collect_radius_m",
		&"wumpa_mask_threshold",
		&"mask_stack_maximum",
		&"invincibility_duration_s",
		&"tnt_fuse_s",
		&"tnt_blast_radius_m",
		&"bounce_crate_max_bounces",
		&"bounce_crate_wumpa_per_bounce",
		&"bounce_launch_height_m",
		&"checkpoint_spacing_limit_s",
		&"mercy_mask_death_threshold",
		&"mercy_skip_death_threshold",
		&"time_crate_small_s",
		&"time_crate_medium_s",
		&"time_crate_large_s",
	],
}


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
	assert_eq(_global_class_name(catalog.get("wall_run")), "WallRunTuning")
	assert_eq(_global_class_name(catalog.get("grind")), "GrindTuning")
	assert_eq(_global_class_name(catalog.get("swing")), "SwingTuning")
	assert_eq(_global_class_name(catalog.get("phase")), "PhaseTuning")
	assert_eq(_global_class_name(catalog.get("economy")), "EconomyTuning")


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


func test_service_catalog_exposes_traversal_sections() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var catalog: Resource = service.get("catalog")
	var wall_run: Resource = catalog.get("wall_run")
	var grind: Resource = catalog.get("grind")
	var swing: Resource = catalog.get("swing")
	var phase: Resource = catalog.get("phase")

	assert_not_null(wall_run, "clone dropped wall_run — dead-wired")
	assert_not_null(grind, "clone dropped grind — dead-wired")
	assert_not_null(swing, "clone dropped swing — dead-wired")
	assert_not_null(phase, "clone dropped phase — dead-wired")
	if wall_run == null or grind == null or swing == null or phase == null:
		return
	assert_eq(wall_run.get("attach_cone_degrees"), 25.0)
	assert_eq(grind.get("attach_snap_m"), 0.35)
	assert_eq(phase.get("retoggle_cooldown_s"), 0.25)


func test_service_catalog_exposes_economy_section() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var catalog: Resource = service.get("catalog")
	var economy: Resource = catalog.get("economy")

	assert_not_null(economy, "clone dropped economy — dead-wired")
	if economy == null:
		return
	assert_eq(economy.get("wumpa_mask_threshold"), 100)
	assert_eq(economy.get("tnt_fuse_s"), 3.0)
	assert_eq(economy.get("mercy_mask_death_threshold"), 3)


func test_fingerprint_moves_when_an_economy_value_changes() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var before: String = service.call("fingerprint")
	var economy: Resource = service.get("catalog").get("economy")
	assert_not_null(economy)
	if economy == null:
		return

	economy.set("tnt_fuse_s", 4.5)

	assert_ne(
		before,
		service.call("fingerprint"),
		"economy never reaches the fingerprint"
	)


func test_fingerprint_moves_when_traversal_value_changes() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var before: String = service.call("fingerprint")
	var grind: Resource = service.get("catalog").get("grind")
	assert_not_null(grind)
	if grind == null:
		return

	grind.set("speed_mps", 11.5)
	var after: String = service.call("fingerprint")

	assert_ne(before, after, "grind values never reach the fingerprint")


func test_loaded_paths_include_the_traversal_resources() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var paths: PackedStringArray = service.call("get_loaded_resource_paths")
	var joined := "|".join(paths)

	assert_true(joined.contains("grind.tres"), "debug HUD will not list grind.tres")
	assert_true(joined.contains("wall_run.tres"))
	assert_true(joined.contains("economy.tres"))


func test_catalog_is_unusable_without_traversal_resources() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	catalog.set("grind", null)

	assert_false(service.call("catalog_is_usable", catalog))


func test_catalog_is_unusable_without_economy() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	catalog.set("economy", null)

	assert_false(service.call("catalog_is_usable", catalog))


func test_phase05_shaped_override_backfills_economy() -> void:
	var service: RefCounted = _new_service()
	var stale := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	stale.set("economy", null)
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH)

	assert_false(
		service.get("override_rejected"),
		"a Phase 0.5 phone override must migrate, not reset operator tuning"
	)
	assert_not_null(service.get("catalog").get("economy"))


func test_old_shape_override_is_migrated_not_rejected() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	var stale := GameplayTuning.new()
	for section_name: StringName in [
		&"move",
		&"input",
		&"camera",
		&"depth",
	]:
		stale.set(
			section_name,
			_detached_resource_copy(
				authored.get(section_name) as Resource
			)
		)
	stale.move.gravity_mps2 = 31.0
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(
			TEST_OVERRIDE_PATH.get_base_dir()
		)
	)
	assert_true(
		directory_error in [OK, ERR_ALREADY_EXISTS],
		"the override fixture must create its own sandbox"
	)
	assert_eq(
		ResourceSaver.save(
			stale,
			TEST_OVERRIDE_PATH
		),
		OK
	)
	assert_true(
		FileAccess.get_file_as_string(TEST_OVERRIDE_PATH).contains(
			"gravity_mps2 = 31.0"
		),
		"the old-shape fixture must really persist the operator edit"
	)

	service.call("load_from_paths", BASE_CATALOG_PATH, TEST_OVERRIDE_PATH)

	assert_false(
		service.get("override_rejected"),
		"a Phase 0 override must migrate, not reset the operator's tuning"
	)
	assert_true(service.get("override_active"))
	assert_eq(
		service.get("catalog").get("move").get("gravity_mps2"),
		31.0,
		"migration must preserve the operator's Phase 0 edits"
	)
	assert_not_null(
		service.get("catalog").get("wall_run"),
		"missing sections must backfill from authored"
	)
	assert_not_null(service.get("catalog").get("grind"))
	assert_not_null(service.get("catalog").get("swing"))
	assert_not_null(service.get("catalog").get("phase"))


func test_phase_zero_input_fields_backfill_without_losing_operator_values() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			PHASE0_INPUT_OVERRIDE_PATH
		),
		OK
	)

	assert_false(
		service.get("override_rejected"),
		"an override with a Phase-0-shaped input section must migrate"
	)
	assert_true(service.get("override_active"))
	var migrated: GameplayTuning = service.get("catalog")
	assert_eq(
		migrated.input.fallback_dpi,
		177.0,
		"migration must preserve the operator's existing field edits"
	)
	assert_eq(
		migrated.input.phase_button_diameter_mm,
		authored.input.phase_button_diameter_mm
	)
	assert_eq(
		migrated.input.phase_button_arc_offset_mm,
		authored.input.phase_button_arc_offset_mm
	)
	assert_eq(
		migrated.input.phase_button_unlocked,
		authored.input.phase_button_unlocked
	)


func test_old_swing_override_backfills_the_chain_catch_assist() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	var legacy_swing := SwingTuning.new()
	legacy_swing.catch_radius_m = authored.swing.catch_radius_m
	legacy_swing.rope_length_m = authored.swing.rope_length_m
	legacy_swing.gravity_scale = authored.swing.gravity_scale
	legacy_swing.maximum_speed_mps = authored.swing.maximum_speed_mps
	legacy_swing.damping_per_s = authored.swing.damping_per_s
	legacy_swing.release_boost_mps = 1.75
	stale.swing = legacy_swing
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)

	assert_false(service.get("override_rejected"))
	assert_true(service.get("override_active"))
	var migrated: GameplayTuning = service.get("catalog")
	assert_eq(
		migrated.swing.minimum_catch_speed_mps,
		authored.swing.minimum_catch_speed_mps
	)
	assert_eq(
		migrated.swing.transfer_catch_radius_m,
		authored.swing.transfer_catch_radius_m
	)
	assert_eq(
		migrated.swing.transfer_minimum_catch_speed_mps,
		authored.swing.transfer_minimum_catch_speed_mps
	)
	assert_eq(
		migrated.swing.release_boost_mps,
		1.75,
		"migration must preserve existing swing edits"
	)


func test_every_exported_field_has_override_migration_coverage() -> void:
	var catalog: GameplayTuning = load(BASE_CATALOG_PATH)
	var service_script := load(SERVICE_SCRIPT_PATH) as Script
	assert_not_null(catalog)
	assert_not_null(service_script)
	if catalog == null or service_script == null:
		return
	var constants := service_script.get_script_constant_map()
	var section_names: Array = constants.get("SECTION_NAMES", [])
	var legacy_groups: Dictionary = constants.get(
		"LEGACY_FIELD_GROUPS_BY_SECTION",
		{}
	)
	assert_eq(
		section_names.size(),
		PHASE0_BASELINE_FIELDS_BY_SECTION.size(),
		"every catalog section needs a frozen migration baseline"
	)

	for section_value: Variant in section_names:
		var section_name := StringName(section_value)
		var section := catalog.get(section_name) as Resource
		assert_not_null(section, "%s section must load" % section_name)
		assert_true(
			PHASE0_BASELINE_FIELDS_BY_SECTION.has(section_name),
			"%s has no migration baseline" % section_name
		)
		if (
			section == null
			or not PHASE0_BASELINE_FIELDS_BY_SECTION.has(section_name)
		):
			continue
		var exported_fields := _exported_property_names(section)
		var covered_fields := {}
		for baseline_field: StringName in (
			PHASE0_BASELINE_FIELDS_BY_SECTION[section_name]
		):
			assert_true(
				exported_fields.has(baseline_field),
				"%s.%s is stale in the migration baseline"
				% [section_name, baseline_field]
			)
			assert_false(covered_fields.has(baseline_field))
			covered_fields[baseline_field] = &"phase0"
		if legacy_groups.has(section_name):
			for field_group: Array in legacy_groups[section_name]:
				for legacy_field: StringName in field_group:
					assert_true(
						exported_fields.has(legacy_field),
						"%s.%s is stale in the legacy cohort registry"
						% [section_name, legacy_field]
					)
					assert_false(
						covered_fields.has(legacy_field),
						"%s.%s cannot be both baseline and legacy"
						% [section_name, legacy_field]
					)
					covered_fields[legacy_field] = &"legacy"
		for exported_field: StringName in exported_fields:
			assert_true(
				covered_fields.has(exported_field),
				(
					"%s.%s is covered by neither the Phase 0 baseline "
					+ "nor a legacy migration cohort"
				) % [section_name, exported_field]
			)
		assert_eq(
			covered_fields.size(),
			exported_fields.size(),
			"%s migration coverage must exactly match its exports"
			% section_name
		)


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
	assert_has(loaded_paths, "res://data/tuning/economy.tres")


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


func test_every_invalid_economy_field_is_rejected_from_disk() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(
			TEST_OVERRIDE_PATH.get_base_dir()
		)
	)
	assert_true(
		directory_error in [OK, ERR_ALREADY_EXISTS],
		"the override scenario must create its real sandbox"
	)
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var invalid_values: Array[Array] = [
		[&"wumpa_per_standard_crate", 0],
		[&"wumpa_collect_radius_m", 0.0],
		[&"wumpa_mask_threshold", 0],
		[&"mask_stack_maximum", 0],
		[&"invincibility_duration_s", 0.0],
		[&"tnt_fuse_s", 0.0],
		[&"tnt_blast_radius_m", 0.0],
		[&"bounce_crate_max_bounces", 0],
		[&"bounce_crate_wumpa_per_bounce", 0],
		[&"bounce_launch_height_m", 0.0],
		[&"checkpoint_spacing_limit_s", 0.0],
		[&"mercy_mask_death_threshold", 0],
		[&"mercy_skip_death_threshold", 0],
		[&"time_crate_small_s", 0.0],
		[&"time_crate_medium_s", 0.0],
		[&"time_crate_large_s", 0.0],
		[
			&"mercy_skip_death_threshold",
			authored.economy.mercy_mask_death_threshold,
		],
		[
			&"time_crate_medium_s",
			authored.economy.time_crate_small_s,
		],
		[
			&"time_crate_large_s",
			authored.economy.time_crate_medium_s,
		],
	]
	for invalid_value: Array in invalid_values:
		var override := load(
			BASE_CATALOG_PATH
		).duplicate_deep(
			Resource.DEEP_DUPLICATE_ALL
		) as GameplayTuning
		var property_name := invalid_value[0] as StringName
		override.economy.set(property_name, invalid_value[1])
		assert_eq(
			ResourceSaver.save(override, TEST_OVERRIDE_PATH),
			OK
		)
		var service := _new_service()
		assert_eq(
			service.call(
				"load_from_paths",
				BASE_CATALOG_PATH,
				TEST_OVERRIDE_PATH
			),
			OK
		)
		assert_true(
			service.get("override_rejected"),
			"%s must reject %s from the real override file"
			% [property_name, invalid_value[1]]
		)
		assert_false(service.get("override_active"))


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


func test_zero_run_speed_and_action_buffers_are_rejected() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog: GameplayTuning = service.get("catalog")
	var guarded_fields: Array[Array] = [
		[catalog.move, &"run_speed_mps"],
		[catalog.input, &"jump_buffer_s"],
		[catalog.input, &"action_buffer_s"],
	]

	for guarded_field: Array in guarded_fields:
		var resource := guarded_field[0] as Resource
		var property_name := guarded_field[1] as StringName
		var original_value: Variant = resource.get(property_name)
		resource.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"%s must reject zero" % property_name
		)
		resource.set(property_name, original_value)

	assert_true(service.call("catalog_is_usable"))


func test_unusable_swing_escape_speeds_are_rejected() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var swing: SwingTuning = service.get("catalog").get("swing")
	var authored_minimum := swing.minimum_catch_speed_mps
	var authored_transfer_radius := swing.transfer_catch_radius_m
	var authored_transfer_minimum := (
		swing.transfer_minimum_catch_speed_mps
	)
	var authored_boost := swing.release_boost_mps

	swing.minimum_catch_speed_mps = 0.0
	assert_false(service.call("catalog_is_usable"))
	swing.minimum_catch_speed_mps = swing.maximum_speed_mps + 0.01
	assert_false(service.call("catalog_is_usable"))
	swing.minimum_catch_speed_mps = authored_minimum
	swing.transfer_catch_radius_m = swing.catch_radius_m - 0.01
	assert_false(service.call("catalog_is_usable"))
	swing.transfer_catch_radius_m = authored_transfer_radius
	swing.transfer_minimum_catch_speed_mps = 0.0
	assert_false(service.call("catalog_is_usable"))
	swing.transfer_minimum_catch_speed_mps = (
		swing.minimum_catch_speed_mps + 0.01
	)
	assert_false(service.call("catalog_is_usable"))
	swing.transfer_minimum_catch_speed_mps = authored_transfer_minimum
	swing.release_boost_mps = 0.0
	assert_false(service.call("catalog_is_usable"))
	swing.release_boost_mps = authored_boost

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


func _exported_property_names(resource: Resource) -> Array[StringName]:
	var names: Array[StringName] = []
	for property_info: Dictionary in resource.get_property_list():
		var usage: int = property_info["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(StringName(property_info["name"]))
	return names


func _detached_resource_copy(source: Resource) -> Resource:
	var script := source.get_script() as Script
	var detached := script.new() as Resource
	for property_name: StringName in _exported_property_names(source):
		detached.set(property_name, source.get(property_name))
	return detached


func _remove_test_override() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_OVERRIDE_PATH)
	if FileAccess.file_exists(TEST_OVERRIDE_PATH):
		DirAccess.remove_absolute(absolute_path)
