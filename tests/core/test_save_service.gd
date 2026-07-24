extends GutTest

const TEST_SAVE_DIR := "user://test_sandbox/task4_save_service"
const LEGACY_FIXTURE := "res://tests/fixtures/saves/profile_v0_valid.json"
const VALID_FIXTURE := "res://tests/fixtures/saves/profile_v1_valid.json"
const CORRUPT_FIXTURE := "res://tests/fixtures/saves/profile_corrupt.json"
const FUTURE_FIXTURE := (
	"res://tests/fixtures/saves/profile_future_version.json"
)


class RecordingSaveService:
	extends SaveService

	var filesystem_events: Array[String] = []
	var copy_error: Error = OK

	func _flush_file(file: FileAccess) -> void:
		filesystem_events.append("flush")
		file.flush()

	func _copy_absolute(
		source_absolute: String,
		target_absolute: String
	) -> Error:
		filesystem_events.append(
			"copy:%s->%s" % [
				source_absolute.get_file(),
				target_absolute.get_file(),
			]
		)
		if copy_error != OK:
			return copy_error
		return DirAccess.copy_absolute(
			source_absolute,
			target_absolute
		)

	func _rename_absolute(
		source_absolute: String,
		target_absolute: String
	) -> Error:
		filesystem_events.append(
			"rename:%s->%s" % [
				source_absolute.get_file(),
				target_absolute.get_file(),
			]
		)
		return DirAccess.rename_absolute(
			source_absolute,
			target_absolute
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


func test_store_flushes_before_atomic_rename_over_primary() -> void:
	var service := RecordingSaveService.new()
	var first := SaveModel.fresh()
	first["lifetime_wumpa"] = 17
	var second := SaveModel.fresh()
	second["lifetime_wumpa"] = 31
	assert_eq(service.store_profile(TEST_SAVE_DIR, first), OK)
	service.filesystem_events.clear()

	assert_eq(service.store_profile(TEST_SAVE_DIR, second), OK)

	assert_eq(
		service.filesystem_events,
		[
			"flush",
			"copy:profile.json->profile.json.bak",
			"rename:profile.json.tmp->profile.json",
		],
		"the real transaction must flush, back up, then publish by rename"
	)
	var stored_primary := _read_json(_save_path("profile.json"))
	var stored_backup := _read_json(_save_path("profile.json.bak"))
	assert_true(SaveModel.validate(stored_primary))
	assert_true(SaveModel.validate(stored_backup))
	assert_eq(int(stored_primary.get("lifetime_wumpa")), 31)
	assert_eq(int(stored_backup.get("lifetime_wumpa")), 17)
	assert_false(FileAccess.file_exists(_save_path("profile.json.tmp")))


func test_failed_backup_copy_keeps_previous_redundancy() -> void:
	var service := RecordingSaveService.new()
	var first := SaveModel.fresh()
	first["lifetime_wumpa"] = 17
	var second := SaveModel.fresh()
	second["lifetime_wumpa"] = 31
	var third := SaveModel.fresh()
	third["lifetime_wumpa"] = 47
	assert_eq(service.store_profile(TEST_SAVE_DIR, first), OK)
	assert_eq(service.store_profile(TEST_SAVE_DIR, second), OK)
	var backup_before := FileAccess.get_file_as_bytes(
		_save_path("profile.json.bak")
	)
	service.copy_error = ERR_CANT_CREATE

	assert_eq(
		service.store_profile(TEST_SAVE_DIR, third),
		ERR_CANT_CREATE
	)

	assert_true(FileAccess.file_exists(
		_save_path("profile.json.bak")
	))
	assert_eq(
		FileAccess.get_file_as_bytes(
			_save_path("profile.json.bak")
		),
		backup_before,
		"a failed replacement copy must preserve the old backup"
	)
	assert_eq(
		int(_read_json(
			_save_path("profile.json")
		).get("lifetime_wumpa")),
		31,
		"the unpublished profile must not replace the primary"
	)
	assert_false(FileAccess.file_exists(
		_save_path("profile.json.tmp")
	))


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


func test_new_corruption_preserves_every_previous_incident() -> void:
	var service := SaveService.new()
	var previous_incident := "{previous corrupt profile"
	var current_incident := "{current corrupt profile"
	_write_text(
		_save_path("profile.json.corrupt"),
		previous_incident
	)
	_write_text(_save_path("profile.json"), current_incident)

	assert_eq(service.load_profile(TEST_SAVE_DIR), SaveModel.fresh())

	assert_eq(
		FileAccess.get_file_as_string(
			_save_path("profile.json.corrupt")
		),
		previous_incident,
		"preserving a new incident must not destroy old evidence"
	)
	assert_eq(
		FileAccess.get_file_as_string(
			_save_path("profile.json.corrupt.1")
		),
		current_incident,
		"the new incident must be preserved beside the old one"
	)
	assert_eq(service.load_profile(TEST_SAVE_DIR), SaveModel.fresh())
	assert_false(
		FileAccess.file_exists(
			_save_path("profile.json.corrupt.2")
		),
		"reloading the same corrupt bytes must not duplicate evidence"
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


func test_legacy_profile_migrates_through_the_real_load_path() -> void:
	var service := SaveService.new()
	_write_fixture(LEGACY_FIXTURE, _save_path("profile.json"))

	var loaded := service.load_profile(TEST_SAVE_DIR)
	var record := SaveModel.level_record(
		loaded,
		&"wr1_n_sanity_beach"
	)

	assert_true(SaveModel.validate(loaded))
	assert_eq(
		loaded.get("schema_version"),
		SaveModel.SCHEMA_VERSION
	)
	assert_eq(loaded.get("lifetime_wumpa"), 4211)
	assert_eq(loaded.get("operator_note"), "keep me")
	assert_true(record.get("completed"))
	assert_true(record.get("gem"))
	assert_eq(record.get("relic_tier"), "platinum")
	assert_eq(record.get("best_relic_time_ms"), 73421)
	assert_true(record.get("flawless"))
	assert_eq(
		record.get("legacy_level_note"),
		"preserve this too"
	)
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


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
