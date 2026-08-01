class_name AiTuning
extends Resource

@export_category("Roster")
@export var opponent_count: float
## Per-slot lateral offset from the pursuit line: slot_i * spacing, centered
## across the field so AI karts don't stack on top of each other or the
## player.
@export var lateral_slot_spacing_m: float

@export_category("Pursuit")
@export var lookahead_min_m: float
## Lookahead distance = lookahead_min_m + speed_mps * lookahead_speed_gain_s.
@export var lookahead_speed_gain_s: float
## Pursuit-angle-to-steer gain: steer input = angle_to_target * steer_gain.
@export var steer_gain: float

@export_category("Cornering")
## Target speed = top_speed * clamp(1 - gain * curvature, floor, 1).
@export var corner_speed_curvature_gain: float
## Ratio in (0.0, 1.0]: floor on the corner-speed multiplier above. Tightened
## from the design brief's "strictly positive" -- it clamps the low end of a
## multiplier whose high end is fixed at 1.0, so a floor above 1.0 would be
## nonsensical and one at or below 0.0 would let target speed collapse to
## zero (or invert) through a sharp corner.
@export var corner_speed_floor_ratio: float
## Brake when current speed > target_speed * brake_margin_ratio.
@export var brake_margin_ratio: float

@export_category("Slide")
## Curvature (1/m) above which the AI enters a slide.
@export var slide_trigger_curvature: float
## Curvature (1/m) below which the AI exits a slide.
@export var slide_exit_curvature: float

@export_category("Boost")
## Flag in {0.0, 1.0}: whether the AI driver taps for a slide-boost.
@export var boost_tap_enabled: float

@export_category("Rubber Band")
@export var rubber_band_full_gap_m: float
## Ratio in (0.0, 1.0) exclusive: max target-speed boost when far behind the
## player.
@export var rubber_band_boost_max_ratio: float
## Ratio in (0.0, 1.0) exclusive: max target-speed drag when far ahead of the
## player.
@export var rubber_band_drag_max_ratio: float

@export_category("Respawn")
@export var respawn_stuck_speed_mps: float
@export var respawn_stuck_after_s: float
@export var respawn_drop_gap_m: float

# Task 4 (CTR R6: circuit polish -- smarter AI). See ai_driver.gd's own
# APEX LATERAL TARGETING/STEER DAMPING/PERSONALITY sections for exactly how
# each of these five fields is consumed; added to the ALREADY-SHIPPED "ai"
# section as one migration cohort (tuning_service.gd's own
# LEGACY_FIELD_GROUPS_BY_SECTION[&"ai"]), the same "new fields on an
# existing section" shape kart.tres's own body-tint fields used one task
# earlier -- NOT a brand-new section (that shape is fx_tuning.gd's own, see
# its doc contrasting the two paths).
@export_category("Apex")
## Maximum lateral shift (meters), toward the corner's own geometric inside,
## at full apex engagement -- see ai_driver.gd's APEX LATERAL TARGETING
## section for the signed-curvature-derived "which side is inside" contract.
@export var apex_offset_max_m: float
## Engagement distance (meters) the apex blend ramps in over: blend_ratio =
## clamp(absf(curvature_ahead) * apex_entry_lookahead_m, 0.0, 1.0) --
## curvature's own units (1/m) paired with this distance (m) give a
## dimensionless engagement ratio, so this doubles as "the corner radius (in
## meters) at which the AI is fully committed to the apex line." See ai_
## driver.gd's own APEX LATERAL TARGETING section for the full derivation.
@export var apex_entry_lookahead_m: float

@export_category("Damping")
## Low-pass coefficient in (0.0, 1.0) exclusive: steer_new = lerp(prev_
## steer_output, raw_steer, 1.0 - steer_damping) -- see ai_driver.gd's own
## STEER DAMPING section for the cold-start/ordering-vs-the-slide-floor
## contract. Bounded exclusive of both ends for the same reason the rubber-
## band ratios are: 0.0 would defeat the whole feature (no smoothing at
## all) and 1.0 would freeze steer at its previous output forever (the
## kart could never actually turn).
@export var steer_damping: float

@export_category("Personality")
## Per-slot brake-threshold step (see ai_driver.gd's PERSONALITY section):
## effective_brake_margin_ratio = brake_margin_ratio + slot_index *
## personality_aggression_step -- a higher slot index brakes later (tolerates
## a higher speed-over-target multiple before braking).
@export var personality_aggression_step: float
## Per-(slot, tick) deterministic miss-probability in (0.0, 1.0) exclusive
## for the boost tap -- see ai_driver.gd's own PERSONALITY section for the
## NO-RNG hash-based confidence this gates against. Bounded exclusive for the
## same reason steer_damping is: 0.0 would defeat the feature (jitter never
## suppresses anything) and 1.0 would suppress every tap unconditionally.
@export var personality_skill_jitter: float

# CTR R7 Task 2b (OPERATOR PRIORITY): operator device report on R6 -- "the AI
# got bug, keep driving back the wrong way and stuck at the side." See ai_
# kart_agent.gd's own WRONG-WAY RECOVERY section for the full sustained-
# trigger/hysteresis contract these three fields power, and its FASTER
# UNSTICK section for how recovery_max_attempts bounds the retry loop before
# the existing stuck-respawn safety net takes over.
@export_category("Recovery")
## Heading error (degrees) between the kart's own facing and the spine's
## tangent at its current progress, beyond which the kart counts as opposing
## the track's own direction of travel. Bounded to (0.0, 180.0] rather than
## merely positive (the same tightening corner_speed_floor_ratio's own doc
## comment above applies to a ratio field with a real physical ceiling):
## Vector3.angle_to's own output range is [0, 180] degrees, so a value above
## 180 could never be exceeded -- silently and permanently disabling
## recovery rather than loosening it.
@export var recovery_heading_error_degrees: float
## How long (seconds) the heading error above must stay CONTINUOUSLY beyond
## recovery_heading_error_degrees before recovery intent arms -- see ai_kart_
## agent.gd's own WRONG-WAY RECOVERY section for the sustained-trigger/
## hysteresis contract (exit re-uses this same angle threshold, halved, not
## a separate time-based hysteresis).
@export var recovery_trigger_s: float
## How many consecutive stuck-and-still-wrong-facing detection windows (see
## ai_kart_agent.gd's own FASTER UNSTICK section) recovery is given before
## the stuck-respawn safety net gives up and teleports the kart anyway. A
## stuck kart that IS correctly facing (recovery never armed) still respawns
## on its very first closing window, exactly as before this field existed --
## this only bounds the NEW recovery-retry path for the wrong-facing case.
@export var recovery_max_attempts: float
