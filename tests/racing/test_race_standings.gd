extends GutTest

# R5 Task 3: session-level coverage for RaceSession.standings() -- the full
# results list race_hud.gd's own finish panel reads for a race (see that
# method's own doc for the ordering/label/is_player contract: finished karts
# first by finish order with real times, then unfinished karts by the live
# RaceRanking composite, labels are "YOU"/"CPU n" BY SLOT, one entry flagged
# is_player for the HUD's own row highlight). The pure composite-sort
# contract itself is test_race_ranking.gd's own job; this file proves the
# real scene wiring, the same "boot the real scene, drive it via its real
# API" shape test_race_live_position.gd already established for R5 Task 2.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func _catalog_with_opponent_count(count: int) -> GameplayTuning:
	var variant: GameplayTuning = _catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	variant.ai.opponent_count = float(count)
	return variant


## Same shape as test_race_live_position.gd's own _boot_race() -- GUT test
## scripts don't share private helpers across files.
func _boot_race(catalog: GameplayTuning) -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", catalog)
	race.call("_tick_countdown", 1000.0)
	return race


## Same technique test_race_live_position.gd's own _cross_all_gates_for_kart()
## uses -- drives a kart to a real race_complete through the session's own
## private gate-crossing handler rather than a real Area3D overlap.
func _cross_all_gates_for_kart(
	race: Node, kart: Node, lap_count: int, gate_count: int
) -> void:
	for _lap in range(lap_count):
		for gate_index in range(gate_count):
			race.call(
				"_on_gate_body_entered",
				kart,
				race.get_node("Track/Gates/Gate%d" % gate_index)
			)
	race.call(
		"_on_gate_body_entered",
		kart,
		race.get_node("Track/Gates/Gate0")
	)


func test_standings_is_empty_before_configure() -> void:
	var packed := load(RACE_SCENE_PATH) as PackedScene
	var race := packed.instantiate()
	add_child_autofree(race)
	# Deliberately no configure() call.
	assert_eq(race.call("standings"), [])


# ---------------------------------------------------------------------------
# 2 finished (in finish order, with real times) + 3 unfinished (ranked by
# progress), labels right by SLOT, and exactly one is_player flag.
# ---------------------------------------------------------------------------


func test_standings_orders_finished_by_finish_order_then_unfinished_by_progress() -> void:
	var race := _boot_race(_catalog_with_opponent_count(4))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	await wait_physics_frames(2)

	# Freeze the player's own kart so its total_progress_m stays pinned --
	# see test_race_live_position.gd's own six-kart arrangement test for the
	# identical rationale (karts auto-throttle forward under their own
	# set_run_active(true) motor tick otherwise).
	kart.set_physics_process(false)
	var player_progress := float(race.call("player_total_progress_m"))

	var ai_karts: Array[CharacterBody3D] = []
	for index in range(4):
		var ai_kart := race.call("ai_kart", index) as CharacterBody3D
		assert_not_null(ai_kart, "fixture setup: AI slot %d must exist" % index)
		if ai_kart == null:
			return
		ai_karts.append(ai_kart)

	# AI slot 0 ("CPU 1") finishes BEFORE the player -- its own finish_order
	# must land 1, ahead of the player's own 2, even though it is the LOWEST
	# indexed slot.
	_cross_all_gates_for_kart(race, ai_karts[0], lap_count, gate_count)
	await wait_physics_frames(2)
	assert_eq(
		int(race.call("finish_order_of", ai_karts[0])),
		1,
		"fixture setup: AI slot 0 must have finished first"
	)

	# Seed AI slots 1-3's own progress relative to the player, descending:
	# slot 1 furthest ahead, slot 3 furthest behind -- none of them ever
	# cross a gate, so laps_complete/gates_this_lap tie at 0 for all three
	# and RaceRanking's own tier-5 total_progress_m tiebreak alone decides
	# their order.
	var offsets_m: Array[float] = [30.0, 10.0, -20.0]
	for offset_index in range(offsets_m.size()):
		var ai_kart := ai_karts[offset_index + 1]
		var agent: Object = race.call("ai_agent", offset_index + 1)
		assert_not_null(agent)
		if agent == null:
			return
		(agent as Node).set_physics_process(false)
		var follower: RefCounted = agent.get("_follower")
		assert_not_null(follower)
		if follower == null:
			return
		follower.reset(player_progress + offsets_m[offset_index])

	# The player finishes second.
	_cross_all_gates_for_kart(race, kart, lap_count, gate_count)
	await wait_physics_frames(2)
	assert_true(bool(race.call("is_finished")))
	assert_eq(int(race.call("finish_order_of", kart)), 2)

	var standings: Array = race.call("standings")
	assert_eq(standings.size(), 5, "1 player + 4 AI karts")

	var first: Dictionary = standings[0]
	assert_eq(int(first.get("position")), 1)
	assert_eq(String(first.get("label")), "CPU 1", "labeled by SLOT, not by live rank")
	assert_true(bool(first.get("finished")))
	assert_false(bool(first.get("is_player")))
	assert_eq(
		float(first.get("elapsed_s")),
		float(race.call("finish_elapsed_s_of", ai_karts[0])),
		"a finished kart's own standings elapsed_s must match finish_elapsed_s_of()"
	)

	var second: Dictionary = standings[1]
	assert_eq(int(second.get("position")), 2)
	assert_eq(String(second.get("label")), "YOU")
	assert_true(bool(second.get("finished")))
	assert_true(bool(second.get("is_player")), "the player's own row must expose is_player true")
	assert_eq(
		float(second.get("elapsed_s")),
		float(race.call("finish_elapsed_s_of", kart)),
	)
	assert_gt(
		float(second.get("elapsed_s")),
		float(first.get("elapsed_s")),
		"fixture sanity: the player finished strictly after AI slot 0"
	)

	# Unfinished karts: slot 1 (+30) ahead of slot 2 (+10) ahead of slot 3
	# (-20), by total_progress_m alone.
	var third: Dictionary = standings[2]
	assert_eq(int(third.get("position")), 3)
	assert_eq(String(third.get("label")), "CPU 2")
	assert_false(bool(third.get("finished")))
	assert_false(bool(third.get("is_player")))
	assert_eq(float(third.get("elapsed_s")), 0.0, "an unfinished kart must show no time")

	var fourth: Dictionary = standings[3]
	assert_eq(int(fourth.get("position")), 4)
	assert_eq(String(fourth.get("label")), "CPU 3")
	assert_false(bool(fourth.get("finished")))

	var fifth: Dictionary = standings[4]
	assert_eq(int(fifth.get("position")), 5)
	assert_eq(String(fifth.get("label")), "CPU 4")
	assert_false(bool(fifth.get("finished")))

	# Exactly one is_player row, and it belongs to the player.
	var player_rows := 0
	for entry: Variant in standings:
		if bool((entry as Dictionary).get("is_player")):
			player_rows += 1
	assert_eq(player_rows, 1, "exactly one standings row may be flagged is_player")


func test_standings_labels_every_solo_kart_you_alone() -> void:
	var race := _boot_race(_catalog_with_opponent_count(0))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	_cross_all_gates_for_kart(race, kart, lap_count, gate_count)
	await wait_physics_frames(2)

	var standings: Array = race.call("standings")
	assert_eq(standings.size(), 1)
	var only: Dictionary = standings[0]
	assert_eq(int(only.get("position")), 1)
	assert_eq(String(only.get("label")), "YOU")
	assert_true(bool(only.get("is_player")))
	assert_true(bool(only.get("finished")))


# ---------------------------------------------------------------------------
# HUD wiring: race_hud.gd's own finish panel actually reads RaceSession.
# standings() for a race, and leaves the solo panel exactly as it was before
# this task (existing solo behavior is the control -- these two prove the
# scene-level wiring, not the pure standings() contract already covered
# above).
# ---------------------------------------------------------------------------


func test_hud_finish_panel_shows_standings_and_hides_splits_in_a_race() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	_cross_all_gates_for_kart(race, kart, lap_count, gate_count)
	await wait_process_frames(1)
	assert_true(bool(race.call("is_finished")))

	var hud := race.get_node("UI/RaceHUD")
	var standings_label := hud.get_node(
		"SafeArea/FinishPanel/Margin/Rows/Standings"
	) as Label
	var splits_label := hud.get_node(
		"SafeArea/FinishPanel/Margin/Rows/Splits"
	) as Label
	assert_true(
		standings_label.visible,
		"a race's own finish panel must show the standings list"
	)
	assert_false(
		splits_label.visible,
		"a race's own finish panel must hide the old per-lap splits list"
	)
	assert_true(
		standings_label.text.contains("YOU"),
		"the standings text must include the player's own labeled row"
	)
	assert_true(
		standings_label.text.contains("CPU 1"),
		"the standings text must include the AI kart's own labeled row"
	)


func test_hud_solo_finish_panel_keeps_splits_and_hides_standings() -> void:
	var race := _boot_race(_catalog_with_opponent_count(0))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	_cross_all_gates_for_kart(race, kart, lap_count, gate_count)
	await wait_process_frames(1)
	assert_true(bool(race.call("is_finished")))

	var hud := race.get_node("UI/RaceHUD")
	var standings_label := hud.get_node(
		"SafeArea/FinishPanel/Margin/Rows/Standings"
	) as Label
	var splits_label := hud.get_node(
		"SafeArea/FinishPanel/Margin/Rows/Splits"
	) as Label
	assert_false(
		standings_label.visible,
		"a solo time trial has nobody to stand against -- standings must stay hidden"
	)
	assert_true(
		splits_label.visible,
		"solo's own per-lap splits list must render exactly as before this task"
	)
	assert_true(
		splits_label.text.begins_with("LAP 1"),
		"solo's own per-lap splits text must be unchanged"
	)
