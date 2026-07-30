extends GutTest


func test_fresh_profile_is_valid_schema_one() -> void:
	var profile := SaveModel.fresh()

	assert_eq(profile.get("schema_version"), SaveModel.SCHEMA_VERSION)
	assert_true(SaveModel.validate(profile))
	assert_eq(profile.get("levels"), {})
	assert_eq(profile.get("lifetime_wumpa"), 0)
	assert_eq(profile.get("boss_defeated"), {"papu_papu": false})
	assert_eq(profile.get("racing"), {})


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
	assert_eq(profile.get("racing"), {})


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
