extends GutTest

# Task 7 (CTR racing mode, R1): RaceSession is the conductor that wires the
# graybox loop + kart + camera + input mode + validator + HUD together into
# a playable time trial. Headless coverage over the REAL
# scenes/racing/race_time_trial.tscn (not a stand-in), the same
# "instantiate the actual scene, drive it via its real API" shape
# test_kart_controller.gd and test_level_scenes.gd already use for their own
# scene-level integration proofs.
#
# Gate crossings are driven by teleporting the kart's global_position onto
# the real authored CheckpointGate Area3D and letting Godot's own physics
# detect the overlap (wait_physics_frames + body_entered), not by calling
# the session's private handler directly -- this is the same
# "set_physics_process(false), then hand-place the body, then let the real
# trigger fire" technique test_level_scenes.gd already uses (see
# test_hog_wild_mounts_forced_run_and_dismounts_at_finish's
# `player.set_physics_process(false)` before a hand-placed mount-trigger
# check) so KartController's own motor tick can't fight the teleport.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


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
		6,
		"the graybox loop authors exactly 6 checkpoint gates"
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
	# Each lap closes on the NEXT crossing of gate 0 -- completing lap_count
	# laps takes lap_count+1 total crossings of the start/finish gate (the
	# initial start plus one closing crossing per lap). The loop above only
	# supplies lap_count of those closings implicitly (gate 0 opens each
	# lap); this final crossing closes out the last one.
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

	# The timer and input routing must both freeze once finished.
	await wait_physics_frames(5)
	assert_almost_eq(
		float(race.call("elapsed_s")),
		total_s,
		0.0001,
		"elapsed_s() must stop advancing once the race is finished"
	)


func test_out_of_order_gate_is_rejected_and_does_not_corrupt_later_progress() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)

	# Gate 2 is not gate 0, the expected first crossing -- must be rejected.
	await _cross_gate(race, kart, 2)

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


func test_wrong_way_flag_raises_only_after_the_tuned_grace_period() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)
	# The spawn tangent faces +X (south straight); driving -X is backward.
	kart.velocity = Vector3(-5.0, 0.0, 0.0)

	assert_false(
		bool(race.call("is_wrong_way")),
		"the flag must not raise before the grace period has elapsed"
	)

	var grace_s: float = _catalog.race.wrong_way_grace_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 5
	var frames_needed := int(ceil(grace_s * physics_fps)) + margin_frames

	await wait_physics_frames(frames_needed)

	assert_true(
		bool(race.call("is_wrong_way")),
		"sustained backward travel past wrong_way_grace_s must raise the flag"
	)


func test_wrong_way_flag_clears_once_travel_direction_corrects() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)
	kart.velocity = Vector3(-5.0, 0.0, 0.0)

	var grace_s: float = _catalog.race.wrong_way_grace_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(grace_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_true(bool(race.call("is_wrong_way")))

	kart.velocity = Vector3(5.0, 0.0, 0.0)
	await wait_physics_frames(2)

	assert_false(
		bool(race.call("is_wrong_way")),
		"correcting direction must clear the flag, not just stop it growing"
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
		"race_time_trial.tscn must exist"
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
	return race
