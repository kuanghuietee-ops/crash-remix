class_name WallRunTuning
extends Resource

@export_category("Attach")
@export var attach_cone_degrees: float
@export var minimum_entry_speed_mps: float
@export var surface_stick_distance_m: float

@export_category("Motion")
@export var run_speed_mps: float
@export var maximum_duration_s: float
@export var gravity_multiplier: float

@export_category("Detach")
@export var detach_outward_speed_mps: float
@export var detach_height_m: float
