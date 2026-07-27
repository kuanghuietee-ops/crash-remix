extends GutTest

const BossFightFlowType := preload("res://src/gameplay/boss/boss_fight_flow.gd")
const INPUT_INTENT_SCRIPT_PATH := "res://src/gameplay/input/input_intent.gd"
const BOSS_TUNING_PATH := "res://data/tuning/boss_papu.tres"


func _authored_tuning() -> BossTuning:
	var tuning := load(BOSS_TUNING_PATH) as BossTuning
	assert_not_null(tuning, "the authored boss tuning must load")
	return tuning


func _flow(overrides: Dictionary = {}) -> BossFightFlowType:
	var tuning := _authored_tuning()
	if tuning == null:
		return null
	var tuned := tuning.duplicate(true) as BossTuning
	for field: String in overrides:
		tuned.set(field, overrides[field])
	var flow: BossFightFlowType = BossFightFlowType.new()
	flow.configure(tuned)
	return flow


func test_a_configured_fight_starts_on_the_first_phase_with_no_strikes() -> void:
	var flow := _flow()
	if flow == null:
		return

	assert_eq(flow.current_phase(), 1)
	assert_eq(flow.strikes_this_phase(), 0)
	assert_false(flow.is_defeated())


func test_the_tuned_number_of_strikes_advances_a_phase() -> void:
	# Authored value is 1, so a production constant of 1 would pass any test
	# written against the authored resource. Override to 2 to reject it.
	var flow := _flow({"arena_strikes_per_phase": 2})
	if flow == null:
		return

	flow.register_strike()

	assert_eq(
		flow.current_phase(),
		1,
		"one strike of two must not advance the phase"
	)
	assert_eq(flow.strikes_this_phase(), 1)

	flow.register_strike()

	assert_eq(flow.current_phase(), 2, "the second strike advances")
	assert_eq(
		flow.strikes_this_phase(),
		0,
		"strikes reset when a new phase opens"
	)


func test_the_fight_lasts_the_tuned_number_of_phases() -> void:
	# Authored phase_count is 3 [spec §8.2]; override to 2 so an inlined 3
	# cannot pass.
	var flow := _flow({"phase_count": 2, "arena_strikes_per_phase": 1})
	if flow == null:
		return

	flow.register_strike()
	assert_eq(flow.current_phase(), 2)
	assert_false(flow.is_defeated(), "two phases means two, not one")

	flow.register_strike()

	assert_true(flow.is_defeated(), "striking the last phase ends the fight")


func test_death_restarts_the_current_phase_only() -> void:
	# Executed, not asserted about: reach phase 2, bank a strike, die.
	var flow := _flow({"phase_count": 3, "arena_strikes_per_phase": 2})
	if flow == null:
		return
	flow.register_strike()
	flow.register_strike()
	assert_eq(flow.current_phase(), 2, "precondition: the fight reached phase 2")
	flow.register_strike()
	assert_eq(flow.strikes_this_phase(), 1, "precondition: one strike banked")

	flow.on_player_death()

	assert_eq(
		flow.current_phase(),
		2,
		"death must not send the player back to phase 1 [spec §8.2]"
	)
	assert_eq(
		flow.strikes_this_phase(),
		0,
		"the phase restarts, so its banked strikes are lost"
	)
	assert_false(flow.is_defeated())


func test_the_checkpoint_follows_the_current_phase() -> void:
	# §8.2: a checkpoint per phase.
	var flow := _flow({"phase_count": 3, "arena_strikes_per_phase": 1})
	if flow == null:
		return

	assert_eq(flow.checkpoint_phase(), 1)

	flow.register_strike()

	assert_eq(
		flow.checkpoint_phase(),
		2,
		"clearing a phase must move the checkpoint with it"
	)


func test_defeat_is_terminal() -> void:
	# Two strikes per phase on purpose. With one, a post-victory strike merely
	# re-asserts defeat and the guard is unobservable -- the assertion would be
	# vacuous. With two, a missing guard banks a strike on a won fight.
	var flow := _flow({"phase_count": 1, "arena_strikes_per_phase": 2})
	if flow == null:
		return
	flow.register_strike()
	flow.register_strike()
	assert_true(flow.is_defeated(), "precondition: the fight is won")

	flow.register_strike()

	assert_true(flow.is_defeated(), "a defeated boss stays defeated")
	assert_eq(
		flow.strikes_this_phase(),
		0,
		"a won fight must not accumulate strikes"
	)
	assert_eq(
		flow.current_phase(),
		1,
		"strikes after victory must not run off the end of the fight"
	)


func test_death_after_defeat_cannot_revive_the_boss() -> void:
	var flow := _flow({"phase_count": 1, "arena_strikes_per_phase": 1})
	if flow == null:
		return
	flow.register_strike()

	flow.on_player_death()

	assert_true(flow.is_defeated(), "a won fight cannot be un-won by dying")


func test_slams_repeat_on_the_tuned_period() -> void:
	var flow := _flow({"slam_period_s": 2.5})
	if flow == null:
		return

	assert_eq(flow.slam_count_by(0.0), 0)
	assert_eq(flow.slam_count_by(2.4), 0, "no slam before the period elapses")
	assert_eq(flow.slam_count_by(2.5), 1)
	assert_eq(flow.slam_count_by(5.0), 2, "slams repeat, they do not fire once")


func test_debris_is_harmless_during_its_telegraph() -> void:
	# §4.14: debris is blob-shadow telegraphed for debris_telegraph_s before
	# it can kill, so a death is always something the player could read.
	var flow := _flow({"debris_telegraph_s": 0.8})
	if flow == null:
		return

	assert_false(flow.debris_is_lethal(0.0))
	assert_false(
		flow.debris_is_lethal(0.79),
		"debris must not kill inside its own telegraph"
	)
	assert_true(flow.debris_is_lethal(0.8))


func test_the_fight_adds_no_new_player_verb() -> void:
	# §8.2: the gauntlet uses standard verbs only, and §5.2 caps the right
	# thumb at four buttons. If Papu needed a fifth action, it would show up
	# here.
	# Collected as String: StringName comparison is by hash, not alphabetical.
	var actions: Array[String] = []
	var input_intent_script := load(INPUT_INTENT_SCRIPT_PATH) as GDScript
	assert_not_null(input_intent_script)
	if input_intent_script == null:
		return
	var constants: Dictionary = (
		input_intent_script.get_script_constant_map()
	)
	for name_value: Variant in constants:
		var constant_name := String(name_value)
		if constant_name.begins_with("ACTION_"):
			actions.append(String(constants[name_value]))
	actions.sort()

	assert_eq(
		actions,
		(["down", "jump", "move", "phase", "spin"] as Array[String]),
		"the boss fight must not add a player action"
	)
