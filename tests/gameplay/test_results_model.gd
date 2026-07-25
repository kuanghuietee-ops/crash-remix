extends GutTest

const RESULTS_MODEL_PATH := "res://src/gameplay/run/results_model.gd"

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _meta: LevelMeta


func before_each() -> void:
	_catalog = load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	_economy = _catalog.economy
	_meta = load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	_meta.crate_count = 4


func test_normal_results_payload_uses_meta_and_groups_misses() -> void:
	var model := _new_model()
	if model == null:
		return
	var run_result := _normal_run_result()
	run_result["crate_count"] = _meta.crate_count + 99
	var previous_record := SaveModel.level_record(
		SaveModel.fresh(),
		_meta.level_id
	)
	previous_record["last_missed_crate_ids"] = [1, 4]

	var payload: Dictionary = model.call(
		"build",
		run_result,
		_meta,
		{
			1: &"Beach Start",
			2: &"Beach Start",
			3: &"Waterfall",
			4: &"Waterfall",
		},
		previous_record
	)

	assert_eq(payload.get("level_id"), _meta.level_id)
	assert_eq(payload.get("display_name"), _meta.display_name)
	assert_eq(payload.get("box_count"), 2)
	assert_eq(payload.get("crate_count"), _meta.crate_count)
	assert_false(payload.get("gem"))
	assert_eq(payload.get("missed_crate_ids"), [2, 4])
	assert_eq(
		payload.get("missed_crate_ids_by_segment"),
		{
			"Beach Start": [2],
			"Waterfall": [4],
		}
	)
	assert_true(payload.get("flawless"))
	assert_eq(
		payload.get("wumpa_banked"),
		_economy.wumpa_per_standard_crate * 2
	)
	assert_eq(payload.get("ghost_marker_ids"), [1, 4])
	assert_null(payload.get("relic_time_s"))
	assert_null(payload.get("relic_tier"))


func test_persisted_result_drives_the_next_replays_ghost_markers() -> void:
	var model := _new_model()
	if model == null:
		return
	var profile := SaveModel.fresh()
	var payload: Dictionary = model.call(
		"build",
		_normal_run_result(),
		_meta,
		{
			1: &"Beach Start",
			2: &"Beach Start",
			3: &"Waterfall",
			4: &"Waterfall",
		},
		SaveModel.level_record(profile, _meta.level_id)
	)

	var updated: Dictionary = model.call(
		"persisted_profile",
		profile,
		payload,
		_meta
	)
	var saved_record := SaveModel.level_record(
		updated,
		_meta.level_id
	)

	assert_true(SaveModel.validate(updated))
	assert_eq(profile.get("levels"), {}, "model must not mutate its input")
	assert_true(saved_record.get("completed"))
	assert_eq(saved_record.get("last_missed_crate_ids"), [2, 4])
	assert_eq(
		updated.get("lifetime_wumpa"),
		payload.get("wumpa_banked")
	)
	assert_eq(
		model.call(
			"ghost_marker_ids",
			updated,
			_meta.level_id
		),
		[2, 4]
	)


func test_earned_gem_suppresses_old_ghost_markers() -> void:
	var model := _new_model()
	if model == null:
		return
	var profile := SaveModel.fresh()
	var record := SaveModel.level_record(profile, _meta.level_id)
	record["gem"] = true
	record["last_missed_crate_ids"] = [2, 4]
	var levels: Dictionary = profile["levels"]
	levels[String(_meta.level_id)] = record

	assert_eq(
		model.call(
			"ghost_marker_ids",
			profile,
			_meta.level_id
		),
		[]
	)


func _normal_run_result() -> Dictionary:
	var state := LevelRunState.new()
	state.start(_meta, LevelRunState.MODE_NORMAL)
	state.register_authored_crate_ids([1, 2, 3, 4])
	state.record_crate_broken(
		1,
		_economy.wumpa_per_standard_crate
	)
	state.record_crate_broken(
		3,
		_economy.wumpa_per_standard_crate
	)
	return state.record_level_complete(_economy)


func _new_model() -> RefCounted:
	assert_true(
		ResourceLoader.exists(RESULTS_MODEL_PATH),
		"ResultsModel implementation must exist"
	)
	if not ResourceLoader.exists(RESULTS_MODEL_PATH):
		return null
	var script := load(RESULTS_MODEL_PATH) as Script
	return script.new() as RefCounted
