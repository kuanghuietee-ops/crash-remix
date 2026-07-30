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
# start_roll(): four-way RNG mapping + exact-boundary/1.0 guard.
# ---------------------------------------------------------------------------


func test_start_roll_transitions_empty_to_rolling() -> void:
	var slot := _new_slot()
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), ROLLING)


func test_rng_value_zero_maps_to_the_first_item_missile() -> void:
	_assert_rng_maps_to(0.0, MISSILE)


func test_rng_value_just_under_one_quarter_maps_to_missile() -> void:
	_assert_rng_maps_to(0.249, MISSILE)


func test_rng_value_at_one_quarter_maps_to_the_second_item_shield() -> void:
	_assert_rng_maps_to(0.25, SHIELD)


func test_rng_value_at_one_half_maps_to_the_third_item_turbo() -> void:
	_assert_rng_maps_to(0.5, TURBO)


func test_rng_value_at_three_quarters_maps_to_the_fourth_item_beaker() -> void:
	_assert_rng_maps_to(0.75, BEAKER)


func test_rng_value_just_under_one_maps_to_the_fourth_item_beaker() -> void:
	_assert_rng_maps_to(0.999, BEAKER)


## Exact-1.0 guard: floor(1.0 * 4) = 4, one past the last valid index (0-3)
## -- must clamp back to the last item (beaker) rather than index out of
## bounds. rng_value = 1.0 is out of RandomNumberGenerator.randf()'s own
## documented [0, 1) range, but start_roll() stays a pure function of its
## input and must not crash on it.
func test_rng_value_of_exactly_one_clamps_to_the_last_item_not_out_of_bounds() -> void:
	_assert_rng_maps_to(1.0, BEAKER)


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
	assert_eq(slot.call("held_item"), TURBO)


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
	assert_eq(
		slot.call("rolling_display_item"),
		MISSILE,
		"a fourth tick interval must wrap back around to the first item"
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

	assert_eq(used, TURBO)
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

	assert_eq(slot.call("held_item"), BEAKER, "a fresh roll after use() must work normally")


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
