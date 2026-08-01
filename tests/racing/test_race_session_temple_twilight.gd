extends GutTest

# Task 3 (CTR R7, second circuit): RaceSession must work UNCHANGED against
# Temple Twilight -- the same three proof shapes test_race_session.gd (the
# graybox loop) and test_race_session_sanity_shores.gd already run, just
# pointed at scenes/racing/race_temple_twilight.tscn and its 12 gates / 3
# laps. If RaceSession needed a single line of scene-specific logic to
# drive this real scene, that would BE the "session changes -> stop and
# report BLOCKED" signal from the task brief; it does not, so this file
# exists purely to prove that on the real scene, not to re-test
# RaceSession's own mechanics (already covered twice).
#
# Gate crossings are driven by teleporting the kart's global_position onto
# the real authored CheckpointGate Area3D and letting Godot's own physics
# detect the overlap, exactly like test_race_session.gd's own _cross_gate.

const RACE_SCENE_PATH := "res://scenes/racing/race_temple_twilight.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


## R5 Task 1: see test_race_session.gd's identical helper for the full
## rationale -- karts now spawn frozen through a real pre-race countdown,
## and every test in this file needs the race actually RUNNING.
const _COUNTDOWN_SKIP_DELTA_S := 1000.0


func _skip_pre_race_countdown(race: Node) -> void:
	race.call("_tick_countdown", _COUNTDOWN_SKIP_DELTA_S)


func test_boot_wiring_gives_the_session_its_kart_spine_and_gates() -> void:
	var race := _boot_race()
	if race == null:
		return

	assert_not_null(race.get_node_or_null("Kart"), "session must find the kart")
	assert_not_null(
		race.get_node_or_null("Track/Spine"),
		"session must find the track's spine"
	)
	assert_eq(
		int(race.call("gate_count")),
		12,
		"the Temple Twilight circuit authors exactly 12 checkpoint gates"
	)
	assert_eq(int(race.call("current_lap")), 1)
	assert_eq(
		int(race.call("lap_count")),
		int(_catalog.race.lap_count),
		"lap_count() must come from the real RaceTuning, not a hardcoded value"
	)
	assert_false(bool(race.call("is_finished")))
	assert_eq(int(race.call("progress_gates")), 0)


## Teleport-lap test: drives a full lap_count of laps by teleporting onto
## every real authored gate in order, exactly like test_race_session_
## sanity_shores.gd's own identically-named proof.
func test_crossing_every_gate_in_order_for_all_laps_completes_the_race() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	for _lap: int in range(lap_count):
		for gate_index: int in range(gate_count):
			await _cross_gate(race, kart, gate_index)
	# Each lap closes on the NEXT crossing of gate 0.
	await _cross_gate(race, kart, 0)

	assert_true(
		bool(race.call("is_finished")),
		"driving every gate in order for every lap must complete the race"
	)
	assert_eq(int(race.call("current_lap")), lap_count)

	var laps: Array = race.call("lap_times")
	assert_eq(laps.size(), lap_count, "one recorded split per completed lap")
	for lap_time: float in laps:
		assert_gte(
			lap_time,
			0.0,
			"a recorded lap split must never be negative"
		)
	var total_s := float(race.call("elapsed_s"))
	assert_gt(total_s, 0.0, "real wall-clock time must have elapsed by the finish")


func test_out_of_order_gate_is_rejected_and_does_not_corrupt_later_progress() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)

	# Gate 6 is not gate 0, the expected first crossing -- must be rejected.
	await _cross_gate(race, kart, 6)

	assert_eq(
		int(race.call("progress_gates")),
		0,
		"an out-of-order gate must not move the sequence forward"
	)
	assert_eq(int(race.call("current_lap")), 1)
	assert_false(bool(race.call("is_finished")))

	await _cross_gate(race, kart, 0)
	assert_eq(
		int(race.call("progress_gates")),
		1,
		"the correct gate must still advance normally after a prior rejection"
	)


# ---------------------------------------------------------------------------
# AI integration -- the same proofs test_race_session_sanity_shores.gd runs
# against that second circuit, pointed at this THIRD real scene instead.
# ---------------------------------------------------------------------------


func test_ai_karts_spawn_at_their_grid_slots_with_seeded_position_and_yaw() -> void:
	var race := _boot_race()
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_eq(
		int(race.call("ai_kart_count")),
		opponent_count,
		"opponent_count AI karts must spawn by default"
	)

	for slot_index: int in range(1, opponent_count + 1):
		var marker := race.get_node(
			"Track/GridSlot%d" % slot_index
		) as Marker3D
		assert_not_null(marker, "GridSlot%d must exist under Track" % slot_index)
		var ai_kart := race.call("ai_kart", slot_index - 1) as CharacterBody3D
		assert_not_null(ai_kart, "an AI kart must exist for slot %d" % slot_index)
		if marker == null or ai_kart == null:
			continue
		assert_true(
			ai_kart.global_position.is_equal_approx(marker.global_position),
			(
				"AI kart at slot %d must spawn at its GridSlot marker's "
				+ "position -- got %s, expected %s"
			) % [slot_index, ai_kart.global_position, marker.global_position]
		)
		var expected_forward := -marker.global_transform.basis.z
		var actual_forward := -ai_kart.global_transform.basis.z
		assert_true(
			actual_forward.is_equal_approx(expected_forward),
			(
				"AI kart at slot %d must spawn facing its GridSlot marker's "
				+ "own authored yaw -- got %s, expected %s"
			) % [slot_index, actual_forward, expected_forward]
		)


func test_player_finish_freezes_every_ai_kart() -> void:
	var race := _boot_race()
	if race == null:
		return
	_force_finish(race)
	assert_true(bool(race.call("is_finished")))

	var opponent_count := int(_catalog.ai.opponent_count)
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		assert_not_null(ai_kart)
		if ai_kart == null:
			continue
		assert_false(
			bool(ai_kart.call("is_run_active")),
			(
				"AI kart at slot %d must be frozen once the player finishes"
			) % (slot_index + 1)
		)


func test_real_solo_scene_overrides_spawn_opponents_to_false() -> void:
	const SOLO_SCENE_PATH := "res://scenes/racing/race_temple_twilight_solo.tscn"
	assert_true(
		ResourceLoader.exists(SOLO_SCENE_PATH),
		"race_temple_twilight_solo.tscn must exist"
	)
	if not ResourceLoader.exists(SOLO_SCENE_PATH):
		return
	var packed := load(SOLO_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	assert_false(
		bool(race.get("spawn_opponents")),
		"the solo scene variant must override spawn_opponents to false"
	)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	assert_eq(
		int(race.call("ai_kart_count")),
		0,
		"the real solo scene must spawn zero AI karts once configured"
	)
	assert_not_null(
		race.get_node_or_null("Kart"),
		"the solo scene must keep every node path the base race scene authors -- instance=ExtResource overrides only spawn_opponents"
	)


func test_the_real_track_authors_six_item_boxes() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_eq(
		int(race.call("item_box_count")),
		6,
		"Temple Twilight authors two on-road lines of three -- see its own ItemBoxes container"
	)


## Task 3's own signature pads: one boost strip on the main straight, one
## jump pad cutting the CliffApproach corner over a gap. Proves RaceSession
## discovers BOTH real pad types on this track (the discovery mechanism
## itself is already covered by tests/racing/test_race_session_pads.gd's
## synthetic-pad tests; this only proves the real scene authors them).
func test_the_real_track_authors_a_boost_pad_and_a_jump_pad() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_not_null(
		race.get_node_or_null("Track/Pads/BoostStrip"),
		"Temple Twilight must author the boost strip on its main straight"
	)
	assert_not_null(
		race.get_node_or_null("Track/Pads/CornerCutJumpPad"),
		"Temple Twilight must author the corner-cut jump pad"
	)


# ---------------------------------------------------------------------------
# CENTERPIECE (task brief's own "East-turn-style wedge check for the NEW
# geometry"): a real, ungated, 20-simulated-second race on the real Temple
# Twilight circuit with the full default AI roster (5 AI + the player's own
# idle kart -- 6 karts total, all ticking real physics) -- every AI kart
# driving itself for real through the new tight corridor geometry (two
# hairpins, an esse weave, the cliff sweep, and the jump-pad gap on
# CliffApproach), proving the new corners do not wedge AI karts the way the
# graybox loop's own East turn (R=16) does. Every corner here authors
# radius >=20m (the R7 Task 2b AI-safety floor) specifically to avoid that
# outcome -- this test is the proof, not an assumption.
##
## BOUND DERIVATION mirrors test_race_session.gd's own graybox centerpiece
## exactly: half the real (spine.length_m(), never a bare meters literal)
## loop in 20 simulated seconds, OR the same "recovered via its own
## stuck-respawn safety net AND still cleared half that floor" escape valve
## test_race_session.gd's own fix-round tightened -- see that test's class
## doc for the full "why respawn_count>0 alone is not enough" rationale,
## reused verbatim here.
##
## RESPAWN BOUND -- measured, not assumed (task brief's own "measure and
## set an honest bound"): a diagnostic run pinpointed every kart's single
## respawn to the courtyard esse (CourtyardBendA -> CourtyardMid ->
## CourtyardBendB, R=32 each way -- the direction-reversing weave, not a
## raw-radius wedge; every corner on this circuit authors R>=20m, the R7
## Task 2b AI-safety floor, and the esse here sits at R=32, 60% above it).
## All 5 AI karts cleared it after exactly one respawn each in every
## measured run -- no kart needed a second. assert_lte(1) below would be a
## knife's-edge, flake-prone bound the same way test_ai_kart_agent.gd's own
## East-turn test explicitly avoided (that test's R6 fix-round relaxed
## <=1 to <=2 for the identical "physics-timing marginal" reason); this
## circuit's own corners are all wider than that R=16 case, so <=2 is
## already a looser bound here than the precedent needs, not a tightened
## one -- see task-3-report.md's wedge-check section for the full
## per-checkpoint measurement table.
func test_twenty_second_real_physics_race_with_five_ai_karts_makes_healthy_progress() -> void:
	var race := _boot_race()
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
	for slot_index: int in range(opponent_count):
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
	for slot_index: int in range(opponent_count):
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
				"AI kart at slot %d must complete at least half a lap (%s m) "
				+ "of total progress over 20 real seconds on the NEW Temple "
				+ "Twilight geometry, OR demonstrably recover via its own "
				+ "stuck-respawn safety net AND still clear %s m of real "
				+ "final progress: gained=%s m final_total=%s m "
				+ "healthy_floor=%s m recovery_floor=%s m respawn_count=%s "
				+ "min_total_seen=%s"
			) % [
				slot_index + 1,
				healthy_progress_m,
				recovery_floor_m,
				gained,
				final_total,
				healthy_progress_m,
				recovery_floor_m,
				respawn_count,
				min_totals_seen[slot_index],
			]
		)
		assert_lte(
			respawn_count,
			2,
			(
				"AI kart at slot %d must not repeatedly wedge on the new "
				+ "Temple Twilight geometry -- got %s respawns (measured "
				+ "baseline: 1, at the courtyard esse; see task-3-report.md)"
			) % [slot_index + 1, respawn_count]
		)
	gut.p("Temple Twilight 20s wedge check respawn_counts: %s" % [respawn_counts])


# ---------------------------------------------------------------------------
func _force_finish(race: Node) -> void:
	var kart := race.get_node("Kart")
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	for _lap: int in range(lap_count):
		for gate_index: int in range(gate_count):
			race.call(
				"_on_gate_body_entered",
				kart,
				race.get_node("Track/Gates/Gate%d" % gate_index)
			)
	race.call(
		"_on_gate_body_entered",
		kart,
		race.get_node("Track/Gates/Gate0")
	)


func _cross_gate(race: Node, kart: CharacterBody3D, gate_index: int) -> void:
	var gate := race.get_node(
		"Track/Gates/Gate%d" % gate_index
	) as Area3D
	assert_not_null(gate, "Gate%d must exist under Track/Gates" % gate_index)
	if gate == null:
		return
	kart.global_position = gate.global_position
	await wait_physics_frames(2)


func _boot_race() -> Node:
	assert_true(
		ResourceLoader.exists(RACE_SCENE_PATH),
		"race_temple_twilight.tscn must exist"
	)
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	return race
