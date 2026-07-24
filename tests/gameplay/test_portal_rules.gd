extends GutTest

const PORTAL_RULES_PATH := "res://src/gameplay/hub/portal_rules.gd"
const LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
	&"wr1_boulders",
	&"wr1_hog_wild",
]
const AVAILABLE_LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
]
const BOSS_ID := &"wr1_papu_papu"


func test_fresh_profile_opens_only_built_levels_and_locks_boss() -> void:
	var rules := _rules()
	if rules == null:
		return
	var profile := SaveModel.fresh()

	for level_id: StringName in LEVEL_IDS:
		var state: Dictionary = rules.call(
			"state_for",
			level_id,
			profile,
			AVAILABLE_LEVEL_IDS
		)
		assert_eq(
			state.get("unlocked", false),
			level_id in AVAILABLE_LEVEL_IDS,
			"%s availability must follow the scene registry" % level_id
		)
		assert_eq(state.get("kind"), &"level")
		assert_false(state.get("completed", true))

	var boss_state: Dictionary = rules.call(
		"state_for",
		BOSS_ID,
		profile,
		AVAILABLE_LEVEL_IDS
	)
	assert_eq(boss_state.get("kind"), &"boss")
	assert_false(boss_state.get("unlocked", true))


func test_boss_unlocks_only_after_all_three_levels_are_completed() -> void:
	var rules := _rules()
	if rules == null:
		return
	var profile := SaveModel.fresh()

	_set_completed(profile, LEVEL_IDS[0])
	_set_completed(profile, LEVEL_IDS[1])
	assert_false(
		rules.call("boss_unlocked", profile),
		"two clears must not unlock Papu Papu"
	)
	assert_false(
		(
			rules.call(
				"state_for",
				BOSS_ID,
				profile,
				AVAILABLE_LEVEL_IDS
			)
			as Dictionary
		).get("unlocked", true)
	)

	_set_completed(profile, LEVEL_IDS[2])
	assert_true(
		rules.call("boss_unlocked", profile),
		"the third distinct level clear must unlock Papu Papu"
	)
	assert_true(
		(
			rules.call(
				"state_for",
				BOSS_ID,
				profile,
				AVAILABLE_LEVEL_IDS
			)
			as Dictionary
		).get("unlocked", false)
	)


func test_level_portal_state_reflects_gem_relic_and_flawless_save_data() -> void:
	var rules := _rules()
	if rules == null:
		return
	var profile := SaveModel.fresh()
	var record := SaveModel.level_record(profile, LEVEL_IDS[0])
	record["completed"] = true
	record["gem"] = true
	record["relic_tier"] = "gold"
	record["best_relic_time_ms"] = 54321
	record["flawless"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(LEVEL_IDS[0])] = record

	var state: Dictionary = rules.call(
		"state_for",
		LEVEL_IDS[0],
		profile,
		AVAILABLE_LEVEL_IDS
	)

	assert_true(state.get("unlocked", false))
	assert_true(state.get("completed", false))
	assert_true(state.get("gem", false))
	assert_eq(state.get("relic_tier"), &"gold")
	assert_true(state.get("flawless", false))


func test_unknown_portal_is_closed_instead_of_defaulting_open() -> void:
	var rules := _rules()
	if rules == null:
		return

	var state: Dictionary = rules.call(
		"state_for",
		&"not_authored",
		SaveModel.fresh(),
		AVAILABLE_LEVEL_IDS
	)

	assert_false(state.get("unlocked", true))
	assert_eq(state.get("kind"), &"unknown")


func _rules() -> Script:
	assert_true(
		ResourceLoader.exists(PORTAL_RULES_PATH),
		"Task 15 must provide the pure portal rules"
	)
	if not ResourceLoader.exists(PORTAL_RULES_PATH):
		return null
	var script := load(PORTAL_RULES_PATH) as Script
	assert_not_null(script)
	return script


func _set_completed(profile: Dictionary, level_id: StringName) -> void:
	var record := SaveModel.level_record(profile, level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(level_id)] = record
