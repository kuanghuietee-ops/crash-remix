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
	&"enemy_crab": [
		&"patrol_speed_mps",
		&"patrol_span_m",
		&"turn_pause_s",
		&"telegraph_s",
		&"attack_active_s",
		&"attack_cooldown_s",
		&"trigger_range_m",
	],
	&"enemy_skink": [
		&"patrol_speed_mps",
		&"patrol_span_m",
		&"turn_pause_s",
		&"telegraph_s",
		&"attack_active_s",
		&"attack_cooldown_s",
		&"trigger_range_m",
	],
	&"enemy_plant": [
		&"patrol_speed_mps",
		&"patrol_span_m",
		&"turn_pause_s",
		&"telegraph_s",
		&"attack_active_s",
		&"attack_cooldown_s",
		&"trigger_range_m",
	],
	&"chase": [
		&"boulder_speed_mps",
		&"boulder_kill_distance_m",
		&"boulder_start_gap_m",
	],
	&"hog": [
		&"ride_speed_mps",
		&"steer_lateral_speed_mps",
		&"hog_jump_height_m",
	],
	&"boss_papu": [
		&"phase_count",
		&"arena_strikes_per_phase",
		&"slam_period_s",
		&"shockwave_speed_mps",
		&"shockwave_height_m",
		&"debris_telegraph_s",
	],
	# Task 1 (CTR racing mode): kart and race are whole new sections, the
	# same shape as enemy/chase/hog/boss_papu above -- _backfill_missing_
	# sections migrates a missing section atomically, so every field authored
	# at introduction joins this baseline (see the comment below).
	&"kart": [
		&"top_speed_mps",
		&"reverse_speed_mps",
		&"accel_mps2",
		&"brake_mps2",
		&"coast_drag_mps2",
		&"steer_rate_degrees_per_s",
		&"steer_speed_falloff",
		&"hop_height_m",
		&"gravity_mps2",
		&"slide_min_steer",
		&"slide_yaw_bonus_degrees_per_s",
		&"slide_counter_yaw_degrees_per_s",
		&"slide_min_duration_s",
		&"boost_window_open_s",
		&"boost_window_close_s",
		&"boost_window_shrink_factor",
		&"boost_speed_bonus_mps",
		&"boost_duration_s",
		&"boost_stack_max",
		&"spin_out_duration_s",
		&"spin_out_speed_keep_ratio",
		&"invulnerable_after_hit_s",
	],
	&"race": [
		&"lap_count",
		&"countdown_step_s",
		&"start_boost_window_s",
		&"start_bog_penalty_s",
		&"wrong_way_grace_s",
		&"checkpoint_tolerance_m",
		&"respawn_drop_height_m",
		&"camera_trail_m",
		&"camera_height_m",
		&"camera_fov_base",
		&"camera_fov_speed_gain",
		&"camera_yaw_lag_s",
		&"camera_drift_yaw_degrees",
	],
	# Task 1 (CTR R3, AI opponents): ai is a whole new section, the same
	# shape as kart/race/enemy/chase/hog/boss_papu above -- _backfill_
	# missing_sections migrates a missing section atomically, so every field
	# authored at introduction joins this baseline (see the comment below).
	&"ai": [
		&"opponent_count",
		&"lateral_slot_spacing_m",
		&"lookahead_min_m",
		&"lookahead_speed_gain_s",
		&"steer_gain",
		&"corner_speed_curvature_gain",
		&"corner_speed_floor_ratio",
		&"brake_margin_ratio",
		&"slide_trigger_curvature",
		&"slide_exit_curvature",
		&"boost_tap_enabled",
		&"rubber_band_full_gap_m",
		&"rubber_band_boost_max_ratio",
		&"rubber_band_drag_max_ratio",
		&"respawn_stuck_speed_mps",
		&"respawn_stuck_after_s",
		&"respawn_drop_gap_m",
	],
	# R4 Task 2 (CTR item loop): items is a whole new section, the same
	# shape as kart/race/ai above -- _backfill_missing_sections migrates a
	# missing section atomically, so every field authored at introduction
	# joins this baseline (see the comment below).
	&"items": [
		&"roulette_duration_s",
		&"roulette_tick_s",
		&"box_respawn_s",
		&"box_pickup_radius_m",
		&"missile_speed_mps",
		&"missile_turn_rate_degrees_per_s",
		&"missile_lifetime_s",
		&"missile_arm_delay_s",
		&"missile_hit_radius_m",
		&"shield_duration_s",
		&"turbo_boost_s",
		&"beaker_arm_delay_s",
		&"beaker_lifetime_s",
		&"beaker_hit_radius_m",
		&"ai_item_use_cooldown_s",
		&"ai_missile_max_target_gap_m",
	],
	# Task 1 (CTR R6, circuit polish): fx is a whole new section, the same
	# shape as kart/race/ai/items above -- _backfill_missing_sections
	# migrates a missing section atomically, so every field authored at
	# introduction joins this baseline (see the comment below).
	&"fx": [
		&"spark_amount_stage0",
		&"spark_amount_per_stage",
		&"spark_lifetime_s",
		&"spark_velocity_mps",
		&"spark_color_stage1",
		&"spark_color_stage2",
		&"spark_color_stage3",
		&"boost_flame_lifetime_s",
		&"boost_flame_amount",
		&"item_box_spin_degrees_per_s",
		&"item_box_bob_amplitude_m",
		&"item_box_bob_hz",
	],
}
# Tasks 17, 19, 20 and 22 add whole enemy, chase, hog and boss_papu sections,
# Task 1 (CTR racing mode) adds whole kart and race sections, Task 1 (CTR R3,
# AI opponents) adds a whole ai section, R4 Task 2 (CTR item loop) adds a
# whole items section, and Task 1 (CTR R6, circuit polish) adds a whole fx
# section; _backfill_missing_sections migrates each atomically for every
# older override. Their initial fields therefore join this baseline; later
# fields inside those sections still belong in a legacy cohort. Computed as
# the sha256 of the sorted "section.field" lines for every entry in that
# dictionary — recompute deliberately (see
# test_phase_zero_baseline_field_set_is_frozen) if this dictionary itself
# ever legitimately needs to change, never to make a wrongly-placed new
# field pass unnoticed.
const PHASE0_BASELINE_FIELD_SET_SHA256 := (
	"6a1d3df7a184a49ef696e4daaaeb3a5bf0667377ded3d9c28f388d4cd6edadd7"
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
	assert_eq(_global_class_name(catalog.get("enemy_crab")), "EnemyTuning")
	assert_eq(_global_class_name(catalog.get("enemy_skink")), "EnemyTuning")
	assert_eq(_global_class_name(catalog.get("enemy_plant")), "EnemyTuning")
	assert_eq(_global_class_name(catalog.get("chase")), "ChaseTuning")
	assert_eq(_global_class_name(catalog.get("hog")), "HogTuning")
	assert_eq(_global_class_name(catalog.get("boss_papu")), "BossTuning")


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


func test_service_catalog_exposes_all_three_enemy_sections() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			"user://tuning/does_not_exist.tres"
		),
		OK
	)
	var catalog: Resource = service.get("catalog")
	# Difficulty-pass (2026-07-29): patrol/telegraph/chomp values are operator
	# tuning, not frozen constants — read the authored source instead of
	# hardcoding it a second time, so this stays a dead-wiring check rather
	# than a value-freeze.
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var expected_values := {
		&"enemy_crab": {
			&"patrol_speed_mps": authored.enemy_crab.patrol_speed_mps,
			&"patrol_span_m": 4.0,
			&"trigger_lateral_m": 0.0,
		},
		&"enemy_skink": {
			&"telegraph_s": authored.enemy_skink.telegraph_s,
			&"attack_active_s": 1.0,
			&"trigger_range_m": 9.5,
			&"trigger_lateral_m": 5.0,
		},
		&"enemy_plant": {
			&"attack_active_s": authored.enemy_plant.attack_active_s,
			&"trigger_range_m": 2.5,
			&"trigger_lateral_m": 0.0,
		},
	}
	for section_name: StringName in expected_values:
		var enemy_tuning := catalog.get(section_name) as Resource
		assert_not_null(
			enemy_tuning,
			"clone dropped %s — enemy tuning is dead-wired"
			% section_name
		)
		if enemy_tuning == null:
			continue
		assert_eq(_global_class_name(enemy_tuning), "EnemyTuning")
		for property_name: StringName in expected_values[section_name]:
			assert_eq(
				enemy_tuning.get(property_name),
				expected_values[section_name][property_name]
			)


func test_service_catalog_exposes_chase_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var chase := service.get("catalog").get("chase") as Resource

	assert_not_null(chase, "clone dropped chase — boulder tuning is dead-wired")
	if chase == null:
		return
	assert_eq(_global_class_name(chase), "ChaseTuning")
	# Difficulty-pass (2026-07-29): boulder speed/gap are operator tuning —
	# read the authored source rather than freezing it a second time.
	var authored_chase := (
		load(BASE_CATALOG_PATH) as GameplayTuning
	).chase
	assert_eq(chase.get("boulder_speed_mps"), authored_chase.boulder_speed_mps)
	assert_eq(chase.get("boulder_kill_distance_m"), 1.0)
	assert_eq(
		chase.get("boulder_start_gap_m"),
		authored_chase.boulder_start_gap_m
	)
	assert_true(
		_exported_property_names(chase).has(
			&"opening_auto_run_duration_s"
		),
		"the three-second opening must be live typed tuning"
	)
	if _exported_property_names(chase).has(
		&"opening_auto_run_duration_s"
	):
		assert_eq(
			chase.get("opening_auto_run_duration_s"),
			3.0
		)


func test_service_catalog_exposes_hog_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var hog := service.get("catalog").get("hog") as Resource

	assert_not_null(
		hog,
		"clone dropped hog — ride tuning is dead-wired"
	)
	if hog == null:
		return
	assert_eq(_global_class_name(hog), "HogTuning")
	# Difficulty-pass (2026-07-29, spec Decision 4): ride_speed_mps is
	# operator tuning — read the authored source instead of freezing it
	# a second time.
	var authored_hog_section := (
		load(BASE_CATALOG_PATH) as GameplayTuning
	).hog
	assert_eq(
		hog.get("ride_speed_mps"),
		authored_hog_section.ride_speed_mps
	)
	assert_eq(hog.get("steer_lateral_speed_mps"), 5.0)
	assert_eq(hog.get("hog_jump_height_m"), 2.0)


func test_service_catalog_exposes_boss_papu_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var boss := service.get("catalog").get("boss_papu") as Resource

	assert_not_null(
		boss,
		"clone dropped boss_papu — the Papu fight is dead-wired"
	)
	if boss == null:
		return
	assert_eq(_global_class_name(boss), "BossTuning")
	# 01-DESIGN §4.2: phase_count is [spec] §8.2; the rest are [proposed] —
	# and, being [proposed] operator tuning, difficulty-pass (2026-07-29)
	# retimes them. Read the authored source instead of freezing it again.
	var authored_boss := (
		load(BASE_CATALOG_PATH) as GameplayTuning
	).boss_papu
	assert_eq(boss.get("phase_count"), 3)
	assert_eq(boss.get("arena_strikes_per_phase"), 1)
	assert_eq(boss.get("slam_period_s"), authored_boss.slam_period_s)
	assert_eq(
		boss.get("shockwave_speed_mps"),
		authored_boss.shockwave_speed_mps
	)
	assert_eq(boss.get("shockwave_height_m"), 0.8)
	assert_eq(
		boss.get("debris_telegraph_s"),
		authored_boss.debris_telegraph_s
	)


func test_fingerprint_moves_when_a_boss_papu_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var boss := service.get("catalog").get("boss_papu") as Resource
	assert_not_null(boss)
	if boss == null:
		return
	var before: String = service.call("fingerprint")

	boss.set("slam_period_s", float(boss.get("slam_period_s")) + 0.1)

	assert_ne(
		service.call("fingerprint"),
		before,
		"boss_papu values never reach the tuning fingerprint"
	)


func test_an_unjumpable_shockwave_is_refused() -> void:
	# §4.14 calls the shockwave jumpable. The on-device drawer can push any
	# float, and a shockwave taller than the jump arc is an unwinnable fight
	# with no way back out — the N1 lesson: bound it against the field that
	# already governs it.
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog := service.get("catalog") as GameplayTuning
	var jump_height: float = catalog.move.jump_full_height_m
	assert_true(
		service.call("catalog_is_usable", catalog),
		"the authored catalog must be usable before the guard is proved"
	)

	catalog.boss_papu.shockwave_height_m = jump_height

	assert_false(
		service.call("catalog_is_usable", catalog),
		"a shockwave at or above the full jump height is not jumpable"
	)


func test_pre_boss_override_backfills_boss_papu() -> void:
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var authored_boss := authored.get("boss_papu") as Resource
	assert_not_null(
		authored_boss,
		"the authored boss_papu section must exist before migration is proved"
	)
	if authored_boss == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("boss_papu", null)
	stale.hog.ride_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return
	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)
	assert_true(
		service.get("override_active"),
		"a pre-boss phone override must migrate, not reset"
	)
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("boss_papu"))
	assert_eq(
		migrated.get("boss_papu").get("slam_period_s"),
		authored_boss.get("slam_period_s")
	)
	assert_almost_eq(
		migrated.hog.ride_speed_mps,
		float(authored.hog.ride_speed_mps) + 0.1,
		0.0001,
		"migration must not discard the edit the phone already had"
	)


func test_fingerprint_moves_when_a_hog_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var hog := service.get("catalog").get("hog") as Resource
	assert_not_null(hog)
	if hog == null:
		return
	var before: String = service.call("fingerprint")

	hog.set(
		"ride_speed_mps",
		float(hog.get("ride_speed_mps")) + 0.1
	)

	assert_ne(
		service.call("fingerprint"),
		before,
		"hog values never reach the tuning fingerprint"
	)


func test_pre_hog_override_backfills_hog_and_preserves_existing_edits() -> void:
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(authored)
	if authored == null:
		return
	var authored_hog := authored.get("hog") as Resource
	assert_not_null(
		authored_hog,
		"the authored hog section must exist before migration can be proved"
	)
	if authored_hog == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("hog", null)
	stale.chase.boulder_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	var service: RefCounted = _new_service()
	assert_not_null(service)
	if service == null:
		return
	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)
	assert_true(
		service.get("override_active"),
		"a pre-hog phone override must migrate, not reset"
	)
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("hog"))
	assert_eq(
		migrated.get("hog").get("ride_speed_mps"),
		authored_hog.get("ride_speed_mps")
	)
	assert_eq(
		migrated.chase.boulder_speed_mps,
		stale.chase.boulder_speed_mps,
		"hog backfill must preserve existing operator tuning"
	)


func test_hog_tuning_rejects_nonpositive_ride_contracts() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var hog := service.get("catalog").get("hog") as Resource
	assert_not_null(hog)
	if hog == null:
		return
	for property_name: StringName in [
		&"ride_speed_mps",
		&"steer_lateral_speed_mps",
		&"hog_jump_height_m",
	]:
		var authored_value: Variant = hog.get(property_name)
		hog.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"%s must reject zero" % property_name
		)
		hog.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_fingerprint_moves_when_a_chase_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var before: String = service.call("fingerprint")
	var chase := service.get("catalog").get("chase") as Resource
	assert_not_null(chase)
	if chase == null:
		return

	chase.set(
		"boulder_speed_mps",
		float(chase.get("boulder_speed_mps")) + 0.1
	)

	assert_ne(
		before,
		service.call("fingerprint"),
		"chase values never reach the tuning fingerprint"
	)


func test_pre_chase_override_backfills_chase_and_toward_camera_offset() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	assert_not_null(authored.get("chase"))
	assert_true(
		_exported_property_names(authored.camera).has(
			&"toward_camera_offset"
		)
	)
	if (
		authored.get("chase") == null
		or not _exported_property_names(authored.camera).has(
			&"toward_camera_offset"
		)
	):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("chase", null)
	stale.camera.set(
		&"toward_camera_offset",
		CameraTuning.new().get(&"toward_camera_offset")
	)
	stale.camera.field_of_view_degrees = 61.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("chase"))
	assert_eq(
		migrated.camera.get(&"toward_camera_offset"),
		authored.camera.get(&"toward_camera_offset")
	)
	assert_eq(
		migrated.camera.field_of_view_degrees,
		61.0,
		"migration must preserve existing camera edits"
	)


func test_chase_tuning_rejects_invalid_pressure_contracts() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var chase := service.get("catalog").get("chase") as Resource
	assert_not_null(chase)
	if chase == null:
		return
	var invalid_cases: Array[Array] = [
		[&"boulder_speed_mps", 0.0],
		[&"boulder_kill_distance_m", 0.0],
		[&"boulder_start_gap_m", 0.0],
		[
			&"boulder_start_gap_m",
			float(chase.get("boulder_kill_distance_m")),
		],
	]
	if _exported_property_names(chase).has(
		&"opening_auto_run_duration_s"
	):
		invalid_cases.append([
			&"opening_auto_run_duration_s",
			-1.0,
		])
	for invalid_case: Array in invalid_cases:
		var field_name := invalid_case[0] as StringName
		var authored_value: Variant = chase.get(field_name)
		chase.set(field_name, invalid_case[1])
		assert_false(
			service.call("catalog_is_usable"),
			"%s=%s must be rejected"
			% [field_name, invalid_case[1]]
		)
		chase.set(field_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_an_uncompletable_boulder_chase_is_refused() -> void:
	# The boulder must never be faster than the player's own run speed:
	# with no rubber-band mechanic, a faster boulder closes the gap and
	# catches Crash regardless of player skill, and the level cannot be
	# finished. Bound it against the field that already governs it -- the
	# same N1 lesson as the boss shockwave-vs-jump-height guard.
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog := service.get("catalog") as GameplayTuning
	var run_speed_mps: float = catalog.move.run_speed_mps
	assert_true(
		service.call("catalog_is_usable", catalog),
		"the authored catalog must be usable before the guard is proved"
	)

	catalog.chase.boulder_speed_mps = run_speed_mps

	assert_false(
		service.call("catalog_is_usable", catalog),
		"a boulder at or above the player's run speed is uncompletable"
	)


func test_old_chase_override_backfills_opening_auto_run_duration() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"opening_auto_run_duration_s"
	assert_true(
		_exported_property_names(authored.chase).has(field),
		"the opening duration must exist before migration can be proved"
	)
	if not _exported_property_names(authored.chase).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	var operator_speed_mps := authored.chase.boulder_speed_mps + 0.1
	stale.chase.set(field, ChaseTuning.new().get(field))
	stale.chase.boulder_speed_mps = operator_speed_mps
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.chase.get(field),
		authored.chase.get(field),
		"an older phone override must receive the three-second opening"
	)
	assert_almost_eq(
		migrated.chase.boulder_speed_mps,
		operator_speed_mps,
		0.001,
		"migration must preserve existing boulder-speed edits"
	)


func test_fingerprint_moves_when_an_enemy_value_changes() -> void:
	var service: RefCounted = _new_service()
	if service == null:
		return
	service.call(
		"load_from_paths",
		BASE_CATALOG_PATH,
		"user://tuning/does_not_exist.tres"
	)
	var before: String = service.call("fingerprint")
	var skink := (
		service.get("catalog").get("enemy_skink") as Resource
	)
	assert_not_null(skink)
	if skink == null:
		return

	skink.set(
		"telegraph_s",
		float(skink.get("telegraph_s")) + 0.1
	)

	assert_ne(
		before,
		service.call("fingerprint"),
		"enemy_skink never reaches the tuning fingerprint"
	)


func test_pre_enemy_override_backfills_all_enemy_sections() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var enemy_sections: Array[StringName] = [
		&"enemy_crab",
		&"enemy_skink",
		&"enemy_plant",
	]
	var sections_exist := true
	for section_name: StringName in enemy_sections:
		var section: Variant = authored.get(section_name)
		assert_not_null(
			section,
			"%s must exist before migration can be proved" % section_name
		)
		sections_exist = sections_exist and section != null
	if not sections_exist:
		return

	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	for section_name: StringName in enemy_sections:
		stale.set(section_name, null)
	stale.economy.tnt_fuse_s = 4.25
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)
	assert_false(
		service.get("override_rejected"),
		"a pre-enemy phone override must migrate, not reset"
	)
	assert_true(service.get("override_active"))
	var migrated := service.get("catalog") as GameplayTuning
	for section_name: StringName in enemy_sections:
		assert_not_null(migrated.get(section_name))
	assert_eq(
		migrated.economy.tnt_fuse_s,
		4.25,
		"enemy backfill must preserve existing operator tuning"
	)


func test_old_enemy_override_backfills_skink_trigger_lateral_bound() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	var operator_telegraph_s := authored.enemy_skink.telegraph_s + 0.1
	stale.enemy_skink.trigger_lateral_m = (
		EnemyTuning.new().trigger_lateral_m
	)
	stale.enemy_skink.telegraph_s = operator_telegraph_s
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.enemy_skink.trigger_lateral_m,
		authored.enemy_skink.trigger_lateral_m,
		"an older phone override must receive the safe trigger bound"
	)
	assert_almost_eq(
		migrated.enemy_skink.telegraph_s,
		operator_telegraph_s,
		0.001,
		"migration must preserve existing skink tuning edits"
	)


func test_enemy_tuning_contract_rejects_invalid_behavior_shapes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog := service.get("catalog") as GameplayTuning
	var sections: Array[StringName] = [
		&"enemy_crab",
		&"enemy_skink",
		&"enemy_plant",
	]
	var sections_exist := true
	for section_name: StringName in sections:
		var section: Variant = catalog.get(section_name)
		assert_not_null(section)
		sections_exist = sections_exist and section != null
	if not sections_exist:
		return

	var crab := catalog.get("enemy_crab") as Resource
	var skink := catalog.get("enemy_skink") as Resource
	var plant := catalog.get("enemy_plant") as Resource
	var invalid_cases: Array[Array] = [
		[crab, &"patrol_speed_mps", 0.0],
		[crab, &"patrol_span_m", 0.0],
		[crab, &"turn_pause_s", -0.01],
		[crab, &"trigger_lateral_m", 0.01],
		[skink, &"telegraph_s", 0.0],
		[skink, &"attack_active_s", 0.0],
		[skink, &"attack_cooldown_s", 0.0],
		[skink, &"trigger_range_m", 0.0],
		[skink, &"trigger_lateral_m", 0.0],
		[plant, &"telegraph_s", 0.0],
		[plant, &"attack_active_s", 0.0],
		[plant, &"attack_cooldown_s", 0.0],
		[plant, &"trigger_range_m", 0.0],
		[plant, &"trigger_lateral_m", 0.01],
	]
	for invalid_case: Array in invalid_cases:
		var section := invalid_case[0] as Resource
		var property_name := invalid_case[1] as StringName
		var authored_value: Variant = section.get(property_name)
		section.set(property_name, invalid_case[2])
		assert_false(
			service.call("catalog_is_usable"),
			"%s=%s must be rejected"
			% [property_name, invalid_case[2]]
		)
		section.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


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
	assert_true(joined.contains("enemy_crab.tres"))
	assert_true(joined.contains("enemy_skink.tres"))
	assert_true(joined.contains("enemy_plant.tres"))
	assert_true(joined.contains("chase.tres"))
	assert_true(joined.contains("hog.tres"))


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


func test_catalog_is_unusable_without_any_enemy_section() -> void:
	var service: RefCounted = _new_service()
	for section_name: StringName in [
		&"enemy_crab",
		&"enemy_skink",
		&"enemy_plant",
	]:
		var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
			Resource.DEEP_DUPLICATE_ALL
		)
		if catalog.get(section_name) == null:
			assert_not_null(
				catalog.get(section_name),
				"%s must exist before null rejection can be proved"
				% section_name
			)
			continue
		catalog.set(section_name, null)
		assert_false(
			service.call("catalog_is_usable", catalog),
			"catalog must reject missing %s" % section_name
			)


func test_catalog_is_unusable_without_chase() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	catalog.set("chase", null)

	assert_false(service.call("catalog_is_usable", catalog))


func test_catalog_is_unusable_without_hog() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("hog"))
	if catalog.get("hog") == null:
		return
	catalog.set("hog", null)

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


func test_old_phase_override_backfills_dedicated_missed_crate_outline() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var outline_fields: Array[Array] = [
		[&"missed_crate_outline_color", TYPE_COLOR],
		[&"missed_crate_outline_opacity", TYPE_FLOAT],
		[&"missed_crate_outline_edge_width_uv", TYPE_FLOAT],
		[&"missed_crate_outline_padding_m", TYPE_FLOAT],
	]
	var outline_fields_exist := true
	for field: Array in outline_fields:
		var property_name := field[0] as StringName
		var expected_type := int(field[1])
		var actual_type := typeof(authored.phase.get(property_name))
		assert_eq(
			actual_type,
			expected_type,
			"%s must be exported by PhaseTuning" % property_name
		)
		outline_fields_exist = (
			outline_fields_exist
			and actual_type == expected_type
		)
	if not outline_fields_exist:
		return

	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	var phase_defaults := PhaseTuning.new()
	for field: Array in outline_fields:
		var property_name := field[0] as StringName
		stale.phase.set(property_name, phase_defaults.get(property_name))
	stale.phase.ghost_opacity = 1.0
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
	for field: Array in outline_fields:
		var property_name := field[0] as StringName
		assert_eq(
			migrated.phase.get(property_name),
			authored.phase.get(property_name),
			"old overrides must receive authored %s" % property_name
		)
	assert_eq(
		migrated.phase.ghost_opacity,
		1.0,
		(
			"migration must preserve every previously valid Phase ghost edit, "
			+ "including full opacity"
		)
	)


func test_missed_crate_outline_tuning_is_bounded() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var catalog: GameplayTuning = service.get("catalog")
	var phase := catalog.phase
	var required_fields := [
		&"missed_crate_outline_color",
		&"missed_crate_outline_opacity",
		&"missed_crate_outline_edge_width_uv",
		&"missed_crate_outline_padding_m",
	]
	var fields_exist := true
	for property_name: StringName in required_fields:
		var value: Variant = phase.get(property_name)
		assert_ne(
			value,
			null,
			"%s must exist before its bounds can be proved" % property_name
		)
		fields_exist = fields_exist and value != null
	if not fields_exist:
		return

	var authored_values := {}
	for property_name: StringName in required_fields:
		authored_values[property_name] = phase.get(property_name)
	var invalid_values: Array[Array] = [
		[
			&"missed_crate_outline_opacity",
			0.0,
		],
		[&"missed_crate_outline_opacity", 1.01],
		[&"missed_crate_outline_edge_width_uv", 0.0],
		[&"missed_crate_outline_edge_width_uv", 0.5],
		[&"missed_crate_outline_padding_m", 0.0],
		[
			&"missed_crate_outline_padding_m",
			catalog.move.collision_radius_m + 0.01,
		],
		[
			&"missed_crate_outline_color",
			Color(1.0, 1.0, 1.0, 0.0),
		],
	]
	for invalid_value: Array in invalid_values:
		var property_name := invalid_value[0] as StringName
		phase.set(property_name, invalid_value[1])
		assert_false(
			service.call("catalog_is_usable"),
			"%s must reject %s" % [property_name, invalid_value[1]]
		)
		phase.set(property_name, authored_values[property_name])
	assert_true(service.call("catalog_is_usable"))


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


func test_old_camera_override_backfills_rail_handle_length_factor() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"rail_handle_length_factor"
	assert_true(
		_exported_property_names(authored.camera).has(field),
		"the rail handle length factor must exist before migration can be proved"
	)
	if not _exported_property_names(authored.camera).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.camera.set(field, CameraTuning.new().get(field))
	stale.camera.field_of_view_degrees = 62.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.camera.get(field),
		authored.camera.get(field),
		"an older phone override must receive the authored handle length factor"
	)
	assert_almost_eq(
		migrated.camera.field_of_view_degrees,
		62.0,
		0.001,
		"migration must preserve existing camera edits"
	)


func test_old_camera_override_backfills_corridor_tangent_baseline_m() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"corridor_tangent_baseline_m"
	assert_true(
		_exported_property_names(authored.camera).has(field),
		"the corridor tangent baseline must exist before migration can be proved"
	)
	if not _exported_property_names(authored.camera).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.camera.set(field, CameraTuning.new().get(field))
	stale.camera.field_of_view_degrees = 63.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.camera.get(field),
		authored.camera.get(field),
		"an older phone override must receive the authored corridor tangent baseline"
	)
	assert_almost_eq(
		migrated.camera.field_of_view_degrees,
		63.0,
		0.001,
		"migration must preserve existing camera edits"
	)


func test_old_input_override_backfills_gesture_axis_slew_degrees_per_s() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"gesture_axis_slew_degrees_per_s"
	assert_true(
		_exported_property_names(authored.input).has(field),
		"the gesture axis slew rate must exist before migration can be proved"
	)
	if not _exported_property_names(authored.input).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.input.set(field, InputTuning.new().get(field))
	stale.input.fallback_dpi = 179.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.input.get(field),
		authored.input.get(field),
		"an older phone override must receive the authored gesture axis slew rate"
	)
	assert_almost_eq(
		migrated.input.fallback_dpi,
		179.0,
		0.001,
		"migration must preserve existing input edits"
	)


func test_old_input_override_backfills_racing_brake_pull_threshold() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"racing_brake_pull_threshold"
	assert_true(
		_exported_property_names(authored.input).has(field),
		"the racing brake pull threshold must exist before migration can be proved"
	)
	if not _exported_property_names(authored.input).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.input.set(field, InputTuning.new().get(field))
	stale.input.fallback_dpi = 179.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.input.get(field),
		authored.input.get(field),
		"an older phone override must receive the authored racing brake pull threshold"
	)
	assert_almost_eq(
		migrated.input.fallback_dpi,
		179.0,
		0.001,
		"migration must preserve existing input edits"
	)


func test_racing_brake_pull_threshold_is_bounded_to_open_unit_interval() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var input := service.get("catalog").get("input") as Resource
	assert_not_null(input)
	if input == null:
		return
	var authored_value: float = input.get("racing_brake_pull_threshold")

	input.set("racing_brake_pull_threshold", 0.0)
	assert_false(
		service.call("catalog_is_usable"),
		"a zero brake pull threshold must be rejected"
	)

	input.set("racing_brake_pull_threshold", 1.0)
	assert_false(
		service.call("catalog_is_usable"),
		"a brake pull threshold of 1.0 (unreachable) must be rejected"
	)

	input.set("racing_brake_pull_threshold", authored_value)
	assert_true(service.call("catalog_is_usable"))


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
	assert_has(loaded_paths, "res://data/tuning/hog.tres")


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


# Task 1 (CTR racing mode): kart and race are brand-new whole sections, the
# same shape as enemy/chase/hog/boss_papu when each was introduced -- a
# missing section backfills wholesale via _backfill_missing_sections rather
# than needing a LEGACY_FIELD_GROUPS_BY_SECTION cohort (that mechanism is for
# a new field on an EXISTING section, not a whole new section).
const KART_RATIO_FIELDS: Array[StringName] = [
	&"steer_speed_falloff",
	&"boost_window_shrink_factor",
	&"spin_out_speed_keep_ratio",
]


func test_service_catalog_exposes_kart_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource

	assert_not_null(kart, "clone dropped kart — kart tuning is dead-wired")
	if kart == null:
		return
	assert_eq(_global_class_name(kart), "KartTuning")
	assert_eq(kart.get("top_speed_mps"), 18.0)
	assert_eq(kart.get("boost_stack_max"), 3.0)
	assert_eq(kart.get("spin_out_speed_keep_ratio"), 0.35)


func test_service_catalog_exposes_race_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var race := service.get("catalog").get("race") as Resource

	assert_not_null(race, "clone dropped race — race tuning is dead-wired")
	if race == null:
		return
	assert_eq(_global_class_name(race), "RaceTuning")
	assert_eq(race.get("lap_count"), 3.0)
	assert_eq(race.get("checkpoint_tolerance_m"), 2.0)


func test_fingerprint_moves_when_a_kart_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(kart)
	if kart == null:
		return
	var before: String = service.call("fingerprint")

	kart.set("top_speed_mps", float(kart.get("top_speed_mps")) + 0.1)

	assert_ne(
		service.call("fingerprint"),
		before,
		"kart values never reach the tuning fingerprint"
	)


func test_fingerprint_moves_when_a_race_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var race := service.get("catalog").get("race") as Resource
	assert_not_null(race)
	if race == null:
		return
	var before: String = service.call("fingerprint")

	race.set("lap_count", float(race.get("lap_count")) + 1.0)

	assert_ne(
		service.call("fingerprint"),
		before,
		"race values never reach the tuning fingerprint"
	)


func test_pre_racing_override_backfills_kart_and_race() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	assert_not_null(authored.get("kart"))
	assert_not_null(authored.get("race"))
	if authored.get("kart") == null or authored.get("race") == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("kart", null)
	stale.set("race", null)
	stale.hog.ride_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)

	assert_false(
		service.get("override_rejected"),
		"a pre-racing phone override must migrate, not reset"
	)
	assert_true(service.get("override_active"))
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("kart"))
	assert_not_null(migrated.get("race"))
	assert_eq(
		migrated.get("kart").get("top_speed_mps"),
		authored.kart.top_speed_mps
	)
	assert_almost_eq(
		migrated.hog.ride_speed_mps,
		float(authored.hog.ride_speed_mps) + 0.1,
		0.0001,
		"migration must not discard the edit the phone already had"
	)


func test_kart_tuning_rejects_nonpositive_fields() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(kart)
	if kart == null:
		return
	for property_name: StringName in _exported_property_names(kart):
		var authored_value: Variant = kart.get(property_name)
		kart.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"kart.%s must reject zero" % property_name
		)
		kart.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_kart_ratio_fields_are_bounded_to_unit_interval() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(kart)
	if kart == null:
		return
	for property_name: StringName in KART_RATIO_FIELDS:
		var authored_value: Variant = kart.get(property_name)
		kart.set(property_name, 1.01)
		assert_false(
			service.call("catalog_is_usable"),
			"kart.%s must reject values above 1.0" % property_name
		)
		kart.set(property_name, 1.0)
		assert_true(
			service.call("catalog_is_usable"),
			"kart.%s must accept exactly 1.0" % property_name
		)
		kart.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


# Carried from the Task 1 review: DriftStateMachine (Task 2) computes each
# boost stage's window as [open_s, close_s] scaled by shrink^n and treats a
# tap before open_s as mistimed, inside as fired, after close_s as ignored --
# a close_s at or below open_s collapses or inverts that window, so it must
# be rejected the same way the other kart cross-field constraints are.
func test_kart_boost_window_close_must_exceed_open() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(kart)
	if kart == null:
		return
	var authored_open: float = kart.get("boost_window_open_s")
	var authored_close: float = kart.get("boost_window_close_s")

	kart.set("boost_window_close_s", authored_open)
	assert_false(
		service.call("catalog_is_usable"),
		"boost_window_close_s equal to boost_window_open_s must be rejected"
	)

	kart.set("boost_window_close_s", authored_open - 0.01)
	assert_false(
		service.call("catalog_is_usable"),
		"boost_window_close_s below boost_window_open_s must be rejected"
	)

	kart.set("boost_window_close_s", authored_close)
	assert_true(
		service.call("catalog_is_usable"),
		"the authored close_s > open_s must remain valid"
	)


# L2 (final fix wave): boost_stack_max is a float field with INTEGER
# semantics -- DriftStateMachine reads it via roundi(_tuning.boost_stack_max)
# to cap how many boost stages a slide can accrue (see drift_state_machine.gd
# line ~163). test_kart_tuning_rejects_nonpositive_fields above only rejects
# <= 0.0, so a panel-authored 0.4 (a real value a slider or on-device edit
# can produce) sails through validation, roundi()s to 0, and boost is
# silently dead for the whole session with no error anywhere.
func test_kart_boost_stack_max_rejects_values_below_one() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(kart)
	if kart == null:
		return
	var authored: float = kart.get("boost_stack_max")

	kart.set("boost_stack_max", 0.4)
	assert_false(
		service.call("catalog_is_usable"),
		"boost_stack_max below 1.0 must be rejected -- it rounds to a dead 0-stage boost"
	)

	kart.set("boost_stack_max", 1.0)
	assert_true(
		service.call("catalog_is_usable"),
		"boost_stack_max of exactly 1.0 must remain valid"
	)

	kart.set("boost_stack_max", authored)
	assert_true(service.call("catalog_is_usable"))


# Task 5 (CTR kart chase camera): camera_look_height_m was added to the
# already-shipped race section after Task 1's initial fields, so an
# override authored before this field existed must be migrated the same
# functionally-proven way as test_old_input_override_backfills_
# racing_brake_pull_threshold, not merely registered in a coverage list.
func test_old_race_override_backfills_camera_look_height_m() -> void:
	var service: RefCounted = _new_service()
	var authored: GameplayTuning = load(BASE_CATALOG_PATH)
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	var field := &"camera_look_height_m"
	assert_true(
		_exported_property_names(authored.race).has(field),
		"the camera look height must exist before migration can be proved"
	)
	if not _exported_property_names(authored.race).has(field):
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.race.set(field, RaceTuning.new().get(field))
	stale.race.lap_count = 5.0
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
	var migrated := service.get("catalog") as GameplayTuning
	assert_eq(
		migrated.race.get(field),
		authored.race.get(field),
		"an older phone override must receive the authored camera look height"
	)
	assert_almost_eq(
		migrated.race.lap_count,
		5.0,
		0.001,
		"migration must preserve existing race edits"
	)


func test_race_tuning_rejects_nonpositive_fields() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var race := service.get("catalog").get("race") as Resource
	assert_not_null(race)
	if race == null:
		return
	for property_name: StringName in _exported_property_names(race):
		var authored_value: Variant = race.get(property_name)
		race.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"race.%s must reject zero" % property_name
		)
		race.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


# L2 (final fix wave): lap_count is a float field with INTEGER semantics --
# race_session.gd reads it via int(_race_tuning.lap_count) for both
# lap_count() (the HUD's "LAP n/N" display) and the LapValidator's own
# configure() call. test_race_tuning_rejects_nonpositive_fields above only
# rejects <= 0.0, so a panel-authored 0.5 sails through validation, truncates
# to 0, and the HUD reads "LAP 0/0" with no error anywhere.
func test_race_lap_count_rejects_values_below_one() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var race := service.get("catalog").get("race") as Resource
	assert_not_null(race)
	if race == null:
		return
	var authored: float = race.get("lap_count")

	race.set("lap_count", 0.5)
	assert_false(
		service.call("catalog_is_usable"),
		"lap_count below 1.0 must be rejected -- it truncates to a dead LAP 0/0"
	)

	race.set("lap_count", 1.0)
	assert_true(
		service.call("catalog_is_usable"),
		"lap_count of exactly 1.0 must remain valid"
	)

	race.set("lap_count", authored)
	assert_true(service.call("catalog_is_usable"))


func test_catalog_is_unusable_without_kart() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("kart"))
	if catalog.get("kart") == null:
		return
	catalog.set("kart", null)

	assert_false(service.call("catalog_is_usable", catalog))


func test_catalog_is_unusable_without_race() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("race"))
	if catalog.get("race") == null:
		return
	catalog.set("race", null)

	assert_false(service.call("catalog_is_usable", catalog))


func test_loaded_paths_include_the_racing_resources() -> void:
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

	assert_true(joined.contains("kart.tres"), "debug HUD will not list kart.tres")
	assert_true(joined.contains("race.tres"), "debug HUD will not list race.tres")
	assert_true(joined.contains("ai.tres"), "debug HUD will not list ai.tres")
	assert_true(joined.contains("items.tres"), "debug HUD will not list items.tres")


# Task 1 (CTR R3, AI opponents): ai is a brand-new whole section, the same
# shape as kart/race/enemy/chase/hog/boss_papu when each was introduced -- a
# missing section backfills wholesale via _backfill_missing_sections rather
# than needing a LEGACY_FIELD_GROUPS_BY_SECTION cohort (that mechanism is for
# a new field on an EXISTING section, not a whole new section).
# boost_tap_enabled is a 0/1 flag stored as a float, so 0.0 is a legal value
# for it and it is excluded from the generic "every field rejects zero" loop
# below, getting its own dedicated flag-bounds test instead.
const AI_STRICTLY_POSITIVE_FIELDS_EXCLUDING_FLAGS: Array[StringName] = [
	&"opponent_count",
	&"lateral_slot_spacing_m",
	&"lookahead_min_m",
	&"lookahead_speed_gain_s",
	&"steer_gain",
	&"corner_speed_curvature_gain",
	&"corner_speed_floor_ratio",
	&"brake_margin_ratio",
	&"slide_trigger_curvature",
	&"slide_exit_curvature",
	&"rubber_band_full_gap_m",
	&"rubber_band_boost_max_ratio",
	&"rubber_band_drag_max_ratio",
	&"respawn_stuck_speed_mps",
	&"respawn_stuck_after_s",
	&"respawn_drop_gap_m",
]
# Bounded to (0.0, 1.0] -- see AiTuning.corner_speed_floor_ratio's doc
# comment: it clamps the low end of a multiplier whose high end is fixed at
# 1.0, so exactly 1.0 must remain valid.
const AI_INCLUSIVE_UNIT_RATIO_FIELDS: Array[StringName] = [
	&"corner_speed_floor_ratio",
]
# Bounded to (0.0, 1.0) exclusive per the design brief -- unlike the kart/
# race ratio fields (which accept exactly 1.0), these two must reject 1.0.
const AI_EXCLUSIVE_UNIT_RATIO_FIELDS: Array[StringName] = [
	&"rubber_band_boost_max_ratio",
	&"rubber_band_drag_max_ratio",
]


func test_service_catalog_exposes_ai_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource

	assert_not_null(ai, "clone dropped ai — AI tuning is dead-wired")
	if ai == null:
		return
	assert_eq(_global_class_name(ai), "AiTuning")
	assert_eq(ai.get("opponent_count"), 5.0)
	assert_eq(ai.get("boost_tap_enabled"), 1.0)
	assert_eq(ai.get("rubber_band_full_gap_m"), 60.0)


func test_fingerprint_moves_when_an_ai_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	var before: String = service.call("fingerprint")

	ai.set("steer_gain", float(ai.get("steer_gain")) + 0.1)

	assert_ne(
		service.call("fingerprint"),
		before,
		"ai values never reach the tuning fingerprint"
	)


func test_pre_ai_override_backfills_ai() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	assert_not_null(authored.get("ai"))
	if authored.get("ai") == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("ai", null)
	stale.hog.ride_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)

	assert_false(
		service.get("override_rejected"),
		"a pre-AI phone override must migrate, not reset"
	)
	assert_true(service.get("override_active"))
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("ai"))
	assert_eq(
		migrated.get("ai").get("opponent_count"),
		authored.ai.opponent_count
	)
	assert_almost_eq(
		migrated.hog.ride_speed_mps,
		float(authored.hog.ride_speed_mps) + 0.1,
		0.0001,
		"migration must not discard the edit the phone already had"
	)


func test_ai_tuning_rejects_nonpositive_fields() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	for property_name: StringName in AI_STRICTLY_POSITIVE_FIELDS_EXCLUDING_FLAGS:
		var authored_value: Variant = ai.get(property_name)
		ai.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"ai.%s must reject zero" % property_name
		)
		ai.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_ai_lookahead_min_m_rejects_nonpositive() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	var authored: float = ai.get("lookahead_min_m")

	ai.set("lookahead_min_m", 0.0)
	assert_false(
		service.call("catalog_is_usable"),
		"a nonpositive lookahead_min_m must be rejected"
	)
	ai.set("lookahead_min_m", -1.0)
	assert_false(
		service.call("catalog_is_usable"),
		"a negative lookahead_min_m must be rejected"
	)

	ai.set("lookahead_min_m", authored)
	assert_true(service.call("catalog_is_usable"))


func test_ai_corner_speed_floor_ratio_is_bounded_to_unit_interval_inclusive() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	for property_name: StringName in AI_INCLUSIVE_UNIT_RATIO_FIELDS:
		var authored_value: Variant = ai.get(property_name)
		ai.set(property_name, 1.01)
		assert_false(
			service.call("catalog_is_usable"),
			"ai.%s must reject values above 1.0" % property_name
		)
		ai.set(property_name, 1.0)
		assert_true(
			service.call("catalog_is_usable"),
			"ai.%s must accept exactly 1.0" % property_name
		)
		ai.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_ai_rubber_band_ratio_fields_are_bounded_to_unit_interval_exclusive() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	for property_name: StringName in AI_EXCLUSIVE_UNIT_RATIO_FIELDS:
		var authored_value: Variant = ai.get(property_name)
		ai.set(property_name, 1.0)
		assert_false(
			service.call("catalog_is_usable"),
			"ai.%s must reject exactly 1.0 -- the brief bounds it (0,1) exclusive"
			% property_name
		)
		ai.set(property_name, 0.99)
		assert_true(
			service.call("catalog_is_usable"),
			"ai.%s must accept a value below 1.0" % property_name
		)
		ai.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_ai_boost_tap_enabled_is_bounded_to_flag_values() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var ai := service.get("catalog").get("ai") as Resource
	assert_not_null(ai)
	if ai == null:
		return
	var authored: float = ai.get("boost_tap_enabled")

	ai.set("boost_tap_enabled", 0.5)
	assert_false(
		service.call("catalog_is_usable"),
		"boost_tap_enabled=0.5 must be rejected -- it is a 0/1 flag, not a ratio"
	)

	ai.set("boost_tap_enabled", 0.0)
	assert_true(
		service.call("catalog_is_usable"),
		"boost_tap_enabled=0.0 (disabled) must remain valid"
	)

	ai.set("boost_tap_enabled", 1.0)
	assert_true(
		service.call("catalog_is_usable"),
		"boost_tap_enabled=1.0 (enabled) must remain valid"
	)

	ai.set("boost_tap_enabled", authored)
	assert_true(service.call("catalog_is_usable"))


func test_catalog_is_unusable_without_ai() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("ai"))
	if catalog.get("ai") == null:
		return
	catalog.set("ai", null)

	assert_false(service.call("catalog_is_usable", catalog))


# R4 Task 2 (CTR item loop): items is a brand-new whole section, the same
# shape as kart/race/ai when each was introduced -- a missing section
# backfills wholesale via _backfill_missing_sections rather than needing a
# LEGACY_FIELD_GROUPS_BY_SECTION cohort (that mechanism is for a new field
# on an EXISTING section, not a whole new section). Every field is a
# duration, speed, or radius with no ratio-typed exception, so every field
# simply rejects zero -- unlike ai, there is no separate flag/ratio-bounds
# test needed here.
const ITEMS_STRICTLY_POSITIVE_FIELDS: Array[StringName] = [
	&"roulette_duration_s",
	&"roulette_tick_s",
	&"box_respawn_s",
	&"box_pickup_radius_m",
	&"missile_speed_mps",
	&"missile_turn_rate_degrees_per_s",
	&"missile_lifetime_s",
	&"missile_arm_delay_s",
	&"missile_hit_radius_m",
	&"shield_duration_s",
	&"turbo_boost_s",
	&"beaker_arm_delay_s",
	&"beaker_lifetime_s",
	&"beaker_hit_radius_m",
	&"ai_item_use_cooldown_s",
	&"ai_missile_max_target_gap_m",
]


func test_service_catalog_exposes_items_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var items := service.get("catalog").get("items") as Resource

	assert_not_null(items, "clone dropped items — item tuning is dead-wired")
	if items == null:
		return
	assert_eq(_global_class_name(items), "ItemTuning")
	assert_eq(items.get("roulette_duration_s"), 1.2)
	assert_eq(items.get("box_respawn_s"), 4.0)
	assert_eq(items.get("missile_speed_mps"), 26.0)
	assert_eq(items.get("ai_missile_max_target_gap_m"), 45.0)


func test_fingerprint_moves_when_an_items_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var items := service.get("catalog").get("items") as Resource
	assert_not_null(items)
	if items == null:
		return
	var before: String = service.call("fingerprint")

	items.set("shield_duration_s", float(items.get("shield_duration_s")) + 0.1)

	assert_ne(
		service.call("fingerprint"),
		before,
		"items values never reach the tuning fingerprint"
	)


func test_pre_items_override_backfills_items() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	assert_not_null(authored.get("items"))
	if authored.get("items") == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("items", null)
	stale.hog.ride_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)

	assert_false(
		service.get("override_rejected"),
		"a pre-items phone override must migrate, not reset"
	)
	assert_true(service.get("override_active"))
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("items"))
	assert_eq(
		migrated.get("items").get("roulette_duration_s"),
		authored.items.roulette_duration_s
	)
	assert_almost_eq(
		migrated.hog.ride_speed_mps,
		float(authored.hog.ride_speed_mps) + 0.1,
		0.0001,
		"migration must not discard the edit the phone already had"
	)


func test_items_tuning_rejects_nonpositive_fields() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var items := service.get("catalog").get("items") as Resource
	assert_not_null(items)
	if items == null:
		return
	for property_name: StringName in ITEMS_STRICTLY_POSITIVE_FIELDS:
		var authored_value: Variant = items.get(property_name)
		items.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"items.%s must reject zero" % property_name
		)
		items.set(property_name, -1.0)
		assert_false(
			service.call("catalog_is_usable"),
			"items.%s must reject a negative value" % property_name
		)
		items.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


func test_catalog_is_unusable_without_items() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("items"))
	if catalog.get("items") == null:
		return
	catalog.set("items", null)

	assert_false(service.call("catalog_is_usable", catalog))


# ---------------------------------------------------------------------------
# Task 1 (CTR R6, circuit polish): fx is a whole new section, the same shape
# as kart/race/ai/items above -- mirrors each of their own registration
# tests one section up.
# ---------------------------------------------------------------------------


const FX_STRICTLY_POSITIVE_FIELDS: Array[StringName] = [
	&"spark_amount_stage0",
	&"spark_amount_per_stage",
	&"spark_lifetime_s",
	&"spark_velocity_mps",
	&"boost_flame_lifetime_s",
	&"boost_flame_amount",
	&"item_box_spin_degrees_per_s",
	&"item_box_bob_amplitude_m",
	&"item_box_bob_hz",
]

const FX_SPARK_COLOR_FIELDS: Array[StringName] = [
	&"spark_color_stage1",
	&"spark_color_stage2",
	&"spark_color_stage3",
]


func test_service_catalog_exposes_fx_section() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource

	assert_not_null(fx, "clone dropped fx — fx tuning is dead-wired")
	if fx == null:
		return
	assert_eq(_global_class_name(fx), "FxTuning")
	assert_eq(fx.get("spark_amount_stage0"), 12.0)
	assert_eq(fx.get("spark_amount_per_stage"), 8.0)
	assert_eq(fx.get("boost_flame_amount"), 20.0)
	assert_eq(fx.get("item_box_spin_degrees_per_s"), 90.0)


func test_fingerprint_moves_when_an_fx_value_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	assert_not_null(fx)
	if fx == null:
		return
	var before: String = service.call("fingerprint")

	fx.set("spark_amount_stage0", float(fx.get("spark_amount_stage0")) + 1.0)

	assert_ne(
		service.call("fingerprint"),
		before,
		"fx values never reach the tuning fingerprint"
	)


## Color-typed fields (spark_color_stage1/2/3) must reach the fingerprint the
## same generic way every other exported field does (var_to_str() serializes
## a Color, see tuning_service.gd's _append_fingerprint_lines) -- pinned
## separately from the float-field test above because a Color property is a
## different Variant type and this repo's own input.control_color precedent
## is the thing this whole field shape is following.
func test_fingerprint_moves_when_an_fx_spark_color_changes() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	assert_not_null(fx)
	if fx == null:
		return
	var before: String = service.call("fingerprint")

	var color: Color = fx.get("spark_color_stage1")
	fx.set("spark_color_stage1", Color(color.r, color.g, color.b, 0.5))

	assert_ne(
		service.call("fingerprint"),
		before,
		"fx spark color values never reach the tuning fingerprint"
	)


func test_pre_fx_override_backfills_fx() -> void:
	var service: RefCounted = _new_service()
	var authored := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(service)
	assert_not_null(authored)
	if service == null or authored == null:
		return
	assert_not_null(authored.get("fx"))
	if authored.get("fx") == null:
		return
	var stale := authored.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	stale.set("fx", null)
	stale.hog.ride_speed_mps += 0.1
	assert_eq(ResourceSaver.save(stale, TEST_OVERRIDE_PATH), OK)

	assert_eq(
		service.call(
			"load_from_paths",
			BASE_CATALOG_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)

	assert_false(
		service.get("override_rejected"),
		"a pre-fx phone override must migrate, not reset"
	)
	assert_true(service.get("override_active"))
	var migrated := service.get("catalog") as GameplayTuning
	assert_not_null(migrated.get("fx"))
	assert_eq(
		migrated.get("fx").get("spark_amount_stage0"),
		authored.fx.spark_amount_stage0
	)
	assert_almost_eq(
		migrated.hog.ride_speed_mps,
		float(authored.hog.ride_speed_mps) + 0.1,
		0.0001,
		"migration must not discard the edit the phone already had"
	)


func test_fx_tuning_rejects_nonpositive_fields() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	assert_not_null(fx)
	if fx == null:
		return
	for property_name: StringName in FX_STRICTLY_POSITIVE_FIELDS:
		var authored_value: Variant = fx.get(property_name)
		fx.set(property_name, 0.0)
		assert_false(
			service.call("catalog_is_usable"),
			"fx.%s must reject zero" % property_name
		)
		fx.set(property_name, -1.0)
		assert_false(
			service.call("catalog_is_usable"),
			"fx.%s must reject a negative value" % property_name
		)
		fx.set(property_name, authored_value)
	assert_true(service.call("catalog_is_usable"))


## The mobile particle budget ceiling (documented in tuning_service.gd's own
## fx validation block): the worst case for the drift spark stream is the
## kart's own top authored boost stage (kart.boost_stack_max), not just the
## raw stage-0 field in isolation -- spark_amount_stage0 + spark_amount_per_
## stage * kart.boost_stack_max is the number that actually reaches
## GPUParticles3D.amount at runtime (see kart_fx.gd).
func test_fx_spark_amount_ceiling_rejects_a_worst_case_stage_amount_above_64() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	var kart := service.get("catalog").get("kart") as Resource
	assert_not_null(fx)
	assert_not_null(kart)
	if fx == null or kart == null:
		return
	var authored_per_stage: float = fx.get("spark_amount_per_stage")
	var stack_max: float = kart.get("boost_stack_max")
	assert_gt(stack_max, 0.0, "fixture sanity: boost_stack_max must be positive")

	# The exact per-stage amount that pushes the worst-case total 1.0 above
	# the ceiling.
	var overflow_per_stage: float = (
		(65.0 - float(fx.get("spark_amount_stage0"))) / stack_max
	)
	fx.set("spark_amount_per_stage", overflow_per_stage)
	assert_false(
		service.call("catalog_is_usable"),
		"a worst-case stage amount above 64 must be rejected"
	)

	fx.set("spark_amount_per_stage", authored_per_stage)
	assert_true(
		service.call("catalog_is_usable"),
		"the authored per-stage amount must stay under the ceiling"
	)


func test_fx_boost_flame_amount_ceiling_rejects_values_above_64() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	assert_not_null(fx)
	if fx == null:
		return
	var authored: float = fx.get("boost_flame_amount")

	fx.set("boost_flame_amount", 64.0)
	assert_true(
		service.call("catalog_is_usable"),
		"exactly the ceiling (64) must remain valid"
	)

	fx.set("boost_flame_amount", 64.01)
	assert_false(
		service.call("catalog_is_usable"),
		"boost_flame_amount above 64 must be rejected -- the mobile particle budget"
	)

	fx.set("boost_flame_amount", authored)
	assert_true(service.call("catalog_is_usable"))


## Mirrors phase.missed_crate_outline_color.a's own bound: an alpha of 0
## would make a fired boost stage's sparks fully invisible, and Color's own
## fields are otherwise unbounded (HDR-capable), so only alpha is checked --
## same shape input.control_color's own (unbounded) precedent leaves RGB
## alone.
func test_fx_spark_color_alpha_is_bounded_to_the_unit_interval() -> void:
	var service: RefCounted = _loaded_service()
	if service == null:
		return
	var fx := service.get("catalog").get("fx") as Resource
	assert_not_null(fx)
	if fx == null:
		return
	for property_name: StringName in FX_SPARK_COLOR_FIELDS:
		var authored_color: Color = fx.get(property_name)

		fx.set(property_name, Color(authored_color.r, authored_color.g, authored_color.b, 0.0))
		assert_false(
			service.call("catalog_is_usable"),
			"fx.%s must reject zero alpha" % property_name
		)

		fx.set(property_name, Color(authored_color.r, authored_color.g, authored_color.b, 1.01))
		assert_false(
			service.call("catalog_is_usable"),
			"fx.%s must reject alpha above 1.0" % property_name
		)

		fx.set(property_name, Color(authored_color.r, authored_color.g, authored_color.b, 1.0))
		assert_true(
			service.call("catalog_is_usable"),
			"fx.%s must accept alpha of exactly 1.0" % property_name
		)

		fx.set(property_name, authored_color)
	assert_true(service.call("catalog_is_usable"))


func test_catalog_is_unusable_without_fx() -> void:
	var service: RefCounted = _new_service()
	var catalog := load(BASE_CATALOG_PATH).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	assert_not_null(catalog.get("fx"))
	if catalog.get("fx") == null:
		return
	catalog.set("fx", null)

	assert_false(service.call("catalog_is_usable", catalog))


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
