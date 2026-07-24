extends GutTest


func test_fresh_profile_is_valid_schema_one() -> void:
	var profile := SaveModel.fresh()

	assert_eq(profile.get("schema_version"), SaveModel.SCHEMA_VERSION)
	assert_true(SaveModel.validate(profile))
	assert_eq(profile.get("levels"), {})
	assert_eq(profile.get("lifetime_wumpa"), 0)
	assert_eq(profile.get("boss_defeated"), {"papu_papu": false})


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
		}
	)
	assert_eq(profile.get("levels"), {})
