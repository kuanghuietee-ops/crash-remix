extends GutTest

## Task 9 (CTR R8, characters/select/classes): the brief's own whole-story
## E2E -- select Papu through the REAL Driver Select overlay tile (not
## SKIP), race a full 2-race Cup (a real 3-2-1-GO countdown for race 1,
## both races teleport-finished the same way every other cup e2e in this
## suite already does -- see test_cup_flow_e2e.gd's own _finish_race()),
## through the between-race interstitial and the final podium, then a
## FRESH GameRoot boot off the SAME save_dir (standing in for relaunching
## the app) that reads racing.selected_driver back off disk and mounts
## papu's own seated model again on the very first race it launches,
## without the player re-picking anything.
##
## What earlier R8 tasks already proved in isolation and this file does
## NOT re-prove: DriverRegistry resolution/fallback (tests/racing/roster/
## test_driver_registry.gd), RaceSession's own configure_selected_driver()/
## AI-fill wiring (tests/racing/test_race_session_driver_roster.gd), the
## Cup holding one pick across both races with a real select-screen tap
## (test_cup_flow_e2e.gd::test_cup_holds_the_selected_driver_across_both_
## races_and_the_ai_field_matches, coco not papu), save v4's selected_
## driver round trip in isolation (tests/core/test_save_model.gd, Task 3).
## This file's own job is different -- prove the REAL, WHOLE pipeline holds
## together end to end THROUGH A RELAUNCH: select screen -> real race ->
## cup chain -> disk write -> a brand-new process boot reading that write
## back and mounting the real mesh from it, with zero unhandled push_error/
## engine-error calls anywhere in the run.
##
## Isolated in scripts/run_gut.sh's own isolated_suites list -- this test
## instantiates and tears down TWO real GameRoot instances (main.tscn) in
## one run, matching test_cup_flow_e2e.gd's own "repeatedly instantiating
## the real main scene must not leak ResourceLoader/renderer state" reason
## for isolation.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const TEST_SAVE_DIR := "user://test_sandbox/task9_papu_cup_reload_e2e"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const PAPU_SEATED_CHARACTER_SCENE_PATH := "res://assets/models/bosses/SK_papu_seated.glb"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_papu_picked_through_the_real_select_screen_races_a_full_cup_and_survives_a_fresh_reload() -> void:
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

	# ------------------------------------------------------------------
	# 1. Pick Papu through the REAL Driver Select overlay tile.
	# ------------------------------------------------------------------
	var driver_overlay := root.get_node("UI/DriverSelectOverlay")
	assert_true(
		driver_overlay.visible,
		"the CUP entry must route through CHOOSE DRIVER before race 1 launches"
	)
	var papu_button := driver_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Papu"
	) as Button
	papu_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(driver_overlay.visible, "picking a tile must dismiss the select screen")

	var race1 := root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(
		race1,
		"picking papu must still launch race 1 (Sanity Shores) through the real registered scene"
	)
	if race1 == null:
		return
	assert_false(cup_overlay.visible)

	# ------------------------------------------------------------------
	# 2. A REAL 3-2-1-GO countdown for race 1 (brief: "real countdown race
	# 1") -- the same wait test_cup_flow_e2e.gd's own R7 Task 7 test uses.
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
	# 3. Papu's own seated GLB must be mounted on the player's kart FOR
	# REAL, mid-race -- not merely picked on the select screen.
	# ------------------------------------------------------------------
	var kart := race1.get_node("Kart") as CharacterBody3D
	assert_eq(
		_mounted_scene_path(kart),
		PAPU_SEATED_CHARACTER_SCENE_PATH,
		"papu must actually be seated on the player's kart in the real race"
	)
	var recorder1: Object = race1.get("_ghost_recorder")
	assert_not_null(recorder1)
	if recorder1 != null:
		assert_eq(
			recorder1.call("driver_id"),
			&"papu",
			"race 1's ghost recorder must thread the real pick"
		)

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
	assert_false(
		driver_overlay.visible,
		"race 2 must launch directly off the cup's own held pick, without asking again"
	)

	var race2 := root.get_node_or_null("Content/RaceTempleTwilight")
	assert_not_null(
		race2,
		"CONTINUE must advance the cup into race 2 (Temple Twilight) through the real registered scene"
	)
	if race2 == null:
		return
	var kart2 := race2.get_node("Kart") as CharacterBody3D
	assert_eq(
		_mounted_scene_path(kart2),
		PAPU_SEATED_CHARACTER_SCENE_PATH,
		"race 2 must mount papu again -- the cup holds the SAME pick across both races"
	)

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

	# ------------------------------------------------------------------
	# 4. The standings chain reaches disk with the real pick attached.
	# ------------------------------------------------------------------
	var profile: Dictionary = root.get("profile")
	assert_eq(
		SaveModel.selected_driver(profile),
		&"papu",
		"picking papu on the select screen must persist racing.selected_driver"
	)
	var cup_record := SaveModel.cup_record(profile, &"island_cup")
	assert_eq(
		cup_record.get("best_placement"),
		1,
		"a cup won outright must persist the player's own best placement"
	)
	var stored := SaveService.new().load_profile(TEST_SAVE_DIR)
	assert_eq(
		SaveModel.selected_driver(stored),
		&"papu",
		"the driver pick must actually reach disk, not just memory"
	)
	assert_eq(
		SaveModel.cup_record(stored, &"island_cup"),
		cup_record,
		"the cup result must actually reach disk, not just memory"
	)

	close_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(cup_overlay.visible, "CLOSE must dismiss the final podium")

	# ------------------------------------------------------------------
	# 5. Zero unexpected errors across the whole real run.
	#
	# R8 gate flip 2026-08-02: cortex/coco/ripper_roo (the last three
	# fallback-active drivers) are now all operator-accepted -- see test_
	# cup_flow_e2e.gd's identical comment for the full history. Papu was
	# already excluded from this run's AI field (he is the PLAYER's own
	# pick, not an AI slot occupant) and every roster id now ships a real
	# gated scene, so this run never reaches DriverRegistry._fallback_
	# scene() for anyone -- reverted to a bare zero-errors check.
	# ------------------------------------------------------------------
	assert_eq(
		get_errors().size(),
		0,
		"zero push_error/engine-error calls must occur across the whole real run"
	)

	# ------------------------------------------------------------------
	# 6. FRESH RELOAD: a brand-new GameRoot instance off the SAME
	# save_dir -- standing in for relaunching the app. SKIP on the select
	# screen keeps whatever racing.selected_driver already holds on disk
	# (the same _skip_driver_select() semantics test_cup_flow_e2e.gd's own
	# helper already documents), proving the pick survives a real reload
	# rather than only this run's own in-memory `profile` dictionary.
	# ------------------------------------------------------------------
	var reloaded_root := _instantiate_main()
	if reloaded_root == null:
		return
	var reloaded_profile: Dictionary = reloaded_root.get("profile")
	assert_eq(
		SaveModel.selected_driver(reloaded_profile),
		&"papu",
		"a fresh GameRoot boot off the same save_dir must read the persisted pick back off disk"
	)

	var reloaded_overlay := await _open_level_list_and_get_overlay(reloaded_root)
	var ordinary_button := reloaded_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingSanityShores"
	) as Button
	ordinary_button.pressed.emit()
	await wait_process_frames(1)
	await _skip_driver_select(reloaded_root)

	var reloaded_race := reloaded_root.get_node_or_null("Content/RaceSanityShores")
	assert_not_null(
		reloaded_race,
		"the reloaded profile must still launch an ordinary race normally"
	)
	if reloaded_race == null:
		return
	var reloaded_kart := reloaded_race.get_node("Kart") as CharacterBody3D
	assert_eq(
		_mounted_scene_path(reloaded_kart),
		PAPU_SEATED_CHARACTER_SCENE_PATH,
		(
			"a fresh reload must mount papu's own seated model again, on "
			+ "the strength of the persisted save value alone -- no re-pick"
		)
	)


## Same shape test_race_session_driver_roster.gd's own copy uses -- GUT test
## scripts do not share helpers across files (established convention, see
## that file's own identical helper).
func _mounted_scene_path(kart: CharacterBody3D) -> String:
	var mounted: Node3D = kart.call("mounted_character")
	if mounted == null:
		return ""
	return mounted.scene_file_path


## Frame-exact "wait for real GO" -- the same shape test_cup_flow_e2e.gd's
## own copy establishes (itself mirroring test_race_start_flow.gd's own
## _wait_until_race_started()); GUT test scripts don't share private helpers
## across files (established convention), so this is a local copy.
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


## Same shape test_cup_flow_e2e.gd's own copy uses -- see that file's own
## identical doc for why every RACE/TIME TRIAL/CUP menu entry now opens
## CHOOSE DRIVER first.
func _skip_driver_select(root: Node) -> void:
	var driver_overlay := root.get_node("UI/DriverSelectOverlay")
	assert_true(
		driver_overlay.visible,
		"the CUP/ordinary racing entry must route through CHOOSE DRIVER first"
	)
	var skip_button := driver_overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Skip"
	) as Button
	skip_button.pressed.emit()
	await wait_process_frames(1)


func _open_level_list_and_get_overlay(root: Node) -> Node:
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)
	return root.get_node("UI/LevelListOverlay")


## Same shape test_cup_flow_e2e.gd's own copy uses (originally test_main_
## boot.gd's own _force_finish_race()): skip the pre-race countdown, then
## teleport-cross every gate in order for every lap plus the finish gate.
## Harmless to call on race 1 here (already past a REAL countdown to GO by
## the time this runs) -- CountdownTimer.tick() (countdown_timer.gd) only
## ever fires _start_race() on the one transition INTO &"go"; once phase is
## already &"go" the next tick() call just advances it to &"running" and
## returns that, never re-firing _start_race().
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
