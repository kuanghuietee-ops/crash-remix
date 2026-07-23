class_name MoveTuning
extends Resource

@export_category("Body")
@export var player_height_m: float
@export var collision_radius_m: float
@export var floor_snap_length_m: float
@export var floor_max_angle_degrees: float
@export var crouch_hurtbox_height_ratio: float
@export var hurtbox_visual_ratio: float
@export var attack_visual_ratio: float

@export_category("Run")
@export var run_speed_mps: float
@export var run_time_to_speed_s: float
@export var stop_time_s: float
@export var crawl_speed_mps: float

@export_category("Jump")
@export var gravity_mps2: float
@export var jump_full_height_m: float
@export var jump_tap_height_m: float
@export var double_jump_height_m: float
@export var double_jump_tap_height_m: float
@export var high_jump_height_m: float
@export var fall_gravity_multiplier: float
@export var apex_gravity_multiplier: float
@export var apex_velocity_threshold_mps: float
@export var maximum_fall_speed_mps: float

@export_category("Spin")
@export var spin_radius_m: float
@export var spin_active_s: float
@export var air_spin_gravity_multiplier: float

@export_category("Slide")
@export var slide_distance_m: float
@export var slide_duration_s: float
@export var slide_minimum_speed_mps: float
@export var slide_jump_distance_m: float
@export var slide_jump_height_m: float

@export_category("Body Slam")
@export var body_slam_speed_mps: float
@export var body_slam_shockwave_radius_m: float
@export var body_slam_recovery_s: float

@export_category("Recovery")
@export var respawn_delay_s: float
@export var respawn_floor_y_m: float
