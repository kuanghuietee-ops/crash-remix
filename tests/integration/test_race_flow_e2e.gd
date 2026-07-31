extends GutTest

# CTR R5 Task 4: END-TO-END race-flow integration coverage -- the whole R5
# loop chained together against the REAL packed scenes, on BOTH real tracks,
# the way an actual play session experiences it: a real 3-2-1 countdown
# ticked through real physics frames (not the synthetic
# _tick_countdown(1000.0) skip every other suite in this codebase uses to
# get past the countdown as fast as possible -- that skip is deliberately
# NOT used here, since driving the real countdown for real is this file's
# whole point, the same rationale test_race_start_flow.gd's own header
# states for its own countdown coverage) through GO, AI karts driving under
# real physics for a bounded window, the player TELEPORTING to finish (the
# same real-Area3D-overlap "teleport the kart's own global_position onto
# each gate and let Godot's own physics detect it" technique
# test_race_session.gd's own _cross_gate() established, not the private-
# handler shortcut test_race_standings.gd's _cross_all_gates_for_kart() uses),
# and the resulting standings() showing a genuine finished/unfinished split.
#
# Every individual mechanic exercised here (countdown phase math, start-boost
# verdicts, live ranking, standings ordering, pause-correctness, retry) is
# already unit/session-tested in its own dedicated file
# (test_countdown_timer.gd, test_start_boost_judge.gd, test_race_ranking.gd,
# test_race_standings.gd, test_race_start_flow.gd, test_race_session.gd).
# This file's own job is different: prove the REAL, WHOLE pipeline holds
# together end to end on the real scenes, not re-prove any one piece's own
# edge cases in isolation.
#
# SEEDED: every fixture below pins RaceSession.item_rng_seed to a fixed
# non-zero value (see race_session.gd's own ITEM RNG section) purely for
# this suite's own reproducibility hygiene -- none of these flows drive
# through an item box, so the item roll sequence itself is never observed,
# but a seeded RNG means a flake here can never be blamed on "got a
# different random sequence this run."

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const SANITY_SHORES_RACE_SCENE_PATH := "res://scenes/racing/race_sanity_shores.tscn"
const SOLO_SCENE_PATH := "res://scenes/racing/race_time_trial_solo.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const _SEED := 918273

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func _boot_race(scene_path: String) -> Node:
	assert_true(ResourceLoader.exists(scene_path), "%s must exist" % scene_path)
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("item_rng_seed", _SEED)
	race.call("configure", _catalog)
	return race


## Frame-exact "wait for real GO", the same shape test_race_start_flow.gd's
## own _wait_until_race_started() establishes (see that file's own doc) --
## GUT test scripts don't share private helpers across files (established
## convention, see test_race_standings.gd's own identical note), so this is
## a local copy, not a reach into another suite's file.
func _wait_until_race_started(race: Node) -> void:
	var physics_fps := float(Engine.physics_ticks_per_second)
	var max_frames := int(ceil(_catalog.race.countdown_step_s * physics_fps)) * 10
	var frames_waited := 0
	while not bool(race.call("is_race_started")) and frames_waited < max_frames:
		await wait_physics_frames(1)
		frames_waited += 1
	assert_true(
		bool(race.call("is_race_started")),
		"fixture setup: the real countdown must reach GO within a generous bound"
	)


## The player kart "teleport-finishes": global_position is hand-placed onto
## each real authored CheckpointGate Area3D in order, letting Godot's own
## physics detect the overlap -- test_race_session.gd's own _cross_gate()
## technique, not the private-handler shortcut. Physics is disabled on the
## kart first (same rationale _cross_gate()'s own callers use throughout
## this codebase: without it, the kart's own auto-throttle motor tick would
## fight the teleport and the next tick's real driving would silently
## overwrite whichever position was just hand-placed).
func _teleport_finish_player(
	race: Node, kart: CharacterBody3D, gate_count: int, lap_count: int
) -> void:
	kart.set_physics_process(false)
	for _lap in range(lap_count):
		for gate_index in range(gate_count):
			var gate := race.get_node("Track/Gates/Gate%d" % gate_index) as Area3D
			kart.global_position = gate.global_position
			await wait_physics_frames(2)
	# One more crossing of gate 0 closes the final lap -- see every other
	# suite's own identical "+1 crossing" comment (test_race_session.gd,
	# test_race_session_sanity_shores.gd).
	var start_gate := race.get_node("Track/Gates/Gate0") as Area3D
	kart.global_position = start_gate.global_position
	await wait_physics_frames(2)


# ---------------------------------------------------------------------------
# Full flow: real countdown -> GO -> real AI physics driving (bounded) ->
# player teleport-finish -> standings shows a real finished/unfinished split.
# One test per real track.
# ---------------------------------------------------------------------------


func _run_full_flow_and_assert_standings(scene_path: String, gate_count_expected: int) -> void:
	var race := _boot_race(scene_path)
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var opponent_count := int(_catalog.ai.opponent_count)

	assert_eq(int(race.call("gate_count")), gate_count_expected, "fixture sanity: gate count")
	assert_eq(race.call("countdown_phase"), &"three", "fixture setup: countdown starts at three")
	assert_false(bool(race.call("is_race_started")))

	# The countdown ticks through real physics frames all the way to GO.
	await _wait_until_race_started(race)
	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.05,
		"the race timer must read essentially zero right at GO -- it starts AT go, not at spawn"
	)

	# The player's own kart is frozen right at GO (a deterministic
	# "teleport-finish" fixture, not a real drive) -- AI karts are left
	# fully alone to drive themselves under real physics for a bounded
	# window. 90 frames (1.5s @ 60Hz) is comfortably short of even a
	# fraction of one lap at kart.tres's top_speed_mps on either real
	# track (both tracks' own authored scale is tens to hundreds of
	# meters between checkpoints -- see spec debt #10's own clearance
	# figures), so no AI kart can genuinely finish inside this window;
	# it exists purely to let real AiKartAgent/AiDriver physics produce
	# real, differentiated progress numbers before the player finishes.
	kart.set_physics_process(false)
	var ai_drive_frames := 90
	await wait_physics_frames(ai_drive_frames)

	# Real driving actually happened -- not a stale zero.
	var any_ai_progressed := false
	for index in range(opponent_count):
		if float(race.call("ai_kart_total_progress_m", index)) > 0.0:
			any_ai_progressed = true
			break
	assert_true(
		any_ai_progressed,
		"at least one AI kart must show real forward progress from real post-GO physics"
	)
	# Live ranking is already populated mid-race (R5 Task 2's own contract).
	assert_eq(
		int(race.call("field_size")),
		opponent_count + 1,
		"the live field must count the player plus every AI kart"
	)
	assert_false(bool(race.call("is_finished")), "fixture sanity: nobody has finished yet")

	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	await _teleport_finish_player(race, kart, gate_count, lap_count)

	assert_true(bool(race.call("is_finished")), "the player's own teleport-finish must complete the race")
	assert_gt(float(race.call("elapsed_s")), 0.0, "a real finish must show a real positive time")

	var standings: Array = race.call("standings")
	assert_eq(standings.size(), opponent_count + 1, "one standings row per kart in the race")

	var player_row: Dictionary = standings[0]
	assert_eq(int(player_row.get("position")), 1, "the only finisher must rank first")
	assert_true(bool(player_row.get("is_player")))
	assert_true(bool(player_row.get("finished")))
	assert_gt(float(player_row.get("elapsed_s")), 0.0)

	var unfinished_count := 0
	for row_index in range(1, standings.size()):
		var row: Dictionary = standings[row_index]
		assert_false(bool(row.get("is_player")))
		assert_false(
			bool(row.get("finished")),
			"no AI kart could have genuinely finished inside the bounded pre-finish drive window"
		)
		assert_eq(float(row.get("elapsed_s")), 0.0, "an unfinished row must show no time")
		unfinished_count += 1
	assert_eq(unfinished_count, opponent_count, "every AI kart must land as an unfinished standings row")

	# The results screen itself (R5 Task 3) actually renders this split.
	var hud := race.get_node("UI/RaceHUD")
	var standings_label := hud.get_node("SafeArea/FinishPanel/Margin/Rows/Standings") as Label
	await wait_process_frames(1)
	assert_true(standings_label.visible, "the finish panel must show the standings list for a race")
	assert_true(standings_label.text.contains("YOU"), "the standings text must include the player's own row")


func test_graybox_loop_full_flow_countdown_through_go_real_ai_driving_teleport_finish_and_standings() -> void:
	await _run_full_flow_and_assert_standings(RACE_SCENE_PATH, 6)


func test_sanity_shores_full_flow_countdown_through_go_real_ai_driving_teleport_finish_and_standings() -> void:
	await _run_full_flow_and_assert_standings(SANITY_SHORES_RACE_SCENE_PATH, 12)


# ---------------------------------------------------------------------------
# Pause during the countdown -- composed within a real, already-progressed
# countdown (not from tick 0, unlike test_race_start_flow.gd's own dedicated
# pause test), proving the freeze holds mid-sequence too.
# ---------------------------------------------------------------------------


func test_pausing_mid_countdown_freezes_progress_toward_go() -> void:
	var race := _boot_race(RACE_SCENE_PATH)
	if race == null:
		return
	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)

	# Advance for real, past the first phase and partway into the second --
	# a stronger proof than pausing at tick 0, since a reset back to "two"
	# after resuming genuinely demonstrates the freeze rather than merely
	# confirming a value that never moved.
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 5)
	assert_eq(race.call("countdown_phase"), &"two", "fixture setup: partway through the countdown")

	race.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 10)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE

	assert_eq(
		race.call("countdown_phase"),
		&"two",
		"the countdown must not advance a single phase while paused, even mid-sequence"
	)
	assert_false(bool(race.call("is_race_started")))
	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.0001,
		"the race timer stays zero through the whole pre-GO countdown regardless of pausing -- it starts AT go"
	)

	await wait_physics_frames(int(ceil(step_s * physics_fps)))
	assert_eq(race.call("countdown_phase"), &"one", "the countdown must resume advancing once unpaused")


# ---------------------------------------------------------------------------
# Pause during the race itself -- elapsed_s() freezes, then resumes.
# ---------------------------------------------------------------------------


func test_pausing_mid_race_freezes_elapsed_s() -> void:
	var race := _boot_race(RACE_SCENE_PATH)
	if race == null:
		return
	await _wait_until_race_started(race)

	await wait_physics_frames(20)
	var elapsed_before_pause := float(race.call("elapsed_s"))
	assert_gt(elapsed_before_pause, 0.0, "fixture setup: real race time must have elapsed before pausing")

	race.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(30)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE

	var elapsed_after_gap := float(race.call("elapsed_s"))
	assert_almost_eq(
		elapsed_after_gap,
		elapsed_before_pause,
		0.05,
		"elapsed_s() must not advance a single tick while paused mid-race"
	)

	await wait_physics_frames(20)
	assert_gt(
		float(race.call("elapsed_s")),
		elapsed_after_gap,
		"elapsed_s() must resume advancing once unpaused"
	)


# ---------------------------------------------------------------------------
# Retry mid-countdown: a reconfigure() fired WHILE still pre-GO (never
# reached GO at all this attempt) must reset back to a completely fresh
# countdown, not resume or half-reset from wherever it had gotten to.
# ---------------------------------------------------------------------------


func test_retry_mid_countdown_resets_to_a_fresh_countdown_with_zero_elapsed() -> void:
	var race := _boot_race(RACE_SCENE_PATH)
	if race == null:
		return
	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)

	# Advance into the second countdown phase -- never reaching GO.
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 5)
	assert_eq(race.call("countdown_phase"), &"two", "fixture setup: mid-countdown, never started")
	assert_false(bool(race.call("is_race_started")))

	# The real retry path frees and reinstantiates the whole scene (see
	# race_session.gd's own retry_requested doc); this codebase's own
	# established stand-in for that (test_race_start_flow.gd's identical
	# test_reconfigure_resets_the_whole_flow_back_to_a_frozen_pre_go_state)
	# is calling configure() again on the SAME instance -- that existing
	# test reconfigures AFTER the countdown had already reached GO; this one
	# is the genuinely different case: retrying from WITHIN an unfinished
	# countdown that never got there at all.
	race.call("configure", _catalog)
	var kart_after := race.get_node("Kart") as CharacterBody3D

	assert_eq(
		race.call("countdown_phase"),
		&"three",
		"a mid-countdown retry must reset all the way back to the very first phase, not resume from \"two\""
	)
	assert_false(bool(race.call("is_race_started")))
	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.0001,
		"the race timer must read exactly zero after a mid-countdown retry"
	)
	assert_false(
		bool(kart_after.call("is_run_active")),
		"the player's own kart must spawn frozen again after a mid-countdown retry"
	)

	# A fresh countdown genuinely runs again from here -- not stuck.
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 5)
	assert_eq(
		race.call("countdown_phase"),
		&"two",
		"the reset countdown must be able to advance again for real, proving it wasn't just frozen"
	)


# ---------------------------------------------------------------------------
# Solo epoch pin (R5 Task 4 brief): solo time trial now runs the SAME real
# countdown + start-ritual as a race (a deliberate R5 decision -- the start
# boost is a player-skill mechanic, not race-only), and the race timer
# starts AT GO for solo too. This is an EPOCH CHANGE from pre-R5 behavior,
# where a solo time-trial's clock started at spawn -- old saved best times
# were set under that old epoch and are NOT directly comparable second-for-
# second to a new run's clock, which now excludes the ~3s (three
# countdown_step_s phases) countdown window entirely. This test pins the
# new behavior; the epoch note itself belongs in this task's own report
# (and the operator TG summary), not just this comment.
# ---------------------------------------------------------------------------


func test_solo_time_trial_elapsed_stays_zero_until_go_pinning_the_epoch_change() -> void:
	var race := _boot_race(SOLO_SCENE_PATH)
	if race == null:
		return
	assert_eq(
		int(race.call("placement_out_of")),
		1,
		"fixture sanity: the real solo scene must spawn no AI opponents"
	)

	# Real ticks well past a full countdown_step_s but comfortably short of
	# the whole ~3-step countdown -- if solo's timer ever started at spawn
	# (the pre-R5 epoch), this alone would already read a large positive
	# elapsed_s().
	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	await wait_physics_frames(int(round(step_s * physics_fps * 1.5)))

	assert_false(bool(race.call("is_race_started")), "fixture sanity: still mid-countdown")
	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.0001,
		"solo's own race timer must stay at zero through the whole pre-GO countdown -- the epoch is GO, not spawn"
	)

	await _wait_until_race_started(race)
	await wait_physics_frames(5)
	assert_gt(
		float(race.call("elapsed_s")),
		0.0,
		"solo's own race timer must start advancing once GO actually fires, same as a race"
	)
