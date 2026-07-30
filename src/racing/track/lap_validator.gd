class_name LapValidator
extends RefCounted

## Pure lap/checkpoint-gate sequencing (Task 6). Tracks progress around a
## closed circuit of gate_count checkpoint gates (index 0 doubles as the
## start/finish line) across lap_count laps. No Node/scene dependency --
## Task 7's race session owns the Area3D wiring (checkpoint_gate.gd) and
## calls gate_crossed() from its own body_entered handler, the same
## configure()-then-poll shape as drift_state_machine.gd.
##
## SEQUENCE. The expected order is 0, 1, ..., gate_count-1, 0 again -- and
## that closing crossing of gate 0 is what completes a lap (or the race, on
## the final lap). The very first crossing of gate 0 -- before anything else
## has been seen -- only starts lap 1; it must not itself read as a
## completed lap, so _started distinguishes "the race just began" from "the
## sequence just wrapped back to the start gate" even though both are index
## 0 events reaching gate_crossed() with the same _expected_gate.
##
## BOUNDARY JITTER. A kart straddling a gate can re-trigger the gate it just
## passed (an Area3D body_entered firing again on a small back-and-forth
## inside the trigger volume). That must read as idempotent &"ok", not
## &"out_of_order" -- see gate_crossed(). Any OTHER unexpected index is a
## genuine skip and is rejected without moving the expectation forward, so a
## later correct crossing still lines up with what the validator was
## already waiting for.
##
## GATE_COUNT == 1 EDGE. With only one gate, that single gate is both the
## start line and the finish line -- there is no partial sequence to walk
## through, so every crossing after the first completes a lap outright.

var _gate_count: int
var _lap_count: int
var _expected_gate: int
var _laps_completed: int
var _gates_seen_this_lap: int
var _started: bool


func configure(gate_count: int, lap_count: int) -> void:
	_gate_count = gate_count
	_lap_count = lap_count
	_expected_gate = 0
	_laps_completed = 0
	_gates_seen_this_lap = 0
	_started = false


func gate_crossed(index: int) -> StringName:
	if index == _expected_gate:
		if index == 0 and _started:
			return _complete_lap()
		_started = true
		_expected_gate = _next_expected(_expected_gate)
		_gates_seen_this_lap += 1
		return &"ok"
	if index == _previous_expected(_expected_gate):
		# Boundary jitter: the gate just passed re-triggered. Idempotent,
		# not a skip -- see the class doc above.
		return &"ok"
	return &"out_of_order"


## 1-based: 1 during the first lap, through _lap_count once the race is
## complete (it never reports a lap beyond the last one that exists).
func current_lap() -> int:
	return mini(_laps_completed + 1, _lap_count)


## How many gates (including the lap's own starting gate 0) have been
## validated toward completing the lap currently in progress.
func progress_gates() -> int:
	return _gates_seen_this_lap


func _complete_lap() -> StringName:
	_laps_completed += 1
	_expected_gate = _next_expected(0)
	# This same crossing IS gate 0 of the new lap, so its progress starts
	# already counting that one gate -- except with only a single gate,
	# where there is no partial in-lap progress to speak of at all.
	_gates_seen_this_lap = 1 if _gate_count > 1 else 0
	if _laps_completed >= _lap_count:
		return &"race_complete"
	return &"lap_complete"


func _next_expected(current: int) -> int:
	var next := current + 1
	if next >= _gate_count:
		next = 0
	return next


func _previous_expected(current: int) -> int:
	var previous := current - 1
	if previous < 0:
		previous = _gate_count - 1
	return previous
