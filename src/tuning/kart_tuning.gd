class_name KartTuning
extends Resource

@export_category("Motion")
@export var top_speed_mps: float
@export var reverse_speed_mps: float
@export var accel_mps2: float
@export var brake_mps2: float
@export var coast_drag_mps2: float
@export var steer_rate_degrees_per_s: float
## Ratio in (0.0, 1.0]: how much steer authority remains at top speed.
@export var steer_speed_falloff: float
@export var hop_height_m: float
@export var gravity_mps2: float

@export_category("Slide")
@export var slide_min_steer: float
@export var slide_yaw_bonus_degrees_per_s: float
@export var slide_counter_yaw_degrees_per_s: float
@export var slide_min_duration_s: float

@export_category("Boost")
@export var boost_window_open_s: float
@export var boost_window_close_s: float
## Ratio in (0.0, 1.0]: shrinks each stacked boost window vs. the last.
@export var boost_window_shrink_factor: float
@export var boost_speed_bonus_mps: float
@export var boost_duration_s: float
@export var boost_stack_max: float

@export_category("Hazard")
@export var spin_out_duration_s: float
## Ratio in (0.0, 1.0]: fraction of speed kept through a spin-out.
@export var spin_out_speed_keep_ratio: float
@export var invulnerable_after_hit_s: float
