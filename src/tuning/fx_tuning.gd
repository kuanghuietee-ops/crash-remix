class_name FxTuning
extends Resource

## Task 1 (CTR R6, circuit polish): the FX loop's own tuning section, the
## sixth whole new section the same shape as kart/race/ai/items before it --
## see tuning_service.gd's SECTION_NAMES and catalog_is_usable() for how a
## new section joins validation, and PHASE0_BASELINE_FIELDS_BY_SECTION in
## tests/tuning/test_tuning_service.gd for how its initial fields join
## migration coverage atomically via _backfill_missing_sections rather than
## a LEGACY_FIELD_GROUPS_BY_SECTION cohort (that mechanism is for a new field
## on an EXISTING section).
##
## Drift sparks (kart_fx.gd) read the CURRENT DriftStateMachine.boost_stage()
## every tick while sliding: amount = spark_amount_stage0 +
## stage * spark_amount_per_stage, and color is spark_color_stage1/2/3
## indexed by clampi(stage, 1, 3) -- stage 0 borrows stage 1's color at the
## lower stage-0 amount (there is no separate "stage 0" color; only the
## amount differs). Boost flame amount/lifetime are NOT stage-dependent --
## just a binary is_boosting() gate.
##
## Particle amount fields (spark_amount_stage0/spark_amount_per_stage/
## boost_flame_amount) are FLOATS with COUNT semantics, the same
## "float field, integer runtime meaning" shape kart.boost_stack_max/
## race.lap_count already use -- kart_fx.gd rounds via roundi() the same way
## DriftStateMachine/race_session.gd already do for those two fields.

@export_category("Drift sparks")
@export var spark_amount_stage0: float
@export var spark_amount_per_stage: float
@export var spark_lifetime_s: float
@export var spark_velocity_mps: float
@export var spark_color_stage1: Color
@export var spark_color_stage2: Color
@export var spark_color_stage3: Color

@export_category("Boost flame")
@export var boost_flame_lifetime_s: float
@export var boost_flame_amount: float

@export_category("Item box")
@export var item_box_spin_degrees_per_s: float
@export var item_box_bob_amplitude_m: float
@export var item_box_bob_hz: float
