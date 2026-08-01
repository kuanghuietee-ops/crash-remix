extends GutTest

# CTR R7 Task 2 (kart-to-kart contact): 6-kart tight-grid bump-heavy real-
# physics proof. The plan's own test list: "AI 6-kart bump-heavy race
# (tight grid, real physics 15s) -- no stuck-detector spam (respawns
# bounded vs the Task 2b baselines in the report), no error spam." 5 AI + 1
# idle player = 6 karts, the same default roster shape test_ai_recovery_
# proof_r7.gd already establishes for the graybox loop's own opponent_count
# (ai.tres authors 5.0).
#
# SCOPE. New file, not an addition to test_ai_recovery_proof_r7.gd or test_
# race_session.gd -- mirrors this suite's own established precedent (see
# that file's own class doc SCOPE paragraph) of a differently-shaped
# multi-AI proof getting its own file rather than growing an existing one.
# This file is deliberately AI-driver-agnostic: it does not touch wrong-way
# recovery or difficulty tuning (Task 2b's own scope) at all, only whether
# real kart-to-kart contact (this task's own new mechanic) behaves under
# heavy traffic.
#
# TIGHT GRID. The authored GridSlot1..5 markers on the graybox loop are
# spread ~1.7-4m apart -- plenty of room for a normal race to only
# occasionally graze. _boot_tight_grid_race() compresses every AI kart's
# own spawn position toward the grid's own centroid by _GRID_SHRINK_FACTOR
# immediately after boot (before the very first tick), guaranteeing real,
# sustained overlap between adjacent karts from the start -- the "tight
# grid" the plan calls for. Only POSITION is compressed; yaw/orientation is
# left exactly as GridSlot1..5 authored it (same forward direction the
# track's own KartSpawn/start line uses), so every AI kart still races the
# correct way from tick one -- this proof does not want to also exercise
# Task 2b's own wrong-way recovery path, only contact.
#
# BASELINE. Task 2b's own test_ai_recovery_proof_r7.gd measured 5-10
# graybox-loop stuck-respawns across a NORMAL-grid 30s/6-kart run (see
# task-2b-report.md's own PROOF table). This scenario is a DIFFERENT shape
# entirely (tight grid, 15s, deliberately bump-heavy from tick one) -- so
# _MAX_RESPAWNS below is bounded against a value measured directly against
# THIS exact scenario (see task-2-report.md's own PROOF section for the
# observed range across repeat runs), with real margin above the measured
# high end, not against the normal-grid number, per this task's own brief
# ("respawns bounded vs the Task 2b baselines in the report").

const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"

# Small enough that adjacent karts (spaced ~1.7-4m apart as authored) start
# well inside each other's ~1.4m collision width, guaranteeing real contact
# from the very first ticks rather than relying on incidental in-race
# jostling to eventually produce one.
const _GRID_SHRINK_FACTOR := 0.15

# Measured directly against this exact 15s/6-kart tight-grid scenario (this
# file, unmodified) across 8 repeat runs while building this task: total
# AI stuck-respawns observed = 1, 1, 1, 1, 2, 3, 3, 3 (bump_count totals
# ranged from ~150 to ~570 across the same runs, always well above zero --
# real, sustained contact every run). Real margin above the measured high
# end (3), following this suite's own established "measure, then bound
# with real margin" precedent (test_ai_recovery_proof_r7.gd's own _RESPAWN_
# BASELINE_BY_TRACK/_MAX_regressing_windows) -- this is a DIFFERENT
# scenario shape than that file's own normal-grid 30s/6-kart baseline
# (5-10 on the graybox loop), so it is bounded against its own measurement,
# not that one, per this task's own brief.
const _MAX_RESPAWNS := 8

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func test_fifteen_second_tight_grid_bump_heavy_race_stays_healthy() -> void:
	var race := _boot_tight_grid_race()
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_eq(
		int(race.call("ai_kart_count")),
		opponent_count,
		"fixture sanity: the default AI roster must spawn"
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var total_seconds := 15.0
	var batches := 15
	var batch_frames := int(round(total_seconds / float(batches) * physics_fps))
	for _batch_index in range(batches):
		await wait_physics_frames(batch_frames)

	var total_bumps := 0
	var total_respawns := 0
	var bump_counts_by_slot: Array = []
	var respawn_counts_by_slot: Array = []
	for slot_index in range(opponent_count):
		var kart: Object = race.call("ai_kart", slot_index)
		var agent: Object = race.call("ai_agent", slot_index)
		var bumps := int(kart.call("bump_count"))
		var respawns := int(agent.call("respawn_count"))
		bump_counts_by_slot.append(bumps)
		respawn_counts_by_slot.append(respawns)
		total_bumps += bumps
		total_respawns += respawns

	print(
		(
			"[task-2 bump proof] tight-grid 15s/6-kart: bump_counts=%s "
			+ "(total %s), respawn_counts=%s (total %s)"
		) % [
			bump_counts_by_slot,
			total_bumps,
			respawn_counts_by_slot,
			total_respawns,
		]
	)

	assert_gt(
		total_bumps,
		0,
		"a tight-grid race must actually produce real kart-to-kart bumps -- fixture sanity"
	)
	assert_true(
		total_respawns <= _MAX_RESPAWNS,
		(
			"stuck-detector respawns (%s) must stay bounded, not spam, even "
			+ "under bump-heavy contact (bound %s)"
		) % [total_respawns, _MAX_RESPAWNS]
	)


## Boots the real graybox-loop race exactly like test_ai_recovery_proof_r7.
## gd's own _boot_race() (same catalog, same "_tick_countdown(1000.0)
## collapses the real pre-race countdown to GO in one call" technique --
## see that file's own doc), then compresses every AI kart's own spawn
## position toward the grid's own centroid -- see this file's own class doc
## TIGHT GRID section for why position-only, yaw untouched.
func _boot_tight_grid_race() -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH), "%s must exist" % RACE_SCENE_PATH)
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", _catalog)
	race.call("_tick_countdown", 1000.0)

	var opponent_count := int(_catalog.ai.opponent_count)
	var originals: Array[Vector3] = []
	var centroid := Vector3.ZERO
	for slot_index in range(opponent_count):
		var kart := race.call("ai_kart", slot_index) as CharacterBody3D
		originals.append(kart.global_position)
		centroid += kart.global_position
	if opponent_count > 0:
		centroid /= float(opponent_count)
	for slot_index in range(opponent_count):
		var kart := race.call("ai_kart", slot_index) as CharacterBody3D
		kart.global_position = centroid + (originals[slot_index] - centroid) * _GRID_SHRINK_FACTOR

	return race
