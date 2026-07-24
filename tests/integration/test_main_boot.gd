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
