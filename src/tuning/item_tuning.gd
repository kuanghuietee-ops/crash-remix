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

## CTR R6 Task 5: lobbed ballistic hazard. No separate lifetime/hit-radius-
## while-grounded fields -- a bomb is airborne, not dropped-and-sitting like
## a beaker/TNT stick, so "ground contact" IS its own arrival signal; its
## un-contacted safety-net despawn reuses beaker_lifetime_s directly (see
## bomb.gd's own class doc's LIFETIME section) rather than adding a near-
## duplicate bomb_lifetime_s field. The LAUNCH ANGLE is not a tuning field
## either: bomb.gd derives a fixed 45-degree arc geometrically (launcher
## forward blended evenly with world UP, two equal-magnitude unit
## components) rather than a bare angle literal or a new field -- see that
## file's own LAUNCH GEOMETRY doc.
@export_category("Bomb")
@export var bomb_speed_mps: float
@export var bomb_blast_radius_m: float
@export var bomb_arm_delay_s: float

## CTR R6 Task 5: dropped-and-attaches hazard. Reuses beaker_arm_delay_s/
## beaker_hit_radius_m/beaker_lifetime_s for its own pre-attach GROUNDED
## phase -- "dropped like the beaker" per the task brief, so the grounded
## phase's own arm/contact/un-contacted-despawn shape is IDENTICAL to
## beaker.gd's, not a near-duplicate set of tnt_arm_delay_s/tnt_hit_radius_m/
## tnt_lifetime_s fields. Only the POST-ATTACH behavior (the fuse countdown
## and the hop-shake-off count) is genuinely new and gets its own fields
## below -- see tnt_stick.gd's own class doc for the full two-phase state
## machine.
@export_category("TNT")
@export var tnt_fuse_s: float
## Whole hop presses to shake the stick off before the fuse -- typed float
## (not int) to match every other numeric ItemTuning field's own export
## type; tnt_stick.gd reads it through roundi() wherever a real hop-press
## COUNT is needed (see that file's own SHAKE-OFF doc).
@export var tnt_shake_hops: float

## CTR R6 Task 5: the brief's own "held triple_turbo carries 3 charges"
## names a charge COUNT with no matching tuning field in its own field list
## -- since src/racing/**'s numeric-literal lint bans every bare literal
## outside 0/1/-1 (see CLAUDE.md), that "3" cannot live in item_slot.gd as a
## literal either. This field is the one place it lives instead, filling a
## gap the brief's own field list left implicit rather than smuggling the
## count in as code. item_slot.gd reads it through roundi() the same way
## tnt_shake_hops above is read.
@export_category("Triple Turbo")
@export var triple_turbo_charges: float

## CTR R6 Task 5: weighted roulette. One (front, back) pair per real
## ITEM_NAMES entry (item_slot.gd) -- "front" is the weight used for the
## race LEADER (position ratio 0.0), "back" for LAST PLACE (ratio 1.0);
## ItemSlot._weights_for_ratio() linearly blends the two by a kart's own
## live position ratio for every other ratio in between. Field names follow
## weight_front_<item_name>/weight_back_<item_name> exactly (matching
## ItemSlot.ITEM_NAMES's own StringName spelling) so ItemSlot can look them
## up generically via Object.get() instead of a hardcoded per-item match --
## see that file's own WEIGHTED MAPPING doc. Validated in tuning_service.gd:
## every individual weight >= 0.0, and the FRONT set's own sum plus the BACK
## set's own sum must each be > 0.0 (a linear blend of two positive sums is
## provably positive at every ratio in between -- see catalog_is_usable()'s
## own comment for the short proof), together satisfying the brief's
## "weights >= 0, at least one positive at any ratio" contract without
## having to check every ratio individually.
##
## DESIGN RULING (this task's own call, not a real-CTR authenticity claim):
## defensive/speed items skew toward the FRONT (a leader wants to protect
## its lead); attack/catch-up items skew toward the BACK (a trailing kart
## wants to close the gap). triple_turbo is the most extreme of either
## direction -- the biggest catch-up tool, rare for a leader, common for
## last place.
@export_category("Roulette Weights")
@export var weight_front_missile: float
@export var weight_back_missile: float
@export var weight_front_shield: float
@export var weight_back_shield: float
@export var weight_front_turbo: float
@export var weight_back_turbo: float
@export var weight_front_beaker: float
@export var weight_back_beaker: float
@export var weight_front_bomb: float
@export var weight_back_bomb: float
@export var weight_front_tnt_stick: float
@export var weight_back_tnt_stick: float
@export var weight_front_triple_turbo: float
@export var weight_back_triple_turbo: float

@export_category("AI")
@export var ai_item_use_cooldown_s: float
@export var ai_missile_max_target_gap_m: float
