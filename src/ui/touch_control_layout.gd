class_name TouchControlLayout
extends RefCounted


static func calculate(
	safe_rect: Rect2,
	dpi: float,
	input_tuning: InputTuning,
	phase_available: bool
) -> Dictionary:
	var resolved_dpi := dpi if dpi > 0.0 else input_tuning.fallback_dpi
	var pixels_per_mm := (
		resolved_dpi / input_tuning.millimeters_per_inch * input_tuning.control_scale
	)
	var safe_end := safe_rect.end
	var actions_on_left := input_tuning.left_handed_layout
	var jump_edge_x := input_tuning.jump_button_edge_x_mm * pixels_per_mm
	var jump_edge_y := input_tuning.jump_button_edge_y_mm * pixels_per_mm
	var spin_edge_x := input_tuning.spin_button_edge_x_mm * pixels_per_mm
	var jump_x := safe_rect.position.x + jump_edge_x if actions_on_left else safe_end.x - jump_edge_x
	var spin_x := safe_rect.position.x + spin_edge_x if actions_on_left else safe_end.x - spin_edge_x
	var button_y := safe_end.y - jump_edge_y
	var jump_center := Vector2(jump_x, button_y)
	var spin_center := Vector2(spin_x, button_y)
	var down_center := jump_center + Vector2.UP * input_tuning.down_button_above_jump_mm * pixels_per_mm
	var phase_horizontal := Vector2.RIGHT if actions_on_left else Vector2.LEFT
	var phase_direction := (phase_horizontal + Vector2.UP).normalized()
	var phase_center := (
		jump_center
		+ phase_direction
		* input_tuning.phase_button_arc_offset_mm
		* pixels_per_mm
	)

	# R6: stick_region_top_exclusion_ratio/jump_catchall_top_ratio are HEIGHT
	# RATIOS -- on a short enough safe rect they resolve to fewer pixels
	# from the top than hud.tscn's pixel-anchored top panels occupy, so the
	# two touch regions and the HUD would silently overlap. hud_reserved_top_px
	# is the single authoritative floor (see input_tuning.gd) both regions'
	# tops are clamped to, independent of safe rect height.
	var hud_floor_y := safe_rect.position.y + input_tuning.hud_reserved_top_px
	var stick_width := safe_rect.size.x * input_tuning.stick_region_width_ratio
	var stick_top := maxf(
		safe_rect.position.y + safe_rect.size.y * input_tuning.stick_region_top_exclusion_ratio,
		hud_floor_y
	)
	var stick_x := safe_end.x - stick_width if actions_on_left else safe_rect.position.x
	var stick_region := Rect2(
		Vector2(stick_x, stick_top),
		Vector2(stick_width, safe_end.y - stick_top)
	)
	var catchall_width := (
		safe_rect.size.x * input_tuning.jump_catchall_width_ratio
	)
	var catchall_x := safe_rect.position.x if actions_on_left else safe_end.x - catchall_width
	var catchall_top := maxf(
		safe_rect.position.y + safe_rect.size.y * input_tuning.jump_catchall_top_ratio,
		hud_floor_y
	)

	var layout := {
		"safe_rect": safe_rect,
		"pixels_per_mm": pixels_per_mm,
		"stick_region": stick_region,
		"stick_ring_radius": input_tuning.stick_ring_diameter_mm * pixels_per_mm * 0.5,
		"stick_knob_radius": input_tuning.stick_knob_diameter_mm * pixels_per_mm * 0.5,
		"jump_center": jump_center,
		"jump_radius": input_tuning.jump_button_diameter_mm * pixels_per_mm * 0.5,
		"spin_center": spin_center,
		"spin_radius": input_tuning.spin_button_diameter_mm * pixels_per_mm * 0.5,
		"down_center": down_center,
		"down_radius": input_tuning.down_button_diameter_mm * pixels_per_mm * 0.5,
		"button_hit_radius_scale": input_tuning.button_hit_radius_scale,
		"jump_catchall_region": Rect2(
			Vector2(catchall_x, catchall_top),
			Vector2(catchall_width, safe_end.y - catchall_top)
		),
	}
	if phase_available and input_tuning.phase_button_unlocked:
		layout["phase_center"] = phase_center
		layout["phase_radius"] = (
			input_tuning.phase_button_diameter_mm * pixels_per_mm * 0.5
		)
	return layout
