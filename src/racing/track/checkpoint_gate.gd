class_name CheckpointGate
extends Area3D

## Ordered lap/checkpoint trigger (Task 6). Carries its position in the gate
## sequence (see lap_validator.gd for the ordering rules) and nothing else --
## it deliberately emits no signal of its own. Task 7's race session
## connects body_entered itself and forwards the crossing index to a
## LapValidator, the same way camera_region.gd stays a passive data carrier
## and lets camera_rail_controller.gd own the wiring.
##
## MONITORING DEFAULTS. A checkpoint only ever needs to detect the kart
## passing through it -- it never needs to be detected BY another Area3D --
## so monitoring is forced on and monitorable forced off here instead of
## leaving every authored gate to get that right (or silently wrong) on its
## own in the scene file.

@export var gate_index: int


func _ready() -> void:
	monitoring = true
	monitorable = false
