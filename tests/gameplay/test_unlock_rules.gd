extends GutTest

const UNLOCK_RULES_PATH := (
	"res://src/gameplay/progression/unlock_rules.gd"
)
const ISLAND_CUT_LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
	&"wr1_boulders",
	&"wr1_hog_wild",
]


func test_fresh_save_keeps_phase_locked() -> void:
	var rules := _rules()
	if rules == null:
		return

	assert_false(
		rules.call("phase_unlocked", SaveModel.fresh())
	)


func test_every_island_cut_clear_still_keeps_phase_locked() -> void:
	var rules := _rules()
	if rules == null:
		return
	var profile := SaveModel.fresh()
	for level_id: StringName in ISLAND_CUT_LEVEL_IDS:
		_set_completed(profile, level_id, true)
	var boss: Dictionary = profile["boss_defeated"]
	boss["papu_papu"] = true

	assert_false(rules.call("phase_unlocked", profile))


func test_completed_warp_room_four_level_unlocks_phase() -> void:
	var rules := _rules()
	if rules == null:
		return
	var profile := SaveModel.fresh()
	var future_level_id := &"wr4_future_fixture"
	_set_completed(profile, future_level_id, false)
	assert_false(rules.call("phase_unlocked", profile))

	_set_completed(profile, future_level_id, true)
	assert_true(
		rules.call("phase_unlocked", profile),
		"a real wr4 completion must falsify a hardcoded false rule"
	)


func _rules() -> Script:
	assert_true(
		ResourceLoader.exists(UNLOCK_RULES_PATH),
		"Task 16 must provide pure progression unlock rules"
	)
	if not ResourceLoader.exists(UNLOCK_RULES_PATH):
		return null
	var script := load(UNLOCK_RULES_PATH) as Script
	assert_not_null(script)
	return script


func _set_completed(
	profile: Dictionary,
	level_id: StringName,
	completed: bool
) -> void:
	var record := SaveModel.level_record(profile, level_id)
	record["completed"] = completed
	var levels: Dictionary = profile["levels"]
	levels[String(level_id)] = record
