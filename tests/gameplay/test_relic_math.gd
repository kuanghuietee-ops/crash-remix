extends GutTest

const STOPWATCH_SCENE := "res://scenes/props/stopwatch.tscn"
const TIME_CRATE_SCENE := "res://scenes/props/crate_time.tscn"
const WUMPA_SCENE := "res://scenes/props/wumpa.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const RESULTS_SCREEN_SCENE := "res://scenes/ui/results_screen.tscn"
const RUN_STATE_SCRIPT := "res://src/gameplay/run/level_run_state.gd"
const LEVEL_SCENE := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _meta: LevelMeta


class FakePlayer:
	extends Node3D


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
	_author_relic_pars(_meta)


func test_timer_arms_only_at_stopwatch_pickup() -> void:
	var state := _new_relic_state()

	state.call("advance_relic_timer", _meta.relic_platinum_s)

	assert_false(bool(state.get("relic_timer_armed")))
	assert_eq(float(state.call("relic_elapsed_s")), 0.0)
	assert_true(bool(state.call("pickup_relic_stopwatch")))
	state.call(
		"advance_relic_timer",
		_economy.time_crate_large_s
	)
	assert_almost_eq(
		float(state.call("relic_elapsed_s")),
		_economy.time_crate_large_s,
		0.0001
	)


func test_time_crates_subtract_all_tuned_values_and_preserve_credit() -> void:
	var state := _new_relic_state()
	state.call("pickup_relic_stopwatch")
	var total_credit := (
		_economy.time_crate_small_s
		+ _economy.time_crate_medium_s
		+ _economy.time_crate_large_s
	)
	state.call(
		"advance_relic_timer",
		total_credit + _economy.time_crate_large_s
	)

	for credit_s: float in [
		_economy.time_crate_small_s,
		_economy.time_crate_medium_s,
		_economy.time_crate_large_s,
	]:
		assert_true(bool(state.call(
			"record_relic_time_credit",
			credit_s
		)))

	assert_almost_eq(
		float(state.call("relic_elapsed_s")),
		_economy.time_crate_large_s,
		0.0001
	)

	var early_credit := _new_relic_state()
	early_credit.call("pickup_relic_stopwatch")
	early_credit.call(
		"record_relic_time_credit",
		_economy.time_crate_large_s
	)
	early_credit.call(
		"advance_relic_timer",
		_economy.time_crate_small_s
	)
	assert_eq(
		float(early_credit.call("relic_elapsed_s")),
		0.0
	)


func test_tier_boundaries_use_level_meta_and_equal_gets_better_tier() -> void:
	var script := load(RUN_STATE_SCRIPT) as Script
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_platinum_s
			- _catalog.input.bounce_timing_s,
			_meta
		),
		&"platinum"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_platinum_s,
			_meta
		),
		&"platinum"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_platinum_s
			+ _catalog.input.bounce_timing_s,
			_meta
		),
		&"gold"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_gold_s
			- _catalog.input.bounce_timing_s,
			_meta
		),
		&"gold"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_gold_s,
			_meta
		),
		&"gold"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_gold_s
			+ _catalog.input.bounce_timing_s,
			_meta
		),
		&"sapphire"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_sapphire_s
			- _catalog.input.bounce_timing_s,
			_meta
		),
		&"sapphire"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_sapphire_s,
			_meta
		),
		&"sapphire"
	)
	assert_eq(
		script.call(
			"relic_tier_for_time",
			_meta.relic_sapphire_s
			+ _catalog.input.bounce_timing_s,
			_meta
		),
		&"none"
	)


func test_unset_pars_refuse_relic_mode_and_entry() -> void:
	var unset_meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	var state := LevelRunState.new()

	state.start(unset_meta, LevelRunState.MODE_RELIC)

	assert_false(state.run_active)
	var completed_record := SaveModel.level_record(
		SaveModel.fresh(),
		unset_meta.level_id
	)
	completed_record["completed"] = true
	var model := ResultsModel.new()
	assert_false(
		bool(model.call(
			"relic_entry_available",
			unset_meta,
			completed_record
		))
	)
	assert_false(
		bool(model.call(
			"relic_entry_available",
			_meta,
			SaveModel.level_record(
				SaveModel.fresh(),
				_meta.level_id
			)
		))
	)
	completed_record["completed"] = true
	assert_true(
		bool(model.call(
			"relic_entry_available",
			_meta,
			completed_record
		))
	)


func test_first_normal_completion_offers_relic_when_pars_are_authored() -> void:
	var normal := LevelRunState.new()
	normal.start(_meta, LevelRunState.MODE_NORMAL)
	var previous_record := SaveModel.level_record(
		SaveModel.fresh(),
		_meta.level_id
	)

	var payload := ResultsModel.new().build(
		normal.record_level_complete(_economy),
		_meta,
		{},
		previous_record
	)

	assert_false(previous_record["completed"])
	assert_true(payload["relic_entry_available"])


func test_relic_completion_reports_effective_time_and_tier() -> void:
	var state := _new_relic_state()
	state.call("pickup_relic_stopwatch")
	state.call(
		"advance_relic_timer",
		_meta.relic_gold_s
		+ _economy.time_crate_small_s
	)
	state.call(
		"record_relic_time_credit",
		_economy.time_crate_small_s
	)

	var result: Dictionary = state.call(
		"record_level_complete",
		_economy
	)

	assert_almost_eq(
		result["relic_time_s"],
		_meta.relic_gold_s,
		0.0001
	)
	assert_eq(result["relic_tier"], &"gold")
	assert_false(result["flawless"])


func test_best_time_only_improves_and_keeps_matching_tier() -> void:
	var model := ResultsModel.new()
	var profile := _completed_profile(true)
	var first := model.persisted_profile(
		profile,
		_relic_payload(_meta.relic_gold_s, &"gold")
	)
	var first_record := SaveModel.level_record(
		first,
		_meta.level_id
	)
	var expected_gold_ms := roundi(
		_meta.relic_gold_s * 1000.0
	)

	assert_eq(
		first_record["best_relic_time_ms"],
		expected_gold_ms
	)
	assert_eq(first_record["relic_tier"], "gold")

	var slower := model.persisted_profile(
		first,
		_relic_payload(
			_meta.relic_gold_s
			+ _economy.time_crate_small_s,
			&"gold"
		)
	)
	var slower_record := SaveModel.level_record(
		slower,
		_meta.level_id
	)
	assert_eq(
		slower_record["best_relic_time_ms"],
		expected_gold_ms
	)
	assert_eq(slower_record["relic_tier"], "gold")

	var faster := model.persisted_profile(
		slower,
		_relic_payload(
			_meta.relic_platinum_s,
			&"platinum"
		)
	)
	var faster_record := SaveModel.level_record(
		faster,
		_meta.level_id
	)
	assert_lt(
		faster_record["best_relic_time_ms"],
		expected_gold_ms
	)
	assert_eq(faster_record["relic_tier"], "platinum")


func test_relic_death_resets_timer_and_pickup_starts_fresh_attempt() -> void:
	var state := _new_relic_state()
	state.call("pickup_relic_stopwatch")
	state.call("advance_relic_timer", _meta.relic_gold_s)
	state.call(
		"record_relic_time_credit",
		_economy.time_crate_small_s
	)

	var outcome: Dictionary = state.call(
		"record_death",
		_economy
	)

	assert_true(outcome["relic_void_reset"])
	assert_true(bool(state.get("relic_void")))
	assert_false(bool(state.get("relic_timer_armed")))
	assert_eq(float(state.call("relic_elapsed_s")), 0.0)
	assert_eq(float(state.get("relic_time_credit_s")), 0.0)

	assert_true(bool(state.call("pickup_relic_stopwatch")))
	assert_false(bool(state.get("relic_void")))
	state.call(
		"advance_relic_timer",
		_economy.time_crate_medium_s
	)
	assert_eq(
		float(state.call("relic_elapsed_s")),
		_economy.time_crate_medium_s
	)


func test_relic_run_does_not_change_saved_flawless_state() -> void:
	var model := ResultsModel.new()
	for original_flawless: bool in [false, true]:
		var profile := _completed_profile(original_flawless)
		var original_record := SaveModel.level_record(
			profile,
			_meta.level_id
		)
		original_record["gem"] = true
		original_record["last_missed_crate_ids"] = [7]
		var levels: Dictionary = profile["levels"]
		levels[String(_meta.level_id)] = original_record
		profile["lifetime_wumpa"] = (
			_economy.wumpa_per_standard_crate
		)

		var updated := model.persisted_profile(
			profile,
			_relic_payload(_meta.relic_gold_s, &"gold")
		)

		assert_eq(
			SaveModel.level_record(
				updated,
				_meta.level_id
			)["flawless"],
			original_flawless
		)
		var updated_record := SaveModel.level_record(
			updated,
			_meta.level_id
		)
		assert_true(updated_record["gem"])
		assert_eq(
			updated_record["last_missed_crate_ids"],
			[7]
		)
		assert_eq(
			updated["lifetime_wumpa"],
			_economy.wumpa_per_standard_crate
		)


func test_stopwatch_scene_and_session_wire_timer_time_crate_and_hud() -> void:
	assert_true(ResourceLoader.exists(STOPWATCH_SCENE))
	if not ResourceLoader.exists(STOPWATCH_SCENE):
		return
	var stopwatch := (
		load(STOPWATCH_SCENE) as PackedScene
	).instantiate() as Area3D
	assert_not_null(stopwatch)
	if stopwatch == null:
		return
	assert_true(stopwatch.is_in_group(&"relic_stopwatch"))
	assert_not_null(stopwatch.get_node_or_null("CollisionShape3D"))
	assert_not_null(stopwatch.get_node_or_null("Mesh"))

	var session := LevelSession.new()
	add_child_autofree(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	session.add_child(stopwatch)
	var time_crate := (
		load(TIME_CRATE_SCENE) as PackedScene
	).instantiate()
	time_crate.set("crate_id", 900)
	session.add_child(time_crate)
	var player := FakePlayer.new()
	session.add_child(player)
	var session_meta := _meta.duplicate(true) as LevelMeta
	session_meta.crate_count = 0
	assert_true(bool(session.call(
		"configure",
		session_meta,
		LevelRunState.MODE_RELIC,
		_economy,
		player,
		_catalog.move,
		_catalog.input
	)))
	var hud := (
		load(HUD_SCENE) as PackedScene
	).instantiate() as Control
	add_child_autofree(hud)
	hud.configure(session, session_meta)
	hud.call("_refresh")
	assert_false(hud.get_node("SafeArea/RelicTimer").visible)

	stopwatch.emit_signal(&"body_entered", player)
	session.call(
		"_physics_process",
		_economy.time_crate_small_s
		+ _economy.time_crate_medium_s
	)
	time_crate.call("apply_verb", &"spin")
	hud.call("_refresh")

	var session_state := session.get("run_state") as RefCounted
	assert_true(bool(session_state.get("relic_timer_armed")))
	assert_almost_eq(
		float(session_state.call("relic_elapsed_s")),
		_economy.time_crate_medium_s,
		0.0001
	)
	assert_true(hud.get_node("SafeArea/RelicTimer").visible)
	assert_eq(
		hud.get_node("SafeArea/RelicTimer").text,
		"RELIC  %.2f" % _economy.time_crate_medium_s
	)


func test_beach_authors_one_stopwatch_and_all_three_time_crates_relic_only() -> void:
	var level := (
		load(LEVEL_SCENE) as PackedScene
	).instantiate()
	add_child_autofree(level)
	var stopwatches: Array[Node] = []
	var time_crates: Array[Node] = []
	var time_crate_sizes: Array[StringName] = []
	for candidate: Node in level.find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if candidate.is_in_group(&"relic_stopwatch"):
			stopwatches.append(candidate)
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if not candidate.has_method("apply_verb"):
			continue
		if StringName(candidate.get("crate_type")) != &"time":
			continue
		assert_true(candidate.is_in_group(&"relic_only"))
		time_crates.append(candidate)
		time_crate_sizes.append(
			StringName(candidate.get("time_crate_size"))
		)
	assert_eq(stopwatches.size(), 1)
	assert_eq(time_crate_sizes.size(), 3)
	assert_has(time_crate_sizes, &"small")
	assert_has(time_crate_sizes, &"medium")
	assert_has(time_crate_sizes, &"large")

	assert_true(level.configure(
		_meta,
		LevelRunState.MODE_NORMAL,
		_economy,
		level.get_node("Player"),
		_catalog.move,
		_catalog.input
	))
	assert_false(stopwatches.front().visible)
	for time_crate: Node in time_crates:
		assert_false(time_crate.call("is_armed"))
		assert_false(time_crate.get_node("Mesh").visible)


func test_relic_death_restores_every_attempt_prop() -> void:
	var session := LevelSession.new()
	add_child_autofree(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var stopwatch := (
		load(STOPWATCH_SCENE) as PackedScene
	).instantiate() as Area3D
	session.add_child(stopwatch)
	var wumpa := (
		load(WUMPA_SCENE) as PackedScene
	).instantiate() as Area3D
	session.add_child(wumpa)
	var time_crate := (
		load(TIME_CRATE_SCENE) as PackedScene
	).instantiate()
	time_crate.set("crate_id", 901)
	session.add_child(time_crate)
	var player := FakePlayer.new()
	session.add_child(player)
	var session_meta := _meta.duplicate(true) as LevelMeta
	session_meta.crate_count = 0
	assert_true(bool(session.call(
		"configure",
		session_meta,
		LevelRunState.MODE_RELIC,
		_economy,
		player,
		_catalog.move,
		_catalog.input
	)))
	stopwatch.emit_signal(&"body_entered", player)

	wumpa.emit_signal(&"body_entered", player)
	time_crate.call("apply_verb", &"spin")

	assert_false(wumpa.visible)
	assert_true(wumpa.get_meta(&"phase1_collected"))
	assert_true(time_crate.call("is_broken"))
	assert_false(time_crate.get_node("Mesh").visible)
	assert_eq(
		session.run_state.wumpa_run,
		_economy.wumpa_per_standard_crate
	)

	session.record_player_death()

	assert_true(wumpa.visible)
	assert_false(wumpa.get_meta(&"phase1_collected"))
	assert_true(stopwatch.visible)
	assert_false(time_crate.call("is_broken"))
	assert_true(time_crate.call("is_armed"))
	assert_true(time_crate.get_node("Mesh").visible)
	assert_eq(session.run_state.wumpa_run, 0)


func test_results_screen_relic_entry_is_visible_and_emits_after_unlock() -> void:
	var screen := (
		load(RESULTS_SCREEN_SCENE) as PackedScene
	).instantiate() as Control
	add_child_autofree(screen)
	assert_true(screen.has_signal(&"relic_requested"))
	var relic_button := screen.get_node_or_null(
		"SafeArea/Center/Panel/Margin/Rows/Actions/RelicTrial"
	) as Button
	assert_not_null(relic_button)
	if relic_button == null:
		return
	watch_signals(screen)

	screen.call("present", {
		"relic_entry_available": true,
	})
	relic_button.emit_signal(&"pressed")

	assert_true(relic_button.visible)
	assert_signal_emitted(screen, &"relic_requested")


func _new_relic_state() -> RefCounted:
	var state := (
		(load(RUN_STATE_SCRIPT) as Script).new()
		as RefCounted
	)
	state.call("start", _meta, LevelRunState.MODE_RELIC)
	assert_true(bool(state.get("run_active")))
	return state


func _author_relic_pars(meta: LevelMeta) -> void:
	meta.relic_platinum_s = _economy.time_crate_small_s
	meta.relic_gold_s = (
		meta.relic_platinum_s
		+ _economy.time_crate_medium_s
	)
	meta.relic_sapphire_s = (
		meta.relic_gold_s
		+ _economy.time_crate_large_s
	)


func _completed_profile(flawless: bool) -> Dictionary:
	var profile := SaveModel.fresh()
	var record := SaveModel.level_record(
		profile,
		_meta.level_id
	)
	record["completed"] = true
	record["flawless"] = flawless
	var levels: Dictionary = profile["levels"]
	levels[String(_meta.level_id)] = record
	return profile


func _relic_payload(
	elapsed_s: float,
	tier: StringName
) -> Dictionary:
	return {
		"level_id": _meta.level_id,
		"mode": LevelRunState.MODE_RELIC,
		"relic_time_s": elapsed_s,
		"relic_tier": tier,
		"wumpa_banked": 0,
		"missed_crate_ids": [],
		"gem": false,
		"flawless": false,
	}
