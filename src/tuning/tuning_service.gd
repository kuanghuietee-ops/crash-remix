class_name TuningService
extends RefCounted

const SECTION_NAMES: Array[StringName] = [
	&"move",
	&"input",
	&"camera",
	&"depth",
	&"wall_run",
	&"grind",
	&"swing",
	&"phase",
	&"economy",
	&"enemy_crab",
	&"enemy_skink",
	&"enemy_plant",
	&"chase",
	&"hog",
	&"boss_papu",
	&"kart",
	&"race",
	&"ai",
	&"items",
	&"fx",
]
# ResourceSaver omits default-valued fields, so migrate version-defining
# cohorts atomically instead of treating every zero as a missing value.
const LEGACY_FIELD_GROUPS_BY_SECTION := {
	&"camera": [
		[
			&"toward_camera_offset",
		],
		[
			&"rail_handle_length_factor",
		],
		[
			&"corridor_tangent_baseline_m",
		],
	],
	&"input": [
		[
			&"phase_button_diameter_mm",
			&"phase_button_arc_offset_mm",
			&"phase_button_unlocked",
		],
		[
			&"hud_reserved_top_px",
		],
		[
			&"gesture_axis_slew_degrees_per_s",
		],
		[
			&"racing_brake_pull_threshold",
		],
	],
	&"swing": [
		[
			&"minimum_catch_speed_mps",
		],
		[
			&"transfer_catch_radius_m",
			&"transfer_minimum_catch_speed_mps",
		],
	],
	&"phase": [
		[
			&"missed_crate_outline_color",
			&"missed_crate_outline_opacity",
			&"missed_crate_outline_edge_width_uv",
			&"missed_crate_outline_padding_m",
		],
	],
	&"economy": [
		[
			&"mask_hit_invulnerability_s",
		],
		[
			&"wumpa_per_pickup",
		],
		[
			&"mercy_banner_duration_s",
		],
		[
			&"checkpoint_respawn_offset",
		],
	],
	&"enemy_crab": [
		[
			&"trigger_lateral_m",
		],
	],
	&"enemy_skink": [
		[
			&"trigger_lateral_m",
		],
	],
	&"enemy_plant": [
		[
			&"trigger_lateral_m",
		],
	],
	&"chase": [
		[
			&"opening_auto_run_duration_s",
		],
	],
	&"race": [
		[
			&"camera_look_height_m",
		],
		# CTR R7 Task 1 (discharges spec debt #2): pad_boost_s/pad_refire_
		# cooldown_s/jump_pad_velocity_scale added to the already-shipped
		# race section as ONE cohort -- mirrors camera_look_height_m's own
		# single-field entry immediately above and kart's own body-tint
		# entry below (an override.tres saved before this task exists
		# would be missing all three at once, never some subset).
		[
			&"pad_boost_s",
			&"pad_refire_cooldown_s",
			&"jump_pad_velocity_scale",
		],
	],
	# CTR R6 Task 3: kart-body tint fields, added to the EXISTING kart
	# section (unlike fx's own brand-new-section shape, see fx_tuning.gd's
	# own doc contrasting the two paths). Grouped as one cohort -- an
	# on-device override.tres saved before this task exists would be
	# missing all six at once, never some subset of them.
	&"kart": [
		[
			&"kart_tint_player",
			&"kart_tint_slot_1",
			&"kart_tint_slot_2",
			&"kart_tint_slot_3",
			&"kart_tint_slot_4",
			&"kart_tint_slot_5",
		],
	],
	# CTR R6 Task 4: apex/damping/personality fields, added to the already-
	# shipped ai section as ONE cohort -- mirrors kart's own body-tint entry
	# immediately above (an override.tres saved before this task exists
	# would be missing all five at once, never some subset).
	&"ai": [
		[
			&"apex_offset_max_m",
			&"apex_entry_lookahead_m",
			&"steer_damping",
			&"personality_aggression_step",
			&"personality_skill_jitter",
		],
		# CTR R7 Task 2b (OPERATOR PRIORITY): recovery fields, added to the
		# already-shipped ai section as their OWN cohort -- a SEPARATE array
		# entry from the apex/damping/personality cohort above, not folded
		# into it, because the two shipped in different tasks: an
		# override.tres saved after CTR R6 Task 4 but before this task would
		# already have the apex/damping/personality fields (real, edited
		# values) and be missing only these three -- migrating them as one
		# combined group would silently re-stamp the OLDER cohort's already-
		# migrated values back to authored defaults instead of leaving them
		# untouched.
		[
			&"recovery_heading_error_degrees",
			&"recovery_trigger_s",
			&"recovery_max_attempts",
		],
	],
	# CTR R6 Task 5: three new items (bomb, TNT stick, triple turbo) plus
	# weighted roulette, added to the already-shipped items section as ONE
	# cohort -- mirrors kart's own body-tint entry and ai's own apex entry
	# above (an override.tres saved before this task exists would be missing
	# every one of these fields at once, never some subset).
	&"items": [
		[
			&"bomb_speed_mps",
			&"bomb_blast_radius_m",
			&"bomb_arm_delay_s",
			&"tnt_fuse_s",
			&"tnt_shake_hops",
			&"triple_turbo_charges",
			&"weight_front_missile",
			&"weight_back_missile",
			&"weight_front_shield",
			&"weight_back_shield",
			&"weight_front_turbo",
			&"weight_back_turbo",
			&"weight_front_beaker",
			&"weight_back_beaker",
			&"weight_front_bomb",
			&"weight_back_bomb",
			&"weight_front_tnt_stick",
			&"weight_back_tnt_stick",
			&"weight_front_triple_turbo",
			&"weight_back_triple_turbo",
		],
	],
}

var catalog: GameplayTuning
var override_active: bool
var override_rejected: bool

var _loaded_resource_paths := PackedStringArray()
var _base_catalog_path: String
var _override_path: String


func load_from_paths(base_catalog_path: String, override_path: String) -> Error:
	override_active = false
	override_rejected = false
	_loaded_resource_paths.clear()
	_base_catalog_path = base_catalog_path
	_override_path = override_path

	var authored := _load_catalog_resource(base_catalog_path)
	if authored == null or not authored is GameplayTuning:
		return ERR_INVALID_DATA

	_record_authored_paths(authored, base_catalog_path)
	catalog = _clone_catalog(authored)
	if not catalog_is_usable(catalog):
		# R7: only the OVERRIDE resource ever ran through catalog_is_usable
		# here -- the authored base catalog was cloned straight into
		# `catalog` with no validation at all, on every boot, whether or
		# not an override even exists. A corrupt or mis-authored base
		# .tres must fail loudly (a real Error return, which
		# GameRoot._ready() already turns into a push_error and an
		# aborted boot) instead of silently becoming "the usable catalog"
		# with nobody ever noticing.
		catalog = null
		return ERR_INVALID_DATA
	if not FileAccess.file_exists(override_path):
		return OK

	var override_resource := _load_catalog_resource(override_path)
	if override_resource == null or not override_resource is GameplayTuning:
		override_rejected = true
		return OK
	_backfill_missing_sections(override_resource, authored)
	if not catalog_is_usable(override_resource):
		override_rejected = true
		return OK

	_copy_catalog_values(override_resource, catalog)
	_loaded_resource_paths.append(override_path)
	override_active = true
	return OK


func _load_catalog_resource(path: String) -> Resource:
	# Exported scripted resources are stored as compiled .res files. Filtering by
	# the script's global class name prevents Godot's binary resource loader from
	# being selected, so load generically and enforce GameplayTuning immediately
	# after the load instead.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func get_loaded_resource_paths() -> PackedStringArray:
	return _loaded_resource_paths.duplicate()


func fingerprint() -> String:
	if catalog == null:
		return ""

	var canonical_lines := PackedStringArray()
	for section_name: StringName in SECTION_NAMES:
		_append_fingerprint_lines(
			canonical_lines,
			String(section_name),
			catalog.get(section_name) as Resource
		)
	canonical_lines.sort()
	return "\n".join(canonical_lines).sha256_text()


func save_override(override_path: String) -> Error:
	if catalog == null:
		return ERR_UNCONFIGURED
	if not catalog_is_usable(catalog):
		return ERR_INVALID_DATA

	var absolute_directory := ProjectSettings.globalize_path(override_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error

	var snapshot := _clone_catalog(catalog)
	var save_error := ResourceSaver.save(snapshot, override_path)
	if save_error == OK:
		override_active = true
		override_rejected = false
		_override_path = override_path
		if not _loaded_resource_paths.has(override_path):
			_loaded_resource_paths.append(override_path)
	return save_error


## Returns whether a catalog preserves Phase 0 playability, recoverable controls,
## and finite runtime math. This is stronger than a serialization-only check.
func catalog_is_usable(candidate: GameplayTuning = null) -> bool:
	var checked := candidate if candidate != null else catalog
	if checked == null:
		return false
	for section_name: StringName in SECTION_NAMES:
		var section := checked.get(section_name) as Resource
		if section == null or not _resource_values_are_finite(section):
			return false

	var move := checked.move
	if (
		move.player_height_m <= 0.0
		or move.collision_radius_m <= 0.0
		or move.run_speed_mps <= 0.0
		or move.run_time_to_speed_s <= 0.0
		or move.stop_time_s <= 0.0
		or move.gravity_mps2 <= 0.0
		or move.jump_full_height_m <= 0.0
		or move.jump_tap_height_m <= 0.0
		or move.jump_tap_height_m > move.jump_full_height_m
		or move.double_jump_height_m <= 0.0
		or move.double_jump_tap_height_m <= 0.0
		or move.double_jump_tap_height_m > move.double_jump_height_m
		or move.high_jump_height_m <= 0.0
		or move.apex_gravity_multiplier <= 0.0
		or move.fall_gravity_multiplier <= 0.0
		or move.maximum_fall_speed_mps <= 0.0
		or move.slide_duration_s <= 0.0
		or move.hurtbox_visual_ratio <= 0.0
		or move.attack_visual_ratio <= 0.0
		or move.respawn_delay_s < 0.0
		or move.respawn_floor_y_m >= 0.0
	):
		return false

	var input := checked.input
	if (
		input.jump_buffer_s <= 0.0
		or input.coyote_time_s < 0.0
		or input.action_buffer_s <= 0.0
		or input.minimum_hop_release_s < 0.0
		or input.full_jump_hold_s < input.minimum_hop_release_s
		or input.millimeters_per_inch <= 0.0
		or input.fallback_dpi <= 0.0
		or input.control_scale <= 0.0
		or input.layout_metrics_poll_interval_s <= 0.0
		or input.stick_dead_zone_mm < 0.0
		or input.stick_full_run_mm <= input.stick_dead_zone_mm
		or input.stick_region_width_ratio <= 0.0
		or input.stick_region_width_ratio > 1.0
		or input.stick_region_top_exclusion_ratio < 0.0
		or input.stick_region_top_exclusion_ratio >= 1.0
		or input.jump_button_diameter_mm <= 0.0
		or input.spin_button_diameter_mm <= 0.0
		or input.down_button_diameter_mm <= 0.0
		or input.phase_button_diameter_mm <= 0.0
		or input.phase_button_arc_offset_mm <= 0.0
		or input.button_hit_radius_scale <= 0.0
		or input.jump_catchall_width_ratio <= 0.0
		or input.jump_catchall_width_ratio > 1.0
		or input.jump_catchall_top_ratio < 0.0
		or input.jump_catchall_top_ratio >= 1.0
		# I17: both ratios are independently bounded to (0.0, 1.0] above,
		# but TouchControlLayout carves the stick region and the jump
		# catchall from opposite edges of the same safe_rect.size.x — if
		# their sum exceeds 1.0 the two regions overlap, and inside the
		# overlap the catchall always wins, so the player can only ever
		# jump and can never start a movement drag there.
		or (
			input.stick_region_width_ratio
			+ input.jump_catchall_width_ratio
			> 1.0
		)
		or input.hud_reserved_top_px < 0.0
		# A non-positive slew rate means a held drag's gesture axis can
		# never reach the corridor axis, silently reproducing the
		# pre-corner-heading latch bug this field exists to fix.
		or input.gesture_axis_slew_degrees_per_s <= 0.0
		# Task 4 (CTR racing input mode): the racing stick's y axis is a
		# filtered magnitude in [0, 1] -- a threshold at or below 0.0 would
		# read every neutral stick as braking, and one at or above 1.0
		# would make the brake pull physically unreachable.
		or input.racing_brake_pull_threshold <= 0.0
		or input.racing_brake_pull_threshold >= 1.0
	):
		return false

	var camera := checked.camera
	if (
		camera.field_of_view_degrees <= 0.0
		or camera.rail_bake_interval_m <= 0.0
		or camera.rail_handle_length_factor < 0.0
		or camera.rail_handle_length_factor > 0.5
		or camera.rail_follow_speed_mps < 0.0
		or camera.region_blend_s < 0.0
		or camera.corridor_tangent_baseline_m <= 0.0
		or camera.toward_camera_offset.y <= 0.0
		or camera.toward_camera_offset.z >= 0.0
	):
		return false

	var wall_run := checked.wall_run
	if (
		wall_run.attach_cone_degrees <= 0.0
		or wall_run.run_speed_mps <= 0.0
		or wall_run.maximum_duration_s <= 0.0
		or wall_run.gravity_multiplier < 0.0
		or wall_run.minimum_entry_speed_mps < 0.0
		or wall_run.surface_stick_distance_m <= 0.0
		or wall_run.detach_outward_speed_mps <= 0.0
		or wall_run.detach_height_m <= 0.0
	):
		return false

	var grind := checked.grind
	if (
		grind.attach_snap_m <= 0.0
		or grind.speed_mps <= 0.0
		or grind.acceleration_mps2 < 0.0
		or grind.hop_lateral_distance_m <= 0.0
		or grind.hop_height_m <= 0.0
		or grind.exit_forward_speed_mps <= 0.0
	):
		return false

	var swing := checked.swing
	if (
		swing.catch_radius_m <= 0.0
		or swing.transfer_catch_radius_m < swing.catch_radius_m
		or swing.rope_length_m <= 0.0
		or swing.minimum_catch_speed_mps <= 0.0
		or swing.transfer_minimum_catch_speed_mps <= 0.0
		or swing.transfer_minimum_catch_speed_mps
		> swing.minimum_catch_speed_mps
		or swing.gravity_scale <= 0.0
		or swing.maximum_speed_mps <= 0.0
		or swing.minimum_catch_speed_mps > swing.maximum_speed_mps
		or swing.release_boost_mps <= 0.0
		or swing.damping_per_s < 0.0
	):
		return false

	var phase := checked.phase
	if (
		phase.retoggle_cooldown_s < 0.0
		or phase.ghost_opacity <= 0.0
		or phase.ghost_opacity > 1.0
		or phase.ghost_outline_width_m <= 0.0
		or phase.missed_crate_outline_opacity <= 0.0
		or phase.missed_crate_outline_opacity > 1.0
		or phase.missed_crate_outline_edge_width_uv <= 0.0
		or phase.missed_crate_outline_edge_width_uv >= 0.5
		or phase.missed_crate_outline_padding_m <= 0.0
		or phase.missed_crate_outline_padding_m
		> move.collision_radius_m
		or phase.missed_crate_outline_color.a <= 0.0
		or phase.missed_crate_outline_color.a > 1.0
	):
		return false

	var economy := checked.economy
	# R1: a checkpoint respawn offset is only ever meant to nudge the
	# spawn point to just beside its checkpoint, so it must stay modest on
	# every axis, not merely clear the kill floor on .y. move.respawn_
	# floor_y_m is the only tuned "how far is definitely too far" distance
	# scale already in the catalog, so its magnitude bounds .x/.z (and the
	# top of .y) instead of introducing an unrelated new magic number.
	var respawn_offset_limit_m := absf(move.respawn_floor_y_m)
	if (
		economy.wumpa_per_standard_crate <= 0
		or economy.wumpa_per_pickup <= 0
		or economy.wumpa_collect_radius_m <= 0.0
		or economy.wumpa_mask_threshold <= 0
		or economy.mask_stack_maximum <= 0
		or economy.invincibility_duration_s <= 0.0
		or economy.mask_hit_invulnerability_s <= 0.0
		or economy.tnt_fuse_s <= 0.0
		or economy.tnt_blast_radius_m <= 0.0
		or economy.bounce_crate_max_bounces <= 0
		or economy.bounce_crate_wumpa_per_bounce <= 0
		or economy.bounce_launch_height_m <= 0.0
		# A respawn offset at or below the tuned fall floor drops the
		# player back through the floor on every checkpoint respawn — an
		# unrecoverable death loop. This also catches the field's own
		# sentinel default (Vector3(-999999,...)), which is finite and so
		# passes _resource_values_are_finite unnoticed.
		or economy.checkpoint_respawn_offset.y <= move.respawn_floor_y_m
		# R1: .x/.z (and the top of .y) were completely unbounded and
		# reachable from the on-device drawer's SpinBox (range
		# +-1,000,000), reproducing P0-2's death-loop shape sideways or
		# upward instead of only downward.
		or absf(economy.checkpoint_respawn_offset.x) > respawn_offset_limit_m
		or absf(economy.checkpoint_respawn_offset.y) > respawn_offset_limit_m
		or absf(economy.checkpoint_respawn_offset.z) > respawn_offset_limit_m
		or economy.checkpoint_spacing_limit_s <= 0.0
		or economy.mercy_mask_death_threshold <= 0
		or economy.mercy_skip_death_threshold
		<= economy.mercy_mask_death_threshold
		or economy.mercy_banner_duration_s <= 0.0
		or economy.time_crate_small_s <= 0.0
		or economy.time_crate_medium_s
		<= economy.time_crate_small_s
		or economy.time_crate_large_s
		<= economy.time_crate_medium_s
	):
		return false

	var crab := checked.enemy_crab
	if (
		crab.patrol_speed_mps <= 0.0
		or crab.patrol_span_m <= 0.0
		or crab.turn_pause_s < 0.0
		or not is_zero_approx(crab.telegraph_s)
		or not is_zero_approx(crab.attack_active_s)
		or not is_zero_approx(crab.attack_cooldown_s)
		or not is_zero_approx(crab.trigger_range_m)
		or not is_zero_approx(crab.trigger_lateral_m)
	):
		return false

	var skink := checked.enemy_skink
	if (
		skink.patrol_speed_mps <= 0.0
		or skink.patrol_span_m <= 0.0
		or not is_zero_approx(skink.turn_pause_s)
		or skink.telegraph_s <= 0.0
		or skink.attack_active_s <= 0.0
		or skink.attack_cooldown_s <= 0.0
		or skink.trigger_range_m <= 0.0
		or skink.trigger_lateral_m <= 0.0
	):
		return false

	var plant := checked.enemy_plant
	if (
		not is_zero_approx(plant.patrol_speed_mps)
		or not is_zero_approx(plant.patrol_span_m)
		or not is_zero_approx(plant.turn_pause_s)
		or plant.telegraph_s <= 0.0
		or plant.attack_active_s <= 0.0
		or plant.attack_cooldown_s <= 0.0
		or plant.trigger_range_m <= 0.0
		or not is_zero_approx(plant.trigger_lateral_m)
	):
		return false

	var chase := checked.chase
	if (
		chase.boulder_speed_mps <= 0.0
		or chase.boulder_kill_distance_m <= 0.0
		or chase.boulder_start_gap_m
		<= chase.boulder_kill_distance_m
		or chase.opening_auto_run_duration_s < 0.0
		# With no rubber-band mechanic, a boulder at or above the player's
		# own run speed closes the gap regardless of skill and the level
		# cannot be finished -- bound it against the field that already
		# governs it (the same N1 lesson as the shockwave-vs-jump guard
		# above).
		or chase.boulder_speed_mps >= move.run_speed_mps
	):
		return false

	var hog := checked.hog
	if (
		hog.ride_speed_mps <= 0.0
		or hog.steer_lateral_speed_mps <= 0.0
		or hog.hog_jump_height_m <= 0.0
	):
		return false

	var boss_papu := checked.boss_papu
	if (
		boss_papu.phase_count <= 0
		or boss_papu.arena_strikes_per_phase <= 0
		or boss_papu.slam_period_s <= 0.0
		or boss_papu.shockwave_speed_mps <= 0.0
		or boss_papu.shockwave_height_m <= 0.0
		# §4.14 calls the shockwave jumpable, and the on-device drawer can
		# push any float. A shockwave at or above the full jump arc is an
		# unwinnable fight with no way back out, so bound it against the
		# field that already governs it (the N1 lesson).
		or boss_papu.shockwave_height_m >= move.jump_full_height_m
		or boss_papu.debris_telegraph_s <= 0.0
	):
		return false

	var kart := checked.kart
	# Task 1 (CTR racing mode): every field is strictly positive; the three
	# ratio-typed fields (steer authority falloff, boost-window shrink,
	# spin-out speed retention) are additionally capped to the (0.0, 1.0]
	# unit interval per the design brief.
	if (
		kart.top_speed_mps <= 0.0
		or kart.reverse_speed_mps <= 0.0
		or kart.accel_mps2 <= 0.0
		or kart.brake_mps2 <= 0.0
		or kart.coast_drag_mps2 <= 0.0
		or kart.steer_rate_degrees_per_s <= 0.0
		or kart.steer_speed_falloff <= 0.0
		or kart.steer_speed_falloff > 1.0
		or kart.hop_height_m <= 0.0
		or kart.gravity_mps2 <= 0.0
		or kart.slide_min_steer <= 0.0
		or kart.slide_yaw_bonus_degrees_per_s <= 0.0
		or kart.slide_counter_yaw_degrees_per_s <= 0.0
		or kart.slide_min_duration_s <= 0.0
		or kart.boost_window_open_s <= 0.0
		or kart.boost_window_close_s <= 0.0
		# Task 2 (CTR racing mode): DriftStateMachine reads each boost
		# stage's tap window as [open_s, close_s] -- a close at or below
		# open collapses or inverts that range, so every tap would be
		# either mistimed or ignored and the slide-boost could never fire.
		or kart.boost_window_close_s <= kart.boost_window_open_s
		or kart.boost_window_shrink_factor <= 0.0
		or kart.boost_window_shrink_factor > 1.0
		or kart.boost_speed_bonus_mps <= 0.0
		or kart.boost_duration_s <= 0.0
		# L2 (final fix wave): boost_stack_max is a float field with
		# INTEGER semantics -- DriftStateMachine reads it via
		# roundi(_tuning.boost_stack_max) to cap boost stages. A value
		# below 1.0 rounds to a dead 0-stage boost (boost_stack_max=0.4
		# passed the old <= 0.0 check but silently killed boost for the
		# whole session).
		or kart.boost_stack_max < 1.0
		or kart.spin_out_duration_s <= 0.0
		or kart.spin_out_speed_keep_ratio <= 0.0
		or kart.spin_out_speed_keep_ratio > 1.0
		or kart.invulnerable_after_hit_s <= 0.0
		# CTR R6 Task 3: the same alpha-only Color bound fx.spark_color_
		# stage1/2/3 already use below (RGB is unbounded/HDR-capable, only
		# alpha has real meaning here -- a zero-alpha tint would make
		# apply_body_tint()'s material_override invisible).
		or kart.kart_tint_player.a <= 0.0
		or kart.kart_tint_player.a > 1.0
		or kart.kart_tint_slot_1.a <= 0.0
		or kart.kart_tint_slot_1.a > 1.0
		or kart.kart_tint_slot_2.a <= 0.0
		or kart.kart_tint_slot_2.a > 1.0
		or kart.kart_tint_slot_3.a <= 0.0
		or kart.kart_tint_slot_3.a > 1.0
		or kart.kart_tint_slot_4.a <= 0.0
		or kart.kart_tint_slot_4.a > 1.0
		or kart.kart_tint_slot_5.a <= 0.0
		or kart.kart_tint_slot_5.a > 1.0
	):
		return false

	var race := checked.race
	if (
		# L2 (final fix wave): lap_count is a float field with INTEGER
		# semantics -- race_session.gd reads it via
		# int(_race_tuning.lap_count) for both the HUD's lap display and
		# LapValidator.configure(). A value below 1.0 truncates to a dead
		# LAP 0/0 (lap_count=0.5 passed the old <= 0.0 check).
		race.lap_count < 1.0
		or race.countdown_step_s <= 0.0
		or race.start_boost_window_s <= 0.0
		or race.start_bog_penalty_s <= 0.0
		or race.wrong_way_grace_s <= 0.0
		or race.checkpoint_tolerance_m <= 0.0
		or race.respawn_drop_height_m <= 0.0
		or race.camera_trail_m <= 0.0
		or race.camera_height_m <= 0.0
		or race.camera_fov_base <= 0.0
		or race.camera_fov_speed_gain <= 0.0
		or race.camera_yaw_lag_s <= 0.0
		or race.camera_drift_yaw_degrees <= 0.0
		# Task 5 (CTR kart chase camera): a zero or negative look height
		# would aim the camera at or below the kart's own origin instead
		# of a point above it.
		or race.camera_look_height_m <= 0.0
		# Task 1 (CTR R7, pads): all three are strictly positive -- a
		# zero/negative pad_boost_s or jump_pad_velocity_scale would make
		# a pad actively HARMFUL (a boost pad that slows a kart down, a
		# jump pad that yanks it into the floor), and a zero/negative
		# pad_refire_cooldown_s would let a single pass through a pad
		# refire every physics tick it stays overlapped.
		or race.pad_boost_s <= 0.0
		or race.pad_refire_cooldown_s <= 0.0
		or race.jump_pad_velocity_scale <= 0.0
	):
		return false

	var ai := checked.ai
	# Task 1 (CTR R3, AI opponents): every field is strictly positive except
	# the three ratio-typed fields, which are additionally bounded per the
	# design brief -- corner_speed_floor_ratio clamps the low end of a
	# multiplier whose high end is fixed at 1.0, so it is tightened to
	# (0.0, 1.0] rather than left merely positive; the two rubber-band caps
	# are bounded to (0.0, 1.0) exclusive; and boost_tap_enabled is a
	# 0/1 flag stored as a float, not merely positive.
	if (
		ai.opponent_count <= 0.0
		or ai.lateral_slot_spacing_m <= 0.0
		or ai.lookahead_min_m <= 0.0
		or ai.lookahead_speed_gain_s <= 0.0
		or ai.steer_gain <= 0.0
		or ai.corner_speed_curvature_gain <= 0.0
		or ai.corner_speed_floor_ratio <= 0.0
		or ai.corner_speed_floor_ratio > 1.0
		or ai.brake_margin_ratio <= 0.0
		or ai.slide_trigger_curvature <= 0.0
		or ai.slide_exit_curvature <= 0.0
		or not (
			is_equal_approx(ai.boost_tap_enabled, 0.0)
			or is_equal_approx(ai.boost_tap_enabled, 1.0)
		)
		or ai.rubber_band_full_gap_m <= 0.0
		or ai.rubber_band_boost_max_ratio <= 0.0
		or ai.rubber_band_boost_max_ratio >= 1.0
		or ai.rubber_band_drag_max_ratio <= 0.0
		or ai.rubber_band_drag_max_ratio >= 1.0
		or ai.respawn_stuck_speed_mps <= 0.0
		or ai.respawn_stuck_after_s <= 0.0
		or ai.respawn_drop_gap_m <= 0.0
		# Task 4 (CTR R6: circuit polish -- smarter AI). apex_offset_max_m/
		# apex_entry_lookahead_m are plain magnitude/distance fields (same
		# "strictly positive, no upper bound" shape as steer_gain/lateral_
		# slot_spacing_m above); personality_aggression_step the same. steer_
		# damping/personality_skill_jitter are ratio-typed exactly like the
		# rubber-band caps above -- bounded (0.0, 1.0) exclusive, see ai_
		# tuning.gd's own doc comment on each for why both ends are rejected.
		or ai.apex_offset_max_m <= 0.0
		or ai.apex_entry_lookahead_m <= 0.0
		or ai.steer_damping <= 0.0
		or ai.steer_damping >= 1.0
		or ai.personality_aggression_step <= 0.0
		or ai.personality_skill_jitter <= 0.0
		or ai.personality_skill_jitter >= 1.0
		# CTR R7 Task 2b (OPERATOR PRIORITY): recovery_trigger_s/recovery_
		# max_attempts are plain duration/count fields, same "strictly
		# positive, no upper bound" shape as respawn_stuck_after_s/
		# respawn_drop_gap_m above. recovery_heading_error_degrees is
		# tightened to (0.0, 180.0] -- see ai_tuning.gd's own doc comment:
		# Vector3.angle_to's own output range is [0, 180] degrees, so a
		# value above 180 could never be exceeded (silently disabling
		# recovery, not loosening it).
		or ai.recovery_heading_error_degrees <= 0.0
		or ai.recovery_heading_error_degrees > 180.0
		or ai.recovery_trigger_s <= 0.0
		or ai.recovery_max_attempts <= 0.0
	):
		return false

	var items := checked.items
	# R4 Task 2 (CTR item loop): items is a brand-new whole section, the
	# same shape as kart/race/ai above -- every field is a duration, speed,
	# or radius with no ratio-typed exception, so every field is simply
	# strictly positive per the design brief.
	if (
		items.roulette_duration_s <= 0.0
		or items.roulette_tick_s <= 0.0
		or items.box_respawn_s <= 0.0
		or items.box_pickup_radius_m <= 0.0
		or items.missile_speed_mps <= 0.0
		or items.missile_turn_rate_degrees_per_s <= 0.0
		or items.missile_lifetime_s <= 0.0
		or items.missile_arm_delay_s <= 0.0
		or items.missile_hit_radius_m <= 0.0
		or items.shield_duration_s <= 0.0
		or items.turbo_boost_s <= 0.0
		or items.beaker_arm_delay_s <= 0.0
		or items.beaker_lifetime_s <= 0.0
		or items.beaker_hit_radius_m <= 0.0
		or items.ai_item_use_cooldown_s <= 0.0
		or items.ai_missile_max_target_gap_m <= 0.0
		# CTR R6 Task 5: bomb/TNT/triple-turbo -- same "every field simply
		# strictly positive" shape as every other items.* field above (see
		# item_tuning.gd's own doc for why bomb/TNT reuse beaker_* for their
		# lifetime/arm/hit-radius fields instead of duplicating them here).
		or items.bomb_speed_mps <= 0.0
		or items.bomb_blast_radius_m <= 0.0
		or items.bomb_arm_delay_s <= 0.0
		or items.tnt_fuse_s <= 0.0
		or items.tnt_shake_hops <= 0.0
		or items.triple_turbo_charges <= 0.0
	):
		return false

	# CTR R6 Task 5: weighted roulette. Every individual weight must be
	# >= 0.0 (a negative weight has no meaning in a cumulative table), and
	# the brief's own "at least one positive at any [position] ratio" is
	# satisfied by checking only the two ENDPOINTS (ratio 0.0 = pure front,
	# ratio 1.0 = pure back) rather than an infinite sweep: ItemSlot's own
	# blend is `(1.0 - ratio) * front + ratio * back` per item, so the total
	# weight at any ratio is `(1.0 - ratio) * sum(front) + ratio * sum(back)`
	# -- a convex combination of the two endpoint sums. If BOTH endpoint sums
	# are > 0.0, every ratio strictly between them multiplies at least one of
	# the two positive sums by a strictly-positive coefficient ((1.0 - ratio)
	# or ratio, and at least one of those two is always > 0.0 for any ratio
	# in [0.0, 1.0]), so the blended total is provably > 0.0 everywhere in
	# the interval, not just at the two checked endpoints. Iterates ItemSlot.
	# ITEM_NAMES + Object.get() rather than a hand-typed field list, so this
	# check and ItemSlot's own weighted-pick table can never drift apart on
	# which fields exist -- see item_slot.gd's own WEIGHTED MAPPING doc for
	# the identical lookup shape.
	var weight_sum_front := 0.0
	var weight_sum_back := 0.0
	for item_name: StringName in ItemSlot.ITEM_NAMES:
		var front_weight: float = float(items.get("weight_front_" + String(item_name)))
		var back_weight: float = float(items.get("weight_back_" + String(item_name)))
		if front_weight < 0.0 or back_weight < 0.0:
			return false
		weight_sum_front += front_weight
		weight_sum_back += back_weight
	if weight_sum_front <= 0.0 or weight_sum_back <= 0.0:
		return false

	var fx := checked.fx
	# Task 1 (CTR R6, circuit polish): fx is a brand-new whole section, the
	# same shape as kart/race/ai/items above. Every duration/speed/degrees-
	# per-second field is simply strictly positive. Particle amount fields
	# additionally carry a MOBILE PARTICLE BUDGET ceiling of 64 (documented
	# bound, not just "must be positive") -- the worst case for the drift
	# spark stream is the top authored boost stage (kart.boost_stack_max,
	# already validated above), so spark_amount_stage0 + spark_amount_per_
	# stage * kart.boost_stack_max is the number that actually reaches
	# GPUParticles3D.amount at runtime (see kart_fx.gd), not just the raw
	# stage-0 field in isolation. Stage color alphas are bounded to (0.0,
	# 1.0] the same way phase.missed_crate_outline_color.a already is above
	# -- an alpha of 0 would make a "fired" boost stage's sparks invisible.
	const FX_PARTICLE_AMOUNT_CEILING := 64.0
	if (
		fx.spark_amount_stage0 <= 0.0
		or fx.spark_amount_per_stage <= 0.0
		or fx.spark_lifetime_s <= 0.0
		or fx.spark_velocity_mps <= 0.0
		or fx.boost_flame_lifetime_s <= 0.0
		or fx.boost_flame_amount <= 0.0
		or fx.boost_flame_amount > FX_PARTICLE_AMOUNT_CEILING
		or (
			fx.spark_amount_stage0
			+ fx.spark_amount_per_stage * kart.boost_stack_max
		) > FX_PARTICLE_AMOUNT_CEILING
		or fx.item_box_spin_degrees_per_s <= 0.0
		or fx.item_box_bob_amplitude_m <= 0.0
		or fx.item_box_bob_hz <= 0.0
		or fx.spark_color_stage1.a <= 0.0
		or fx.spark_color_stage1.a > 1.0
		or fx.spark_color_stage2.a <= 0.0
		or fx.spark_color_stage2.a > 1.0
		or fx.spark_color_stage3.a <= 0.0
		or fx.spark_color_stage3.a > 1.0
	):
		return false

	var depth := checked.depth
	return (
		depth.shadow_diameter_m > 0.0
		and depth.shadow_ray_length_m > 0.0
		and depth.prediction_step_s > 0.0
		and depth.prediction_horizon_s > 0.0
		and depth.collision_probe_radius_m > 0.0
		and depth.collision_probe_stride > 0
		and depth.ring_outer_radius_m > depth.ring_inner_radius_m
		and depth.ring_inner_radius_m > 0.0
		and depth.landing_assist_probe_depth_m > 0.0
		and depth.landing_assist_last_fall_ratio >= 0.0
		and depth.landing_assist_last_fall_ratio <= 1.0
	)


func reset_to_authored() -> Error:
	if _base_catalog_path.is_empty() or _override_path.is_empty():
		return ERR_UNCONFIGURED
	if FileAccess.file_exists(_override_path):
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_override_path)
		)
		if remove_error != OK:
			return remove_error
	return load_from_paths(_base_catalog_path, _override_path)


func _record_authored_paths(authored: GameplayTuning, base_catalog_path: String) -> void:
	_loaded_resource_paths.append(base_catalog_path)
	for section_name: StringName in SECTION_NAMES:
		_append_resource_path(authored.get(section_name) as Resource)


func _append_resource_path(resource: Resource) -> void:
	if resource != null and not resource.resource_path.is_empty():
		_loaded_resource_paths.append(resource.resource_path)


func _resource_values_are_finite(resource: Resource) -> bool:
	for property_name: StringName in _exported_property_names(resource):
		var value: Variant = resource.get(property_name)
		if typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
			return false
		if typeof(value) == TYPE_VECTOR3 and not (value as Vector3).is_finite():
			return false
		if typeof(value) == TYPE_COLOR:
			var color := value as Color
			if (
				not is_finite(color.r)
				or not is_finite(color.g)
				or not is_finite(color.b)
				or not is_finite(color.a)
			):
				return false
	return true


func _clone_catalog(source: GameplayTuning) -> GameplayTuning:
	var clone := GameplayTuning.new()
	for section_name: StringName in SECTION_NAMES:
		var source_section := source.get(section_name) as Resource
		if source_section != null:
			clone.set(section_name, source_section.duplicate(true))
	return clone


func _copy_catalog_values(source: GameplayTuning, target: GameplayTuning) -> void:
	for section_name: StringName in SECTION_NAMES:
		_copy_exported_values(
			source.get(section_name) as Resource,
			target.get(section_name) as Resource
		)


func _backfill_missing_sections(
	target: GameplayTuning,
	authored: GameplayTuning
) -> void:
	for section_name: StringName in SECTION_NAMES:
		var authored_section := authored.get(section_name) as Resource
		if authored_section == null:
			continue
		var target_section := target.get(section_name) as Resource
		if target_section == null:
			target.set(section_name, authored_section.duplicate(true))
			continue
		_backfill_legacy_field_groups(
			section_name,
			target_section,
			authored_section
		)


func _backfill_legacy_field_groups(
	section_name: StringName,
	target: Resource,
	authored: Resource
) -> void:
	if not LEGACY_FIELD_GROUPS_BY_SECTION.has(section_name):
		return
	var target_script := target.get_script() as Script
	if target_script == null:
		return
	var defaults := target_script.new() as Resource
	if defaults == null:
		return
	var target_properties := _exported_property_names(target)
	for field_group: Array in LEGACY_FIELD_GROUPS_BY_SECTION[section_name]:
		var group_is_legacy := true
		for property_name: StringName in field_group:
			if (
				not target_properties.has(property_name)
				or target.get(property_name) != defaults.get(property_name)
			):
				group_is_legacy = false
				break
		if not group_is_legacy:
			continue
		for property_name: StringName in field_group:
			var authored_value: Variant = authored.get(property_name)
			if authored_value != defaults.get(property_name):
				target.set(property_name, authored_value)


func _copy_exported_values(source: Resource, target: Resource) -> void:
	if source == null or target == null:
		return
	for property_name in _exported_property_names(source):
		target.set(property_name, source.get(property_name))


func _append_fingerprint_lines(
	lines: PackedStringArray,
	section_name: String,
	resource: Resource
) -> void:
	if resource == null:
		lines.append(section_name + "=<null>")
		return
	for property_name in _exported_property_names(resource):
		lines.append(
			section_name
			+ "."
			+ property_name
			+ "="
			+ var_to_str(resource.get(property_name))
		)


func _exported_property_names(resource: Resource) -> PackedStringArray:
	var names := PackedStringArray()
	for property_info in resource.get_property_list():
		var usage: int = property_info["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property_info["name"])
	return names
