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
