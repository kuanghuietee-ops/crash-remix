extends GutTest

# Task 6 (CTR racing mode): LapValidator is pure RefCounted sequencing logic
# (configure/gate_crossed poll model, same shape as drift_state_machine.gd)
# -- see lap_validator.gd's class doc and .superpowers/sdd/
# 2026-07-30-ctr-r1-r2-kart-and-circuit/task-6-brief.md.

const VALIDATOR_SCRIPT_PATH := "res://src/racing/track/lap_validator.gd"

const OK := &"ok"
const OUT_OF_ORDER := &"out_of_order"
const LAP_COMPLETE := &"lap_complete"
const RACE_COMPLETE := &"race_complete"


# ---------------------------------------------------------------------------
# Full-sequence lap and race completion.
# ---------------------------------------------------------------------------


func test_full_gate_sequence_completes_a_lap() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return

	assert_eq(validator.call("gate_crossed", 0), OK, "starting crossing of gate 0")
	assert_eq(validator.call("gate_crossed", 1), OK)
	assert_eq(validator.call("gate_crossed", 2), OK)
	assert_eq(
		validator.call("gate_crossed", 0),
		LAP_COMPLETE,
		"all gates seen, back at gate 0: lap 1 of 2 must complete"
	)
	assert_eq(validator.call("current_lap"), 2, "must now be racing lap 2")


func test_race_completes_after_lap_count_laps() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	_drive_full_lap(validator, 3)
	assert_eq(validator.call("current_lap"), 2)

	validator.call("gate_crossed", 1)
	validator.call("gate_crossed", 2)
	assert_eq(
		validator.call("gate_crossed", 0),
		RACE_COMPLETE,
		"the final lap's closing gate-0 crossing must complete the race"
	)
	assert_eq(
		validator.call("current_lap"),
		2,
		"current_lap must not report a lap beyond the last one that exists"
	)


func test_single_lap_race_completes_immediately_on_first_full_cycle() -> void:
	var validator := _new_validator(3, 1)
	if validator == null:
		return
	validator.call("gate_crossed", 0)
	validator.call("gate_crossed", 1)
	validator.call("gate_crossed", 2)

	assert_eq(
		validator.call("gate_crossed", 0),
		RACE_COMPLETE,
		"lap_count 1 must go straight to race_complete, never lap_complete"
	)


# ---------------------------------------------------------------------------
# Out-of-order (skipped gate) rejection.
# ---------------------------------------------------------------------------


func test_skipping_a_gate_is_rejected_and_does_not_advance_expectation() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	validator.call("gate_crossed", 0)
	validator.call("gate_crossed", 1)

	# Gate 2 is expected next; jumping straight to gate 0 skips it.
	var result: StringName = validator.call("gate_crossed", 0)

	assert_eq(result, OUT_OF_ORDER)
	assert_eq(
		validator.call("progress_gates"),
		2,
		"a rejected crossing must not change how many gates have been validated"
	)

	# The skipped sequence must still be recoverable: gate 2 is still what
	# the validator is waiting for.
	assert_eq(validator.call("gate_crossed", 2), OK)
	assert_eq(validator.call("gate_crossed", 0), LAP_COMPLETE)


func test_crossing_a_gate_two_steps_ahead_is_rejected() -> void:
	var validator := _new_validator(4, 1)
	if validator == null:
		return
	validator.call("gate_crossed", 0)

	var result: StringName = validator.call("gate_crossed", 3)

	assert_eq(result, OUT_OF_ORDER, "gate 1 is expected, not gate 3")


# ---------------------------------------------------------------------------
# Boundary jitter: re-crossing the gate just passed is idempotent &"ok".
# ---------------------------------------------------------------------------


func test_recrossing_the_gate_just_passed_is_idempotent_ok_not_out_of_order() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	validator.call("gate_crossed", 0)
	validator.call("gate_crossed", 1)

	# The kart straddles gate 1's trigger volume and re-enters it.
	var jitter_result: StringName = validator.call("gate_crossed", 1)

	assert_eq(
		jitter_result,
		OK,
		"a kart straddling a gate must not spam out_of_order"
	)
	assert_eq(
		validator.call("progress_gates"),
		2,
		"idempotent jitter must not double-count the gate"
	)
	# The sequence must still be intact afterward.
	assert_eq(validator.call("gate_crossed", 2), OK)
	assert_eq(validator.call("gate_crossed", 0), LAP_COMPLETE)


func test_recrossing_the_start_gate_right_after_starting_is_idempotent_ok() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	validator.call("gate_crossed", 0)

	var jitter_result: StringName = validator.call("gate_crossed", 0)

	assert_eq(jitter_result, OK)
	assert_eq(validator.call("current_lap"), 1, "jitter must not complete a lap early")
	assert_eq(validator.call("progress_gates"), 1)


# Fix round 1 (review): before _started, _previous_expected(_expected_gate)
# used to alias the LAST gate in the sequence (wrap-around from expected
# gate 0), so crossing that gate first -- before the race has genuinely
# begun -- was misread as idempotent jitter against a gate that was never
# actually passed. Jitter tolerance only makes sense once there IS a gate
# that was legitimately just crossed, i.e. once _started is true.
func test_crossing_the_last_gate_first_before_anything_started_is_out_of_order() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return

	var result: StringName = validator.call("gate_crossed", 2)

	assert_eq(
		result,
		OUT_OF_ORDER,
		"nothing has been crossed yet -- there is no 'gate just passed' to jitter against"
	)
	assert_eq(validator.call("current_lap"), 1, "a rejected crossing must not start the race")
	assert_eq(validator.call("progress_gates"), 0)

	# The real start must still work normally afterward.
	assert_eq(validator.call("gate_crossed", 0), OK)


# Pin: the fix above must not touch the gate-0-straddle-at-the-start-line
# case, which is already _started by the time it can occur (see
# test_recrossing_the_start_gate_right_after_starting_is_idempotent_ok
# above) -- this just names the distinction explicitly for the fix round.
func test_gate_zero_straddle_at_the_start_line_stays_idempotent_ok_after_the_fix() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	validator.call("gate_crossed", 0)

	assert_eq(
		validator.call("gate_crossed", 0),
		OK,
		"once _started, re-crossing gate 0 right at the start line is still jitter, not a skip"
	)


# ---------------------------------------------------------------------------
# gate_count == 1 degenerate edge: every crossing after the first advances
# a lap outright.
# ---------------------------------------------------------------------------


func test_single_gate_track_first_crossing_only_starts_the_race() -> void:
	var validator := _new_validator(1, 2)
	if validator == null:
		return

	assert_eq(validator.call("gate_crossed", 0), OK)
	assert_eq(validator.call("current_lap"), 1)


func test_single_gate_track_every_crossing_after_the_first_advances_a_lap() -> void:
	var validator := _new_validator(1, 2)
	if validator == null:
		return
	validator.call("gate_crossed", 0)

	assert_eq(validator.call("gate_crossed", 0), LAP_COMPLETE)
	assert_eq(validator.call("current_lap"), 2)
	assert_eq(
		validator.call("gate_crossed", 0),
		RACE_COMPLETE,
		"a single-gate track's second re-crossing must finish the race"
	)


# ---------------------------------------------------------------------------
# current_lap() / progress_gates() arithmetic.
# ---------------------------------------------------------------------------


func test_current_lap_is_one_before_anything_is_crossed() -> void:
	var validator := _new_validator(3, 3)
	if validator == null:
		return
	assert_eq(validator.call("current_lap"), 1)
	assert_eq(validator.call("progress_gates"), 0)


func test_progress_gates_counts_up_through_a_lap_and_resets_after_it_completes() -> void:
	var validator := _new_validator(3, 2)
	if validator == null:
		return
	assert_eq(validator.call("progress_gates"), 0)
	validator.call("gate_crossed", 0)
	assert_eq(validator.call("progress_gates"), 1)
	validator.call("gate_crossed", 1)
	assert_eq(validator.call("progress_gates"), 2)
	validator.call("gate_crossed", 2)
	assert_eq(validator.call("progress_gates"), 3)
	validator.call("gate_crossed", 0)
	assert_eq(
		validator.call("progress_gates"),
		1,
		"a completed lap's closing gate-0 crossing is also gate 0 of the new lap"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_validator(gate_count: int, lap_count: int) -> RefCounted:
	var script: Script = load(VALIDATOR_SCRIPT_PATH)
	assert_not_null(script, "LapValidator implementation must exist")
	if script == null:
		return null
	var validator: RefCounted = script.new()
	validator.call("configure", gate_count, lap_count)
	return validator


## Drives one complete lap from a freshly-configured (never-crossed)
## validator: the starting crossing of gate 0, then 1..gate_count-1 in
## order, then the closing crossing of gate 0 that completes the lap.
func _drive_full_lap(validator: RefCounted, gate_count: int) -> void:
	validator.call("gate_crossed", 0)
	var index := 1
	while index < gate_count:
		validator.call("gate_crossed", index)
		index += 1
	validator.call("gate_crossed", 0)
