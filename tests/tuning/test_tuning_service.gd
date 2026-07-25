extends GutTest

const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const SERVICE_SCRIPT_PATH := "res://src/tuning/tuning_service.gd"
const TEST_OVERRIDE_PATH := "user://test_sandbox/tuning_override.tres"
const PHASE0_INPUT_OVERRIDE_PATH := (
	"res://tests/fixtures/phase0_input_override_all_sections.tres"
)
# Frozen at the field shape understood when cohort migration was introduced.
# A later field belongs in LEGACY_FIELD_GROUPS_BY_SECTION, not in this baseline.
#
# A8: this dictionary is hand-maintained and freely editable, so nothing
# stops a genuinely new field from being added here instead of to the real
# LEGACY_FIELD_GROUPS_BY_SECTION cohort in tuning_service.gd — the coverage
# loop in test_every_exported_field_has_override_migration_coverage cannot
# tell the difference, even though only a legacy cohort is ever actually
# backfilled at runtime. An on-device override that predates such a
# wrongly-baselined field would silently keep its raw script default
# forever. PHASE0_BASELINE_FIELD_SET_SHA256 below freezes the exact
# (section, field) set so that can never happen silently: growing this
# dictionary requires deliberately recomputing that hash, and a genuinely
# new field belongs in a legacy cohort instead, which is verified for real.
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
# See A8 comment above PHASE0_BASELINE_FIELDS_BY_SECTION. Computed as the
# sha256 of the sorted "section.field" lines for every entry in that
# dictionary — recompute deliberately (see
# test_phase_zero_baseline_field_set_is_frozen) if this dictionary itself
# ever legitimately needs to change, never to make a wrongly-placed new
# field pass unnoticed.
const PHASE0_BASELINE_FIELD_SET_SHA256 := (
	"82ca926b700d262fde76f28c96159bedc47883bba9e12497c20e7c4ac46a1386"
)


func before_each() -> void:
	_remove_test_override()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(
			TEST_OVERRIDE_PATH.get_base_dir()
		)
	)
	assert_true(directory_error in [OK, ERR_ALREADY_EXISTS])


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


func test_old_economy_override_backfills_mask_hit_grace() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.economy.mask_hit_invulnerability_s = (
		EconomyTuning.new().mask_hit_invulnerability_s
	)
	stale.economy.wumpa_per_standard_crate += 1
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
		migrated.economy.mask_hit_invulnerability_s,
		authored.economy.mask_hit_invulnerability_s
	)
	assert_eq(
		migrated.economy.wumpa_per_standard_crate,
		stale.economy.wumpa_per_standard_crate,
		"migration must preserve existing economy edits"
	)


func test_old_economy_override_backfills_placed_wumpa_payout() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.economy.wumpa_per_pickup = (
		EconomyTuning.new().wumpa_per_pickup
	)
	stale.economy.wumpa_per_standard_crate += 1
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
		migrated.economy.wumpa_per_pickup,
		authored.economy.wumpa_per_pickup
	)
	assert_eq(
		migrated.economy.wumpa_per_standard_crate,
		stale.economy.wumpa_per_standard_crate,
		"migration must preserve the crate-specific payout"
	)


func test_old_economy_override_backfills_mercy_banner_duration() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var default_duration: Variant = EconomyTuning.new().get(
		&"mercy_banner_duration_s"
	)
	assert_eq(
		typeof(default_duration),
		TYPE_FLOAT,
		"the mercy notice lifetime must be an exported tuning field"
	)
	if typeof(default_duration) != TYPE_FLOAT:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.economy.set(
		&"mercy_banner_duration_s",
		default_duration
	)
	stale.economy.mercy_mask_death_threshold += 1
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
		migrated.economy.get(&"mercy_banner_duration_s"),
		authored.economy.get(&"mercy_banner_duration_s")
	)
	assert_eq(
		migrated.economy.mercy_mask_death_threshold,
		stale.economy.mercy_mask_death_threshold,
		"migration must preserve existing mercy edits"
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


## A8: the coverage loop above treats "listed in PHASE0_BASELINE_FIELDS_BY_
## SECTION" and "listed in a LEGACY_FIELD_GROUPS_BY_SECTION cohort" as
## equally valid coverage, but only a legacy cohort is ever actually
## backfilled at runtime (see _backfill_legacy_field_groups). A field that
## genuinely needs migration but is added to the baseline dictionary
## instead — trivial to do, since it is just a hand-typed test constant —
## would still satisfy every assertion above, while an on-device override
## that predates it would silently keep the field's raw script default
## forever. This test closes that hole: the exact (section, field) set in
## PHASE0_BASELINE_FIELDS_BY_SECTION is frozen against a signature, so
## growing it can never be silent. Proved by mutation (see the A8 fix
## report): temporarily adding a real legacy-registered field's name to
## this dictionary — the exact shape of the hole — turns this test red.
func test_phase_zero_baseline_field_set_is_frozen() -> void:
	var baseline_signature_lines := PackedStringArray()
	for section_value: Variant in PHASE0_BASELINE_FIELDS_BY_SECTION:
		var section_name := StringName(section_value)
		for field_name: StringName in (
			PHASE0_BASELINE_FIELDS_BY_SECTION[section_name]
		):
			baseline_signature_lines.append(
				String(section_name) + "." + String(field_name)
			)
	baseline_signature_lines.sort()
	assert_eq(
		"\n".join(baseline_signature_lines).sha256_text(),
		PHASE0_BASELINE_FIELD_SET_SHA256,
		(
			"the Phase 0 baseline field set changed — a field belongs "
			+ "here ONLY if it never needed migration; a genuinely new "
			+ "field belongs in LEGACY_FIELD_GROUPS_BY_SECTION instead, "
			+ "where it gets real, functionally-proven backfill coverage, "
			+ "not just a name in a list (see A8)"
		)
	)


## R4: the sha256 freeze above is a speed bump, not a barrier — recomputing
## it to match whatever PHASE0_BASELINE_FIELDS_BY_SECTION currently says is
## a purely mechanical paste of the value the failing test itself prints,
## with no judgment about whether a field genuinely predates migration.
## Executed proof (see the R4 fix report): mis-register a real
## LEGACY_FIELD_GROUPS_BY_SECTION field (e.g. phase_button_diameter_mm)
## into the input baseline instead, paste the new hash, and both
## test_every_exported_field_has_override_migration_coverage and
## test_phase_zero_baseline_field_set_is_frozen go green while a real old
## override predating that field would still silently lose its authored
## value.
##
## PHASE0_INPUT_OVERRIDE_PATH is not just a name — it is a real, committed
## resource authored in the exact Phase-0 shape (predating the
## phase_button_* fields), driven through the real production load path by
## test_phase_zero_input_fields_backfill_without_losing_operator_values
## above. This test derives the input section's baseline directly from
## which fields are textually present in that real artifact and requires
## PHASE0_BASELINE_FIELDS_BY_SECTION[&"input"] to match it exactly, field
## for field. Unlike the sha256 freeze, there is no hash to silently
## recompute here: a mis-registered field disagrees with a real committed
## file's actual content, not with a claim about itself.
##
## This does not extend to the other 8 sections: no equivalent real
## Phase-0-era artifact is committed for move/camera/depth/wall_run/grind/
## swing/phase/economy today. Authoring one now would not be "real" in the
## same sense — it would just be another hand-typed claim about the past
## wearing a .tres extension, providing no more protection than the
## existing sha256 freeze already does. Those sections keep the frozen
## hash as the strongest available guard until a genuine historical
## artifact exists for them too.
func test_input_phase_zero_baseline_matches_the_real_committed_artifact() -> void:
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var artifact_fields := _tres_subresource_field_names(
		PHASE0_INPUT_OVERRIDE_PATH
	)
	assert_gt(
		artifact_fields.size(),
		0,
		"the real Phase 0 artifact must actually author some input fields"
	)
	var artifact_field_set := {}
	for field_name: StringName in artifact_fields:
		artifact_field_set[field_name] = true

	var claimed_baseline: Array = PHASE0_BASELINE_FIELDS_BY_SECTION.get(
		&"input", []
	)
	for exported_field: StringName in _exported_property_names(authored.input):
		assert_eq(
			claimed_baseline.has(exported_field),
			artifact_field_set.has(exported_field),
			(
				"input.%s's baseline-vs-legacy classification does not "
				+ "match the real Phase 0 artifact — a field present in "
				+ "PHASE0_INPUT_OVERRIDE_PATH belongs in the baseline; one "
				+ "absent from it (added since) belongs in "
				+ "LEGACY_FIELD_GROUPS_BY_SECTION instead (see R4)"
			) % exported_field
		)


## Reads which properties are textually assigned inside a .tres file's
## [sub_resource] block(s), skipping the `script =` assignment itself.
## Scoped to fixtures shaped like PHASE0_INPUT_OVERRIDE_PATH (a single
## sub_resource carrying one section's fields) — not a general .tres
## parser.
func _tres_subresource_field_names(artifact_path: String) -> Array[StringName]:
	var field_names: Array[StringName] = []
	var text := FileAccess.get_file_as_string(artifact_path)
	var inside_sub_resource := false
	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("["):
			inside_sub_resource = line.begins_with("[sub_resource")
			continue
		if not inside_sub_resource:
			continue
		var equals_index := line.find(" = ")
		if equals_index == -1:
			continue
		var property_name := line.substr(0, equals_index)
		if property_name == "script":
			continue
		field_names.append(StringName(property_name))
	return field_names


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


## Shared by test_every_invalid_economy_field_is_rejected_from_disk and
## test_every_exported_economy_field_has_a_rejection_case (N1's guard-the-
## guard check) so a field can never gain "coverage" without a real,
## behaviorally-asserted bad value.
func _economy_invalid_values(authored: GameplayTuning) -> Array[Array]:
	return [
		[&"wumpa_per_standard_crate", 0],
		[&"wumpa_per_pickup", 0],
		[&"wumpa_collect_radius_m", 0.0],
		[&"wumpa_mask_threshold", 0],
		[&"mask_stack_maximum", 0],
		[&"invincibility_duration_s", 0.0],
		[&"mask_hit_invulnerability_s", 0.0],
		[&"tnt_fuse_s", 0.0],
		[&"tnt_blast_radius_m", 0.0],
		[&"bounce_crate_max_bounces", 0],
		[&"bounce_crate_wumpa_per_bounce", 0],
		[&"bounce_launch_height_m", 0.0],
		# N1: not the literal sentinel, since that value equals this field's
		# own script default and its legacy cohort is a lone field — the
		# real backfill path would silently heal it before catalog_is_usable
		# ever runs, which would make this specific case a false rejection.
		# A value at the tuned fall floor is fatal without being the
		# sentinel, so it reaches catalog_is_usable unmigrated. Every other
		# axis is held at its authored value so this case isolates .y (see
		# R1's guard-the-guard: a case that also moves an untested axis
		# away from baseline cannot prove that axis is bounded).
		[
			&"checkpoint_respawn_offset",
			Vector3(
				authored.economy.checkpoint_respawn_offset.x,
				authored.move.respawn_floor_y_m,
				authored.economy.checkpoint_respawn_offset.z,
			),
		],
		# R1: .x and .z were completely unbounded — catalog_is_usable used
		# to check only .y against move.respawn_floor_y_m. Each case here
		# isolates its own axis so the per-component bound is genuinely
		# proven, not just asserted for the field as a whole.
		[
			&"checkpoint_respawn_offset",
			Vector3(
				absf(authored.move.respawn_floor_y_m) + 1.0,
				authored.economy.checkpoint_respawn_offset.y,
				authored.economy.checkpoint_respawn_offset.z,
			),
		],
		[
			&"checkpoint_respawn_offset",
			Vector3(
				authored.economy.checkpoint_respawn_offset.x,
				authored.economy.checkpoint_respawn_offset.y,
				absf(authored.move.respawn_floor_y_m) + 1.0,
			),
		],
		[&"checkpoint_spacing_limit_s", 0.0],
		[&"mercy_mask_death_threshold", 0],
		[&"mercy_skip_death_threshold", 0],
		[&"mercy_banner_duration_s", 0.0],
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
	for invalid_value: Array in _economy_invalid_values(authored):
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


## Guard-the-guard for N1/R1: proves every exported EconomyTuning field has
## a real, behaviorally-asserted bad value in _economy_invalid_values (and
## therefore gets exercised by test_every_invalid_economy_field_is_rejected_
## from_disk above), so a new field can never go unbounded the way
## checkpoint_respawn_offset did. R1: field-name coverage alone is not
## enough for a Vector3 field -- one case whose bad value happens to touch
## only one axis (e.g. Vector3(0, floor, 0), which incidentally also moves
## .z away from its authored value) can satisfy "the field is covered"
## while a sibling axis (.x here) stays completely unbounded. So for every
## Vector3-typed field, also demand a case per axis that ISOLATES that
## axis -- every other component held at its authored value -- proving the
## bound genuinely holds component-by-component, not just field-by-field.
func test_every_exported_economy_field_has_a_rejection_case() -> void:
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var covered_fields := {}
	var isolated_axes_by_field := {}
	for invalid_value: Array in _economy_invalid_values(authored):
		var field_name := invalid_value[0] as StringName
		covered_fields[field_name] = true
		var bad_value: Variant = invalid_value[1]
		if bad_value is Vector3:
			var baseline: Vector3 = authored.economy.get(field_name)
			var differing_axes: Array[int] = []
			for axis in range(3):
				if not is_equal_approx(bad_value[axis], baseline[axis]):
					differing_axes.append(axis)
			if differing_axes.size() == 1:
				var axes: Dictionary = isolated_axes_by_field.get(
					field_name, {}
				)
				axes[differing_axes[0]] = true
				isolated_axes_by_field[field_name] = axes
	var axis_names := ["x", "y", "z"]
	for exported_field: StringName in _exported_property_names(authored.economy):
		assert_true(
			covered_fields.has(exported_field),
			(
				"%s has no rejection case in _economy_invalid_values — an "
				+ "unbounded economy field can silently carry its sentinel "
				+ "default straight into play (see N1)"
			) % exported_field
		)
		var field_value: Variant = authored.economy.get(exported_field)
		if field_value is Vector3:
			var covered_axes: Dictionary = isolated_axes_by_field.get(
				exported_field, {}
			)
			for axis in range(3):
				assert_true(
					covered_axes.has(axis),
					(
						"%s.%s has no rejection case that isolates that "
						+ "axis (every other component held at its "
						+ "authored value) -- a field-name-only case can "
						+ "leave one axis completely unbounded while the "
						+ "field is reported 'covered' (see R1)"
					) % [exported_field, axis_names[axis]]
				)


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
		# N1: the sentinel default must never be usable — a stale on-device
		# override whose backfill cohort does not match (e.g. a future
		# field rename) would otherwise leave this exact value in play and
		# respawn the player ~999 km under the world on every checkpoint.
		[
			catalog.economy,
			&"checkpoint_respawn_offset",
			Vector3(-999999.0, -999999.0, -999999.0),
		],
		# N1: an offset at or below the tuned fall floor is just as fatal —
		# e.g. an operator dragging the drawer's Y slider far down — and is
		# not the sentinel, so backfill would not touch it either.
		[
			catalog.economy,
			&"checkpoint_respawn_offset",
			Vector3(0.0, catalog.move.respawn_floor_y_m, 0.0),
		],
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


func test_checkpoint_respawn_offset_x_and_z_axes_are_bounded_like_y() -> void:
	# R1: catalog_is_usable only ever bounded checkpoint_respawn_offset.y
	# against move.respawn_floor_y_m. The on-device drawer's SpinBox for
	# this field allows +-1,000,000 on every axis (tuning_debug_ui.gd), so
	# an operator (or a stale override) could leave .x/.z completely
	# unbounded while .y stays just inside the old check -- landing the
	# player a million meters sideways from every checkpoint on respawn,
	# reproducing P0-2's unrecoverable death-loop shape sideways instead
	# of downward.
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog: GameplayTuning = service.get("catalog")
	var authored_offset := catalog.economy.checkpoint_respawn_offset
	assert_true(service.call("catalog_is_usable"))

	# Exact repro from the recheck: y stays just inside the old floor
	# check, x/z are set to the on-device drawer's own max magnitude.
	catalog.economy.checkpoint_respawn_offset = Vector3(
		1000000.0, authored_offset.y, 1000000.0
	)
	assert_false(
		service.call("catalog_is_usable"),
		(
			"a checkpoint respawn offset with huge x/z must be rejected "
			+ "even when y alone clears the fall floor"
		)
	)

	# Isolate each axis in turn against an otherwise-authored offset, so a
	# future regression confined to a single axis is caught here too.
	catalog.economy.checkpoint_respawn_offset = Vector3(
		1000000.0, authored_offset.y, authored_offset.z
	)
	assert_false(
		service.call("catalog_is_usable"),
		"checkpoint_respawn_offset.x alone must be bounded"
	)
	catalog.economy.checkpoint_respawn_offset = Vector3(
		authored_offset.x, authored_offset.y, 1000000.0
	)
	assert_false(
		service.call("catalog_is_usable"),
		"checkpoint_respawn_offset.z alone must be bounded"
	)

	catalog.economy.checkpoint_respawn_offset = authored_offset
	assert_true(service.call("catalog_is_usable"))


func test_stick_region_and_jump_catchall_overlap_is_rejected() -> void:
	# I17: stick_region_width_ratio and jump_catchall_width_ratio are each
	# bounded to (0.0, 1.0] independently, but both regions are carved
	# from opposite edges of the same safe_rect.size.x (touch_control_
	# layout.gd) -- once their sum exceeds 1.0 the regions overlap, and
	# TouchControlLayout resolves every touch in the overlap as a jump
	# (the jump catchall check runs first), so the player can never
	# start a movement drag there. Same shape as N1: per-field bounds
	# both pass while the cross-field invariant silently does not hold.
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog: GameplayTuning = service.get("catalog")
	assert_true(service.call("catalog_is_usable"))

	var authored_catchall := catalog.input.jump_catchall_width_ratio
	# Stays inside jump_catchall_width_ratio's own (0.0, 1.0] bound but
	# pushes the sum past 1.0 against the real authored stick ratio --
	# this is the same combination verified against the real
	# TouchControlLayout.calculate() during this finding's derivation
	# (real input.tres stick=0.42, catchall raised to 0.7 -> a real
	# 124,416 px^2 overlap where a live TouchControls resolves JUMP and
	# stick_touch_index() stays -1).
	catalog.input.jump_catchall_width_ratio = clampf(
		1.0 - catalog.input.stick_region_width_ratio + 0.1,
		0.0001,
		1.0
	)
	assert_false(
		service.call("catalog_is_usable"),
		"a stick region and jump catchall that overlap must be rejected"
	)
	catalog.input.jump_catchall_width_ratio = authored_catchall

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


func test_a_corrupt_authored_base_catalog_is_rejected_loudly() -> void:
	# R7: load_from_paths only ever ran catalog_is_usable against the
	# OVERRIDE resource -- the authored base catalog was cloned straight
	# into `catalog` with no validation at all, on every boot, whether or
	# not an override even exists. A corrupt or mis-authored base .tres
	# (a bad export, a hand-edit that broke a value, a merge that landed
	# wrong) would silently become "the usable catalog" with nobody ever
	# noticing -- the exact "authored, persisted, consumed unchecked"
	# shape this project exists to prevent.
	var broken_base_path := "user://test_sandbox/broken_base_catalog.tres"
	var authored: GameplayTuning = load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	authored.move.run_speed_mps = 0.0
	assert_eq(ResourceSaver.save(authored, broken_base_path), OK)

	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return
	var missing_override_path := "user://test_sandbox/no_such_override.tres"
	assert_false(FileAccess.file_exists(missing_override_path))

	var boot_error: Error = service.call(
		"load_from_paths", broken_base_path, missing_override_path
	)

	assert_ne(
		boot_error,
		OK,
		"a corrupt authored base catalog must fail loudly, not load silently"
	)
	assert_null(
		service.get("catalog"),
		"a rejected base catalog must not remain the effective catalog"
	)

	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(broken_base_path)
	)


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
