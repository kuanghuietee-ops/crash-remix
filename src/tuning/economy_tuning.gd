class_name EconomyTuning
extends Resource

@export_category("Wumpa")
@export var wumpa_per_standard_crate: int
@export var wumpa_collect_radius_m: float
@export var wumpa_mask_threshold: int

@export_category("Aku Aku")
@export var mask_stack_maximum: int
@export var invincibility_duration_s: float
@export var mask_hit_invulnerability_s: float = -1.0

@export_category("Crates")
@export var tnt_fuse_s: float
@export var tnt_blast_radius_m: float
@export var bounce_crate_max_bounces: int
@export var bounce_crate_wumpa_per_bounce: int
@export var bounce_launch_height_m: float

@export_category("Authoring")
@export var checkpoint_spacing_limit_s: float

@export_category("Mercy")
@export var mercy_mask_death_threshold: int
@export var mercy_skip_death_threshold: int

@export_category("Relic Time Crates")
@export var time_crate_small_s: float
@export var time_crate_medium_s: float
@export var time_crate_large_s: float
