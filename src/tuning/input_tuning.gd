class_name InputTuning
extends Resource

@export_category("Forgiveness")
@export var jump_buffer_s: float
@export var coyote_time_s: float
@export var action_buffer_s: float
@export var minimum_hop_release_s: float
@export var full_jump_hold_s: float
@export var edge_landing_nudge_m: float
@export var bounce_timing_s: float

@export_category("Latency")
@export var touch_response_target_s: float
@export var touch_response_hard_fail_s: float

@export_category("Floating Stick")
@export var millimeters_per_inch: float
@export var fallback_dpi: float
@export var stick_region_width_ratio: float
@export var stick_region_top_exclusion_ratio: float
@export var stick_ring_diameter_mm: float
@export var stick_knob_diameter_mm: float
@export var stick_opacity: float
@export var stick_dead_zone_mm: float
@export var stick_full_run_mm: float
@export var corridor_magnet_cone_degrees: float
@export var corridor_magnet_strength: float
@export var gamepad_magnet_disable_magnitude: float
@export var gamepad_dead_zone: float

@export_category("Buttons")
@export var jump_button_diameter_mm: float
@export var spin_button_diameter_mm: float
@export var down_button_diameter_mm: float
@export var jump_button_edge_x_mm: float
@export var jump_button_edge_y_mm: float
@export var spin_button_edge_x_mm: float
@export var down_button_above_jump_mm: float
@export var button_hit_radius_scale: float
@export var jump_catchall_width_ratio: float
@export var jump_catchall_top_ratio: float
@export var button_opacity: float
@export var button_label_height_mm: float
@export var control_outline_width_mm: float
@export var control_color: Color
@export var control_label_color: Color
@export var haptic_duration_ms: int
@export var haptics_enabled: bool
@export var left_handed_layout: bool
@export var control_scale: float

@export_category("Phase Button")
@export var phase_button_diameter_mm: float
@export var phase_button_arc_offset_mm: float
@export var phase_button_unlocked: bool

@export_category("Platform Layout")
@export var layout_metrics_poll_interval_s: float
