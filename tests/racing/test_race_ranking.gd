extends GutTest

# R5 Task 2: pure coverage for RaceRanking.rank() -- see race_ranking.gd's
# own class doc for the full six-tier SORT contract. Every test here builds
# its own small, synthetic Array[Dictionary] (never a real kart/scene) --
# this class is pure RefCounted, no Node dependency, so it is tested exactly
# like lap_validator.gd's/spine_follower.gd's own pure suites.

const RaceRankingType := preload("res://src/racing/flow/race_ranking.gd")

var _ranking: RaceRankingType


func before_each() -> void:
	_ranking = RaceRankingType.new()


func _entry(
	id: Variant,
	finished_order: int = -1,
	laps_complete: int = 0,
	gates_this_lap: int = 0,
	total_progress_m: float = 0.0
) -> Dictionary:
	return {
		"id": id,
		"finished_order": finished_order,
		"laps_complete": laps_complete,
		"gates_this_lap": gates_this_lap,
		"total_progress_m": total_progress_m,
	}


# ---------------------------------------------------------------------------
# Tier 1: finished beats unfinished, unconditionally -- even against a huge
# progress lead for the unfinished kart.
# ---------------------------------------------------------------------------


func test_finished_beats_unfinished_regardless_of_progress() -> void:
	var entries: Array[Dictionary] = [
		_entry(&"unfinished_leader", -1, 5, 5, 100000.0),
		_entry(&"finished_last_place", 1, 0, 0, 0.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[&"finished_last_place", &"unfinished_leader"],
		"a finished kart must outrank an unfinished one no matter how far ahead the unfinished kart's own progress reads"
	)


# ---------------------------------------------------------------------------
# Tier 2: among finished karts, ascending finished_order -- decisive even
# against a reversed laps/gates/progress ordering.
# ---------------------------------------------------------------------------


func test_finished_karts_rank_by_ascending_finish_order_regardless_of_other_fields() -> void:
	var entries: Array[Dictionary] = [
		# 3rd to finish, but the "biggest" numbers on every other field.
		_entry(&"third", 3, 9, 9, 9000.0),
		_entry(&"first", 1, 0, 0, 0.0),
		_entry(&"second", 2, 5, 5, 500.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(result, [&"first", &"second", &"third"])


# ---------------------------------------------------------------------------
# Tier 3: among unfinished karts, laps_complete is decisive over gates and
# total_progress_m even when both of those point the other way.
# ---------------------------------------------------------------------------


func test_unfinished_ranked_by_laps_complete_decisively() -> void:
	var entries: Array[Dictionary] = [
		# Fewer laps, but far more gates AND far more raw progress.
		_entry(&"behind_on_laps", -1, 1, 5, 9999.0),
		_entry(&"ahead_on_laps", -1, 2, 0, 0.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[&"ahead_on_laps", &"behind_on_laps"],
		"laps_complete must decide the ranking even when gates and total_progress_m both disagree"
	)


# ---------------------------------------------------------------------------
# Tier 4: with laps tied, gates_this_lap is decisive over total_progress_m.
# ---------------------------------------------------------------------------


func test_unfinished_ties_on_laps_ranked_by_gates_this_lap_decisively() -> void:
	var entries: Array[Dictionary] = [
		_entry(&"behind_on_gates", -1, 1, 1, 9999.0),
		_entry(&"ahead_on_gates", -1, 1, 4, 0.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[&"ahead_on_gates", &"behind_on_gates"],
		"gates_this_lap must decide the ranking once laps_complete ties, even against a huge total_progress_m gap"
	)


# ---------------------------------------------------------------------------
# Tier 5: with laps and gates both tied, total_progress_m is the final
# decisive tiebreaker.
# ---------------------------------------------------------------------------


func test_unfinished_ties_on_laps_and_gates_ranked_by_total_progress_m() -> void:
	var entries: Array[Dictionary] = [
		_entry(&"behind_on_progress", -1, 2, 3, 10.0),
		_entry(&"ahead_on_progress", -1, 2, 3, 50.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(result, [&"ahead_on_progress", &"behind_on_progress"])


# ---------------------------------------------------------------------------
# Tier 6: a true tie on every field is STABLE -- input order preserved.
# ---------------------------------------------------------------------------


func test_a_full_tie_preserves_input_order_both_directions() -> void:
	var entries_ab: Array[Dictionary] = [
		_entry(&"a", -1, 2, 3, 40.0),
		_entry(&"b", -1, 2, 3, 40.0),
	]
	assert_eq(
		_ranking.rank(entries_ab),
		[&"a", &"b"],
		"a full tie must keep the original a-then-b input order"
	)

	var entries_ba: Array[Dictionary] = [
		_entry(&"b", -1, 2, 3, 40.0),
		_entry(&"a", -1, 2, 3, 40.0),
	]
	assert_eq(
		_ranking.rank(entries_ba),
		[&"b", &"a"],
		"the same full tie fed in b-then-a order must keep THAT input order -- stability tracks input position, not id"
	)


func test_finished_karts_tied_on_finish_order_are_stable_too() -> void:
	var entries: Array[Dictionary] = [
		_entry(&"x", 1),
		_entry(&"y", 1),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[&"x", &"y"],
		"two entries tied on finished_order itself (a caller bug elsewhere, or a legitimate simultaneous-order scheme) must still resolve stably rather than erroring or reordering arbitrarily"
	)


# ---------------------------------------------------------------------------
# Missing keys read their own documented defaults rather than erroring.
# ---------------------------------------------------------------------------


func test_missing_keys_default_to_unfinished_and_zero() -> void:
	var entries: Array[Dictionary] = [
		{"id": &"bare"},
		_entry(&"decorated", -1, 1, 1, 1.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[&"decorated", &"bare"],
		"an entry with no laps/gates/progress keys at all must read as the documented 0/0.0 defaults, ranking behind any entry with real positive progress"
	)


# ---------------------------------------------------------------------------
# Composite: a realistic 6-kart mid-race snapshot exercising every tier at
# once, matching the brief's own "each tier decisive" coverage request.
# ---------------------------------------------------------------------------


func test_composite_six_kart_snapshot_orders_every_tier_correctly() -> void:
	var entries: Array[Dictionary] = [
		# Unfinished, 1 lap banked, 2 gates into lap 2, mid progress.
		_entry(&"mid_pack", -1, 1, 2, 150.0),
		# Finished 2nd.
		_entry(&"finished_second", 2, 3, 0, 900.0),
		# Unfinished, most laps banked -- must lead every other unfinished
		# kart regardless of its own low gate/progress numbers.
		_entry(&"lap_leader_unfinished", -1, 2, 0, 5.0),
		# Finished 1st.
		_entry(&"finished_first", 1, 3, 0, 850.0),
		# Unfinished, tied on laps+gates with mid_pack but strictly less
		# progress.
		_entry(&"mid_pack_behind", -1, 1, 2, 90.0),
		# Unfinished, dead last -- zero everything.
		_entry(&"tail", -1, 0, 0, 0.0),
	]

	var result := _ranking.rank(entries)

	assert_eq(
		result,
		[
			&"finished_first",
			&"finished_second",
			&"lap_leader_unfinished",
			&"mid_pack",
			&"mid_pack_behind",
			&"tail",
		]
	)
