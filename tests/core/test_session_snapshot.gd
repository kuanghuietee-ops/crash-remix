extends GutTest

const SESSION_SNAPSHOT_PATH := "res://src/core/session_snapshot.gd"
const TEST_SAVE_DIR := "user://test_sandbox/task9_session_snapshot"

var _catalog: GameplayTuning
var _meta: LevelMeta


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)
	_catalog = load(
		"res://data/tuning/gameplay.tres"
	).duplicate(true) as GameplayTuning
	_meta = load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	_meta.crate_count = _catalog.economy.mercy_mask_death_threshold


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_snapshot_round_trip_restores_level_run_state() -> void:
	var service := _new_service()
	if service == null:
		return
	var state := LevelRunState.new()
	state.start(_meta, &"normal")
	state.record_crate_broken(
		1,
		_catalog.economy.wumpa_per_standard_crate
	)
	state.record_checkpoint(
		_catalog.economy.mercy_mask_death_threshold
	)

	assert_eq(
		service.call("store", TEST_SAVE_DIR, state.snapshot()),
		OK
	)
	var loaded: Dictionary = service.call("load", TEST_SAVE_DIR)
	var restored := LevelRunState.restore(loaded, _meta)

	assert_eq(restored.broken_crate_ids, [1])
	assert_eq(
		restored.checkpoint_id,
		_catalog.economy.mercy_mask_death_threshold
	)
	assert_eq(
		restored.wumpa_run,
		_catalog.economy.wumpa_per_standard_crate
	)
	assert_true(loaded.has("timestamp_unix_s"))
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json.tmp")
		)
	)


func test_relic_snapshot_restores_as_voided_fresh_attempt() -> void:
	var service := _new_service()
	if service == null:
		return
	var state := LevelRunState.new()
	state.start(_meta, &"relic")
	state.record_crate_broken(
		1,
		_catalog.economy.wumpa_per_standard_crate
	)

	assert_eq(
		service.call("store", TEST_SAVE_DIR, state.snapshot()),
		OK
	)
	var restored := LevelRunState.restore(
		service.call("load", TEST_SAVE_DIR),
		_meta
	)

	assert_true(restored.relic_void)
	assert_eq(restored.broken_crate_ids, [])
	assert_eq(restored.wumpa_run, 0)
	assert_eq(restored.checkpoint_id, -1)


func test_corrupt_snapshot_is_discarded_without_parser_error() -> void:
	var service := _new_service()
	if service == null:
		return
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		"{broken session"
	)

	var loaded: Dictionary = service.call("load", TEST_SAVE_DIR)

	assert_eq(loaded, {})
	assert_true(service.get("discarded_corrupt"))
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_delete_removes_primary_and_stale_temp() -> void:
	var service := _new_service()
	if service == null:
		return
	var state := LevelRunState.new()
	state.start(_meta, &"normal")
	assert_eq(
		service.call("store", TEST_SAVE_DIR, state.snapshot()),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json.tmp"),
		"{partial"
	)

	assert_eq(service.call("delete", TEST_SAVE_DIR), OK)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json.tmp")
		)
	)


func _new_service() -> RefCounted:
	assert_true(
		ResourceLoader.exists(SESSION_SNAPSHOT_PATH),
		"SessionSnapshot implementation must exist"
	)
	if not ResourceLoader.exists(SESSION_SNAPSHOT_PATH):
		return null
	var script := load(SESSION_SNAPSHOT_PATH) as Script
	return script.new() as RefCounted


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
