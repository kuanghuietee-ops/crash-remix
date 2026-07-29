class_name CameraTuning
extends Resource

@export_category("Rail")
@export var field_of_view_degrees: float
@export var rail_bake_interval_m: float
@export var rail_handle_length_factor: float
@export var rail_follow_speed_mps: float
@export var region_blend_s: float
@export var look_ahead_m: float
@export var corridor_tangent_baseline_m: float
@export var look_at_height_m: float
@export var player_screen_left_bias_m: float
@export var default_offset: Vector3
@export var close_offset: Vector3
@export var side_on_offset: Vector3
@export var grind_offset: Vector3
@export var wall_run_offset: Vector3
@export var swing_offset: Vector3
@export var toward_camera_offset: Vector3
@export var wall_run_bank_degrees: float

@export_category("Readability")
@export var minimum_jump_depression_degrees: float
