class_name GrindTuning
extends Resource

@export_category("Attach")
@export var attach_snap_m: float

@export_category("Motion")
@export var speed_mps: float
@export var acceleration_mps2: float
@export var bank_degrees: float

@export_category("Hop")
@export var hop_lateral_distance_m: float
@export var hop_height_m: float

@export_category("Exit")
@export var exit_forward_speed_mps: float
