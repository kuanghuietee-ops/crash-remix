extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const DEFAULT_SAVE_DIR := "user://save"
const TEST_SAVE_DIR := "user://test_sandbox/task5_main_boot"
const PLACEHOLDER_LEVEL_ID := &"test_level"
const FUTURE_SAVE_FIXTURE := (
	"res://tests/fixtures/saves/profile_future_version.json"
)
const N_SANITY_META_PATH := (
	"res://data/tuning/levels/n_sanity_beach.tres"
)


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)
	var phase_state := get_node_or_null("/root/PhaseState")
	if phase_state != null:
		phase_state.call("reset_to_authored_set")


func test_main_boots_fresh_profile_to_warp_room_through_scratch_path() -> void:
	var live_primary := DEFAULT_SAVE_DIR.path_join("profile.json")
	var live_existed := FileAccess.file_exists(live_primary)
	var live_bytes := (
		FileAccess.get_file_as_bytes(live_primary)
		if live_existed
		else PackedByteArray()
	)
	assert_true(
		ResourceLoader.exists(MAIN_SCENE_PATH),
		"Phase 1 main scene must exist"
	)
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		return
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"warp_room")
	assert_true(SaveModel.validate(root.get("profile")))
	assert_eq(root.get("save_dir"), TEST_SAVE_DIR)
	assert_true(root.has_node("Content/WarpRoom1"))
	var hub_player := root.get_node("Content/WarpRoom1/Player")
	assert_true(
		_has_property(hub_player, &"_phase_enabled"),
		"the hub player must receive the progression consumption gate"
	)
	if _has_property(hub_player, &"_phase_enabled"):
		assert_false(hub_player.get("_phase_enabled"))
	assert_false(
		DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(TEST_SAVE_DIR)
		),
		"loading a fresh profile must not create a save directory"
	)
	assert_eq(FileAccess.file_exists(live_primary), live_existed)
	if live_existed:
		assert_eq(FileAccess.get_file_as_bytes(live_primary), live_bytes)


func test_future_profile_refuses_real_boot_without_overwrite() -> void:
	var primary_path := TEST_SAVE_DIR.path_join("profile.json")
	_write_text(
		primary_path,
		FileAccess.get_file_as_string(FUTURE_SAVE_FIXTURE)
	)
	var before := FileAccess.get_file_as_bytes(primary_path)
	var root := _instantiate_main()
	if root == null:
		return

	await wait_process_frames(1)

	assert_push_error("Save data was written by a newer version")
	assert_eq(root.get("boot_error"), ERR_UNAVAILABLE)
	assert_eq(root.call("state_name"), &"boot")
	assert_false(root.has_node("Content/WarpRoom1"))
	assert_eq(
		FileAccess.get_file_as_bytes(primary_path),
		before,
		"Q9 must leave the future save byte-identical"
	)


func test_wr4_completion_routes_phase_unlock_to_hub_ui_and_player() -> void:
	var profile := SaveModel.fresh()
	var future_level_id := &"wr4_future_fixture"
	var record := SaveModel.level_record(profile, future_level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(future_level_id)] = record
	var service := SaveService.new()
	assert_eq(
		service.store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var player := root.get_node("Content/WarpRoom1/Player")
	assert_true(
		_has_property(player, &"_phase_enabled"),
		"the hub player must expose the progression gate"
	)
	if not _has_property(player, &"_phase_enabled"):
		return

	assert_true(player.get("_phase_enabled"))
	var touch := root.get_node(
		"Content/WarpRoom1/UI/TouchControls"
	)
	assert_true(
		(touch.call("current_layout") as Dictionary).has(
			"phase_center"
		)
	)


func test_fresh_profile_keeps_phase_locked_in_authored_level() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	assert_not_null(level, "the known level id must load the authored scene")
	if level == null:
		return
	var player := level.get_node("Player")
	assert_false(player.get("_phase_enabled"))
	var touch := level.get_node("UI/TouchControls")
	assert_false(
		(touch.call("current_layout") as Dictionary).has(
			"phase_center"
		)
	)


func test_wr4_unlock_reaches_real_level_portal_player_and_touch() -> void:
	var profile := SaveModel.fresh()
	var future_level_id := &"wr4_future_fixture"
	var record := SaveModel.level_record(profile, future_level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(future_level_id)] = record
	assert_eq(
		SaveService.new().store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var portal := _portal_for_level(
		room,
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return

	portal.emit_signal(&"body_entered", room.get_node("Player"))
	var level := await _wait_for_authored_level(root)
	assert_not_null(level, "the real hub portal must load the authored scene")
	if level == null:
		return
	var touch := level.get_node("UI/TouchControls")
	var layout := touch.call("current_layout") as Dictionary
	assert_true(
		layout.has("phase_center"),
		"the unlocked level must render a real PHASE touch target"
	)
	if not layout.has("phase_center"):
		return
	var phase_state := get_node("/root/PhaseState")
	var before: StringName = phase_state.call("active_set")
	var press := InputEventScreenTouch.new()
	press.index = 29
	press.position = layout["phase_center"]
	press.pressed = true
	touch.call("handle_touch_event", press)

	await wait_physics_frames(1)

	var release := InputEventScreenTouch.new()
	release.index = press.index
	release.position = press.position
	release.pressed = false
	touch.call("handle_touch_event", release)
	assert_ne(
		phase_state.call("active_set"),
		before,
		"the real level player must consume the routed PHASE intent"
	)


func test_main_scene_owns_live_tuning_fingerprint_contract() -> void:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		assert_true(false, "Phase 1 main scene must exist")
		return
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	var service: Variant = root.get("tuning_service")
	var debug_ui := root.get_node("UI/TuningDebug")
	var summary: String = debug_ui.call("summary_text")
	assert_not_null(service)
	assert_not_null(service.get("catalog"))
	assert_string_contains(summary, service.call("fingerprint"))
	assert_string_contains(summary, "res://data/tuning/gameplay.tres")


func test_real_level_entry_reports_level_meta_to_live_tuning_hud() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var portal := _portal_for_level(
		room,
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return

	portal.emit_signal(&"body_entered", room.get_node("Player"))
	var level := await _wait_for_authored_level(root)
	assert_not_null(level, "the real hub portal must load the authored scene")
	if level == null:
		return
	var meta := load(N_SANITY_META_PATH) as LevelMeta
	var summary: String = root.get_node(
		"UI/TuningDebug"
	).call("summary_text")

	assert_string_contains(summary, N_SANITY_META_PATH)
	assert_string_contains(
		summary,
		String(meta.fingerprint()).left(12)
	)


func test_project_boots_the_new_main_scene() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"),
		MAIN_SCENE_PATH
	)


func test_boot_consumes_valid_session_into_the_authored_level() -> void:
	var snapshot := _normal_snapshot()
	snapshot["timestamp_unix_s"] = Time.get_unix_time_from_system()
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(snapshot)
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	var flow: Variant = root.get("flow")
	assert_eq(root.call("state_name"), &"level")
	var level := await _wait_for_authored_level(root)
	if level == null:
		return
	assert_eq(level.run_state.broken_crate_ids, [1])
	assert_eq(level.run_state.wumpa_run, 1)
	assert_eq(
		level.run_state.authored_crate_ids.size(),
		level.run_state.meta.crate_count,
		"the live scene catalog must override stale snapshot crate ids"
	)
	assert_true(flow.get("resume_snapshot").is_empty())


func test_corrupt_session_is_discarded_while_profile_still_loads() -> void:
	var profile := SaveModel.fresh()
	profile["lifetime_wumpa"] = 17
	var profile_service := SaveService.new()
	assert_eq(
		profile_service.store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		"{broken session"
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"warp_room")
	assert_eq(root.get("profile").get("lifetime_wumpa"), 17)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_application_pause_auto_pauses_and_snapshots_active_run() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call("set_active_level_session", session)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)

	assert_eq(root.call("state_name"), &"paused")
	var stored: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_true(stored is Dictionary)
	if stored is Dictionary:
		assert_eq(stored.get("crates_broken"), [1.0])


func test_level_completion_deletes_session_snapshot() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(_normal_snapshot())
	)

	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_quit_to_hub_deletes_session_snapshot() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(_normal_snapshot())
	)

	assert_eq(
		root.call("dispatch", {"type": &"quit_level"}),
		OK
	)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_task11_ui_is_owned_by_main_and_starts_out_of_the_way() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	assert_true(root.has_node("UI/HUD"))
	assert_true(root.has_node("UI/ResultsScreen"))
	assert_true(root.has_node("UI/PauseOverlay"))
	assert_true(root.has_node("UI/LevelListOverlay"))
	if not root.has_node("UI/HUD"):
		return
	for screen_name: String in [
		"HUD",
		"ResultsScreen",
		"PauseOverlay",
		"LevelListOverlay",
	]:
		assert_true(
			root.has_node("UI/%s/SafeArea" % screen_name),
			"%s must map required UI into the device safe area"
			% screen_name
		)
	assert_false(root.get_node("UI/HUD").visible)
	assert_false(root.get_node("UI/ResultsScreen").visible)
	assert_false(root.get_node("UI/PauseOverlay").visible)
	assert_false(root.get_node("UI/LevelListOverlay").visible)


func test_level_completion_builds_persists_and_presents_results() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.get_node("Content/LevelPlaceholder").add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 2
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call(
		"set_active_level_session",
		session,
		meta,
		{
			1: &"Beach Start",
			2: &"Finish",
		}
	)

	session.complete_level()

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(payload.get("box_count"), 1)
	assert_eq(payload.get("crate_count"), 2)
	assert_eq(payload.get("missed_crate_ids"), [2])
	assert_eq(
		payload.get("missed_crate_ids_by_segment"),
		{"Finish": [2]}
	)
	assert_eq(root.get("last_save_error"), OK)
	var saved_record := SaveModel.level_record(
		root.get("profile"),
		meta.level_id
	)
	assert_true(saved_record.get("completed"))
	assert_eq(saved_record.get("last_missed_crate_ids"), [2])
	assert_true(root.get_node("UI/ResultsScreen").visible)
	assert_true(root.has_node("Content/ResultsPlaceholder"))


func test_results_relic_entry_stays_locked_then_retries_in_relic_mode() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	root.set("_active_level_meta", meta)
	var profile: Dictionary = root.get("profile")
	var record := SaveModel.level_record(
		profile,
		meta.level_id
	)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(meta.level_id)] = record
	root.set("profile", profile)
	var results := root.get_node("UI/ResultsScreen")

	results.emit_signal(&"relic_requested")

	assert_eq(root.call("state_name"), &"results")
	assert_eq(
		root.get("flow").get("active_level_mode"),
		LevelRunState.MODE_NORMAL
	)

	var economy := (
		load("res://data/tuning/gameplay.tres")
		as GameplayTuning
	).economy
	meta.relic_platinum_s = economy.time_crate_small_s
	meta.relic_gold_s = (
		meta.relic_platinum_s
		+ economy.time_crate_medium_s
	)
	meta.relic_sapphire_s = (
		meta.relic_gold_s
		+ economy.time_crate_large_s
	)
	results.emit_signal(&"relic_requested")

	assert_eq(root.call("state_name"), &"level")
	assert_eq(
		root.get("flow").get("active_level_mode"),
		LevelRunState.MODE_RELIC
	)


func test_pause_overlay_preserves_level_content_and_retry_is_direct() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var level_content := root.get_node("Content/LevelPlaceholder")

	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	assert_same(
		root.get_node("Content/LevelPlaceholder"),
		level_content
	)
	assert_true(root.get_node("UI/PauseOverlay").visible)
	assert_eq(
		root.call("dispatch", {"type": &"resume"}),
		OK
	)
	assert_same(
		root.get_node("Content/LevelPlaceholder"),
		level_content
	)

	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	root.get_node("UI/ResultsScreen").emit_signal(
		"retry_requested"
	)
	assert_eq(root.call("state_name"), &"level")
	assert_eq(
		root.get("flow").get("active_level_id"),
		PLACEHOLDER_LEVEL_ID
	)


func test_hud_pause_button_reaches_the_real_pause_overlay() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var pause_button := root.get_node_or_null(
		"UI/HUD/SafeArea/Pause"
	) as Button
	assert_not_null(
		pause_button,
		"the live HUD must expose a touch-reachable pause button"
	)
	if pause_button == null:
		return
	assert_true(pause_button.visible)
	assert_false(root.get_node("UI/PauseOverlay").visible)
	await wait_process_frames(1)
	var touch_position := pause_button.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 21
	press.position = touch_position
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.index = press.index
	release.position = touch_position
	release.pressed = false

	var hud := root.get_node("UI/HUD")
	hud.call("_input", press)
	hud.call("_input", release)
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"paused")
	assert_true(root.get_node("UI/PauseOverlay").visible)
	assert_true(get_tree().paused)


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
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	return await _wait_for_authored_level(root)


func _portal_for_level(
	room: Node,
	level_id: StringName
) -> Area3D:
	for candidate: Node in room.find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if (
			candidate.is_in_group(&"warp_portal")
			and StringName(
				candidate.get_meta("level_id", &"")
			) == level_id
		):
			return candidate as Area3D
	return null


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


func _normal_snapshot() -> Dictionary:
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var state := LevelRunState.new()
	state.start(meta, &"normal")
	state.record_crate_broken(1, 1)
	return state.snapshot()


func _write_text(path: String, text: String) -> void:
	assert_eq(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(path.get_base_dir())
		),
		OK
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


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
