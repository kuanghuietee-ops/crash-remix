extends GutTest

# Task 8 (CTR racing mode, R2): RaceSession must work UNCHANGED against the
# new Sanity Shores circuit -- these are the same three proof shapes
# tests/racing/test_race_session.gd already runs against the graybox loop
# (boot wiring, full-race completion via teleport-to-gate, out-of-order
# rejection), just pointed at scenes/racing/race_sanity_shores.tscn and its
# 12 gates / 3 laps instead of 6 gates. If RaceSession needed a single line
# of scene-specific logic to drive this real scene, that would BE the
# "session changes -> stop and report BLOCKED" signal from the task brief;
# it does not, so this file exists purely to prove that on the real scene,
# not to re-test RaceSession's own mechanics (already covered once).
#
# Gate crossings are driven by teleporting the kart's global_position onto
# the real authored CheckpointGate Area3D and letting Godot's own physics
# detect the overlap, exactly like test_race_session.gd's own _cross_gate.

const RACE_SCENE_PATH := "res://scenes/racing/race_sanity_shores.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


## R5 Task 1: see test_race_session.gd's identical helper for the full
## rationale -- karts now spawn frozen through a real pre-race countdown
## (race_session.gd's own COUNTDOWN + START BOOST class doc), and every test
## in this file needs the race actually RUNNING to exercise what it's
## testing, none of it the countdown machinery itself.
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
		"the Sanity Shores circuit authors exactly 12 checkpoint gates"
	)
	assert_eq(int(race.call("current_lap")), 1)
	assert_eq(
		int(race.call("lap_count")),
		int(_catalog.race.lap_count),
		"lap_count() must come from the real RaceTuning, not a hardcoded value"
	)
	assert_false(bool(race.call("is_finished")))
	assert_eq(int(race.call("progress_gates")), 0)


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
	# Each lap closes on the NEXT crossing of gate 0 -- see
	# test_race_session.gd's identical comment on this same +1 crossing.
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

	# Gate 5 is not gate 0, the expected first crossing -- must be rejected.
	await _cross_gate(race, kart, 5)

	assert_eq(
		int(race.call("progress_gates")),
		0,
		"an out-of-order gate must not move the sequence forward"
	)
	assert_eq(int(race.call("current_lap")), 1)
	assert_false(bool(race.call("is_finished")))

	# The real first gate must still be accepted afterwards, proving the
	# rejected crossing above left the validator's own expectation intact.
	await _cross_gate(race, kart, 0)
	assert_eq(
		int(race.call("progress_gates")),
		1,
		"the correct gate must still advance normally after a prior rejection"
	)


# ---------------------------------------------------------------------------
# Task 5 (CTR R3 integration): the same AI-integration proofs
# tests/racing/test_race_session.gd runs against the graybox loop, pointed
# at this real Sanity Shores scene instead -- see that file's own doc for
# why nothing above this point needed touching. The expensive 10-second
# real-physics centerpiece is deliberately NOT duplicated here (see the task
# brief's own "keep it lean" note); the graybox loop already proves the
# sustained-drive integration holds, and this file's job (per its own class
# doc) is proving RaceSession works UNCHANGED on the second circuit, not
# re-proving mechanics already covered once.
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


func test_ai_kart_gate_crossing_routes_to_its_own_validator_not_the_players() -> void:
	var race := _boot_race()
	if race == null:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart)
	if ai_kart == null:
		return
	ai_kart.set_physics_process(false)
	var gate := race.get_node("Track/Gates/Gate0") as Area3D
	ai_kart.global_position = gate.global_position
	await wait_physics_frames(2)

	assert_eq(
		int(race.call("ai_kart_progress_gates", 0)),
		1,
		"the AI kart's own validator must advance when IT crosses a gate"
	)
	assert_eq(
		int(race.call("progress_gates")),
		0,
		"the player's own validator must be untouched by an AI kart's crossing"
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


func test_placement_is_first_when_every_ai_kart_is_behind_the_player() -> void:
	var race := _boot_race()
	if race == null:
		return
	_force_finish(race)

	assert_eq(
		int(race.call("placement")),
		1,
		"with every AI kart behind the player at the finish, placement must be 1st"
	)
	assert_eq(
		int(race.call("placement_out_of")),
		int(_catalog.ai.opponent_count) + 1,
		"placement_out_of must be opponent_count + 1 (every AI kart plus the player)"
	)


func test_placement_reflects_an_ai_kart_seeded_strictly_ahead_of_the_player() -> void:
	var race := _boot_race()
	if race == null:
		return
	var agent: Object = race.call("ai_agent", 0)
	assert_not_null(agent, "fixture setup: slot 1's AiKartAgent must exist")
	if agent == null:
		return
	var follower: RefCounted = agent.get("_follower")
	assert_not_null(follower, "fixture introspection: the agent must still own its private follower")
	if follower == null:
		return
	var ahead_progress: float = float(race.call("player_total_progress_m")) + 1000.0
	follower.reset(ahead_progress)

	_force_finish(race)

	assert_eq(
		int(race.call("placement")),
		2,
		"one AI kart strictly ahead of the player at the finish must push placement to 2nd"
	)
	assert_eq(
		int(race.call("placement_out_of")),
		int(_catalog.ai.opponent_count) + 1
	)


func test_reconfigure_rebuilds_ai_karts_without_leaking_old_instances() -> void:
	var race := _boot_race()
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	var first_instance_ids: Array[int] = []
	for slot_index: int in range(opponent_count):
		first_instance_ids.append(race.call("ai_kart", slot_index).get_instance_id())

	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	await wait_physics_frames(2)

	assert_eq(
		int(race.call("ai_kart_count")),
		opponent_count,
		"a rebuild must still spawn the full AI roster"
	)
	var ai_root := race.get_node_or_null("AiKarts")
	assert_not_null(ai_root, "the AI container node must exist after a rebuild")
	if ai_root != null:
		assert_eq(
			ai_root.get_child_count(),
			opponent_count,
			"no orphaned AI kart nodes may remain under AiKarts after a rebuild"
		)
	for slot_index: int in range(opponent_count):
		assert_ne(
			race.call("ai_kart", slot_index).get_instance_id(),
			first_instance_ids[slot_index],
			"a rebuild must spawn FRESH AI kart instances, not reuse stale ones"
		)


## Fix-wave MEDIUM-2: the graybox loop's own centerpiece (test_race_session.
## gd's test_twenty_second_real_physics_race_with_five_ai_karts_makes_
## healthy_progress) was Sanity Shores's own coverage gap -- this file only
## ever asserted a solo kart's real physics ran (the individual proofs
## above), never that the full 5-AI roster keeps making healthy SUSTAINED
## progress together on this second, longer, more sharply-curved circuit.
## 15 real seconds (the bound's own "15-20s" range, lower end -- this
## file's job per its own class doc is proving RaceSession works UNCHANGED
## on the second circuit, not re-proving the graybox centerpiece's own
## already-covered mechanics, so this stays leaner than that 20s test).
##
## BOUND DERIVATION: a fraction of THIS track's own spine length (the
## graybox centerpiece's own approach) does not transplant cleanly -- Sanity
## Shores' real lap is roughly 2.4x the graybox loop's own length (measured
## while calibrating this bound), so "half A lap" is a much larger absolute
## distance here even at the same real pace, and an early version of this
## test pinned to that shape failed on the slower karts in the default
## roster (gained ~226-230m of a demanded ~251m over 15s -- close, but
## consistently short, not a fluke of one run). Rebased on kart.tres's own
## tuning instead of this track's own geometry: total_seconds *
## (top_speed_mps * ai.corner_speed_floor_ratio) -- the TIGHTEST-CORNER
## sustained pace floor AiDriver's own cornering formula already guarantees
## (18 * 0.45 = 8.1 m/s), the same floor ai_driver.gd's own CORNERING/BRAKE
## doc names as the worst-case target speed on any corner, however tight.
## 15s * 8.1 m/s = 121.5m -- comfortably inside the calibration run's own
## worst observed ~226m (roughly 1.85x headroom) while still asserting real,
## meaningful, sustained progress rather than merely ">0".
func test_fifteen_second_real_physics_race_with_five_ai_karts_makes_healthy_progress() -> void:
	var race := _boot_race()
	if race == null:
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
	var total_seconds := 15.0
	var batches := int(round(total_seconds * physics_fps / float(batch_frames)))
	for _batch_index in range(batches):
		await wait_physics_frames(batch_frames)
		for slot_index: int in range(opponent_count):
			var current := float(race.call("ai_kart_total_progress_m", slot_index))
			min_totals_seen[slot_index] = minf(min_totals_seen[slot_index], current)

	var healthy_progress_m := (
		total_seconds * _catalog.kart.top_speed_mps * _catalog.ai.corner_speed_floor_ratio
	)
	for slot_index: int in range(opponent_count):
		var final_total := float(race.call("ai_kart_total_progress_m", slot_index))
		var respawn_count := int(race.call("ai_agent", slot_index).call("respawn_count"))
		var gained := final_total - start_totals[slot_index]
		var recovered := (
			respawn_count > 0
			and final_total > min_totals_seen[slot_index] + _catalog.ai.respawn_drop_gap_m
		)
		assert_true(
			gained >= healthy_progress_m or recovered,
			(
				"AI kart at slot %d must make at least %s m of total progress "
				+ "over 15 real seconds, OR demonstrably recover via its own "
				+ "stuck-respawn safety net: gained=%s m respawn_count=%s "
				+ "min_total_seen=%s"
			) % [
				slot_index + 1,
				healthy_progress_m,
				gained,
				respawn_count,
				min_totals_seen[slot_index],
			]
		)


## Fix-wave MEDIUM-5: the REAL packaged race_sanity_shores_solo.tscn -- see
## test_race_session.gd's identical proof for the graybox loop's own twin.
func test_real_solo_scene_overrides_spawn_opponents_to_false() -> void:
	const SOLO_SCENE_PATH := "res://scenes/racing/race_sanity_shores_solo.tscn"
	assert_true(
		ResourceLoader.exists(SOLO_SCENE_PATH),
		"race_sanity_shores_solo.tscn must exist"
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


## Drives the session to race_complete by calling its own gate-crossing
## handler directly against the real authored gate nodes -- the same
## _force_finish helper test_race_session.gd's own H2 fix-round tests use.
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
		"race_sanity_shores.tscn must exist"
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
