class_name EnemyTuning
extends Resource

@export_category("Patrol")
@export var patrol_speed_mps: float
@export var patrol_span_m: float
@export var turn_pause_s: float

@export_category("Attack")
@export var telegraph_s: float
@export var attack_active_s: float
@export var attack_cooldown_s: float
@export var trigger_range_m: float
@export var trigger_lateral_m: float
