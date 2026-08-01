extends GutTest

## Task 5 (CTR R7): pure logic tests for CupSession -- no scene tree, no real
## race scenes (that half is proven end to end by tests/integration/
## test_cup_flow_e2e.gd, driving two real race scenes through CupSession).
## See cup_session.gd's own class doc for the OWNERSHIP/RETRY SEMANTICS/
## TIE-BREAK RULE design this file locks down.

const CupSessionType := preload("res://src/racing/flow/cup_session.gd")
const AUTHORED_RACE_TUNING_PATH := "res://data/tuning/racing/race.tres"


func _points_tuning(
	place1: float,
	place2: float,
	place3: float,
	place4: float,
	place5: float,
	place6: float
) -> RaceTuning:
	var tuning := RaceTuning.new()
	tuning.cup_points_place1 = place1
	tuning.cup_points_place2 = place2
	tuning.cup_points_place3 = place3
	tuning.cup_points_place4 = place4
	tuning.cup_points_place5 = place5
	tuning.cup_points_place6 = place6
	return tuning


func _standings_row(
	position: int,
	label: String,
	finished: bool = true
) -> Dictionary:
	return {
		"position": position,
		"label": label,
		"finished": finished,
		"elapsed_s": 0.0,
		"is_player": label == CupSessionType.LABEL_PLAYER,
	}


func test_authored_race_tuning_carries_the_spec_points_table() -> void:
	var authored: RaceTuning = load(AUTHORED_RACE_TUNING_PATH)
	assert_not_null(authored)
	if authored == null:
		return
	assert_eq(authored.cup_points_place1, 8.0)
	assert_eq(authored.cup_points_place2, 6.0)
	assert_eq(authored.cup_points_place3, 5.0)
	assert_eq(authored.cup_points_place4, 4.0)
	assert_eq(authored.cup_points_place5, 3.0)
	assert_eq(authored.cup_points_place6, 2.0)


func test_track_order_matches_the_registry_sanity_shores_then_temple_twilight() -> void:
	var cup := CupSessionType.new()
	assert_eq(cup.race_count(), 2)
	assert_eq(cup.track_id_for_race(0), &"sanity_shores")
	assert_eq(cup.track_id_for_race(1), &"temple_twilight")
	assert_eq(
		cup.track_id_for_race(2),
		&"",
		"an out-of-range race index must fail closed to an empty StringName"
	)
	assert_eq(cup.track_id_for_race(-1), &"")


func test_points_for_placement_reads_the_configured_table_and_clamps_outside_it() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	assert_eq(cup.points_for_placement(1), 8.0)
	assert_eq(cup.points_for_placement(2), 6.0)
	assert_eq(cup.points_for_placement(3), 5.0)
	assert_eq(cup.points_for_placement(4), 4.0)
	assert_eq(cup.points_for_placement(5), 3.0)
	assert_eq(cup.points_for_placement(6), 2.0)
	assert_eq(
		cup.points_for_placement(7),
		0.0,
		"a placement outside the configured table must earn zero points"
	)
	assert_eq(cup.points_for_placement(0), 0.0)
	assert_eq(cup.points_for_placement(-1), 0.0)


func test_next_race_index_advances_as_results_are_recorded() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	assert_eq(cup.next_race_index(), 0)
	assert_false(cup.has_result(0))
	assert_false(cup.is_complete())

	cup.record_race_result(0, [_standings_row(1, "YOU")])

	assert_eq(cup.next_race_index(), 1)
	assert_true(cup.has_result(0))
	assert_false(cup.is_complete())

	cup.record_race_result(1, [_standings_row(1, "YOU")])

	assert_eq(
		cup.next_race_index(),
		-1,
		"every race recorded must report no further next race"
	)
	assert_true(cup.is_complete())


func test_record_race_result_ignores_malformed_entries() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	cup.record_race_result(0, [
		{"position": 1, "label": "", "is_player": true},
		{"position": 0, "label": "CPU 1"},
		{"position": -1, "label": "CPU 2"},
		{"label": "CPU 3"},
		"not a dictionary",
		_standings_row(2, "CPU 4"),
	])

	var rows := cup.standings()
	assert_eq(
		rows.size(),
		1,
		"only the one well-formed entry should have been recorded"
	)
	assert_eq(rows[0].label, "CPU 4")


func test_record_race_result_out_of_range_index_is_a_no_op() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	cup.record_race_result(5, [_standings_row(1, "YOU")])

	assert_eq(cup.standings(), [])


func test_standings_accumulates_total_points_across_both_races() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	cup.record_race_result(0, [
		_standings_row(1, "YOU"),
		_standings_row(2, "CPU 1"),
		_standings_row(3, "CPU 2"),
	])
	cup.record_race_result(1, [
		_standings_row(2, "YOU"),
		_standings_row(1, "CPU 1"),
		_standings_row(3, "CPU 2"),
	])

	var rows := cup.standings()
	var by_label := {}
	for row: Dictionary in rows:
		by_label[row.label] = row

	assert_eq(by_label["YOU"].total_points, 14.0, "1st (8) + 2nd (6) = 14")
	assert_eq(by_label["CPU 1"].total_points, 14.0, "2nd (6) + 1st (8) = 14")
	assert_eq(by_label["CPU 2"].total_points, 10.0, "3rd (5) + 3rd (5) = 10")


func test_standings_tie_break_uses_race_two_placement_ascending() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	# YOU and CPU 1 finish tied at 14 total points each, but YOU had the
	# better (lower-numbered) SECOND race -- see the class doc's own
	# TIE-BREAK RULE section for why race index 1 is the decider, not race
	# index 0.
	cup.record_race_result(0, [
		_standings_row(1, "YOU"),
		_standings_row(2, "CPU 1"),
	])
	cup.record_race_result(1, [
		_standings_row(2, "YOU"),
		_standings_row(1, "CPU 1"),
	])

	var rows := cup.standings()
	assert_eq(rows[0].label, "CPU 1", "CPU 1 won race 2 (1st) -- it must rank first on the tie")
	assert_eq(rows[0].position, 1)
	assert_eq(rows[1].label, "YOU")
	assert_eq(rows[1].position, 2)


func test_standings_before_race_two_falls_back_to_race_one_finishing_order() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	# Same points value for both, forcing a tie -- but only race 0 has been
	# recorded, so there is no race-2 placement to break the tie with.
	cup.record_race_result(0, [
		_standings_row(1, "YOU"),
	])

	var rows := cup.standings()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].label, "YOU")
	assert_true(rows[0].is_player)


func test_retry_overwrites_the_same_race_index_instead_of_accumulating() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	# First attempt at race 1: the player finishes 3rd.
	cup.record_race_result(0, [
		_standings_row(1, "CPU 1"),
		_standings_row(2, "CPU 2"),
		_standings_row(3, "YOU"),
	])
	assert_eq(
		_find_row(cup.standings(), "YOU").total_points,
		5.0,
		"sanity: the first (abandoned) attempt recorded 3rd place"
	)

	# The player retries race 1 (a fresh RaceSession instance -- see the
	# class doc's RETRY SEMANTICS section) and this time wins it outright.
	cup.record_race_result(0, [
		_standings_row(1, "YOU"),
		_standings_row(2, "CPU 1"),
		_standings_row(3, "CPU 2"),
	])

	var rows := cup.standings()
	assert_eq(
		_find_row(rows, "YOU").total_points,
		8.0,
		"the retried attempt must REPLACE the abandoned one, not add to it"
	)
	assert_eq(
		_find_row(rows, "CPU 1").total_points,
		6.0,
		"a retry must not double-count anyone else's placement either"
	)
	assert_eq(
		cup.next_race_index(),
		1,
		"race 1 must still read as recorded exactly once after the retry"
	)


func test_is_player_flag_matches_the_you_label() -> void:
	var cup := CupSessionType.new()
	cup.configure(_points_tuning(8.0, 6.0, 5.0, 4.0, 3.0, 2.0))

	cup.record_race_result(0, [
		_standings_row(1, "CPU 1"),
		_standings_row(2, "YOU"),
	])

	var rows := cup.standings()
	assert_true(_find_row(rows, "YOU").is_player)
	assert_false(_find_row(rows, "CPU 1").is_player)


func _find_row(rows: Array, label: String) -> Dictionary:
	for row: Variant in rows:
		if String((row as Dictionary).get("label", "")) == label:
			return row
	return {}
