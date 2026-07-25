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
]
# ResourceSaver omits default-valued fields, so migrate version-defining
# cohorts atomically instead of treating every zero as a missing value.
const LEGACY_FIELD_GROUPS_BY_SECTION := {
	&"input": [
		[
			&"phase_button_diameter_mm",
			&"phase_button_arc_offset_mm",
			&"phase_button_unlocked",
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
	):
		return false

	var camera := checked.camera
	if (
		camera.field_of_view_degrees <= 0.0
		or camera.rail_bake_interval_m <= 0.0
		or camera.rail_follow_speed_mps < 0.0
		or camera.region_blend_s < 0.0
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
	):
		return false

	var economy := checked.economy
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
