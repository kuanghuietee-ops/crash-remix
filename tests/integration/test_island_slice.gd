extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const LEVEL_ID := &"wr1_n_sanity_beach"
const TEST_SAVE_DIR := "user://test_sandbox/task13_island_slice"
const CRATE_TOTAL := 40


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_real_scene_spawn_stays_on_authored_floor_without_death() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D

	await wait_physics_frames(120)

	assert_true(
		player.is_on_floor(),
		"the real player must settle on authored floor without input"
	)
	assert_true(
		level.run_state.flawless,
		"falling from the authored spawn must not record a player death"
	)
	assert_eq(level.run_state.deaths_at_checkpoint, 0)


func test_real_player_walking_into_finish_completes_level() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var finish := level.get_node("Finish") as Area3D
	var finish_collision := (
		finish.get_node("CollisionShape3D") as CollisionShape3D
	)
	var finish_shape := finish_collision.shape as BoxShape3D
	assert_not_null(finish_shape)
	if finish_shape == null:
		return
	await wait_physics_frames(2)
	player.global_position = Vector3(
		finish.global_position.x,
		player.global_position.y,
		(
			finish.global_position.z
			+ finish_shape.size.z * 0.5
			+ 1.0
		)
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(1)
	assert_false(
		finish.overlaps_body(player),
		"the test must begin outside the real Finish trigger"
	)
	var start_z := player.global_position.z
	var router := level.get_node("Input/InputRouter") as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2(0.0, -1.0),
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var walked_forward := false
	for _physics_index: int in range(120):
		if root.call("state_name") == &"results":
			break
		if is_instance_valid(player):
			walked_forward = (
				walked_forward
				or player.global_position.z < start_z
			)
		await wait_physics_frames(1)

	assert_true(
		walked_forward,
		"the real controller must walk the player toward the exit"
	)
	assert_eq(
		root.call("state_name"),
		&"results",
		"walking into the real Finish Area3D must complete the run"
	)


func test_authored_level_wumpa_total_is_visible_on_hud() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var first_crate := _crate(level, 1)
	assert_not_null(first_crate)
	if first_crate == null:
		return
	var economy := (
		root.get("tuning_service").get("catalog").get("economy")
		as EconomyTuning
	)
	var visible_meta := (
		level.run_state.meta.duplicate(true) as LevelMeta
	)
	visible_meta.wumpa_total += economy.wumpa_per_standard_crate
	root.call(
		"set_active_level_session",
		level,
		visible_meta,
		root.get("_segment_by_crate_id")
	)

	player.get_node("SpinArea").emit_signal(
		&"body_entered",
		first_crate
	)
	await wait_process_frames(1)

	assert_eq(
		root.get_node(
			"UI/HUD/SafeArea/Stats/Margin/Rows/Wumpa"
		).text,
		"WUMPA  %d / %d" % [
			economy.wumpa_per_standard_crate,
			visible_meta.wumpa_total,
		],
		"the live HUD must consume LevelMeta.wumpa_total"
	)


func test_island_slice_full_loop() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(root.call("state_name"), &"warp_room")
	var level := await _enter_authored_level(root)
	assert_not_null(level, "the known level id must load the authored scene")
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var first_crate := _crate(level, 1)
	var checkpoint := _crate(level, 14)
	var second_crate := _crate(level, 15)
	var third_crate := _crate(level, 16)
	var first_pickup := level.get_node(
		"Segments/BeachLanding/WumpaA"
	) as Area3D
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	assert_not_null(first_crate)
	assert_not_null(checkpoint)
	assert_not_null(second_crate)
	assert_not_null(third_crate)
	assert_not_null(first_pickup)
	assert_not_null(catalog)
	if (
		first_crate == null
		or checkpoint == null
		or second_crate == null
		or third_crate == null
		or first_pickup == null
		or catalog == null
	):
		return

	var fresh_meta := level.run_state.meta
	player.global_position = Vector3(
		first_pickup.global_position.x,
		0.05,
		first_pickup.global_position.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if bool(first_pickup.get_meta(&"phase1_collected", false)):
			break
		await wait_physics_frames(1)
	assert_true(
		bool(first_pickup.get_meta(&"phase1_collected", false)),
		"the real player must collect the authored Wumpa"
	)
	assert_false(first_pickup.visible)
	assert_eq(
		level.run_state.wumpa_run,
		catalog.economy.wumpa_per_pickup
	)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_true(level.configure(
		fresh_meta,
		LevelRunState.MODE_NORMAL,
		catalog.economy,
		player,
		catalog.move,
		catalog.input
	))
	await wait_process_frames(1)
	assert_false(
		bool(first_pickup.get_meta(&"phase1_collected", false))
	)
	assert_true(
		first_pickup.visible,
		"configure re-entry must restore collected Wumpa visibility"
	)
	assert_true(first_pickup.monitoring)
	assert_true(first_pickup.monitorable)
	player.global_position = Vector3(
		first_pickup.global_position.x,
		0.05,
		first_pickup.global_position.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if level.run_state.wumpa_run > 0:
			break
		await wait_physics_frames(1)
	assert_eq(
		level.run_state.wumpa_run,
		catalog.economy.wumpa_per_pickup,
		"the restored authored Wumpa must collect through its real Area3D"
	)

	level.record_player_death()
	await wait_process_frames(1)
	await _fall_real_player_from_entry(level, player, 2)
	level.record_player_death()
	assert_true(level.configure(
		fresh_meta,
		LevelRunState.MODE_NORMAL,
		catalog.economy,
		player,
		catalog.move,
		catalog.input
	))
	assert_true(
		level.run_state.flawless,
		"the fresh run must begin flawless after the manual death hook"
	)

	player.get_node("SpinArea").emit_signal(
		&"body_entered",
		first_crate
	)
	await wait_process_frames(1)
	assert_true(first_crate.call("is_broken"))
	assert_eq(level.run_state.broken_crate_ids, [1])
	assert_eq(
		root.get_node(
			"UI/HUD/SafeArea/Stats/Margin/Rows/Crates"
		).text,
		"CRATES  1 / %d" % CRATE_TOTAL
	)

	checkpoint.call("apply_verb", &"spin", 2.0)
	assert_eq(level.run_state.checkpoint_id, 14)
	var checkpoint_spawn: Transform3D = player.get(
		"_spawn_transform"
	)
	assert_true(
		is_equal_approx(checkpoint_spawn.origin.y, 0.05),
		"checkpoint respawn must put the player's feet above the route"
	)
	assert_gt(
		checkpoint_spawn.origin.z,
		(checkpoint as Node3D).global_position.z,
		"checkpoint respawn must sit safely behind the broken crate"
	)
	second_crate.call("apply_verb", &"spin", 3.0)
	third_crate.call("apply_verb", &"spin", 4.0)
	assert_eq(
		level.run_state.broken_crate_ids,
		[1, 14, 15, 16]
	)

	player.global_position = Vector3(
		4.5,
		0.05,
		0.0
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if player.is_on_floor():
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor(),
		"the death proof must begin on the real entry floor"
	)
	var router := level.get_node("Input/InputRouter") as InputRouter
	var fall_start_x := player.global_position.x
	var farthest_x := fall_start_x
	router.push_intent(
		InputIntent.move(
			Vector2.RIGHT,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var fell_below_route := false
	var entered_respawn_delay := false
	for _physics_index: int in range(300):
		farthest_x = maxf(farthest_x, player.global_position.x)
		fell_below_route = (
			fell_below_route
			or player.global_position.y < 0.0
		)
		if player.call("is_respawning"):
			entered_respawn_delay = true
			router.push_intent(
				InputIntent.move(
					Vector2.ZERO,
					0.0,
					InputIntent.SOURCE_KEYBOARD
				)
			)
		if level.run_state.deaths_at_checkpoint == 1:
			break
		await wait_physics_frames(1)
	assert_gt(
		farthest_x,
		fall_start_x,
		"the real controller must move the player off the floor"
	)
	assert_true(
		fell_below_route,
		"the player body must physically fall below the route"
	)
	assert_true(
		entered_respawn_delay,
		"the real controller must enter its tuned respawn delay"
	)
	assert_eq(
		level.run_state.deaths_at_checkpoint,
		1,
		"the respawned signal must record exactly one real death"
	)
	for _physics_index: int in range(30):
		if player.is_on_floor():
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor(),
		"the real respawn must settle on checkpoint floor"
	)
	assert_true(
		Vector2(
			player.global_position.x,
			player.global_position.z
		).is_equal_approx(
			Vector2(
				checkpoint_spawn.origin.x,
				checkpoint_spawn.origin.z
			)
		),
		"the real respawn must return to the checkpoint position"
	)
	for crate_id: int in [1, 14, 15, 16]:
		var broken_crate := _crate(level, crate_id)
		assert_true(broken_crate.call("is_broken"))
		assert_false(broken_crate.get_node("Mesh").visible)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	assert_true(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_eq(
		root.call("dispatch", {"type": &"resume"}),
		OK
	)
	var finish := level.get_node("Finish") as Area3D
	var finish_shape := (
		finish.get_node("CollisionShape3D").shape as BoxShape3D
	)
	player.global_position = Vector3(
		finish.global_position.x,
		player.global_position.y,
		(
			finish.global_position.z
			+ finish_shape.size.z * 0.5
			+ 1.0
		)
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(1)
	assert_false(
		finish.overlaps_body(player),
		"the completion proof must begin outside the real exit"
	)
	var finish_start_z := player.global_position.z
	router.push_intent(
		InputIntent.move(
			Vector2(0.0, -1.0),
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var walked_into_finish := false
	for _physics_index: int in range(120):
		if root.call("state_name") == &"results":
			break
		if is_instance_valid(player):
			walked_into_finish = (
				walked_into_finish
				or player.global_position.z < finish_start_z
			)
		await wait_physics_frames(1)
	assert_true(
		walked_into_finish,
		"the real controller must walk the player into the exit"
	)

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(payload.get("box_count"), 4)
	assert_eq(payload.get("crate_count"), CRATE_TOTAL)
	assert_false(payload.get("gem"))
	var missed_by_segment: Dictionary = payload.get(
		"missed_crate_ids_by_segment",
		{}
	)
	assert_true(missed_by_segment.has("Beach Landing"))
	assert_false(missed_by_segment.has("Unassigned"))

	var profile_path := TEST_SAVE_DIR.path_join("profile.json")
	assert_true(FileAccess.file_exists(profile_path))
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("profile.json.tmp")
		)
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(profile_path)
	)
	assert_true(parsed is Dictionary)
	if parsed is Dictionary:
		assert_true(SaveModel.validate(parsed))
		var migrated := SaveModel.migrate(parsed)
		var record := SaveModel.level_record(
			migrated,
			LEVEL_ID
		)
		assert_true(record.get("completed"))
		assert_eq(
			record.get("last_missed_crate_ids"),
			payload.get("missed_crate_ids")
		)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_real_mercy_skip_voids_relic_entry_at_results() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var checkpoint := _crate(level, 14)
	assert_not_null(checkpoint)
	if checkpoint == null:
		return
	var spin_area := player.get_node("SpinArea") as Area3D
	spin_area.emit_signal(&"body_entered", checkpoint)
	await wait_process_frames(1)
	assert_eq(
		level.run_state.checkpoint_id,
		14,
		"the real checkpoint crate must establish the mercy counter"
	)

	var economy := (
		root.get("tuning_service").get("catalog").get("economy")
		as EconomyTuning
	)
	assert_not_null(economy)
	if economy == null:
		return
	assert_eq(economy.mercy_mask_death_threshold, 3)
	assert_eq(economy.mercy_skip_death_threshold, 6)
	var scenario_economy := economy.duplicate(true) as EconomyTuning
	scenario_economy.mercy_mask_death_threshold += (
		economy.wumpa_per_standard_crate
	)
	scenario_economy.mercy_skip_death_threshold += (
		economy.wumpa_per_standard_crate
	)
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	level.refresh_tuning(
		scenario_economy,
		catalog.move,
		catalog.input
	)
	var mercy_grants: Array[int] = []
	var skip_offers: Array[int] = []
	level.mercy_granted.connect(
		func(mask_count: int) -> void:
			mercy_grants.append(mask_count)
	)
	level.skip_offered.connect(
		func(checkpoint_id: int) -> void:
			skip_offers.append(checkpoint_id)
	)
	for expected_deaths: int in range(
		1,
		scenario_economy.mercy_skip_death_threshold + 1
	):
		await _fall_real_player_from_entry(
			level,
			player,
			expected_deaths
		)
		assert_eq(
			mercy_grants.size(),
			(
				1
				if expected_deaths
				>= scenario_economy.mercy_mask_death_threshold
				else 0
			),
			"mask mercy must fire at its live tuned boundary"
		)
		assert_eq(
			level.run_state.masks,
			(
				1
				if expected_deaths
				== scenario_economy.mercy_mask_death_threshold
				else 0
			),
			"the real player stack must receive only the boundary grant"
		)
		assert_eq(
			skip_offers.size(),
			(
				1
				if expected_deaths
				>= scenario_economy.mercy_skip_death_threshold
				else 0
			),
			"skip mercy must fire at its live tuned boundary"
		)

	var mercy_panel := root.get_node(
		"UI/HUD/SafeArea/MercyPanel"
	) as PanelContainer
	var skip_button := mercy_panel.get_node(
		"Margin/Rows/Skip"
	) as Button
	assert_true(
		mercy_panel.visible and skip_button.visible,
		"the sixth real death must surface the HUD skip offer"
	)
	skip_button.emit_signal(&"pressed")
	await wait_process_frames(1)
	assert_false(
		mercy_panel.visible,
		"the real HUD button must accept and dismiss the skip offer"
	)
	assert_eq(
		level.run_state.checkpoint_id,
		30,
		"the accepted offer must advance to the next authored checkpoint"
	)
	assert_true(level.run_state.gem_void)
	assert_true(level.run_state.relic_void)

	for crate_id: int in range(1, CRATE_TOTAL + 1):
		var authored_crate := _crate(level, crate_id)
		assert_not_null(
			authored_crate,
			"the gem-void scenario requires authored crate %d"
			% crate_id
		)
		if (
			authored_crate != null
			and not bool(authored_crate.call("is_broken"))
		):
			spin_area.emit_signal(
				&"body_entered",
				authored_crate
			)
	await wait_process_frames(1)
	assert_eq(
		level.run_state.broken_crate_ids.size(),
		CRATE_TOTAL,
		"all normal crates must break through the real player attack wiring"
	)

	var relic_meta := (
		level.run_state.meta.duplicate(true) as LevelMeta
	)
	relic_meta.relic_platinum_s = economy.time_crate_small_s
	relic_meta.relic_gold_s = (
		relic_meta.relic_platinum_s
		+ economy.time_crate_medium_s
	)
	relic_meta.relic_sapphire_s = (
		relic_meta.relic_gold_s
		+ economy.time_crate_large_s
	)
	level.run_state.meta = relic_meta
	root.set("_active_level_meta", relic_meta)

	await _walk_real_player_into_finish(root, level, player)
	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(
		payload.get("box_count"),
		CRATE_TOTAL,
		"gem-void proof must complete with every authored crate broken"
	)
	assert_eq(
		payload.get("missed_crate_ids"),
		[],
		"gem-void proof must not rely on a missed crate"
	)
	assert_false(
		payload.get("gem", true),
		"mercy skip must suppress the otherwise-earned gem"
	)
	assert_false(
		SaveModel.level_record(
			root.get("profile"),
			LEVEL_ID
		).get("gem", true),
		"the voided gem must not reach the real saved profile"
	)
	assert_true(
		payload.get("relic_void", false),
		"the real skipped run must carry its relic void to results"
	)
	assert_false(
		payload.get("relic_entry_available", true),
		"the skipped run must not offer an immediate relic trial"
	)
	assert_false(
		root.get_node(
			"UI/ResultsScreen/SafeArea/Center/Panel/Margin/Rows/Actions/RelicTrial"
		).visible,
		"the real results screen must hide the voided relic action"
	)


func test_new_real_run_clears_previous_mercy_banner() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var economy := (
		root.get("tuning_service").get("catalog").get("economy")
		as EconomyTuning
	)
	assert_not_null(economy)
	if economy == null:
		return
	economy.mercy_mask_death_threshold = (
		economy.wumpa_per_standard_crate
	)
	await _fall_real_player_from_entry(level, player, 1)
	var mercy_panel := root.get_node(
		"UI/HUD/SafeArea/MercyPanel"
	) as PanelContainer
	var skip_button := mercy_panel.get_node(
		"Margin/Rows/Skip"
	) as Button
	assert_true(mercy_panel.visible)
	assert_false(skip_button.visible)

	root.get_node(
		"UI/HUD/SafeArea/Pause"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"paused")
	root.get_node(
		"UI/PauseOverlay/SafeArea/Center/Panel/Margin/Rows/Quit"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"warp_room")
	var next_level := await _enter_authored_level(root)
	if next_level == null:
		return

	assert_false(
		mercy_panel.visible,
		"a new real run must not inherit the previous run's notice"
	)


func test_real_mercy_banner_expires_after_tuned_active_play_time() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	assert_not_null(catalog)
	if catalog == null:
		return
	catalog.economy.mercy_mask_death_threshold = (
		catalog.economy.wumpa_per_standard_crate
	)
	catalog.economy.mercy_skip_death_threshold = (
		catalog.economy.mercy_mask_death_threshold
		+ catalog.economy.wumpa_per_standard_crate
	)
	await _fall_real_player_from_entry(level, player, 1)
	var mercy_panel := root.get_node(
		"UI/HUD/SafeArea/MercyPanel"
	) as PanelContainer
	var skip_button := mercy_panel.get_node(
		"Margin/Rows/Skip"
	) as Button
	assert_true(mercy_panel.visible)
	assert_false(skip_button.visible)

	var frame_limit := (
		ceili(
			catalog.economy.mercy_banner_duration_s
			* Engine.physics_ticks_per_second
		)
		+ Engine.physics_ticks_per_second
	)
	for _physics_index: int in range(frame_limit):
		if not mercy_panel.visible:
			break
		await wait_physics_frames(1)

	assert_false(
		mercy_panel.visible,
		"the informational mercy notice must expire while play continues"
	)

	await _fall_real_player_from_entry(level, player, 2)
	assert_true(mercy_panel.visible)
	assert_true(
		skip_button.visible,
		"the real skip offer must remain an actionable modal"
	)
	for _physics_index: int in range(frame_limit):
		await wait_physics_frames(1)
	assert_true(
		mercy_panel.visible and skip_button.visible,
		"the tuned info timeout must not dismiss the skip offer"
	)


func test_final_checkpoint_mercy_skip_completes_a_voided_run() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var final_checkpoint := _crate(level, 30)
	assert_not_null(final_checkpoint)
	if final_checkpoint == null:
		return
	player.get_node("SpinArea").emit_signal(
		&"body_entered",
		final_checkpoint
	)
	await wait_process_frames(1)
	assert_eq(
		level.run_state.checkpoint_id,
		30,
		"the scenario must begin at the final authored checkpoint"
	)
	var skip_offers: Array[int] = []
	level.skip_offered.connect(
		func(checkpoint_id: int) -> void:
			skip_offers.append(checkpoint_id)
	)
	var economy := (
		root.get("tuning_service").get("catalog").get("economy")
		as EconomyTuning
	)
	assert_not_null(economy)
	if economy == null:
		return

	for expected_deaths: int in range(
		1,
		economy.mercy_skip_death_threshold + 1
	):
		await _fall_real_player_from_entry(
			level,
			player,
			expected_deaths
		)

	assert_eq(
		skip_offers,
		[30],
		"the sixth real death must offer relief at the final checkpoint"
	)
	var mercy_panel := root.get_node(
		"UI/HUD/SafeArea/MercyPanel"
	) as PanelContainer
	var skip_button := mercy_panel.get_node(
		"Margin/Rows/Skip"
	) as Button
	assert_true(mercy_panel.visible and skip_button.visible)
	assert_string_contains(
		mercy_panel.get_node("Margin/Rows/Message").text,
		"remaining level"
	)

	skip_button.pressed.emit()
	await wait_process_frames(1)

	assert_eq(
		root.call("state_name"),
		&"results",
		"accepting final-checkpoint mercy must finish instead of stall"
	)
	var payload: Dictionary = root.get("last_results_payload")
	assert_false(payload.get("gem", true))
	assert_true(payload.get("relic_void", false))
	assert_true(
		SaveModel.level_record(
			root.get("profile"),
			LEVEL_ID
		).get("completed", false),
		"the real results path must persist the mercy completion"
	)


func test_real_relic_death_can_finish_as_void_without_stranding_run() -> void:
	var seeded_profile := SaveModel.fresh()
	var seeded_record := SaveModel.level_record(
		seeded_profile,
		LEVEL_ID
	)
	seeded_record["completed"] = true
	seeded_profile["levels"][String(LEVEL_ID)] = seeded_record
	assert_eq(
		SaveService.new().store_profile(
			TEST_SAVE_DIR,
			seeded_profile
		),
		OK
	)

	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var start_position := player.global_position
	var checkpoint := _crate(level, 14)
	assert_not_null(checkpoint)
	if checkpoint == null:
		return
	var spin_area := player.get_node("SpinArea") as Area3D
	spin_area.emit_signal(&"body_entered", checkpoint)
	await wait_process_frames(1)
	assert_eq(
		level.run_state.checkpoint_id,
		14,
		"the real checkpoint must replace the normal respawn target"
	)
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	var relic_meta := (
		level.run_state.meta.duplicate(true) as LevelMeta
	)
	relic_meta.relic_platinum_s = (
		catalog.economy.time_crate_small_s
	)
	relic_meta.relic_gold_s = (
		relic_meta.relic_platinum_s
		+ catalog.economy.time_crate_medium_s
	)
	relic_meta.relic_sapphire_s = (
		relic_meta.relic_gold_s
		+ catalog.economy.time_crate_large_s
	)
	assert_true(level.configure(
		relic_meta,
		LevelRunState.MODE_RELIC,
		catalog.economy,
		player,
		catalog.move,
		catalog.input
	))
	root.set("_active_level_meta", relic_meta)
	var run_state := level.run_state

	for _physics_index: int in range(30):
		if run_state.relic_timer_armed:
			break
		await wait_physics_frames(1)
	assert_true(
		run_state.relic_timer_armed,
		"the authored stopwatch overlap must arm the relic attempt"
	)
	var stopwatch := level.get_node(
		"RelicOnly/Stopwatch"
	) as Area3D
	stopwatch.global_position.z = -20.0
	await _fall_real_relic_player_once(level, player)
	assert_true(run_state.relic_void)
	assert_false(run_state.relic_timer_armed)
	for _physics_index: int in range(120):
		if player.is_on_floor() and not player.call("is_respawning"):
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor() and not player.call("is_respawning"),
		"the real player must finish the relic respawn"
	)
	assert_true(
		Vector2(
			player.global_position.x,
			player.global_position.z
		).is_equal_approx(
			Vector2(start_position.x, start_position.z)
		),
		"a relic death after a checkpoint must land at level start"
	)

	await _walk_real_player_into_finish(root, level, player)

	assert_eq(
		root.call("state_name"),
		&"results",
		"a voided relic attempt must not strand the flow in LEVEL"
	)
	assert_false(run_state.run_active)
	assert_null(root.get("active_level_session"))
	assert_eq(root.get("last_save_error"), OK)
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(payload.get("mode"), LevelRunState.MODE_RELIC)
	assert_true(payload.get("relic_void", false))
	assert_null(payload.get("relic_time_s"))
	assert_null(payload.get("relic_tier"))
	assert_eq(
		root.get("profile"),
		seeded_profile,
		"a voided relic finish must save without inventing an award"
	)
	assert_true(
		root.get_node("UI/ResultsScreen").visible,
		"the real results screen must receive the voided finish"
	)


func test_process_killed_relaunch_restores_real_run_at_checkpoint() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var first_crate := _crate(level, 1)
	var aku_crate := _crate(level, 11)
	var checkpoint := _crate(level, 14)
	assert_not_null(first_crate)
	assert_not_null(aku_crate)
	assert_not_null(checkpoint)
	if (
		first_crate == null
		or aku_crate == null
		or checkpoint == null
	):
		return
	var spin_area := player.get_node("SpinArea") as Area3D

	spin_area.emit_signal(&"body_entered", first_crate)
	spin_area.emit_signal(&"body_entered", checkpoint)
	await wait_process_frames(1)
	assert_eq(level.run_state.broken_crate_ids, [1, 14])
	assert_eq(level.run_state.checkpoint_id, 14)
	var checkpoint_spawn: Transform3D = player.get(
		"_spawn_transform"
	)

	player.global_position = Vector3(4.5, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if player.is_on_floor():
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor(),
		"the relaunch scenario must begin on the real entry floor"
	)
	var router := level.get_node("Input/InputRouter") as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2.RIGHT,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var physically_fell := false
	for _physics_index: int in range(300):
		physically_fell = (
			physically_fell
			or player.global_position.y < 0.0
		)
		if player.call("is_respawning"):
			router.push_intent(
				InputIntent.move(
					Vector2.ZERO,
					0.0,
					InputIntent.SOURCE_KEYBOARD
				)
			)
		if level.run_state.deaths_at_checkpoint == 1:
			break
		await wait_physics_frames(1)
	assert_true(
		physically_fell,
		"the real player must fall off the authored route"
	)
	assert_eq(
		level.run_state.deaths_at_checkpoint,
		1,
		"the real respawn signal must record the death"
	)
	for _physics_index: int in range(120):
		if player.is_on_floor() and not player.call("is_respawning"):
			break
		await wait_physics_frames(1)
	assert_true(player.is_on_floor())

	spin_area.emit_signal(&"body_entered", aku_crate)
	await wait_process_frames(1)
	assert_eq(level.run_state.broken_crate_ids, [1, 11, 14])
	assert_eq(level.run_state.masks, 1)
	assert_eq(player.call("mask_count"), 1)
	var played_snapshot := level.run_state.snapshot()
	assert_false(played_snapshot.get("flawless"))
	assert_eq(played_snapshot.get("deaths_at_checkpoint"), 1)
	assert_gt(int(played_snapshot.get("wumpa_run")), 0)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	assert_true(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	root.free()
	assert_false(
		is_instance_valid(root),
		"the killed process root must be fully disposed before relaunch"
	)
	assert_false(
		get_tree().paused,
		"destroying the paused process root must release tree pause"
	)

	var resumed_root := _instantiate_main()
	if resumed_root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		resumed_root.call("state_name"),
		&"level",
		"boot must consume a valid tier-2 snapshot"
	)
	if resumed_root.call("state_name") != &"level":
		return
	var resumed_level := await _wait_for_authored_level(resumed_root)
	if resumed_level == null:
		return
	var resumed_player := (
		resumed_level.get_node("Player") as CharacterBody3D
	)

	assert_eq(
		resumed_level.run_state.snapshot(),
		played_snapshot,
		"the real session must restore the complete played run state"
	)
	assert_eq(resumed_player.call("mask_count"), 1)
	assert_true(
		Vector2(
			resumed_player.global_position.x,
			resumed_player.global_position.z
		).is_equal_approx(
			Vector2(
				checkpoint_spawn.origin.x,
				checkpoint_spawn.origin.z
			)
		),
		"tier-2 resume must place the player at the checkpoint"
	)
	for crate_id: int in [1, 11, 14]:
		var restored_crate := _crate(resumed_level, crate_id)
		assert_true(restored_crate.call("is_broken"))
		assert_false(restored_crate.get_node("Mesh").visible)
	assert_true(
		resumed_root.get("flow").get("resume_snapshot").is_empty(),
		"the in-memory resume decision must be consumed once"
	)


func test_bounce_launch_and_tnt_chain_are_wired_in_scene() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var bounce := _crate(level, 9)
	var tnt := _crate(level, 27)
	var blast_neighbour := _crate(level, 26)
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	assert_not_null(bounce)
	assert_not_null(tnt)
	assert_not_null(blast_neighbour)
	assert_not_null(catalog)
	if (
		bounce == null
		or tnt == null
		or blast_neighbour == null
		or catalog == null
	):
		return

	catalog.economy.bounce_launch_height_m += (
		catalog.move.jump_full_height_m
	)
	var bounce_shape := (
		bounce.get_node("CollisionShape3D").shape
		as BoxShape3D
	)
	assert_not_null(bounce_shape)
	if bounce_shape == null:
		return
	var router := level.get_node("Input/InputRouter") as InputRouter
	var wumpa_before_bounce := level.run_state.wumpa_run
	player.global_position = Vector3(
		bounce.global_position.x,
		bounce.global_position.y
			+ bounce_shape.size.y * 0.5
			+ 0.01,
		bounce.global_position.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(
		Engine.physics_ticks_per_second
	):
		await wait_physics_frames(1)
		if level.run_state.wumpa_run > wumpa_before_bounce:
			break
	assert_gt(
		player.velocity.y,
		0.0,
		"real top contact must apply the ordinary bounce launch"
	)
	assert_eq(
		level.run_state.wumpa_run,
		wumpa_before_bounce
			+ catalog.economy.bounce_crate_wumpa_per_bounce
	)
	var ordinary_launch_speed := (
		JumpKinematics.upward_speed_for_height(
			catalog.move.jump_full_height_m,
			catalog.move
		)
	)
	var high_launch_speed := (
		JumpKinematics.upward_speed_for_height(
			catalog.economy.bounce_launch_height_m,
			catalog.move
		)
	)
	assert_almost_eq(
		player.velocity.y,
		ordinary_launch_speed,
		0.0001
	)
	var late_press_s := MonotonicClock.now_s()
	router.push_intent(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		late_press_s,
		InputIntent.SOURCE_KEYBOARD
	))
	await wait_physics_frames(1)
	assert_gt(
		player.velocity.y,
		lerpf(ordinary_launch_speed, high_launch_speed, 0.5),
		"a post-contact JUMP inside the tuned window must upgrade the bounce"
	)
	router.push_intent(InputIntent.button(
		InputIntent.ACTION_JUMP,
		false,
		MonotonicClock.now_s(),
		InputIntent.SOURCE_KEYBOARD
	))
	await wait_physics_frames(1)
	var held_press_s := MonotonicClock.now_s()
	router.push_intent(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		held_press_s,
		InputIntent.SOURCE_KEYBOARD
	))
	await wait_physics_frames(
		ceili(
			catalog.input.bounce_timing_s
				* Engine.physics_ticks_per_second
		) + 1
	)
	var wumpa_before_held_bounce := level.run_state.wumpa_run
	player.global_position = Vector3(
		bounce.global_position.x,
		bounce.global_position.y
			+ bounce_shape.size.y * 0.5
			+ 0.01,
		bounce.global_position.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(
		Engine.physics_ticks_per_second
	):
		await wait_physics_frames(1)
		if (
			level.run_state.wumpa_run
			> wumpa_before_held_bounce
		):
			break
	assert_eq(
		level.run_state.wumpa_run,
		wumpa_before_held_bounce
			+ catalog.economy.bounce_crate_wumpa_per_bounce
	)
	assert_gt(
		player.velocity.y,
		lerpf(ordinary_launch_speed, high_launch_speed, 0.5),
		"real contact must keep a long-held JUMP on the high branch"
	)
	router.push_intent(InputIntent.button(
		InputIntent.ACTION_JUMP,
		false,
		MonotonicClock.now_s(),
		InputIntent.SOURCE_KEYBOARD
	))
	var relic_meta := (
		level.run_state.meta.duplicate(true) as LevelMeta
	)
	relic_meta.relic_platinum_s = (
		catalog.economy.time_crate_small_s
	)
	relic_meta.relic_gold_s = (
		relic_meta.relic_platinum_s
		+ catalog.economy.time_crate_medium_s
	)
	relic_meta.relic_sapphire_s = (
		relic_meta.relic_gold_s
		+ catalog.economy.time_crate_large_s
	)
	assert_true(level.configure(
		relic_meta,
		LevelRunState.MODE_RELIC,
		catalog.economy,
		player,
		catalog.move,
		catalog.input
	))
	var tnt_shape := (
		tnt.get_node("CollisionShape3D").shape
		as BoxShape3D
	)
	assert_not_null(tnt_shape)
	if tnt_shape == null:
		return
	player.global_position = Vector3(
		tnt.global_position.x,
		tnt.global_position.y + tnt_shape.size.y * 0.5 + 0.01,
		tnt.global_position.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var collided_with_tnt := false
	var landed_on_tnt := false
	for _physics_index: int in range(
		Engine.physics_ticks_per_second
	):
		await wait_physics_frames(1)
		for collision_index: int in range(
			player.get_slide_collision_count()
		):
			var collision := player.get_slide_collision(
				collision_index
			)
			if collision.get_collider() == tnt:
				collided_with_tnt = true
				landed_on_tnt = collision.get_normal().y > 0.0
		if collided_with_tnt:
			break
	assert_true(
		collided_with_tnt,
		"the real body must retain the TNT slide collision after contact"
	)
	assert_true(
		landed_on_tnt,
		"the real body must contact the authored TNT from above"
	)
	assert_true(tnt.call("is_armed"))
	assert_false(tnt.call("is_broken"))
	await wait_physics_frames(1)
	assert_true(
		tnt.call("tnt_fuse_active"),
		"the real top contact must light the authored TNT first"
	)

	player.respawn()
	assert_false(
		tnt.call("tnt_fuse_active"),
		"the real relic death must reset the TNT attempt"
	)
	await wait_physics_frames(1)
	assert_false(
		tnt.call("tnt_fuse_active"),
		"a pre-teleport collision must not light TNT after respawn"
	)

	tnt.call("apply_verb", &"spin", 2.0)
	assert_true(tnt.call("is_broken"))
	assert_true(
		blast_neighbour.call("is_broken"),
		"TNT detonation must reach nearby authored crates"
	)


func test_real_app_pause_freezes_invincibility_and_tnt_fuse() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var tnt := _crate(level, 27)
	var catalog := (
		root.get("tuning_service").get("catalog")
		as GameplayTuning
	)
	assert_not_null(tnt)
	assert_not_null(catalog)
	if tnt == null or catalog == null:
		return
	var timer_duration_s := catalog.input.bounce_timing_s
	assert_gt(timer_duration_s, 0.0)
	if timer_duration_s <= 0.0:
		return
	catalog.economy.invincibility_duration_s = timer_duration_s
	catalog.economy.tnt_fuse_s = timer_duration_s
	var started_at_s := MonotonicClock.now_s()
	for _mask_index: int in range(
		catalog.economy.mask_stack_maximum + 1
	):
		player.call("grant_mask", started_at_s)
	tnt.call("apply_verb", &"touch", started_at_s)
	assert_true(player.call("is_invincible", started_at_s))
	assert_true(tnt.call("tnt_fuse_active"))

	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	await get_tree().create_timer(
		timer_duration_s + timer_duration_s,
		true,
		false,
		true
	).timeout
	root.get_node(
		"UI/PauseOverlay/SafeArea/Center/Panel/Margin/Rows/Resume"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"level")
	await wait_physics_frames(1)

	assert_true(
		player.call("is_invincible", MonotonicClock.now_s()),
		"background time must not consume player invincibility"
	)
	assert_false(
		tnt.call("is_broken"),
		"background time must not consume the authored TNT fuse"
	)
	assert_true(tnt.call("tnt_fuse_active"))

	var active_frame_limit := (
		ceili(timer_duration_s * Engine.physics_ticks_per_second)
		+ Engine.physics_ticks_per_second
	)
	for _physics_index: int in range(active_frame_limit):
		if (
			not player.call(
				"is_invincible",
				MonotonicClock.now_s()
			)
			and tnt.call("is_broken")
		):
			break
		await wait_physics_frames(1)
	assert_false(
		player.call("is_invincible", MonotonicClock.now_s()),
		"invincibility must still expire during active gameplay"
	)
	assert_true(
		tnt.call("is_broken"),
		"the TNT fuse must still detonate during active gameplay"
	)


func test_replay_marks_only_the_previous_runs_missed_crates() -> void:
	var seeded_profile := SaveModel.fresh()
	var record := SaveModel.level_record(
		seeded_profile,
		LEVEL_ID
	)
	record["completed"] = true
	record["last_missed_crate_ids"] = [1, 2]
	seeded_profile["levels"][String(LEVEL_ID)] = record
	assert_eq(
		SaveService.new().store_profile(
			TEST_SAVE_DIR,
			seeded_profile
		),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var missed_one := _crate(level, 1)
	var missed_two := _crate(level, 2)
	var collected_last_run := _crate(level, 3)
	var ghost_one := missed_one.get_node_or_null(
		"GhostMarker"
	) as MeshInstance3D
	assert_not_null(ghost_one)
	assert_not_null(missed_two.get_node_or_null("GhostMarker"))
	assert_null(collected_last_run.get_node_or_null("GhostMarker"))
	if ghost_one != null:
		var material := ghost_one.material_override as ShaderMaterial
		assert_not_null(material)
		if material != null:
			assert_eq(
				material.shader.resource_path,
				"res://assets/shaders/phase_ghost.gdshader"
			)

	missed_one.call("apply_verb", &"spin", 1.0)
	assert_false(ghost_one.visible)


func test_authored_level_touch_spin_remains_live_under_the_hud() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var touch := level.get_node("UI/TouchControls") as Control
	var spin_press := InputEventScreenTouch.new()
	spin_press.index = 13
	spin_press.position = (
		touch.call("current_layout")["spin_center"]
	)
	spin_press.pressed = true

	touch.call("handle_touch_event", spin_press)
	await wait_physics_frames(2)

	assert_true(player.call("is_spinning"))
	spin_press.pressed = false
	touch.call("handle_touch_event", spin_press)


func _instantiate_main() -> Node:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	return root


func _enter_authored_level(root: Node) -> LevelSession:
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": LEVEL_ID,
			}
		),
		OK
	)
	return await _wait_for_authored_level(root)


func _wait_for_authored_level(root: Node) -> LevelSession:
	for _poll_index: int in range(120):
		var level := root.get_node_or_null(
			"Content/NSanityBeach"
		) as LevelSession
		if level != null:
			return level
		await wait_process_frames(1)
	assert_true(false, "the authored level must finish threaded loading")
	return null


func _crate(level: Node, crate_id: int) -> Node:
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			candidate.has_method("apply_verb")
			and int(candidate.get("crate_id")) == crate_id
		):
			return candidate
	return null


func _fall_real_player_from_entry(
	level: LevelSession,
	player: CharacterBody3D,
	expected_deaths: int
) -> void:
	var router := level.get_node("Input/InputRouter") as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2.ZERO,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	player.global_position = Vector3(4.5, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if player.is_on_floor() and not player.call("is_respawning"):
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor(),
		"each mercy death must begin on the authored entry floor"
	)

	router.push_intent(
		InputIntent.move(
			Vector2.RIGHT,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var physically_fell := false
	for _physics_index: int in range(300):
		physically_fell = (
			physically_fell
			or player.global_position.y < 0.0
		)
		if player.call("is_respawning"):
			router.push_intent(
				InputIntent.move(
					Vector2.ZERO,
					0.0,
					InputIntent.SOURCE_KEYBOARD
				)
			)
		if level.run_state.deaths_at_checkpoint == expected_deaths:
			break
		await wait_physics_frames(1)
	assert_true(
		physically_fell,
		"each mercy retry must come from the real player falling"
	)
	assert_eq(
		level.run_state.deaths_at_checkpoint,
		expected_deaths,
		"the real respawn signal must advance the mercy counter once"
	)
	for _physics_index: int in range(120):
		if player.is_on_floor() and not player.call("is_respawning"):
			break
		await wait_physics_frames(1)
	assert_true(
		player.is_on_floor() and not player.call("is_respawning"),
		"the real player must finish respawning before the next fall"
	)


func _fall_real_relic_player_once(
	level: LevelSession,
	player: CharacterBody3D
) -> void:
	var router := level.get_node("Input/InputRouter") as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2.ZERO,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	player.global_position = Vector3(4.5, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for _physics_index: int in range(30):
		if player.is_on_floor() and not player.call("is_respawning"):
			break
		await wait_physics_frames(1)
	assert_true(player.is_on_floor())

	router.push_intent(
		InputIntent.move(
			Vector2.RIGHT,
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var physically_fell := false
	var entered_respawn_delay := false
	for _physics_index: int in range(300):
		physically_fell = (
			physically_fell
			or player.global_position.y < 0.0
		)
		if player.call("is_respawning"):
			entered_respawn_delay = true
			router.push_intent(
				InputIntent.move(
					Vector2.ZERO,
					0.0,
					InputIntent.SOURCE_KEYBOARD
				)
			)
		if (
			level.run_state.relic_void
			and not level.run_state.relic_timer_armed
		):
			break
		await wait_physics_frames(1)
	assert_true(
		physically_fell,
		"the relic death must come from leaving the real floor"
	)
	assert_true(
		entered_respawn_delay,
		"the real controller must execute its respawn delay"
	)
	assert_true(
		level.run_state.relic_void
		and not level.run_state.relic_timer_armed,
		"the real death hook must expose the void before a fresh pickup"
	)


func _walk_real_player_into_finish(
	root: Node,
	level: LevelSession,
	player: CharacterBody3D
) -> void:
	var finish := level.get_node("Finish") as Area3D
	var finish_shape := (
		finish.get_node("CollisionShape3D").shape as BoxShape3D
	)
	player.global_position = Vector3(
		finish.global_position.x,
		player.global_position.y,
		(
			finish.global_position.z
			+ finish_shape.size.z * 0.5
			+ 1.0
		)
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(1)
	assert_false(
		finish.overlaps_body(player),
		"the mercy completion must begin outside the real Finish trigger"
	)
	var start_z := player.global_position.z
	var router := level.get_node("Input/InputRouter") as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2(0.0, -1.0),
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var walked_forward := false
	for _physics_index: int in range(120):
		if root.call("state_name") == &"results":
			break
		if is_instance_valid(player):
			walked_forward = (
				walked_forward
				or player.global_position.z < start_z
			)
		await wait_physics_frames(1)
	assert_true(
		walked_forward,
		"the real controller must walk the skipped run into the exit"
	)


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for child_name: String in directory.get_directories():
		_remove_tree(path.path_join(child_name))
	DirAccess.remove_absolute(absolute)
