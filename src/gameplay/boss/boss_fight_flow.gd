class_name BossFightFlow
extends RefCounted

## Pure phase flow for the Papu Papu gauntlet (01-DESIGN §4.14, spec §8.2).
## No Node, no scene, no timers: the arena drives this and reads it back, so
## every rule below is provable headless.

var _tuning: BossTuning
var _current_phase: int = 1
var _strikes_this_phase: int = 0
var _defeated: bool = false


func configure(tuning: BossTuning) -> void:
	_tuning = tuning
	_current_phase = 1
	_strikes_this_phase = 0
	_defeated = false


func current_phase() -> int:
	return _current_phase


func strikes_this_phase() -> int:
	return _strikes_this_phase


## spec §8.2: a checkpoint per phase. Death returns the player here, never to
## the start of the fight.
func checkpoint_phase() -> int:
	return _current_phase


func is_defeated() -> bool:
	return _defeated


func register_strike() -> void:
	if _defeated:
		return
	_strikes_this_phase += 1
	if _strikes_this_phase < _tuning.arena_strikes_per_phase:
		return
	_strikes_this_phase = 0
	if _current_phase >= _tuning.phase_count:
		_defeated = true
		return
	_current_phase += 1


## The phase restarts, losing its banked strikes -- it does not restart the
## fight, and it cannot un-win a fight already won.
func on_player_death() -> void:
	if _defeated:
		return
	_strikes_this_phase = 0


## When the Nth slam of a phase lands, counted from the phase's start. The
## arena needs this to age a ripple correctly when one frame spans a slam
## boundary, instead of backdating it to the frame's start.
func slam_landing_time_s(slam_index: int) -> float:
	return float(slam_index) * _tuning.slam_period_s


## Slams are percussion, not a one-shot: the arena asks how many have landed
## by now and drives the platforms from the count.
func slam_count_by(elapsed_s: float) -> int:
	if _tuning.slam_period_s <= 0.0:
		return 0
	return int(floor(elapsed_s / _tuning.slam_period_s))


## §4.14: debris is blob-shadow telegraphed before it can kill, so a death is
## always something the player had the information to avoid.
func debris_is_lethal(age_s: float) -> bool:
	return age_s >= _tuning.debris_telegraph_s


## How far a slam's ripple has crossed the floor since it was emitted. A wave
## that has not been emitted yet sits at the origin rather than travelling
## backwards.
func shockwave_distance_m(age_s: float) -> float:
	return maxf(age_s, 0.0) * _tuning.shockwave_speed_mps


## How far through its telegraph a piece of debris is, 0 at emission and 1 at
## the moment it arms, so a visual can land exactly as it becomes lethal.
func debris_fall_ratio(age_s: float) -> float:
	if _tuning.debris_telegraph_s <= 0.0:
		return 1.0
	return clampf(maxf(age_s, 0.0) / _tuning.debris_telegraph_s, 0.0, 1.0)


## Debris stops threatening once it has sat for a second telegraph's worth,
## so a phase does not silt up with permanent hazards.
func debris_is_spent(age_s: float) -> bool:
	return age_s >= _tuning.debris_telegraph_s + _tuning.debris_telegraph_s


## The authored crest height, so a visual can stand exactly as tall as the arc
## the player must clear rather than guessing at it.
func shockwave_height_m() -> float:
	return _tuning.shockwave_height_m


## §4.14 calls the shockwave jumpable: a player above its authored height
## passes over it, a grounded one does not.
func shockwave_clears_player(player_height_m: float) -> bool:
	return player_height_m > _tuning.shockwave_height_m
