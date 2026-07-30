class_name ItemTuning
extends Resource

## R4 Task 2: the item loop's own tuning section, the same "whole new
## section" shape kart/race (R4 Task 1's predecessor, R3's CTR racing mode)
## and ai (CTR R3) introduced -- see tuning_service.gd's SECTION_NAMES and
## catalog_is_usable() for how a new section joins validation, and
## PHASE0_BASELINE_FIELDS_BY_SECTION in tests/tuning/test_tuning_service.gd
## for how its initial fields join migration coverage atomically via
## _backfill_missing_sections rather than a LEGACY_FIELD_GROUPS_BY_SECTION
## cohort (that mechanism is for a new field on an EXISTING section).

@export_category("Roulette")
@export var roulette_duration_s: float
@export var roulette_tick_s: float

@export_category("Box")
@export var box_respawn_s: float
@export var box_pickup_radius_m: float

@export_category("Missile")
@export var missile_speed_mps: float
@export var missile_turn_rate_degrees_per_s: float
@export var missile_lifetime_s: float
@export var missile_arm_delay_s: float
@export var missile_hit_radius_m: float

@export_category("Shield")
@export var shield_duration_s: float

@export_category("Turbo")
@export var turbo_boost_s: float

@export_category("Beaker")
@export var beaker_arm_delay_s: float
@export var beaker_lifetime_s: float
@export var beaker_hit_radius_m: float

@export_category("AI")
@export var ai_item_use_cooldown_s: float
@export var ai_missile_max_target_gap_m: float
