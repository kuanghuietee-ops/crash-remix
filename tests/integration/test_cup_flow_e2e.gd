extends GutTest

## Task 5 (CTR R7, the Cup): the real end-to-end proof -- a real GameRoot
## (main.tscn), a real CUP menu click, two real registered race scenes
## (Sanity Shores then Temple Twilight), each force-finished the same
## "teleport every gate, then the finish gate" way test_main_boot.gd's own
## racing tests already establish (see _force_finish_race() below, copied
## verbatim from that file's own helper -- GUT test scripts do not share
## helpers across files, matching every other *_e2e.gd/test_main_boot.gd
## precedent in this suite). Proves: the CUP menu entry actually boots a
## cup, race 1's finish shows the between-race interstitial with correct
## points, CONTINUE actually advances to race 2 through the SAME registered
## scene an ordinary menu pick would use, race 2's finish shows the final
## podium with the correct winner and save v3 write, retrying INSIDE a cup
## does not corrupt its running totals, and picking an ordinary race from
## the menu abandons a cup in progress.
##
## Isolated in scripts/run_gut.sh's own isolated_suites list, the same
## reason test_main_boot.gd/test_island_slice.gd/test_warp_room.gd already
## are there -- repeatedly instantiating and tearing down the real main
## scene must not leak ResourceLoader/renderer state into shared-process
## suites.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const TEST_SAVE_DIR := "user://test_sandbox/task5_cup_flow_e2e"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_cup_menu_entry_plays_both_races_and_shows_the_final_podium() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	var cup_overlay := root.get_node("UI/CupStandingsOverlay")
	var overlay := await _open_level_list_and_get_overlay(root)

	var cup_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingCup"
	) as Button
	assert_true(
		cup_button.visible,
		"debug builds must expose the CUP entry through the real level list"
	)
	cup_button.pressed.emit()
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"level")
	var race1 := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(
		race1,
		"the cup must launch race 1 (Sanity Shores) through the real registered scene"
	)
	if race1 == null:
		return
	assert_false(cup_overlay.visible)

	await _finish_race(race1)
	await wait_process_frames(1)
	assert_true(bool(race1.call("is_finished")))

	assert_true(
		cup_overlay.visible,
		"the between-race interstitial must show right after race 1's own finish"
	)
	var continue_button := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Continue"
	) as Button
	var close_button := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Close"
	) as Button
	assert_true(continue_button.visible)
	assert_false(close_button.visible)
	var row1 := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Row1"
	) as Label
	assert_true(row1.visible)
	assert_true(
		row1.text.begins_with("> 1. YOU"),
		"the player finished 1st (only kart force-finished) and must be highlighted: got '%s'" % row1.text
	)

	continue_button.pressed.emit()
	await wait_process_frames(1)

	assert_false(
		cup_overlay.visible,
		"CONTINUE must dismiss the interstitial"
	)
	assert_eq(root.call("state_name"), &"level")
	var race2 := root.get_node_or_null("Content/RaceTempleTwilight")
	assert_not_null(
		race2,
		"CONTINUE must advance the cup into race 2 (Temple Twilight) through the real registered scene"
	)
	if race2 == null:
		return

	await _finish_race(race2)
	await wait_process_frames(1)
	assert_true(bool(race2.call("is_finished")))

	assert_true(
		cup_overlay.visible,
		"the final podium must show right after race 2's own finish"
	)
	assert_false(continue_button.visible)
	assert_true(close_button.visible)
	var winner_label := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Winner"
	) as Label
	assert_true(winner_label.visible)
	assert_eq(winner_label.text, "CHAMPION: YOU")
	assert_true(
		row1.text.begins_with("> 1. YOU   16 PTS"),
		"1st (8) + 1st (8) = 16 total points: got '%s'" % row1.text
	)

	var profile: Dictionary = root.get("profile")
	var cup_record := SaveModel.cup_record(profile, &"island_cup")
	assert_eq(
		cup_record.get("best_placement"),
		1,
		"a cup won outright must persist the player's own best placement"
	)
	var stored := SaveService.new().load_profile(TEST_SAVE_DIR)
	assert_eq(
		SaveModel.cup_record(stored, &"island_cup"),
		cup_record,
		"the cup result must actually reach disk, not just memory"
	)

	close_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(cup_overlay.visible, "CLOSE must dismiss the final podium")


## "retry race 1 = restart race 1, cup totals unaffected until finish" --
## driven through the real GameRoot round-trip (request_retry -> GameRoot ->
## a fresh race scene), not just CupSession's own pure unit proof (see
## tests/racing/test_cup_session.gd's own test_retry_overwrites_the_same_
## race_index_instead_of_accumulating for that half in isolation).
func test_retrying_race_one_inside_a_cup_does_not_corrupt_the_running_total() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	var cup_overlay := root.get_node("UI/CupStandingsOverlay")
	var overlay := await _open_level_list_and_get_overlay(root)
	var cup_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingCup"
	) as Button
	cup_button.pressed.emit()
	await wait_process_frames(1)

	var race1_first := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(race1_first)
	if race1_first == null:
		return
	await _finish_race(race1_first)
	await wait_process_frames(1)
	var row1 := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Row1"
	) as Label
	assert_true(
		row1.text.begins_with("> 1. YOU   8 PTS"),
		"sanity: the first attempt recorded a win: got '%s'" % row1.text
	)

	# The player retries race 1 INSTEAD of continuing -- a fresh race scene,
	# same track, same cup untouched (see cup_session.gd's own RETRY
	# SEMANTICS doc). The instance id is captured BEFORE request_retry() --
	# retry frees this node (see _clear_content()), so reading it off
	# race1_first afterward would hit a freed instance.
	var race1_first_id := race1_first.get_instance_id()
	race1_first.call("request_retry")
	await wait_process_frames(1)
	assert_eq(root.call("state_name"), &"level")
	var race1_retry := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(race1_retry)
	if race1_retry == null:
		return
	assert_ne(
		race1_retry.get_instance_id(),
		race1_first_id,
		"retry must reinstantiate the race scene, not reuse the old one"
	)
	assert_false(
		cup_overlay.visible,
		"a mid-cup retry must not itself pop any cup screen"
	)

	await _finish_race(race1_retry)
	await wait_process_frames(1)

	assert_true(cup_overlay.visible)
	assert_true(
		row1.text.begins_with("> 1. YOU   8 PTS"),
		"the retried finish must REPLACE the abandoned attempt, not add to it: got '%s'" % row1.text
	)


## Picking an ordinary racing-menu entry abandons a cup in progress -- see
## game_root.gd's own _abandon_active_cup() doc for why this matters even
## when the ordinary pick lands on the exact track the cup was waiting on.
func test_picking_an_ordinary_race_from_the_menu_abandons_an_active_cup() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	var cup_overlay := root.get_node("UI/CupStandingsOverlay")
	var overlay := await _open_level_list_and_get_overlay(root)
	var cup_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingCup"
	) as Button
	cup_button.pressed.emit()
	await wait_process_frames(1)
	var race1 := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(race1)
	if race1 == null:
		return

	# The player quits back to the hub mid-race (never finishing race 1) and
	# picks the ORDINARY "RACE — SANITY SHORES" menu entry instead of
	# continuing the cup.
	root.call("dispatch", {"type": &"quit_level"})
	await wait_process_frames(1)
	var overlay_again := await _open_level_list_and_get_overlay(root)
	var ordinary_button := overlay_again.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingSanityShores"
	) as Button
	ordinary_button.pressed.emit()
	await wait_process_frames(1)

	var ordinary_race := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(ordinary_race)
	if ordinary_race == null:
		return
	await _finish_race(ordinary_race)
	await wait_process_frames(1)

	assert_false(
		cup_overlay.visible,
		"an ordinarily-launched race finish must never be mistaken for cup progress"
	)


## Task 7 (CTR R7, integration + verification): the REAL whole-Cup story,
## through the REAL 3-2-1-GO countdown (not the `_tick_countdown(1000.0)`
## skip every other test in this file uses) for race 1, proving two of this
## phase's own new mechanics fire for real inside that real race before it
## teleport-finishes the same way the rest of this suite does: a real
## overlap with Sanity Shores' own authored `BoostStripHome` pad (Task 4
## retrofit) reaching the real KartMotor, and a real move_and_slide contact
## between two real AI karts producing a real, non-zero `bump_count()` on
## at least one side (Task 2's own kart-to-kart contact). Race 2 (Temple
## Twilight) then plays out the same teleport-finish way the rest of this
## file already establishes -- the countdown/pad/bump proof only needs to
## happen once, in a real race, to demonstrate the whole real GameRoot flow
## carries every R7 feature live; repeating it a second time on Temple
## would not prove anything new (see task-3/4's own reports for Temple's
## own pad-trajectory and lint proofs already covering that track in
## isolation). Ends with the same final-podium/save-write proof
## test_cup_menu_entry_plays_both_races_and_shows_the_final_podium already
## established, plus an explicit zero-error-spam assertion (this suite's
## own GUT error_tracker already fails a test on any unhandled push_error/
## engine-error by default -- this makes that contract visible rather than
## relying on it silently, the same convention test_race_flow_r6_e2e.gd's
## own step 8 established).
func test_full_r7_cup_run_through_a_real_countdown_fires_a_real_pad_and_exchanges_a_real_bump() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	var cup_overlay := root.get_node("UI/CupStandingsOverlay")
	var overlay := await _open_level_list_and_get_overlay(root)
	var cup_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingCup"
	) as Button
	cup_button.pressed.emit()
	await wait_process_frames(1)

	var race1 := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(
		race1,
		"the cup must launch race 1 (Sanity Shores) through the real registered scene"
	)
	if race1 == null:
		return

	# ------------------------------------------------------------------
	# 1. REAL 3-2-1-GO countdown, ticked through real physics frames --
	# not skipped. Every kart (player + AI) stays frozen (set_run_active
	# false) until this resolves, per race_session.gd's own COUNTDOWN +
	# START BOOST class-doc section.
	# ------------------------------------------------------------------
	assert_eq(race1.call("countdown_phase"), &"three", "fixture setup: countdown starts at three")
	assert_false(bool(race1.call("is_race_started")))
	await _wait_until_race_started(race1)
	assert_almost_eq(
		float(race1.call("elapsed_s")),
		0.0,
		0.05,
		"the race timer must read essentially zero right at GO"
	)

	# ------------------------------------------------------------------
	# 2. A REAL boost pad fire (Task 1/4): the player kart overlaps
	# Sanity Shores' own authored BoostStripHome retrofit pad and the
	# real Area3D body_entered signal must reach the real KartMotor.
	# ------------------------------------------------------------------
	var kart := race1.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	var boost_pad := race1.get_node_or_null("Track/Pads/BoostStripHome") as Area3D
	assert_not_null(
		boost_pad,
		"fixture setup: Sanity Shores must author its own Task 4 retrofit boost pad"
	)
	if motor != null and boost_pad != null:
		assert_false(bool(motor.call("is_boosting")), "fixture sanity: no boost yet")
		kart.set_physics_process(false)
		kart.global_position = boost_pad.global_position
		await wait_physics_frames(2)
		assert_true(
			bool(motor.call("is_boosting")),
			"a real overlap with a real, authored boost pad in a real race must boost the real motor"
		)
		kart.set_physics_process(true)

	# ------------------------------------------------------------------
	# 3. A REAL kart-to-kart bump (Task 2): two real AI karts forced into
	# overlap (position only -- yaw untouched, same "still races the
	# correct way" technique test_kart_bump_proof_r7.gd's own tight-grid
	# proof uses) and left driving real physics must exchange a real,
	# non-zero bump_count() through the real post-move_and_slide contact
	# path.
	#
	# Fix round 1 (review [MEDIUM]): a 60-frame wait was flaky (~29%
	# failure across 7 standalone runs) -- right at GO both AI karts
	# accelerate from rest in the SAME direction, so the relative closing
	# speed that actually produces a bump only crosses
	# bump_min_relative_speed_mps once the pair's own overlap window and
	# speed-ramp window happen to coincide, which a mere 1s (60 frames)
	# does not reliably reach (measured: 60f/180f -> 1 bump, marginal;
	# 600f -> 63-64 bumps, reliably well clear of the gate). Widened to
	# 600 frames -- test-only, no product change; the two karts' own
	# accelerate-from-rest-together behavior is real AiDriver output, not
	# a fixture artifact, so giving it enough real time to close is the
	# honest fix, not a lowered bar.
	# ------------------------------------------------------------------
	var opponent_count := int(race1.call("ai_kart_count"))
	assert_gt(opponent_count, 1, "fixture sanity: at least two AI karts must be racing")
	var kart_a := race1.call("ai_kart", 0) as CharacterBody3D
	var kart_b := race1.call("ai_kart", 1) as CharacterBody3D
	assert_not_null(kart_a)
	assert_not_null(kart_b)
	if kart_a != null and kart_b != null:
		var midpoint := (kart_a.global_position + kart_b.global_position) * 0.5
		kart_a.global_position = midpoint + Vector3(0.3, 0.0, 0.0)
		kart_b.global_position = midpoint - Vector3(0.3, 0.0, 0.0)
		await wait_physics_frames(600)
		var total_bumps := int(kart_a.call("bump_count")) + int(kart_b.call("bump_count"))
		assert_gt(
			total_bumps,
			0,
			"two AI karts forced into real contact in a real race must exchange a real bump"
		)

	# ------------------------------------------------------------------
	# 4. Teleport-finish race 1 the same way the rest of this file does,
	# then run the whole Cup through to the final podium and save write.
	# ------------------------------------------------------------------
	await _finish_race(race1)
	await wait_process_frames(1)
	assert_true(bool(race1.call("is_finished")))

	assert_true(
		cup_overlay.visible,
		"the between-race interstitial must show right after race 1's own finish"
	)
	var continue_button := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Continue"
	) as Button
	continue_button.pressed.emit()
	await wait_process_frames(1)

	assert_false(cup_overlay.visible, "CONTINUE must dismiss the interstitial")
	var race2 := root.get_node_or_null("Content/RaceTempleTwilight")
	assert_not_null(
		race2,
		"CONTINUE must advance the cup into race 2 (Temple Twilight) through the real registered scene"
	)
	if race2 == null:
		return

	await _finish_race(race2)
	await wait_process_frames(1)
	assert_true(bool(race2.call("is_finished")))

	assert_true(
		cup_overlay.visible,
		"the final podium must show right after race 2's own finish"
	)
	var close_button := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Close"
	) as Button
	var winner_label := cup_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Winner"
	) as Label
	assert_true(winner_label.visible)
	assert_eq(winner_label.text, "CHAMPION: YOU")

	var profile: Dictionary = root.get("profile")
	var cup_record := SaveModel.cup_record(profile, &"island_cup")
	assert_eq(
		cup_record.get("best_placement"),
		1,
		"a cup won outright must persist the player's own best placement"
	)
	var stored := SaveService.new().load_profile(TEST_SAVE_DIR)
	assert_eq(
		SaveModel.cup_record(stored, &"island_cup"),
		cup_record,
		"the cup result must actually reach disk, not just memory"
	)

	close_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(cup_overlay.visible, "CLOSE must dismiss the final podium")

	# ------------------------------------------------------------------
	# 5. NO ERROR SPAM across the whole real countdown+pad+bump+cup run.
	# ------------------------------------------------------------------
	assert_eq(
		get_errors().size(),
		0,
		"zero push_error/engine-error calls must occur across the whole real R7 cup run"
	)


## Frame-exact "wait for real GO" -- the same shape test_race_flow_r6_e2e.gd's
## own copy establishes (itself mirroring test_race_start_flow.gd's own
## _wait_until_race_started()); GUT test scripts don't share private helpers
## across files (established convention, see that file's own identical
## note), so this is a local copy, not a reach into another suite's file.
func _wait_until_race_started(race: Node) -> void:
	var physics_fps := float(Engine.physics_ticks_per_second)
	var max_frames := int(ceil(_catalog.race.countdown_step_s * physics_fps)) * 10
	var frames_waited := 0
	while not bool(race.call("is_race_started")) and frames_waited < max_frames:
		await wait_physics_frames(1)
		frames_waited += 1
	assert_true(
		bool(race.call("is_race_started")),
		"fixture setup: the real countdown must reach GO within a generous bound"
	)


func _open_level_list_and_get_overlay(root: Node) -> Node:
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)
	return root.get_node("UI/LevelListOverlay")


## Same shape test_main_boot.gd's own _force_finish_race() uses (see that
## file for the original): skip the pre-race countdown, let a few physics
## ticks accumulate a real, non-zero elapsed_s(), then teleport-cross every
## gate in order for every lap plus the finish gate. AI karts are left at
## their spawn (never driven), which is fine here -- CupSession only needs a
## real, ordered standings() result, and an unfinished AI kart still gets a
## real (worse) placement ranked by progress (see race_ranking.gd's own
## tier ordering), never a crash or a missing entry.
func _finish_race(race: Node) -> void:
	race.call("_tick_countdown", 1000.0)
	await wait_physics_frames(10)
	var kart := race.get_node("Kart")
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	for _lap: int in range(lap_count):
		for gate_index: int in range(gate_count):
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


func _instantiate_main() -> Node:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	return root


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_recursive(absolute)


func _remove_recursive(absolute_path: String) -> void:
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child_path := absolute_path.path_join(entry)
			if dir.current_is_dir():
				_remove_recursive(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
