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


# Task 9 (CTR racing mode, R2): the same round-trip-equality proof as above,
# through the real atomic store/load path, but exercising the new racing
# section (best_total_time_ms/best_lap_time_ms keyed by track id) instead of
# the platformer's own fields.
func test_round_trip_equality_preserves_racing_best_times() -> void:
	var service := SaveService.new()
	var profile := SaveModel.fresh()
	var record := SaveModel.racing_record(profile, &"graybox_loop")
	record = SaveModel.improved_racing_record(record, 61.234, [31.0, 30.234])
	var racing: Dictionary = profile["racing"]
	racing[String(&"graybox_loop")] = record

	assert_eq(service.store_profile(TEST_SAVE_DIR, profile), OK)
	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, profile)
	assert_eq(
		SaveModel.racing_record(loaded, &"graybox_loop"),
		{
			"best_total_time_ms": 61234,
			"best_lap_time_ms": 30234,
		}
	)


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


func test_store_preserves_corrupt_primary_before_publishing_profile() -> void:
	var service := SaveService.new()
	var corrupt_bytes := "{corrupt primary before store"
	_write_text(_save_path("profile.json"), corrupt_bytes)
	var replacement := SaveModel.fresh()
	replacement["lifetime_wumpa"] = 53

	assert_eq(
		service.store_profile(TEST_SAVE_DIR, replacement),
		OK
	)

	assert_eq(
		service.load_profile(TEST_SAVE_DIR),
		replacement,
		"the valid replacement must publish through the real store path"
	)
	assert_eq(
		FileAccess.get_file_as_string(
			_save_path("profile.json.corrupt")
		),
		corrupt_bytes,
		"store must preserve the invalid primary before replacing it"
	)
	assert_false(FileAccess.file_exists(
		_save_path("profile.json.tmp")
	))


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


# Task 9 (CTR racing mode, R2): the exact "a pre-racing save file must load"
# proof CLAUDE.md's compatibility rule demands. VALID_FIXTURE predates the
# racing section entirely (schema_version 1, no "racing" key at all) --
# loading it through the real service must migrate it to the current schema
# and hand back an empty-but-valid racing section, not fail closed.
#
# Task 5 (CTR R7, the Cup): SCHEMA_VERSION 2 -> 3 -- this fixture now chains
# through BOTH _migrate_v1_to_v2 AND _migrate_v2_to_v3 (see save_model.gd's
# own migrate() while-loop), so "racing" lands as {"cups": {}}, not {}. See
# test_pre_racing_v1_profile_migrates_through_the_full_v1_to_v3_chain below
# for the dedicated platformer-data-survives-and-cups-lands-empty proof
# CLAUDE.md's "same rigor as v1->v2" instruction calls for.
func test_pre_racing_v1_profile_migrates_with_empty_racing_section() -> void:
	var service := SaveService.new()
	_write_fixture(VALID_FIXTURE, _save_path("profile.json"))

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(loaded.get("schema_version"), SaveModel.SCHEMA_VERSION)
	assert_eq(loaded.get("racing"), {"cups": {}, "selected_driver": "crash"})
	assert_eq(
		SaveModel.racing_record(loaded, &"graybox_loop"),
		{
			"best_total_time_ms": 0,
			"best_lap_time_ms": 0,
		}
	)
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


# ---------------------------------------------------------------------------
# Task 5 (CTR R7, the Cup): save v3, driven through the REAL SaveService.
# load_profile() path (not SaveModel.migrate() in isolation -- that half is
# test_save_model.gd's job), with the same rigor test_legacy_profile_
# migrates_through_the_real_load_path and test_pre_racing_v1_profile_
# migrates_with_empty_racing_section above already established for v0->v1
# and v1->v2.
# ---------------------------------------------------------------------------


## The FULL v1->v4 chain (all three migration steps in one real load), on a
## fixture that carries real platformer progress predating racing entirely
## (VALID_FIXTURE, same fixture the test above uses) -- proves platformer
## data survives the whole trip AND racing.cups/racing.selected_driver both
## land at their defaults, the same "the v1 file must still load through
## EVERY migration" instruction CLAUDE.md's compatibility rule calls for.
## CTR R8 Task 3 (save v3->v4): renamed from its original "...to_v3..." name
## -- see test_save_model.gd's own identically-renamed sibling for why.
func test_pre_racing_v1_profile_migrates_through_the_full_v1_to_v4_chain() -> void:
	var service := SaveService.new()
	_write_fixture(VALID_FIXTURE, _save_path("profile.json"))

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(loaded.get("schema_version"), 4)
	assert_eq(loaded.get("lifetime_wumpa"), 17)
	assert_true(
		SaveModel.level_record(
			loaded,
			&"wr1_n_sanity_beach"
		).get("completed"),
		"pre-racing platformer progress must survive the full v1->v4 chain"
	)
	assert_true(
		SaveModel.level_record(
			loaded,
			&"wr1_n_sanity_beach"
		).get("flawless"),
	)
	assert_eq(
		loaded.get("racing"),
		{"cups": {}, "selected_driver": "crash"},
		"a v1 profile predates racing, the cup, AND the driver roster -- all three must land at their defaults"
	)
	assert_eq(
		SaveModel.cup_record(loaded, &"island_cup"),
		{"best_placement": 0}
	)
	assert_eq(SaveModel.selected_driver(loaded), &"crash")
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


## A v2 profile that already carries a real per-track best time (post-R2,
## pre-Cup, pre-driver-roster) -- proves the existing racing best SURVIVES
## the full v2->v4 chain untouched while cups and selected_driver both
## backfill to their own defaults alongside it.
func test_v2_profile_with_racing_bests_migrates_to_v4_and_gains_empty_cups_and_default_driver() -> void:
	var service := SaveService.new()
	_write_fixture(
		"res://tests/fixtures/saves/profile_v2_with_racing.json",
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(loaded.get("schema_version"), 4)
	assert_eq(
		SaveModel.racing_record(loaded, &"sanity_shores"),
		{
			"best_total_time_ms": 92500,
			"best_lap_time_ms": 30100,
		},
		"an existing v2 racing best must survive the v2->v4 migration untouched"
	)
	assert_eq(
		SaveModel.cup_record(loaded, &"island_cup"),
		{"best_placement": 0},
		"a v2 profile has never played a cup -- cups must backfill empty"
	)
	assert_eq(
		SaveModel.selected_driver(loaded),
		&"crash",
		"a v2 profile predates the driver roster entirely -- selected_driver must backfill to crash"
	)
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


## The v3->v4 step alone, on a fixture that already carries a real cup
## placement AND a real racing best (post-Cup, pre-driver-roster) -- proves
## BOTH existing reserved/per-track values survive untouched while
## selected_driver backfills to crash alongside them.
func test_v3_profile_with_racing_and_cups_migrates_to_v4_and_gains_the_default_driver() -> void:
	var service := SaveService.new()
	_write_fixture(
		"res://tests/fixtures/saves/profile_v3_with_racing.json",
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(loaded.get("schema_version"), 4)
	assert_eq(
		SaveModel.racing_record(loaded, &"sanity_shores"),
		{
			"best_total_time_ms": 88000,
			"best_lap_time_ms": 29000,
		},
		"an existing v3 racing best must survive the v3->v4 migration untouched"
	)
	assert_eq(
		SaveModel.cup_record(loaded, &"island_cup"),
		{"best_placement": 2},
		"an existing v3 cup placement must survive the v3->v4 migration untouched"
	)
	assert_eq(SaveModel.selected_driver(loaded), &"crash")
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)


## The brief's own "corrupt/unknown driver -> crash, never an error" contract,
## driven through the REAL on-disk load path (not SaveModel.migrate() in
## isolation -- that half is test_save_model.gd's job): a v4 primary whose
## selected_driver names no real DriverRegistry id must still load as _VALID
## (self-healed to crash inside migrate(), see save_model.gd's own
## _normalize_selected_driver() doc) -- UNLIKE a malformed "cups" shape
## (test_corrupt_cups_without_a_good_backup_fails_closed_to_fresh below),
## this must never fall through to _INVALID/evidence-preservation/backup-or-
## fresh, and the rest of an otherwise-valid profile (lifetime_wumpa here)
## must survive untouched.
func test_unknown_selected_driver_self_heals_to_crash_through_the_real_load_path_without_losing_the_rest_of_the_profile() -> void:
	var service := SaveService.new()
	_write_fixture(
		"res://tests/fixtures/saves/profile_v4_corrupt_driver.json",
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_true(SaveModel.validate(loaded))
	assert_eq(SaveModel.selected_driver(loaded), &"crash")
	assert_eq(
		loaded.get("lifetime_wumpa"),
		15,
		"a corrupt driver pick must not sacrifice the rest of an otherwise-valid profile"
	)
	assert_false(service.recovered_from_backup)
	assert_false(service.refused_future_version)
	assert_false(
		FileAccess.file_exists(_save_path("profile.json.corrupt")),
		"a self-healing driver id is not save-file corruption -- no evidence should be preserved"
	)


## Corrupt cups -> fail-closed to fresh(), the established path (see
## test_double_corruption_preserves_primary_evidence_and_starts_fresh above
## for the same shape on a syntactically-broken file): a v3 primary whose
## "cups" section is malformed fails SaveModel.validate() inside SaveService.
## _read_candidate(), so it is treated exactly like unparseable JSON --
## _INVALID, evidence preserved, fall through to a good backup if one exists
## or SaveModel.fresh() if not. No new SaveService code was needed for this;
## it is a direct consequence of validate() correctly rejecting the
## malformed shape (see test_save_model.gd's own test_corrupt_cups_fails_
## validation_and_migration_closed for that half in isolation).
func test_corrupt_cups_recovers_previous_good_backup() -> void:
	var service := SaveService.new()
	var good := SaveModel.fresh()
	good["racing"]["cups"]["island_cup"] = {"best_placement": 2}
	var second := SaveModel.fresh()
	second["lifetime_wumpa"] = 99
	# Two stores, same shape test_corrupt_primary_recovers_previous_good_
	# backup above uses: store_profile() only writes a .bak from whatever the
	# PREVIOUS primary already held (see save_service.gd's own store_profile()
	# doc), so a single store leaves no backup at all -- the second store is
	# what turns `good` into the backup this test recovers from.
	assert_eq(service.store_profile(TEST_SAVE_DIR, good), OK)
	assert_eq(service.store_profile(TEST_SAVE_DIR, second), OK)
	assert_true(FileAccess.file_exists(_save_path("profile.json.bak")))
	_write_fixture(
		"res://tests/fixtures/saves/profile_v3_corrupt_cups.json",
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, good)
	assert_true(service.recovered_from_backup)


func test_corrupt_cups_without_a_good_backup_fails_closed_to_fresh() -> void:
	var service := SaveService.new()
	_write_fixture(
		"res://tests/fixtures/saves/profile_v3_corrupt_cups.json",
		_save_path("profile.json")
	)

	var loaded := service.load_profile(TEST_SAVE_DIR)

	assert_eq(loaded, SaveModel.fresh())
	assert_true(
		FileAccess.file_exists(_save_path("profile.json.corrupt")),
		"the malformed cups primary must be preserved as evidence, not silently discarded"
	)
	assert_false(service.recovered_from_backup)


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
