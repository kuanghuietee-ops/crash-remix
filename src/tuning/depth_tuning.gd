class_name DepthTuning
extends Resource

@export_category("Blob Shadow")
@export var shadow_diameter_m: float
@export var shadow_opacity: float
@export var shadow_ray_length_m: float
@export var shadow_ray_origin_offset_m: float
@export var shadow_surface_offset_m: float

@export_category("Landing Ring")
@export var prediction_step_s: float
@export var prediction_horizon_s: float
@export var collision_probe_radius_m: float
@export var collision_probe_stride: int
@export var ring_outer_radius_m: float
@export var ring_inner_radius_m: float
@export var ring_surface_offset_m: float
@export var landable_color: Color
@export var hazard_color: Color

@export_category("Optional Landing Assist")
@export var landing_assist_last_fall_ratio: float
@export var landing_assist_edge_distance_m: float
@export var landing_assist_probe_depth_m: float
@export var landing_assist_touch_strength: float
@export var landing_assist_gamepad_strength: float
