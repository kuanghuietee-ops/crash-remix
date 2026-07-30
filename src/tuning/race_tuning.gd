class_name RaceTuning
extends Resource

@export_category("Race")
@export var lap_count: float
@export var countdown_step_s: float
@export var start_boost_window_s: float
@export var start_bog_penalty_s: float
@export var wrong_way_grace_s: float
@export var checkpoint_tolerance_m: float
@export var respawn_drop_height_m: float

@export_category("Camera")
@export var camera_trail_m: float
@export var camera_height_m: float
@export var camera_fov_base: float
@export var camera_fov_speed_gain: float
@export var camera_yaw_lag_s: float
@export var camera_drift_yaw_degrees: float
# Task 5 (CTR kart chase camera): KartCamera's look-at target is the kart
# position raised by this much, so the camera aims a little above the
# kart's origin (roughly cockpit/roof height) instead of dead-level into
# its base -- kept as its own field rather than reusing camera_height_m (a
# fraction of the camera's OWN mount height above ground has no reason to
# equal a good look-at height above the kart) so each stays independently
# tunable.
@export var camera_look_height_m: float
