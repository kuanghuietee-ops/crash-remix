class_name KartTuning
extends Resource

@export_category("Motion")
@export var top_speed_mps: float
@export var reverse_speed_mps: float
@export var accel_mps2: float
@export var brake_mps2: float
@export var coast_drag_mps2: float
@export var steer_rate_degrees_per_s: float
## Ratio in (0.0, 1.0]: how much steer authority remains at top speed.
@export var steer_speed_falloff: float
@export var hop_height_m: float
@export var gravity_mps2: float

@export_category("Slide")
@export var slide_min_steer: float
@export var slide_yaw_bonus_degrees_per_s: float
@export var slide_counter_yaw_degrees_per_s: float
@export var slide_min_duration_s: float

@export_category("Boost")
@export var boost_window_open_s: float
@export var boost_window_close_s: float
## Ratio in (0.0, 1.0]: shrinks each stacked boost window vs. the last.
@export var boost_window_shrink_factor: float
@export var boost_speed_bonus_mps: float
@export var boost_duration_s: float
@export var boost_stack_max: float

@export_category("Hazard")
@export var spin_out_duration_s: float
## Ratio in (0.0, 1.0]: fraction of speed kept through a spin-out.
@export var spin_out_speed_keep_ratio: float
@export var invulnerable_after_hit_s: float

## CTR R7 Task 2 (kart-to-kart contact): see kart_controller.gd's own
## _process_kart_bumps()/receive_bump() doc for the full mechanic this
## powers, and kart_motor.gd's own apply_bump()/velocity() doc for where
## the resulting impulse actually lives. Below bump_min_relative_speed_mps
## of relative closing speed between two touching karts, NO impulse fires
## at all (a graze at walking pace should not fling either kart sideways) --
## at or above it, the lateral separation impulse magnitude is relative
## speed * bump_impulse_scale, capped at bump_lateral_cap_mps so an
## arbitrarily hard high-speed collision can never exceed a bounded sideways
## kick. Deliberately independent of every Hazard-section field above: a
## bump is a physical shove, not a hit -- it never touches spin_out/
## invulnerability, and invulnerability never gates it either (see the
## controller's own doc for why).
@export_category("Contact")
@export var bump_impulse_scale: float
@export var bump_min_relative_speed_mps: float
@export var bump_lateral_cap_mps: float

## CTR R6 Task 3: kart-body tint colours, applied via KartController.
## apply_body_tint() -- see that method's own doc. The kart mesh's own
## "BODY" palette cell (scripts/blender/build_kart.py) is painted a light,
## near-neutral grey specifically so a runtime material_override (albedo_
## color = one of these, vertex_color_use_as_albedo = true) reads as a clean
## recolour rather than a muddy double-tint. Every kart -- player included --
## gets one of these; there is no "untinted" kart. Five distinct AI slot
## colours plus the player's own is the minimum the design brief asks for
## ("5 distinct slot tints, deterministic"); named fields (not a single
## Array[Color] export) so each is individually authored/fingerprinted the
## same way every other tuning field in this repo is, and tint_for_slot()
## below builds the lookup array at call time so the src/racing/** numeric-
## literal lint (CLAUDE.md: only 0/1/-1 in code) never has to see a bare
## slot-index literal 2/3/4/5 -- mirrors kart_fx.gd's own _spark_color_for_
## stage() array-then-index shape exactly, see that method's doc.
@export_category("Visual")
@export var kart_tint_player: Color
@export var kart_tint_slot_1: Color
@export var kart_tint_slot_2: Color
@export var kart_tint_slot_3: Color
@export var kart_tint_slot_4: Color
@export var kart_tint_slot_5: Color


## slot_index is 1-based (RaceSession._spawn_ai_karts()'s own GridSlot1..N
## numbering, see race_session.gd). Wraps via modulo on the array's own
## size rather than clamping, so a future opponent_count above 5 degrades to
## a repeating rotation instead of every extra kart collapsing onto slot 5's
## colour -- deterministic either way, and never an out-of-range crash.
func tint_for_slot(slot_index: int) -> Color:
	var slots: Array[Color] = [
		kart_tint_slot_1,
		kart_tint_slot_2,
		kart_tint_slot_3,
		kart_tint_slot_4,
		kart_tint_slot_5,
	]
	var zero_based := (slot_index - 1) % slots.size()
	if zero_based < 0:
		zero_based += slots.size()
	return slots[zero_based]
