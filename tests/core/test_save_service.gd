extends GutTest

const TEST_SAVE_DIR := "user://test_sandbox/task4_save_service"
const VALID_FIXTURE := "res://tests/fixtures/saves/profile_v1_valid.json"
const CORRUPT_FIXTURE := "res://tests/fixtures/saves/profile_corrupt.json"
const FUTURE_FIXTURE := (
	"res://tests/fixtures/saves/profile_future_version.json"
)


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_round_trip_equality() -> void:
	var service := SaveService.new()
	var profile := SaveModel.fresh()
	profile["lifetime_wumpa"] = 17
	profile["operator_note"] = "preserve"

	assert_eq(service.store_profile(TEST_SAVE_DIR, profile), OK)
	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, profile)
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


func test_first_store_without_existing_primary_succeeds() -> void:
	var service := SaveService.new()
	var profile := SaveModel.fresh()

	assert_eq(service.store_profile(TEST_SAVE_DIR, profile), OK)

	assert_true(FileAccess.file_exists(_save_path("profile.json")))
	assert_true(SaveModel.validate(_read_json(_save_path("profile.json"))))
	assert_false(FileAccess.file_exists(_save_path("profile.json.bak")))


func test_corrupt_primary_recovers_previous_good_backup() -> void:
	var service := SaveService.new()
	var first := SaveModel.fresh()
	first["lifetime_wumpa"] = 17
	var second := SaveModel.fresh()
	second["lifetime_wumpa"] = 31
	assert_eq(service.store_profile(TEST_SAVE_DIR, first), OK)
	assert_eq(service.store_profile(TEST_SAVE_DIR, second), OK)
	assert_true(FileAccess.file_exists(_save_path("profile.json.bak")))
	_write_text(_save_path("profile.json"), "{broken primary")

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, first)
	assert_true(service.recovered_from_backup)


func test_stale_tmp_is_ignored_and_cleaned() -> void:
	var service := SaveService.new()
	var profile := SaveModel.fresh()
	profile["lifetime_wumpa"] = 23
	assert_eq(service.store_profile(TEST_SAVE_DIR, profile), OK)
	_write_text(_save_path("profile.json.tmp"), "{\"partial\":")

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, profile)
	assert_false(FileAccess.file_exists(_save_path("profile.json.tmp")))


func test_future_version_is_refused_without_overwrite() -> void:
	var service := SaveService.new()
	_write_fixture(FUTURE_FIXTURE, _save_path("profile.json"))
	var before := FileAccess.get_file_as_string(_save_path("profile.json"))

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, {})
	assert_true(service.refused_future_version)
	assert_eq(
		FileAccess.get_file_as_string(_save_path("profile.json")),
		before
	)
	assert_eq(
		service.store_profile(TEST_SAVE_DIR, SaveModel.fresh()),
		ERR_UNAVAILABLE
	)
	assert_eq(
		FileAccess.get_file_as_string(_save_path("profile.json")),
		before
	)


func test_double_corruption_preserves_primary_evidence_and_starts_fresh() -> void:
	var service := SaveService.new()
	_write_fixture(CORRUPT_FIXTURE, _save_path("profile.json"))
	_write_text(_save_path("profile.json.bak"), "{broken backup")
	var primary_bytes := FileAccess.get_file_as_string(
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, SaveModel.fresh())
	assert_true(FileAccess.file_exists(_save_path("profile.json.corrupt")))
	assert_eq(
		FileAccess.get_file_as_string(_save_path("profile.json.corrupt")),
		primary_bytes
	)


func test_valid_fixture_loads() -> void:
	var service := SaveService.new()
	_write_fixture(VALID_FIXTURE, _save_path("profile.json"))

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(loaded.get("lifetime_wumpa"), 17)
	assert_true(
		SaveModel.level_record(
			loaded,
			&"wr1_n_sanity_beach"
		).get("completed")
	)


func _save_path(file_name: String) -> String:
	return TEST_SAVE_DIR.path_join(file_name)


func _write_fixture(source_path: String, target_path: String) -> void:
	_write_text(target_path, FileAccess.get_file_as_string(source_path))


func _write_text(path: String, text: String) -> void:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	assert_eq(
		DirAccess.make_dir_recursive_absolute(absolute_directory),
		OK
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


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
