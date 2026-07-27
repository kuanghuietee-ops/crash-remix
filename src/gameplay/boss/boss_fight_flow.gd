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
