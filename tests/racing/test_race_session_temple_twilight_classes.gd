extends GutTest

## CTR R8 Task 2 (characters/select/classes): the brief's own mandatory
## "per-class real-physics health race" -- Temple Twilight (the R7 wedge-
## check circuit: two hairpins, an esse weave, the cliff sweep) with driver
## classes ACTIVE for the first time (Task 1 always composed with null;
## this task is what makes a real, non-identity class multiplier reach a
## kart's own motor/drift tuning during a real race -- see race_session.gd's
## own _spawn_ai_karts() doc). The design spec's own named risk: Speed class
## trades steer_rate_mult down to 0.90 for extra top speed, and Temple
## Twilight's hairpins are exactly the geometry a fast, less-nimble kart is
## most likely to overshoot -- "per-class real-physics health races there
## are mandatory (wedge/respawn bounds per class, the East-turn precedent
## applied per class)" (design spec, section B).
##
## THREE RUNS, not one -- "run once per non-balanced class (speed/accel/
## turning as the player-absent field mix)" (task brief). The roster's
## class assignments are fixed (crash/cortex/lab_assistant -> Balanced;
## papu -> Speed; coco -> Acceleration; ripper_roo -> Turning), so any
## single player pick already puts all three non-Balanced drivers into the
## AI fill together (only 3 of 6 roster ids are Balanced, and a pick only
## ever removes ONE). True per-class ISOLATION is not achievable from this
## fixed 6-driver roster without inventing a test-only synthetic fill this
## task's brief does not ask for -- so instead, each of the 3 runs below
## picks a DIFFERENT Balanced driver as the player, which genuinely varies
## the grid: _ai_fill_driver_ids()'s own fixed roster order means each non-
## Balanced driver's own SLOT shifts depending on which Balanced driver sat
## out (see each test's own comment for the exact slot each run puts papu/
## coco/ripper_roo in). Every slot is asserted in every run (not just the
## "named" one) for full regression coverage, matching the R7 precedent's
## own "assert every slot" shape; the per-test doc names which class this
## run's grid arrangement is specifically chosen to exercise.
##
## BOUND DERIVATION mirrors test_race_session_temple_twilight.gd's own
## centerpiece exactly (see that file's own BOUND DERIVATION/RESPAWN BOUND
## docs for the full measured rationale, reused verbatim here): half the
## real spine length in 20 simulated seconds, OR recovered via the stuck-
## respawn safety net AND still cleared half that floor; respawn_count <= 2
## (the same measured R7 baseline for this circuit -- "respawns <= R7
## baseline" per the task brief). Classes multiply top_speed_mps/accel_
## mps2/steer_rate_degrees_per_s by single-digit percentages (see data/
## tuning/racing/classes/*.tres), nowhere near enough to invalidate a bound
## with the R7 precedent's own measured ~1.85x headroom (see test_race_
## session_sanity_shores.gd's identically-derived bound for that headroom
## figure on a comparable circuit) -- these runs PROVE that expectation
## holds on the real track rather than assuming it.
##
## DETERMINISM. Matches the R7 precedent's own approach exactly: no
## item_rng_seed override (item pickups do not affect wedge/respawn
## outcomes -- see race_session.gd's own ITEM RNG doc), and AiDriver itself
## carries no RNG of any kind (see ai_driver.gd's own "NO randf()/randi()"
## doc) -- the physics/AI-driving half of this race is fully deterministic
## given the fixed track geometry, fixed tuning, and fixed timestep already
## in play.

const RACE_SCENE_PATH := "res://scenes/racing/race_temple_twilight.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


# R5 Task 1: see test_race_session_temple_twilight.gd's identical helper --
# karts spawn frozen through a real pre-race countdown, and every run here
# needs the race actually driving.
const _COUNTDOWN_SKIP_DELTA_S := 1000.0


func _skip_pre_race_countdown(race: Node) -> void:
	race.call("_tick_countdown", _COUNTDOWN_SKIP_DELTA_S)


func _boot_race(selected_driver_id: StringName) -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH), "race_temple_twilight.tscn must exist")
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	# CTR R8 Task 2: must be called BEFORE configure() -- see configure_
	# selected_driver()'s own doc.
	race.call("configure_selected_driver", selected_driver_id)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	return race


## Shared centerpiece body -- see this file's own class doc for the full
## BOUND DERIVATION/DETERMINISM rationale. run_label only affects assertion
## text/diagnostic printing, never the bound itself -- every run is held to
## the identical R7-baseline bound.
func _run_class_health_race(player_pick: StringName, run_label: String) -> void:
	var race := _boot_race(player_pick)
	if race == null:
		return
	var spine := race.get_node("Track/Spine") as TrackSpine
	assert_not_null(spine, "fixture sanity: the real Track/Spine node must exist")
	if spine == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_eq(
		int(race.call("ai_kart_count")),
		opponent_count,
		"fixture sanity: the default AI roster must spawn"
	)

	var start_totals: Array[float] = []
	var min_totals_seen: Array[float] = []
	for slot_index in range(opponent_count):
		var start_total := float(race.call("ai_kart_total_progress_m", slot_index))
		start_totals.append(start_total)
		min_totals_seen.append(start_total)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var batch_frames := 30
	var total_seconds := 20.0
	var batches := int(round(total_seconds * physics_fps / float(batch_frames)))
	for _batch_index in range(batches):
		await wait_physics_frames(batch_frames)
		for slot_index: int in range(opponent_count):
			var current := float(race.call("ai_kart_total_progress_m", slot_index))
			min_totals_seen[slot_index] = minf(min_totals_seen[slot_index], current)

	var healthy_progress_m := spine.length_m() * 0.5
	const _RECOVERY_FRACTION := 0.5
	var recovery_floor_m := healthy_progress_m * _RECOVERY_FRACTION
	var respawn_counts: Array[int] = []
	for slot_index in range(opponent_count):
		var final_total := float(race.call("ai_kart_total_progress_m", slot_index))
		var respawn_count := int(race.call("ai_agent", slot_index).call("respawn_count"))
		respawn_counts.append(respawn_count)
		var gained := final_total - start_totals[slot_index]
		var recovered := (
			respawn_count > 0
			and final_total > min_totals_seen[slot_index] + _catalog.ai.respawn_drop_gap_m
			and final_total >= recovery_floor_m
		)
		assert_true(
			gained >= healthy_progress_m or recovered,
			(
				"[%s] AI kart at slot %d must complete at least half a lap "
				+ "(%s m) of total progress over 20 real seconds with driver "
				+ "classes ACTIVE on Temple Twilight, OR demonstrably recover "
				+ "via its own stuck-respawn safety net AND still clear %s m "
				+ "of real final progress: gained=%s m final_total=%s m "
				+ "respawn_count=%s min_total_seen=%s"
			) % [
				run_label,
				slot_index + 1,
				healthy_progress_m,
				recovery_floor_m,
				gained,
				final_total,
				respawn_count,
				min_totals_seen[slot_index],
			]
		)
		assert_lte(
			respawn_count,
			2,
			(
				"[%s] AI kart at slot %d must not repeatedly wedge with "
				+ "classes active on Temple Twilight -- got %s respawns "
				+ "(R7 measured baseline bound: <=2, see test_race_session_"
				+ "temple_twilight.gd's own RESPAWN BOUND doc)"
			) % [run_label, slot_index + 1, respawn_count]
		)
	gut.p(
		"[%s] Temple Twilight 20s class-active health check respawn_counts: %s"
		% [run_label, respawn_counts]
	)


## Player picks crash (Balanced) -- AI fill (registry order minus crash) is
## papu(SPEED, slot 1), cortex(Balanced, slot 2), coco(Acceleration, slot 3),
## ripper_roo(Turning, slot 4), lab_assistant(Balanced, slot 5). This is the
## design spec's own named risk in its sharpest arrangement: papu (Speed,
## steer_rate_mult 0.90) sits at the FRONT of the AI grid, closest behind
## the player's own pole position.
func test_speed_class_papu_health_on_temple_twilight_with_classes_active() -> void:
	await _run_class_health_race(&"crash", "speed")


## Player picks cortex (Balanced) -- AI fill is crash(Balanced, slot 1),
## papu(Speed, slot 2), coco(ACCELERATION, slot 3), ripper_roo(Turning,
## slot 4), lab_assistant(Balanced, slot 5). coco (Acceleration, accel_mult
## 1.12) is this run's own focus.
func test_acceleration_class_coco_health_on_temple_twilight_with_classes_active() -> void:
	await _run_class_health_race(&"cortex", "acceleration")


## Player picks lab_assistant (Balanced) -- AI fill is crash(Balanced,
## slot 1), papu(Speed, slot 2), cortex(Balanced, slot 3), coco
## (Acceleration, slot 4), ripper_roo(TURNING, slot 5). ripper_roo (Turning,
## steer_rate_mult 1.12, top_speed_mult 0.96) lands at the BACK of the grid
## here -- the opposite end from the speed run above -- and is this run's
## own focus.
func test_turning_class_ripper_roo_health_on_temple_twilight_with_classes_active() -> void:
	await _run_class_health_race(&"lab_assistant", "turning")
