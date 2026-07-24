extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const DEFAULT_SAVE_DIR := "user://save"
const TEST_SAVE_DIR := "user://test_sandbox/task5_main_boot"


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


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
	assert_true(root.has_node("Content/WarpRoomPlaceholder"))
	assert_false(
		DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(TEST_SAVE_DIR)
		),
		"loading a fresh profile must not create a save directory"
	)
	assert_eq(FileAccess.file_exists(live_primary), live_existed)
	if live_existed:
		assert_eq(FileAccess.get_file_as_bytes(live_primary), live_bytes)


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


func test_project_boots_the_new_main_scene() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"),
		MAIN_SCENE_PATH
	)


func test_boot_surfaces_valid_session_as_flow_resume_decision() -> void:
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
	var resume_snapshot: Variant = flow.get("resume_snapshot")
	assert_eq(root.call("state_name"), &"warp_room")
	assert_true(resume_snapshot is Dictionary)
	if resume_snapshot is Dictionary:
		assert_eq(
			resume_snapshot.get("level_id"),
			&"wr1_n_sanity_beach"
		)


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
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.add_child(session)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate(true) as GameplayTuning
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
				"level_id": &"wr1_n_sanity_beach",
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
				"level_id": &"wr1_n_sanity_beach",
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
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.get_node("Content/LevelPlaceholder").add_child(session)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 2
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate(true) as GameplayTuning
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
				"level_id": &"wr1_n_sanity_beach",
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
		&"wr1_n_sanity_beach"
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
