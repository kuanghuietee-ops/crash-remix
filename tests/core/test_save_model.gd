extends GutTest


func test_fresh_profile_is_valid_schema_one() -> void:
	var profile := SaveModel.fresh()

	assert_eq(profile.get("schema_version"), SaveModel.SCHEMA_VERSION)
	assert_true(SaveModel.validate(profile))
	assert_eq(profile.get("levels"), {})
	assert_eq(profile.get("lifetime_wumpa"), 0)
	assert_eq(profile.get("boss_defeated"), {"papu_papu": false})
	# Task 5 (CTR R7, the Cup): SCHEMA_VERSION 2 -> 3 -- "racing" now carries
	# a required, reserved "cups" key alongside its (still empty on a fresh
	# profile) per-track best-time entries. See _fresh_racing_record()'s own
	# sibling assertion below for the per-track shape, unchanged.
	assert_eq(profile.get("racing"), {"cups": {}})


func test_migration_identity_preserves_unknown_fields() -> void:
	var profile := SaveModel.fresh()
	profile["operator_note"] = "keep me"

	var migrated := SaveModel.migrate(profile)

	assert_eq(migrated.get("operator_note"), "keep me")
	assert_true(SaveModel.validate(migrated))
	assert_not_same(migrated, profile)


func test_future_schema_is_detected_and_not_migrated() -> void:
	var future := SaveModel.fresh()
	future["schema_version"] = SaveModel.SCHEMA_VERSION + 1

	assert_true(SaveModel.is_future_version(future))
	assert_eq(SaveModel.migrate(future), {})


func test_level_record_supplies_v1_defaults_without_mutating_profile() -> void:
	var profile := SaveModel.fresh()

	var record := SaveModel.level_record(profile, &"wr1_n_sanity_beach")

	assert_eq(
		record,
		{
			"completed": false,
			"gem": false,
			"relic_tier": "none",
			"best_relic_time_ms": 0,
			"flawless": false,
			"last_missed_crate_ids": [],
		}
	)
	assert_eq(profile.get("levels"), {})


func test_task4_v1_without_last_missed_crate_ids_defaults_to_empty() -> void:
	var task4_profile := SaveModel.fresh()
	var levels: Dictionary = task4_profile["levels"]
	levels["wr1_n_sanity_beach"] = {
		"completed": true,
		"gem": false,
		"relic_tier": "none",
		"best_relic_time_ms": 0,
		"flawless": true,
	}

	assert_true(SaveModel.validate(task4_profile))
	assert_eq(
		SaveModel.level_record(
			task4_profile,
			&"wr1_n_sanity_beach"
		).get("last_missed_crate_ids"),
		[]
	)


# Task 9 (CTR racing mode, R2): the racing section mirrors "levels" --
# SCHEMA_VERSION bumped 1 -> 2, racing_record() supplies the same
# fresh-defaults-without-mutating-profile contract level_record() already
# proves above, keyed by a track id (StringName) instead of a level id.
func test_racing_record_supplies_defaults_without_mutating_profile() -> void:
	var profile := SaveModel.fresh()

	var record := SaveModel.racing_record(profile, &"graybox_loop")

	assert_eq(
		record,
		{
			"best_total_time_ms": 0,
			"best_lap_time_ms": 0,
		}
	)
	assert_eq(profile.get("racing"), {"cups": {}})


func test_improved_racing_record_stores_first_total_and_lap_time() -> void:
	var record := SaveModel.racing_record(SaveModel.fresh(), &"graybox_loop")

	var updated := SaveModel.improved_racing_record(
		record,
		61.234,
		[31.0, 30.234]
	)

	assert_eq(updated.get("best_total_time_ms"), 61234)
	assert_eq(updated.get("best_lap_time_ms"), 30234)


func test_improved_racing_record_keeps_the_faster_total_and_lap_independently() -> void:
	var record := {
		"best_total_time_ms": 60000,
		"best_lap_time_ms": 29000,
	}

	var slower := SaveModel.improved_racing_record(record, 65.0, [32.5, 32.5])
	assert_eq(
		slower,
		record,
		"a slower total and slower laps must not touch either best"
	)

	var faster_total := SaveModel.improved_racing_record(
		record,
		58.0,
		[29.0, 29.0]
	)
	assert_eq(faster_total.get("best_total_time_ms"), 58000)
	assert_eq(
		faster_total.get("best_lap_time_ms"),
		29000,
		"a lap time that merely ties the existing best must not overwrite it"
	)

	var faster_lap_only := SaveModel.improved_racing_record(
		record,
		61.0,
		[28.5, 32.5]
	)
	assert_eq(
		faster_lap_only.get("best_total_time_ms"),
		60000,
		"a slower total must not be overwritten by an unrelated faster lap"
	)
	assert_eq(faster_lap_only.get("best_lap_time_ms"), 28500)


func test_improved_racing_record_rejects_invalid_input() -> void:
	var record := SaveModel.racing_record(SaveModel.fresh(), &"graybox_loop")

	assert_eq(
		SaveModel.improved_racing_record(record, -1.0, [10.0]),
		{},
		"a negative elapsed time must be rejected"
	)
	assert_eq(
		SaveModel.improved_racing_record({}, 10.0, [10.0]),
		{},
		"a malformed existing record must be rejected"
	)


# ---------------------------------------------------------------------------
# Task 5 (CTR R7, the Cup): save v3. cup_record()/improved_cup_record() are
# the cup's own counterpart to racing_record()/improved_racing_record()
# above -- same shape, same tests, one level deeper (through racing's own
# reserved "cups" key).
# ---------------------------------------------------------------------------


func test_cup_record_supplies_defaults_without_mutating_profile() -> void:
	var profile := SaveModel.fresh()

	var record := SaveModel.cup_record(profile, &"island_cup")

	assert_eq(record, {"best_placement": 0})
	assert_eq(profile.get("racing"), {"cups": {}})


func test_improved_cup_record_stores_first_placement() -> void:
	var record := SaveModel.cup_record(SaveModel.fresh(), &"island_cup")

	var updated := SaveModel.improved_cup_record(record, 3)

	assert_eq(updated.get("best_placement"), 3)


func test_improved_cup_record_keeps_the_better_lower_placement() -> void:
	var record := {"best_placement": 2}

	var worse := SaveModel.improved_cup_record(record, 4)
	assert_eq(
		worse,
		record,
		"a worse (higher-numbered) placement must not overwrite the best"
	)

	var tie := SaveModel.improved_cup_record(record, 2)
	assert_eq(
		tie,
		record,
		"a tying placement must not be treated as an improvement"
	)

	var better := SaveModel.improved_cup_record(record, 1)
	assert_eq(better.get("best_placement"), 1)


func test_improved_cup_record_rejects_invalid_input() -> void:
	var record := SaveModel.cup_record(SaveModel.fresh(), &"island_cup")

	assert_eq(
		SaveModel.improved_cup_record(record, 0),
		{},
		"a zero placement must be rejected -- 1 is the best possible finish"
	)
	assert_eq(
		SaveModel.improved_cup_record(record, -1),
		{},
		"a negative placement must be rejected"
	)
	assert_eq(
		SaveModel.improved_cup_record({}, 1),
		{},
		"a malformed existing record must be rejected"
	)


# ---------------------------------------------------------------------------
# Task 5 (CTR R7, the Cup): SCHEMA_VERSION 2 -> 3 migration proofs at the
# pure SaveModel.migrate() level (see test_save_service.gd for the same
# proofs driven through the real on-disk SaveService load path, including
# the v1->v3 FULL chain and corrupt-cups fail-closed behavior).
# ---------------------------------------------------------------------------


func test_migrate_v2_to_v3_backfills_empty_cups_without_touching_existing_racing_bests() -> void:
	var v2_profile := {
		"schema_version": 2,
		"levels": {},
		"lifetime_wumpa": 9,
		"boss_defeated": {"papu_papu": false},
		"racing": {
			"graybox_loop": {
				"best_total_time_ms": 61234,
				"best_lap_time_ms": 30234,
			},
		},
	}

	var migrated := SaveModel.migrate(v2_profile)

	assert_true(SaveModel.validate(migrated))
	assert_eq(migrated.get("schema_version"), 3)
	assert_eq(
		SaveModel.racing_record(migrated, &"graybox_loop"),
		{
			"best_total_time_ms": 61234,
			"best_lap_time_ms": 30234,
		},
		"an existing per-track best must survive the v2->v3 migration untouched"
	)
	assert_eq(
		SaveModel.cup_record(migrated, &"island_cup"),
		{"best_placement": 0},
		"a v2 profile has never played a cup -- cups must backfill empty"
	)


func test_migrate_v1_to_v3_full_chain_preserves_platformer_data_and_backfills_empty_cups() -> void:
	var v1_profile := {
		"schema_version": 1,
		"levels": {
			"wr1_n_sanity_beach": {
				"completed": true,
				"gem": false,
				"relic_tier": "none",
				"best_relic_time_ms": 0,
				"flawless": true,
			},
		},
		"lifetime_wumpa": 17,
		"boss_defeated": {"papu_papu": false},
	}

	var migrated := SaveModel.migrate(v1_profile)

	assert_true(SaveModel.validate(migrated))
	assert_eq(migrated.get("schema_version"), 3)
	assert_eq(
		migrated.get("lifetime_wumpa"),
		17,
		"platformer progress must survive the full v1->v3 chain"
	)
	assert_true(
		SaveModel.level_record(
			migrated,
			&"wr1_n_sanity_beach"
		).get("completed"),
		"pre-racing level progress must survive the full v1->v3 chain"
	)
	assert_eq(
		migrated.get("racing"),
		{"cups": {}},
		"a v1 profile predates racing entirely -- racing.cups must land empty"
	)


func test_corrupt_cups_fails_validation_and_migration_closed() -> void:
	var malformed_type := SaveModel.fresh()
	malformed_type["racing"]["cups"] = "not-a-dictionary"
	assert_false(SaveModel.validate(malformed_type))
	assert_eq(SaveModel.migrate(malformed_type), {})

	var malformed_record := SaveModel.fresh()
	malformed_record["racing"]["cups"] = {"island_cup": {"best_placement": -1}}
	assert_false(SaveModel.validate(malformed_record))
	assert_eq(SaveModel.migrate(malformed_record), {})

	var missing_field := SaveModel.fresh()
	missing_field["racing"]["cups"] = {"island_cup": {}}
	assert_false(SaveModel.validate(missing_field))
	assert_eq(SaveModel.migrate(missing_field), {})
