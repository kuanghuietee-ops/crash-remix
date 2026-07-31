extends GutTest

# R4 Task 3 (CTR item loop): ItemSlot is pure RefCounted roulette-state
# logic (configure/start_roll/tick poll model, same shape as
# drift_state_machine.gd/lap_validator.gd) -- see item_slot.gd's own class
# doc and .superpowers/sdd/2026-07-30-ctr-r4-items/task-3-brief.md.

const SLOT_SCRIPT_PATH := "res://src/racing/items/item_slot.gd"
const TUNING_PATH := "res://data/tuning/racing/items.tres"

const EMPTY := &"empty"
const ROLLING := &"rolling"
const HELD := &"held"
const NONE := &"none"
const MISSILE := &"missile"
const SHIELD := &"shield"
const TURBO := &"turbo"
const BEAKER := &"beaker"
const BOMB := &"bomb"
const TNT_STICK := &"tnt_stick"
const TRIPLE_TURBO := &"triple_turbo"

var _tuning: ItemTuning


func before_all() -> void:
	_tuning = load(TUNING_PATH)
	assert_not_null(_tuning, "items.tres must load -- Task 2 registers it")


# ---------------------------------------------------------------------------
# Initial state.
# ---------------------------------------------------------------------------


func test_a_fresh_slot_starts_empty_with_no_held_item() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	assert_eq(slot.call("state"), EMPTY)
	assert_eq(slot.call("held_item"), NONE)
	assert_eq(slot.call("rolling_display_item"), NONE)


# ---------------------------------------------------------------------------
# start_roll(): N-WAY UNIFORM RNG mapping (no position_ratio -- see item_
# slot.gd's own class doc) + exact-boundary/1.0 guard. CTR R6 Task 5 grew
# ITEM_NAMES from four entries to seven (bomb/tnt_stick/triple_turbo added),
# so every boundary below is now an i/7 fraction, not the old i/4 -- the
# MAPPING'S SHAPE (floor(rng_value * n), clamped) is unchanged, only n grew.
# ---------------------------------------------------------------------------


func test_start_roll_transitions_empty_to_rolling() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), ROLLING)


func test_rng_value_zero_maps_to_the_first_item_missile() -> void:
	_assert_rng_maps_to(0.0, MISSILE)


func test_rng_value_just_under_one_seventh_maps_to_missile() -> void:
	_assert_rng_maps_to(1.0 / 7.0 - 0.001, MISSILE)


func test_rng_value_at_one_seventh_maps_to_the_second_item_shield() -> void:
	_assert_rng_maps_to(1.0 / 7.0, SHIELD)


func test_rng_value_at_two_sevenths_maps_to_the_third_item_turbo() -> void:
	_assert_rng_maps_to(2.0 / 7.0, TURBO)


func test_rng_value_at_three_sevenths_maps_to_the_fourth_item_beaker() -> void:
	_assert_rng_maps_to(3.0 / 7.0, BEAKER)


func test_rng_value_at_four_sevenths_maps_to_the_fifth_item_bomb() -> void:
	_assert_rng_maps_to(4.0 / 7.0, BOMB)


func test_rng_value_at_five_sevenths_maps_to_the_sixth_item_tnt_stick() -> void:
	_assert_rng_maps_to(5.0 / 7.0, TNT_STICK)


func test_rng_value_at_six_sevenths_maps_to_the_seventh_item_triple_turbo() -> void:
	_assert_rng_maps_to(6.0 / 7.0, TRIPLE_TURBO)


func test_rng_value_just_under_one_maps_to_the_seventh_item_triple_turbo() -> void:
	_assert_rng_maps_to(0.999, TRIPLE_TURBO)


## Exact-1.0 guard: floor(1.0 * 7) = 7, one past the last valid index (0-6)
## -- must clamp back to the last item (triple_turbo) rather than index out
## of bounds. rng_value = 1.0 is out of RandomNumberGenerator.randf()'s own
## documented [0, 1) range, but start_roll() stays a pure function of its
## input and must not crash on it.
func test_rng_value_of_exactly_one_clamps_to_the_last_item_not_out_of_bounds() -> void:
	_assert_rng_maps_to(1.0, TRIPLE_TURBO)


func test_negative_rng_value_clamps_to_the_first_item() -> void:
	_assert_rng_maps_to(-0.5, MISSILE)


func _assert_rng_maps_to(rng_value: float, expected_item: StringName) -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", rng_value)
	# tick all the way through so held_item() (the only place the decided
	# item is externally observable once landed) can confirm the mapping.
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(
		slot.call("held_item"),
		expected_item,
		"rng_value=%s must land on %s" % [rng_value, expected_item]
	)


# ---------------------------------------------------------------------------
# start_roll() is a no-op unless the slot is currently &"empty".
# ---------------------------------------------------------------------------


func test_start_roll_while_already_rolling_does_not_restart_or_change_the_item() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), ROLLING)

	# A second box pickup mid-roll, with an rng_value that would map to a
	# DIFFERENT item -- must be fully ignored.
	slot.call("start_roll", 0.75)

	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(
		slot.call("held_item"),
		MISSILE,
		"the second start_roll() must not have overwritten the first roll's decided item"
	)


func test_start_roll_while_held_does_not_overwrite_the_held_item() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("state"), HELD)

	slot.call("start_roll", 0.75)

	assert_eq(slot.call("state"), HELD, "a held slot must not be knocked back into rolling")
	assert_eq(slot.call("held_item"), MISSILE, "the already-held item must be unchanged")


# ---------------------------------------------------------------------------
# tick(): roulette timing.
# ---------------------------------------------------------------------------


func test_tick_before_roulette_duration_s_stays_rolling() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s * 0.5)
	assert_eq(slot.call("state"), ROLLING)
	assert_eq(slot.call("held_item"), NONE, "held_item() must stay none mid-roll")


func test_tick_reaching_roulette_duration_s_exactly_lands_on_held() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("state"), HELD)
	assert_eq(slot.call("held_item"), BEAKER, "0.5 lands on ITEM_NAMES[3] under the 7-way mapping")


func test_tick_accumulates_across_multiple_calls() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)
	var half := _tuning.roulette_duration_s * 0.5
	slot.call("tick", half)
	assert_eq(slot.call("state"), ROLLING, "fixture setup: half the duration must not be enough")
	slot.call("tick", half)
	assert_eq(
		slot.call("state"),
		HELD,
		"two half-duration ticks must sum to the full roulette_duration_s"
	)


func test_tick_is_a_no_op_while_empty() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("tick", _tuning.roulette_duration_s * 10.0)
	assert_eq(slot.call("state"), EMPTY, "ticking an empty slot must never start a roll")


func test_tick_is_a_no_op_once_held() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("state"), HELD)

	slot.call("tick", _tuning.roulette_duration_s * 10.0)
	assert_eq(slot.call("state"), HELD, "ticking a held slot must not change anything")
	assert_eq(slot.call("held_item"), MISSILE)


# ---------------------------------------------------------------------------
# rolling_display_item(): the HUD flicker, cycling every roulette_tick_s.
# ---------------------------------------------------------------------------


func test_rolling_display_item_is_none_outside_the_rolling_state() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	assert_eq(slot.call("rolling_display_item"), NONE, "empty must read none")

	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("rolling_display_item"), NONE, "held must read none")


func test_rolling_display_item_starts_on_the_first_item() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)
	assert_eq(
		slot.call("rolling_display_item"),
		MISSILE,
		"the very first display frame (elapsed 0.0) must show ITEM_NAMES[0]"
	)


## CTR R6 Task 5: ITEM_NAMES grew from four entries to seven -- the flicker
## now cycles through all seven before wrapping, not four.
func test_rolling_display_item_cycles_every_roulette_tick_s() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(slot.call("rolling_display_item"), SHIELD, "one tick interval must advance to the second item")

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(slot.call("rolling_display_item"), TURBO, "two tick intervals must advance to the third item")

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(slot.call("rolling_display_item"), BEAKER, "three tick intervals must advance to the fourth item")

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(slot.call("rolling_display_item"), BOMB, "four tick intervals must advance to the fifth item")

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(slot.call("rolling_display_item"), TNT_STICK, "five tick intervals must advance to the sixth item")

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(
		slot.call("rolling_display_item"),
		TRIPLE_TURBO,
		"six tick intervals must advance to the seventh item"
	)

	slot.call("tick", _tuning.roulette_tick_s)
	assert_eq(
		slot.call("rolling_display_item"),
		MISSILE,
		"a seventh tick interval must wrap back around to the first item"
	)


# ---------------------------------------------------------------------------
# held_item() / use(): single-held semantics, returns-and-clears.
# ---------------------------------------------------------------------------


func test_held_item_is_none_while_empty_or_rolling() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	assert_eq(slot.call("held_item"), NONE)
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("held_item"), NONE, "held_item() must stay none while rolling")


func test_use_returns_none_while_empty() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	assert_eq(slot.call("use"), NONE)
	assert_eq(slot.call("state"), EMPTY, "a no-op use() must not change the state")


func test_use_returns_none_while_rolling_and_does_not_disturb_the_roll() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)

	assert_eq(slot.call("use"), NONE, "an item is not usable until the roll lands")
	assert_eq(slot.call("state"), ROLLING, "a no-op use() must not cancel the in-progress roll")

	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(
		slot.call("use"),
		MISSILE,
		"the roll must still complete normally after a no-op use() attempt"
	)


func test_use_returns_the_held_item_and_clears_back_to_empty() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("state"), HELD)

	var used: StringName = slot.call("use")

	assert_eq(used, BEAKER)
	assert_eq(slot.call("state"), EMPTY, "use() must clear the slot back to empty")
	assert_eq(slot.call("held_item"), NONE, "held_item() must read none immediately after use()")


func test_a_second_use_after_a_successful_use_returns_none_not_the_same_item_again() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.5)
	slot.call("tick", _tuning.roulette_duration_s)
	slot.call("use")

	assert_eq(
		slot.call("use"),
		NONE,
		"a slot must never hand out the same item twice"
	)


## A used, now-empty slot must be able to roll again from scratch.
func test_a_slot_can_roll_again_after_being_used() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	slot.call("use")
	assert_eq(slot.call("state"), EMPTY)

	slot.call("start_roll", 0.75)
	slot.call("tick", _tuning.roulette_duration_s)

	assert_eq(
		slot.call("held_item"),
		TNT_STICK,
		"a fresh roll after use() must work normally (0.75 lands on ITEM_NAMES[5] under the 7-way mapping)"
	)


# ---------------------------------------------------------------------------
# CTR R6 Task 5: WEIGHTED MAPPING -- start_roll(rng_value, position_ratio)
# with a real [0.0, 1.0] ratio blends per-item weight_front_*/weight_back_*
# instead of the plain N-WAY UNIFORM buckets above. Isolated synthetic
# tunings (only the two items under test carry nonzero weight, every other
# ITEM_NAMES entry left at its ItemTuning default of 0.0) make the pinned
# outcome provable by hand rather than merely plausible.
# ---------------------------------------------------------------------------


func test_weighted_roll_at_front_ratio_uses_only_the_front_weight() -> void:
	# missile is the ONLY item with any front weight -- at ratio 0.0 (pure
	# front) it is the entire cumulative table, so every rng_value in [0, 1)
	# must land on it, not just one lucky draw. Each rng_value needs its own
	# fresh slot (start_roll() is a no-op once no longer &"empty").
	for rng_value: float in [0.0, 0.3, 0.6, 0.999]:
		var slot := _new_weighted_slot({MISSILE: 1.0}, {SHIELD: 1.0})
		if slot == null:
			return
		slot.call("start_roll", rng_value, 0.0)
		slot.call("tick", _tuning.roulette_duration_s)
		assert_eq(slot.call("held_item"), MISSILE, "rng_value=%s at ratio 0.0" % rng_value)


func test_weighted_roll_at_back_ratio_uses_only_the_back_weight() -> void:
	for rng_value: float in [0.0, 0.3, 0.6, 0.999]:
		var slot := _new_weighted_slot({MISSILE: 1.0}, {SHIELD: 1.0})
		if slot == null:
			return
		slot.call("start_roll", rng_value, 1.0)
		slot.call("tick", _tuning.roulette_duration_s)
		assert_eq(slot.call("held_item"), SHIELD, "rng_value=%s at ratio 1.0" % rng_value)


func test_weighted_roll_at_a_mid_ratio_linearly_blends_both_weights() -> void:
	# front={missile:1.0}, back={shield:1.0} -- at ratio 0.5 each is blended
	# to weight 0.5, an even 50/50 split of the [0, 1.0) total: rng < 0.5
	# lands on missile (the earlier ITEM_NAMES entry), rng >= 0.5 on shield.
	var below_slot := _new_weighted_slot({MISSILE: 1.0}, {SHIELD: 1.0})
	if below_slot == null:
		return
	below_slot.call("start_roll", 0.4, 0.5)
	below_slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(below_slot.call("held_item"), MISSILE)

	var above_slot := _new_weighted_slot({MISSILE: 1.0}, {SHIELD: 1.0})
	if above_slot == null:
		return
	above_slot.call("start_roll", 0.6, 0.5)
	above_slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(above_slot.call("held_item"), SHIELD)


func test_weighted_roll_ignores_a_zero_weighted_item_entirely() -> void:
	# turbo carries weight at BOTH endpoints but missile only at the front --
	# at ratio 1.0 (pure back), missile's own weight is 0.0 everywhere, so
	# turbo must win the whole table regardless of rng_value.
	var slot := _new_weighted_slot({MISSILE: 1.0, TURBO: 1.0}, {TURBO: 1.0})
	if slot == null:
		return
	slot.call("start_roll", 0.01, 1.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("held_item"), TURBO)


## Defensive robustness, not a real production path (tuning_service.gd's own
## catalog_is_usable() rejects an all-zero-at-any-ratio table before it ever
## reaches a real ItemSlot -- see test_tuning_service.gd's own weight
## validation tests): a fully degenerate (every weight 0.0) table must still
## return SOME item deterministically rather than crash or hand back &"none".
func test_weighted_roll_on_a_fully_degenerate_table_does_not_crash() -> void:
	var slot := _new_weighted_slot({}, {})
	if slot == null:
		return
	slot.call("start_roll", 0.5, 0.5)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(
		slot.call("held_item"),
		TRIPLE_TURBO,
		"a degenerate all-zero table falls through every bucket to the last item"
	)


## Pinned against the REAL, shipped items.tres weight authoring (not a
## synthetic isolated table) -- proves the production tuning actually
## produces a real, computable mapping, worked by hand from the authored
## front weights (missile=1.0, shield=2.0, turbo=1.0, beaker=1.5, bomb=1.0,
## tnt_stick=1.5, triple_turbo=0.5; sum=8.5): rng=0.2 -> target=1.7, which
## falls in shield's own cumulative bucket [1.0, 3.0).
func test_weighted_roll_against_the_real_shipped_tuning_at_the_front() -> void:
	_assert_weighted_rng_maps_to(0.2, 0.0, SHIELD)


## Same real tuning, BACK weights this time (missile=2.5, shield=0.5,
## turbo=1.5, beaker=1.0, bomb=2.0, tnt_stick=1.0, triple_turbo=2.0;
## sum=10.5): rng=0.95 -> target=9.975, which falls in triple_turbo's own
## cumulative bucket [8.5, 10.5) -- the catch-up item is easier to draw at
## the back (this rng_value maps to missile, not triple_turbo, at the FRONT
## ratio -- see the front-tuning test above's own cumulative table) than at
## the front, matching this task's own documented DESIGN RULING.
func test_weighted_roll_against_the_real_shipped_tuning_at_the_back() -> void:
	_assert_weighted_rng_maps_to(0.95, 1.0, TRIPLE_TURBO)


func _assert_weighted_rng_maps_to(
	rng_value: float, position_ratio: float, expected_item: StringName
) -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", rng_value, position_ratio)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(
		slot.call("held_item"),
		expected_item,
		"rng_value=%s at position_ratio=%s must land on %s" % [rng_value, position_ratio, expected_item]
	)


# ---------------------------------------------------------------------------
# CTR R6 Task 5: CHARGES -- &"triple_turbo" carries ItemTuning.triple_turbo_
# charges uses before clearing; every other item is still exactly one-shot.
# ---------------------------------------------------------------------------


func test_charges_remaining_is_zero_while_empty_or_rolling() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	assert_eq(int(slot.call("charges_remaining")), 0, "empty must read zero")
	slot.call("start_roll", 6.0 / 7.0)
	assert_eq(int(slot.call("charges_remaining")), 0, "still rolling must read zero, even though the count is already decided internally")


func test_ordinary_items_still_report_exactly_one_charge_once_held() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("held_item"), MISSILE)
	assert_eq(int(slot.call("charges_remaining")), 1, "a single-use item carries exactly one charge")


func test_triple_turbo_reports_the_full_tuned_charge_count_once_held() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 6.0 / 7.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("held_item"), TRIPLE_TURBO)
	assert_eq(
		int(slot.call("charges_remaining")),
		roundi(_tuning.triple_turbo_charges),
		"a freshly-landed triple_turbo must carry the full tuned charge count"
	)


## The load-bearing state-machine-extension proof: three consecutive use()
## calls on a triple_turbo hand back the item name EVERY time (so the
## caller applies one turbo boost per call, per race_session.gd's own
## dispatch_item_use() doc) and only the THIRD clears the slot back to
## &"empty" -- exactly ItemTuning.triple_turbo_charges (3.0 in the real
## shipped tuning) consecutive uses, never more, never fewer.
func test_triple_turbo_use_returns_the_item_for_every_charge_then_clears_to_empty() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 6.0 / 7.0)
	slot.call("tick", _tuning.roulette_duration_s)
	var charge_count := roundi(_tuning.triple_turbo_charges)
	assert_gt(charge_count, 1, "fixture sanity: the real tuning must author more than one charge")

	for charge_index in range(charge_count - 1):
		assert_eq(
			slot.call("use"),
			TRIPLE_TURBO,
			"charge %d of %d must still hand back the item, not clear early" % [charge_index + 1, charge_count]
		)
		assert_eq(
			slot.call("state"),
			HELD,
			"the slot must stay held between charges"
		)
		assert_eq(
			int(slot.call("charges_remaining")),
			charge_count - charge_index - 1,
			"charges_remaining must count down by exactly one per use()"
		)

	# The FINAL charge: still hands back the item, but now clears to empty.
	assert_eq(slot.call("use"), TRIPLE_TURBO, "the final charge must still hand back the item")
	assert_eq(slot.call("state"), EMPTY, "the final charge must clear the slot back to empty")
	assert_eq(slot.call("held_item"), NONE)
	assert_eq(int(slot.call("charges_remaining")), 0)

	assert_eq(
		slot.call("use"),
		NONE,
		"a fourth use() past the tuned charge count must never hand out the item again"
	)


func test_other_items_are_still_single_use_after_the_charges_extension() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	slot.call("tick", _tuning.roulette_duration_s)
	assert_eq(slot.call("use"), MISSILE, "the first use() of an ordinary item must hand it back")
	assert_eq(slot.call("state"), EMPTY, "unlike triple_turbo, ONE use() must already clear an ordinary item")
	assert_eq(
		slot.call("use"),
		NONE,
		"an ordinary item must never be usable a second time, charges extension or not"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_slot() -> RefCounted:
	var script: Script = load(SLOT_SCRIPT_PATH)
	assert_not_null(script, "ItemSlot implementation must exist")
	if script == null:
		return null
	var slot: RefCounted = script.new()
	slot.call("configure", _tuning)
	return slot


## A slot configured against a SYNTHETIC ItemTuning where every weight_
## front_*/weight_back_* field starts at its Resource default of 0.0, then
## only the entries named in front_weights/back_weights are set -- isolates
## the weighted-mapping tests above from the real items.tres authoring, so
## an outcome can be proven by hand rather than merely observed. roulette_
## duration_s/roulette_tick_s are copied from the real tuning (needed for
## tick()/rolling_display_item() to behave sensibly); triple_turbo_charges
## is also copied so the CHARGES tests below can use this same builder.
func _new_weighted_slot(front_weights: Dictionary, back_weights: Dictionary) -> RefCounted:
	var script: Script = load(SLOT_SCRIPT_PATH)
	assert_not_null(script, "ItemSlot implementation must exist")
	if script == null:
		return null
	var synthetic := ItemTuning.new()
	synthetic.roulette_duration_s = _tuning.roulette_duration_s
	synthetic.roulette_tick_s = _tuning.roulette_tick_s
	synthetic.triple_turbo_charges = _tuning.triple_turbo_charges
	for item_name: StringName in ItemSlot.ITEM_NAMES:
		synthetic.set(
			"weight_front_" + String(item_name), float(front_weights.get(item_name, 0.0))
		)
		synthetic.set(
			"weight_back_" + String(item_name), float(back_weights.get(item_name, 0.0))
		)
	var slot: RefCounted = script.new()
	slot.call("configure", synthetic)
	return slot
