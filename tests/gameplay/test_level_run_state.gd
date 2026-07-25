extends GutTest

const RUN_STATE_PATH := "res://src/gameplay/run/level_run_state.gd"
const LEVEL_SESSION_PATH := "res://src/gameplay/run/level_session.gd"
const STANDARD_SCENE := "res://scenes/props/crate_standard.tscn"
const CHECKPOINT_SCENE := "res://scenes/props/crate_checkpoint.tscn"

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _meta: LevelMeta


class FakePlayer:
	extends Node3D

	signal respawned

	var spawn_transform := Transform3D.IDENTITY

	func set_spawn_transform(value: Transform3D) -> void:
		spawn_transform = value


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
	_meta.crate_count = _economy.mercy_skip_death_threshold


func test_broken_crates_persist_across_death() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	for crate_id: int in [1, 2, 3]:
		state.call(
			"record_crate_broken",
			crate_id,
			_economy.wumpa_per_standard_crate
		)
	var before: Array = state.get("broken_crate_ids").duplicate()

	state.call("record_death", _economy)

	assert_eq(state.get("broken_crate_ids"), before)
	assert_eq(state.get("broken_crate_ids").size(), 3)


func test_wumpa_persists_across_death_q2() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_crate_broken",
		1,
		_economy.wumpa_per_standard_crate
	)
	state.call(
		"record_wumpa_collected",
		_economy.bounce_crate_wumpa_per_bounce
	)
	var before: int = state.get("wumpa_run")

	state.call("record_death", _economy)

	assert_eq(state.get("wumpa_run"), before)


func test_masks_reset_on_death_q3() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_mask_granted",
		_economy.mask_stack_maximum
	)

	state.call("record_death", _economy)

	assert_eq(state.get("masks"), 0)


func test_death_before_first_checkpoint_respawns_at_start() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return

	var outcome: Dictionary = state.call("record_death", _economy)

	assert_eq(outcome["respawn_checkpoint"], -1)


func test_checkpoint_persists_across_death() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	var checkpoint_id := _economy.mercy_mask_death_threshold
	state.call("record_checkpoint", checkpoint_id)

	var outcome: Dictionary = state.call("record_death", _economy)

	assert_eq(outcome["respawn_checkpoint"], checkpoint_id)
	assert_eq(state.get("checkpoint_id"), checkpoint_id)


func test_mercy_counter_increments_at_same_checkpoint_and_resets_on_new_q14() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	var first_checkpoint := _economy.mercy_mask_death_threshold
	var next_checkpoint := _economy.mercy_skip_death_threshold
	state.call("record_checkpoint", first_checkpoint)
	state.call("record_death", _economy)
	state.call("record_death", _economy)
	state.call("record_checkpoint", first_checkpoint)
	assert_eq(state.get("deaths_at_checkpoint"), 2)

	state.call("record_checkpoint", next_checkpoint)

	assert_eq(state.get("deaths_at_checkpoint"), 0)


func test_third_death_grants_mask_and_sixth_offers_skip() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_checkpoint",
		_economy.mercy_mask_death_threshold
	)
	var outcome: Dictionary
	while (
		state.get("deaths_at_checkpoint")
		< _economy.mercy_mask_death_threshold - 1
	):
		outcome = state.call("record_death", _economy)
	assert_false(outcome["grant_mercy_mask"])
	outcome = state.call("record_death", _economy)
	assert_true(outcome["grant_mercy_mask"])
	assert_eq(
		state.get("deaths_at_checkpoint"),
		_economy.mercy_mask_death_threshold
	)

	while (
		state.get("deaths_at_checkpoint")
		< _economy.mercy_skip_death_threshold - 1
	):
		outcome = state.call("record_death", _economy)
	assert_false(outcome["offer_skip"])
	outcome = state.call("record_death", _economy)
	assert_true(outcome["offer_skip"])
	assert_eq(
		state.get("deaths_at_checkpoint"),
		_economy.mercy_skip_death_threshold
	)


func test_accept_mercy_skip_rejects_a_skip_that_was_never_offered() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return

	var accepted: bool = state.call(
		"accept_mercy_skip",
		_economy.mercy_skip_death_threshold,
		_economy
	)

	assert_false(
		accepted,
		(
			"a skip must never be accepted before deaths_at_checkpoint "
			+ "reaches mercy_skip_death_threshold"
		)
	)
	assert_false(state.get("gem_void"))
	assert_false(state.get("relic_void"))
	assert_eq(
		state.get("checkpoint_id"),
		LevelRunState.START_CHECKPOINT
	)


func test_skip_voids_gem_and_relic_for_the_run() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	for _death_index: int in range(
		_economy.mercy_skip_death_threshold
	):
		state.call("record_death", _economy)

	var accepted: bool = state.call(
		"accept_mercy_skip",
		_economy.mercy_skip_death_threshold,
		_economy
	)

	state.call("record_death", _economy)

	assert_true(
		accepted,
		"a skip legitimately offered at the threshold must be accepted"
	)
	assert_true(state.get("gem_void"))
	assert_true(state.get("relic_void"))
	assert_eq(
		state.get("checkpoint_id"),
		_economy.mercy_skip_death_threshold
	)


func test_relic_completion_never_reports_wumpa_as_banked() -> void:
	var state := _new_state(&"relic", _relic_meta())
	if state == null:
		return
	state.call("pickup_relic_stopwatch")
	state.call(
		"record_crate_broken",
		1,
		_economy.wumpa_per_standard_crate
	)

	var result: Dictionary = state.call(
		"record_level_complete",
		_economy
	)

	assert_eq(
		result["wumpa_banked"],
		0,
		(
			"relic-mode wumpa is never applied to the lifetime total "
			+ "(ResultsModel.persisted_profile only banks MODE_NORMAL "
			+ "results) so the payload must not claim otherwise"
		)
	)


func test_flawless_cleared_by_first_death() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	assert_true(state.get("flawless"))

	state.call("record_death", _economy)

	assert_false(state.get("flawless"))


func test_relic_death_voids_and_resets_everything_q4() -> void:
	var state := _new_state(&"relic", _relic_meta())
	if state == null:
		return
	state.call("pickup_relic_stopwatch")
	state.call(
		"advance_relic_timer",
		_economy.time_crate_large_s
	)
	state.call(
		"record_crate_broken",
		1,
		_economy.wumpa_per_standard_crate
	)
	state.call(
		"record_wumpa_collected",
		_economy.bounce_crate_wumpa_per_bounce
	)
	state.call(
		"record_mask_granted",
		_economy.mask_stack_maximum
	)

	var outcome: Dictionary = state.call("record_death", _economy)

	assert_true(outcome["relic_void_reset"])
	assert_eq(outcome["respawn_checkpoint"], -1)
	assert_eq(state.get("broken_crate_ids"), [])
	assert_eq(state.get("wumpa_run"), 0)
	assert_eq(state.get("masks"), 0)
	assert_eq(state.get("deaths_at_checkpoint"), 0)
	assert_true(state.get("relic_void"))
	assert_false(state.get("relic_timer_armed"))
	assert_eq(state.call("relic_elapsed_s"), 0.0)
	assert_eq(state.get("relic_time_credit_s"), 0.0)


func test_completion_banks_wumpa_and_reports_gem_on_full_sweep() -> void:
	var full_meta := _meta.duplicate(true) as LevelMeta
	full_meta.crate_count = _economy.mercy_mask_death_threshold
	var full := _new_state(&"normal", full_meta)
	if full == null:
		return
	for crate_id: int in range(1, full_meta.crate_count + 1):
		full.call(
			"record_crate_broken",
			crate_id,
			_economy.wumpa_per_standard_crate
		)

	var full_result: Dictionary = full.call(
		"record_level_complete",
		_economy
	)

	assert_true(full_result["gem"])
	assert_eq(full_result["box_count"], full_meta.crate_count)
	assert_eq(full_result["missing_crate_ids"], [])
	assert_eq(
		full_result["wumpa_banked"],
		full_meta.crate_count * _economy.wumpa_per_standard_crate
	)

	var missed := _new_state(&"normal", full_meta)
	if missed == null:
		return
	for crate_id: int in range(1, full_meta.crate_count):
		missed.call("record_crate_broken", crate_id, 0)

	var missed_result: Dictionary = missed.call(
		"record_level_complete",
		_economy
	)

	assert_false(missed_result["gem"])
	assert_eq(
		missed_result["missing_crate_ids"],
		[full_meta.crate_count]
	)


func test_completion_discards_masks_and_mercy_counter() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_mask_granted",
		_economy.mask_stack_maximum
	)
	state.call("record_death", _economy)

	state.call("record_level_complete", _economy)

	assert_eq(state.get("masks"), 0)
	assert_eq(state.get("deaths_at_checkpoint"), 0)


func test_exit_discards_run_state_q2() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_crate_broken",
		1,
		_economy.wumpa_per_standard_crate
	)
	state.call(
		"record_mask_granted",
		_economy.mask_stack_maximum
	)
	state.call(
		"record_checkpoint",
		_economy.mercy_mask_death_threshold
	)
	for _death_index: int in range(
		_economy.mercy_skip_death_threshold
	):
		state.call("record_death", _economy)
	state.call(
		"accept_mercy_skip",
		_economy.mercy_skip_death_threshold,
		_economy
	)

	state.call("record_exit")

	assert_eq(state.call("snapshot"), {})
	assert_false(state.get("run_active"))
	assert_eq(state.get("broken_crate_ids"), [])
	assert_eq(state.get("wumpa_run"), 0)
	assert_eq(state.get("masks"), 0)
	assert_false(state.get("gem_void"))
	assert_false(state.get("relic_void"))


func test_snapshot_restore_preserves_normal_run_state() -> void:
	var state := _new_state(&"normal")
	if state == null:
		return
	state.call(
		"record_crate_broken",
		1,
		_economy.wumpa_per_standard_crate
	)
	state.call(
		"record_checkpoint",
		_economy.mercy_mask_death_threshold
	)
	var snapshot: Dictionary = state.call("snapshot")
	var script := load(RUN_STATE_PATH) as Script

	var restored: RefCounted = script.call(
		"restore",
		snapshot,
		_meta
	)

	assert_eq(restored.get("broken_crate_ids"), [1])
	assert_eq(
		restored.get("checkpoint_id"),
		_economy.mercy_mask_death_threshold
	)
	assert_eq(
		restored.get("wumpa_run"),
		_economy.wumpa_per_standard_crate
	)


func test_level_session_wires_crate_checkpoint_and_single_death_record() -> void:
	assert_true(
		ResourceLoader.exists(LEVEL_SESSION_PATH),
		"LevelSession implementation must exist"
	)
	if not ResourceLoader.exists(LEVEL_SESSION_PATH):
		return
	var session_script := load(LEVEL_SESSION_PATH) as Script
	var session := session_script.new() as Node
	add_child_autofree(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var standard := _instantiate(STANDARD_SCENE)
	var checkpoint := _instantiate(CHECKPOINT_SCENE)
	if standard == null or checkpoint == null:
		return
	standard.set("crate_id", 1)
	checkpoint.set("crate_id", 2)
	checkpoint.position = Vector3(
		_economy.tnt_blast_radius_m,
		0.0,
		0.0
	)
	session.add_child(standard)
	session.add_child(checkpoint)
	var player := FakePlayer.new()
	session.add_child(player)
	var session_meta := _meta.duplicate(true) as LevelMeta
	session_meta.crate_count = 2

	session.call(
		"configure",
		session_meta,
		&"normal",
		_economy,
		player,
		_catalog.move,
		_catalog.input
	)
	standard.call("apply_verb", &"spin")
	checkpoint.call("apply_verb", &"spin")
	var outcome: Dictionary = session.call("record_player_death")
	player.respawned.emit()

	var run_state: RefCounted = session.get("run_state")
	assert_eq(run_state.get("broken_crate_ids"), [1, 2])
	assert_eq(run_state.get("deaths_at_checkpoint"), 1)
	assert_eq(outcome["respawn_checkpoint"], 2)
	var expected_checkpoint_spawn := (
		checkpoint as Node3D
	).global_transform
	expected_checkpoint_spawn.origin += (
		expected_checkpoint_spawn.basis
		* _economy.checkpoint_respawn_offset
	)
	assert_eq(
		player.spawn_transform,
		expected_checkpoint_spawn,
		(
			"respawn must be derived from the live tuned "
			+ "checkpoint_respawn_offset, not an authored scene marker"
		)
	)
	assert_false(standard.get_node("Mesh").visible)


func _new_state(
	mode: StringName,
	meta: LevelMeta = null
) -> RefCounted:
	assert_true(
		ResourceLoader.exists(RUN_STATE_PATH),
		"LevelRunState implementation must exist"
	)
	if not ResourceLoader.exists(RUN_STATE_PATH):
		return null
	var script := load(RUN_STATE_PATH) as Script
	var state := script.new() as RefCounted
	state.call("start", meta if meta != null else _meta, mode)
	return state


func _relic_meta() -> LevelMeta:
	var relic_meta := _meta.duplicate(true) as LevelMeta
	relic_meta.relic_platinum_s = _economy.time_crate_small_s
	relic_meta.relic_gold_s = (
		relic_meta.relic_platinum_s
		+ _economy.time_crate_medium_s
	)
	relic_meta.relic_sapphire_s = (
		relic_meta.relic_gold_s
		+ _economy.time_crate_large_s
	)
	return relic_meta


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null
