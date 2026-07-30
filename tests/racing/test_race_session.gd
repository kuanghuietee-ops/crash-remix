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
#
# EXCEPTION: the two H2 fix-round tests below (finish-freeze behavior) call
# the session's private gate-crossing handler directly instead, and
# deliberately leave the kart's own physics_process running throughout --
# see their own doc comments. set_physics_process(false) would exclude the
# very tick the freeze fix operates on, which is exactly what the reviewer
# flagged in the prior round.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

var _catalog: GameplayTuning
var _kart_tuning: KartTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load")


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

	# The timer must freeze once finished. (Whether the KART itself comes
	# to rest and stays there is a separate, real-physics-driven proof --
	# see test_finishing_the_race_decelerates_the_kart_to_a_stop_and_it_
	# stays_stopped below. This test's kart has its own physics_process
	# disabled throughout for the gate-teleport determinism every test in
	# this file needs, so it cannot also be the proof that the freeze
	# actually stops a REAL moving kart.)
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


func test_request_retry_emits_the_retry_requested_signal() -> void:
	# H1 fix round: RaceHUD's RETRY button now only calls this -- GameRoot
	# is the one that actually reloads the race (see race_session.gd's
	# retry_requested doc and game_root.gd's DEBUG_RACING_LEVEL_ID branch).
	# This proves the session side of that contract in isolation, headless.
	var race := _boot_race()
	if race == null:
		return
	watch_signals(race)

	race.call("request_retry")

	assert_signal_emitted(race, "retry_requested")


# ---------------------------------------------------------------------------
# M1 (final fix wave): elapsed_s() must exclude time the tree is paused.
# ---------------------------------------------------------------------------


## race_session.gd's elapsed_s() used to be a raw MonotonicClock diff against
## a start timestamp -- correct on a running clock, but GameRoot pauses the
## whole tree (see game_root.gd's _sync_tree_pause()) while a PAUSED overlay
## is up, and real wall-clock time keeps moving underneath that regardless.
## The fix mirrors level_session.gd's own precedent for this exact class of
## bug (LevelRunState.advance_relic_timer(delta_s), summed only from
## _physics_process): RaceSession now sets process_mode =
## PROCESS_MODE_PAUSABLE in configure() (previously left at the INHERIT
## default, which silently picked up GameRoot's own PROCESS_MODE_ALWAYS) and
## accumulates its own elapsed timer from delta_s each tick instead of
## reading the wall clock directly, so a tick that never runs while paused
## contributes nothing.
##
## Simulated here by manipulating the session's own process_mode directly
## rather than the real SceneTree.paused flag -- a deterministic,
## tree-global-state-free way to prove a PAUSABLE node's own physics-driven
## accumulation actually stops when it isn't processing, the same shape
## GameRoot's real pause achieves by setting SceneTree.paused = true while
## every PAUSABLE node (this session included, once configured) just stops
## being ticked.
func test_elapsed_s_excludes_time_the_race_session_is_not_processing() -> void:
	var race := _boot_race()
	if race == null:
		return

	await wait_physics_frames(20)
	var elapsed_before_pause := float(race.call("elapsed_s"))
	assert_gt(
		elapsed_before_pause,
		0.0,
		"fixture setup: real time must have elapsed before the simulated pause"
	)

	race.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(30)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE

	var elapsed_after_gap := float(race.call("elapsed_s"))
	assert_almost_eq(
		elapsed_after_gap,
		elapsed_before_pause,
		0.05,
		(
			"elapsed_s() must not advance while the race session isn't "
			+ "processing -- got before=%s after=%s (background/paused "
			+ "wall-clock time leaking in is exactly the bug this pins)"
		) % [elapsed_before_pause, elapsed_after_gap]
	)

	await wait_physics_frames(20)
	var elapsed_after_resume := float(race.call("elapsed_s"))
	assert_gt(
		elapsed_after_resume,
		elapsed_after_gap,
		"elapsed_s() must resume advancing once processing resumes"
	)


## "Lap splits consistent": a split recorded across a simulated pause must
## still equal the ACTIVE elapsed time between the two boundary crossings,
## not the wall-clock time (which includes the paused gap). Drives through
## a real lap via the same teleport-cross technique the rest of this file
## uses, with a simulated pause inserted partway through.
func test_lap_split_stays_consistent_across_a_simulated_pause() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)
	var gate_count := int(race.call("gate_count"))

	# The very first crossing of gate 0 only starts lap 1 -- it records no
	# split (see lap_validator.gd's own class doc) -- so this establishes
	# the boundary the eventual lap-1 split will be measured from.
	await _cross_gate(race, kart, 0)
	var lap_start_elapsed := float(race.call("elapsed_s"))

	await wait_physics_frames(15)
	race.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(30)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE
	await wait_physics_frames(15)

	for gate_index: int in range(1, gate_count):
		await _cross_gate(race, kart, gate_index)
	# Closes lap 1.
	await _cross_gate(race, kart, 0)

	var lap_end_elapsed := float(race.call("elapsed_s"))
	var laps: Array = race.call("lap_times")
	assert_eq(laps.size(), 1, "fixture setup: exactly one lap must have completed")
	if laps.size() != 1:
		return
	# A couple of ticks of slack: the split's own boundary is stamped
	# INSIDE the gate's body_entered handler, which can fire on either
	# physics tick _cross_gate's own wait_physics_frames(2) advances
	# through -- this tolerance absorbs that natural capture skew while
	# staying far tighter than the ~0.5s simulated pause gap it must still
	# catch leaking in.
	assert_almost_eq(
		float(laps[0]),
		lap_end_elapsed - lap_start_elapsed,
		0.05,
		"a recorded lap split must equal elapsed_s()'s own active-time "
		+ "accounting between the two boundary crossings, pause included"
	)


## H2 fix round: proves the freeze through REAL physics -- the kart's own
## _physics_process stays enabled throughout (unlike every gate-crossing
## test above, which disables it for teleport determinism; the reviewer's
## exact finding was that doing so here would exclude the very tick the
## fix operates on). The race is driven to completion by calling the
## session's own gate-crossing handler directly with the real authored gate
## nodes (see _force_finish) so this test isn't ALSO re-proving Area3D
## wiring already covered by test_crossing_every_gate_in_order_for_all_
## laps_completes_the_race above -- only the post-finish motor freeze is
## new ground here.
func test_finishing_the_race_decelerates_the_kart_to_a_stop_and_it_stays_stopped() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	# Let the real auto-throttle build up real speed first.
	await wait_physics_frames(30)
	assert_gt(
		float(kart.call("speed_mps")),
		0.0,
		"fixture setup: the kart must really be moving before it finishes"
	)

	_force_finish(race)
	assert_true(bool(race.call("is_finished")))

	# Bounded sim time: enough real ticks for brake_mps2 to bring even a
	# kart at top speed down to rest, plus margin.
	var stop_time_s: float = (
		_kart_tuning.top_speed_mps / _kart_tuning.brake_mps2
	)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 10
	var frames_needed := (
		int(ceil(stop_time_s * physics_fps)) + margin_frames
	)
	await wait_physics_frames(frames_needed)

	assert_almost_eq(
		float(kart.call("speed_mps")),
		0.0,
		0.05,
		"the kart must come to rest once the race finishes"
	)
	assert_false(
		bool(kart.call("is_run_active")),
		"the kart must report itself frozen once the race finishes"
	)

	# And it must STAY there: more real ticks must not creep it forward
	# again under auto-throttle -- the exact bug this fix closes.
	var resting_position := kart.global_position
	await wait_physics_frames(30)

	assert_almost_eq(
		float(kart.call("speed_mps")),
		0.0,
		0.05,
		"the kart must stay stopped, not resume auto-throttling"
	)
	assert_lt(
		kart.global_position.distance_to(resting_position),
		0.05,
		"a stopped kart must not keep creeping forward"
	)


## H2 fix round: a race can finish while the kart is mid-drift -- the slide
## must end immediately (not just stop being fed real input) and the
## kart's yaw must not keep accumulating afterward. Real physics
## throughout, same rationale as the test above.
func test_finishing_mid_slide_ends_the_slide_with_no_further_rotation() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# RaceSession's OWN _physics_process routes InputRouter's (here: idle,
	# zero) buffered move vector into the kart every tick -- steer(0.0) --
	# which would fight this test's manual steer() calls below on the very
	# next physics frame. This disables the SESSION's input-routing tick
	# only; the KART's own _physics_process (the thing actually under test:
	# DriftStateMachine + KartMotor + the H2 freeze) stays fully enabled the
	# whole time, unlike the teleport tests above.
	race.set_physics_process(false)

	await wait_physics_frames(10)
	assert_true(
		kart.is_on_floor(),
		"fixture setup: the kart must be grounded before sliding"
	)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(
		bool(kart.call("is_sliding")),
		"fixture setup: the kart must really be sliding before it finishes"
	)

	_force_finish(race)

	assert_true(bool(race.call("is_finished")))
	assert_false(
		bool(kart.call("is_sliding")),
		"a finish caught mid-slide must force-end the slide immediately"
	)

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	var yaw_at_finish: float = motor.call("yaw_degrees")

	await wait_physics_frames(30)

	assert_almost_eq(
		float(motor.call("yaw_degrees")),
		yaw_at_finish,
		0.001,
		"yaw must not keep accumulating after a mid-slide finish"
	)


# ---------------------------------------------------------------------------
# M2 (final fix wave): on-device tuning edits must reach a race already in
# progress, not just the next one configure() boots -- the racing
# counterpart to LevelSession.refresh_tuning()/phase0_game.gd's
# refresh_tuning(), see game_root.gd's _refresh_active_level_tuning().
# ---------------------------------------------------------------------------


func test_refresh_tuning_reapplies_a_live_kart_tuning_value_to_the_motor() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return

	# duplicate(true) only deep-copies embedded sub-resources, not
	# externally-referenced ones like data/tuning/racing/kart.tres (an
	# ExtResource from gameplay.tres's own point of view) -- it would leave
	# tuning_variant.kart pointing at the SAME KartTuning object _catalog.kart
	# does, so mutating it below would silently pollute every other test's
	# shared fixture too. duplicate_deep(DEEP_DUPLICATE_ALL) is the idiom
	# test_tuning_service.gd's own migration tests already establish for
	# genuinely detaching the whole racing catalog.
	var tuning_variant: GameplayTuning = _catalog.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	tuning_variant.kart.top_speed_mps = _catalog.kart.top_speed_mps * 2.0

	race.call("refresh_tuning", tuning_variant)

	# Parked exactly at the OLD top speed: with the stale tuning still in
	# effect, auto-throttle's target would already equal this and the motor
	# would not move at all. Only a motor now actually reading the doubled
	# top_speed_mps has anywhere further to accelerate toward.
	motor.set("_forward_speed_mps", _catalog.kart.top_speed_mps)
	await wait_physics_frames(30)

	assert_gt(
		float(motor.call("forward_speed_mps")),
		_catalog.kart.top_speed_mps,
		(
			"refresh_tuning() must reach the real motor this controller "
			+ "owns -- the next tick after a live tuning edit must "
			+ "already accelerate toward the NEW top_speed_mps, not stay "
			+ "parked at the stale one"
		)
	)


# ---------------------------------------------------------------------------
# Task 5 (CTR R3 integration): opponent_count AI karts now spawn alongside
# the player by default (ai.tres's own opponent_count=5.0 -- this IS the R3
# product, see the task brief's own "the two race scenes get AI by default"
# ruling). Every test above this point boots the exact same real scene
# through the exact same real configure() path and stays green UNMODIFIED
# with those 5 extra karts now also driving themselves in the background --
# none of it asserts a kart count, so nothing above needed touching.
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


## Binding contract 2 (seam ruling): a gate crossing routes to the CORRECT
## kart's own validator by body identity -- an AI kart driving through gate 0
## must advance only ITS OWN LapValidator, never the player's, and the
## player's own progress_gates() must stay untouched. set_physics_process(
## false) on the AI kart mirrors _cross_gate's own "teleport, then let the
## real Area3D overlap detect it" technique below; the AI kart's own
## AiKartAgent keeps ticking (a separate Node, unaffected by that call) but
## only ever WRITES steer/brake/speed_scale onto a KartController whose own
## _physics_process never runs to consume them, so the teleported position
## holds for the few frames this test needs.
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
				"AI kart at slot %d must be frozen once the player finishes "
				+ "-- set_run_active(false), the same freeze the player's "
				+ "own kart gets"
			) % (slot_index + 1)
		)


## Binding contract 3: with every AI kart still sitting at (or behind) its
## own spawn -- every GridSlot sits physically behind the player's own
## KartSpawn, see track_graybox_loop.tscn -- an immediate finish with zero
## driving is already the "everyone is behind the player" case.
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


## Reaches into one AI kart's own private SpineFollower (agent.get(
## "_follower"), the same white-box technique this suite already uses for
## KartController's private _motor/_drift below) to deterministically seed
## its total_progress_m() past the player's own, rather than relying on
## real, possibly-flaky AI driving physics to get there -- this test's job
## is proving the PLACEMENT MATH, not grading the AI's racing line.
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
	assert_gt(
		float(race.call("ai_kart_total_progress_m", 0)),
		float(race.call("player_total_progress_m")),
		"fixture setup: the seeded AI kart must actually read ahead of the player"
	)

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


## Item 3 (solo time-trial compatibility): a test that needs a solo race
## overrides the tuning catalog in-test rather than RaceSession weakening any
## assertion -- the established pattern this whole file's own H2/M2 fix-round
## tests already use for a detached, mutation-safe tuning copy (see
## test_refresh_tuning_reapplies_a_live_kart_tuning_value_to_the_motor's own
## duplicate_deep() comment). Proves placement_out_of() reads 1 (no AI karts
## to place against) with opponent_count pinned to 0, which is exactly what
## RaceHUD's own "m > 1" gate (see race_hud.gd's _on_race_finished) keys off
## of to leave the old solo finish panel completely unchanged.
func test_solo_race_with_zero_opponents_spawns_no_ai_and_places_first_alone() -> void:
	var solo_catalog: GameplayTuning = _catalog.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	solo_catalog.ai.opponent_count = 0.0

	var race := _boot_race_with_catalog(solo_catalog)
	if race == null:
		return

	assert_eq(int(race.call("ai_kart_count")), 0, "opponent_count=0 must spawn zero AI karts")

	_force_finish(race)

	assert_eq(int(race.call("placement")), 1)
	assert_eq(
		int(race.call("placement_out_of")),
		1,
		"a solo race's placement_out_of() must read 1 -- RaceHUD's own m > 1 gate keys off exactly this"
	)


## Fix-wave MEDIUM-5: solo time trial restored via the NEW exported
## spawn_opponents flag (default true, unmodified GameplayTuning) rather
## than the opponent_count=0 tuning override above -- the flag is the real
## scene-level mechanism scenes/racing/race_time_trial_solo.tscn/race_
## sanity_shores_solo.tscn now use (see game_root.gd's own wiring), and the
## brief's own ruling ("do NOT change opponent_count validation -- the flag
## owns solo-ness") means this must work with a perfectly ordinary,
## opponent_count=5 catalog: the flag alone must be sufficient, with no
## tuning override required. The pre-existing opponent_count=0 test above is
## left completely unchanged -- both are legitimate, independent ways to
## reach zero AI karts, not a replacement of one by the other.
func test_spawn_opponents_false_spawns_no_ai_even_with_a_positive_opponent_count() -> void:
	assert_true(
		_catalog.ai.opponent_count > 0.0,
		"fixture sanity: the shared catalog's own opponent_count must stay positive -- this test's whole point is proving the flag alone suffices"
	)
	assert_true(
		ResourceLoader.exists(RACE_SCENE_PATH),
		"race_time_trial.tscn must exist"
	)
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("spawn_opponents", false)
	race.call("configure", _catalog)

	assert_eq(
		int(race.call("ai_kart_count")),
		0,
		"spawn_opponents=false must spawn zero AI karts regardless of opponent_count"
	)

	_force_finish(race)

	assert_eq(int(race.call("placement")), 1)
	assert_eq(
		int(race.call("placement_out_of")),
		1,
		"a spawn_opponents=false race's placement_out_of() must read 1, same as the opponent_count=0 path"
	)


func test_spawn_opponents_defaults_to_true_and_does_not_change_the_ai_race_shape() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_true(
		bool(race.get("spawn_opponents")),
		"spawn_opponents must default to true -- every existing race scene/test relies on this"
	)
	assert_eq(
		int(race.call("ai_kart_count")),
		int(_catalog.ai.opponent_count),
		"the default flag value must not change the ordinary AI roster size"
	)


## Fix-wave MEDIUM-5: the REAL packaged race_time_trial_solo.tscn (not just
## the RaceSession class field in isolation) must actually override spawn_
## opponents to false -- the real "thin scene variant" GameRoot's own level
## list now dispatches to for the graybox loop's TIME TRIAL entry.
func test_real_solo_scene_overrides_spawn_opponents_to_false() -> void:
	const SOLO_SCENE_PATH := "res://scenes/racing/race_time_trial_solo.tscn"
	assert_true(
		ResourceLoader.exists(SOLO_SCENE_PATH),
		"race_time_trial_solo.tscn must exist"
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
	assert_eq(
		int(race.call("ai_kart_count")),
		0,
		"the real solo scene must spawn zero AI karts once configured"
	)
	assert_not_null(
		race.get_node_or_null("Kart"),
		"the solo scene must keep every node path the base race scene authors -- instance=ExtResource overrides only spawn_opponents"
	)


## Item 2 (retry rebuilds AI cleanly). The REAL retry path (RaceHUD ->
## request_retry() -> GameRoot re-selecting the level) frees this entire
## scene and instantiates a fresh one, so every AI kart/agent (ordinary
## scene children) already dies with it -- nothing scene-level to prove
## beyond what Godot's own node-tree ownership already guarantees. What IS
## this session's own responsibility is _spawn_ai_karts()'s defensive
## idempotency: calling configure() again on the SAME instance (a stand-in
## for "rebuild", exercised directly since this suite has no GameRoot to
## drive a real retry through) must not leak the previous batch of AI karts
## or hand back stale instances.
func test_reconfigure_rebuilds_ai_karts_without_leaking_old_instances() -> void:
	var race := _boot_race()
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	var first_instance_ids: Array[int] = []
	for slot_index: int in range(opponent_count):
		first_instance_ids.append(race.call("ai_kart", slot_index).get_instance_id())

	race.call("configure", _catalog)
	# queue_free() on the old batch is deferred to end-of-frame -- give it a
	# couple of physics frames to actually process before checking for
	# leftovers.
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


## CENTERPIECE (Task 5, strengthened fix-wave MEDIUM-2): a real, ungated,
## 20-simulated-second race on the real graybox loop with the full default
## AI roster -- every AI kart driving itself for real (steer/hop/slide/
## rubber-band/stuck-respawn, the whole Task 3/4 pipeline) alongside the
## player's own idle kart, proving the integration holds up under real
## sustained physics rather than the shorter, synthetic slices every other
## test above uses.
##
## BOUND DERIVATION (the old version of this test only asserted total
## progress > 0, a coverage gap Task 5's own review flagged): AI karts drive
## at a real, tuned pace between corner_speed_floor_ratio * top_speed_mps
## (kart.tres: 18 * 0.45 = 8.1 m/s, the tightest-corner floor) and
## top_speed_mps itself (18 m/s, open straight); real-physics runs measured
## while building this fix landed in the ~5-14 m/s range once slide
## slowdowns and the occasional stuck-respawn recovery cycle are folded in.
## Half the loop's own real (measured via spine.length_m(), never a bare
## meters literal) length in 20 simulated seconds is comfortably clearable
## even near the low end of that range, while a full lap in 60s (the
## brief's own looser alternative) would triple this already-long test's
## own suite-time cost for a floor that is not meaningfully tighter -- 0.5
## lap / 20s is the brief's own explicit "keep suite runtime sane" pick.
##
## RECOVERED-VIA-RESPAWN ESCAPE VALVE: reuses test_ai_kart_agent.gd's own
## test_east_turn_never_permanently_wedges_over_twenty_real_seconds shape
## (min-total-seen tracked per kart, healthy-OR-recovered) rather than a
## bare floor, because the graybox loop's East turn is a KNOWN, spec-
## recorded, already-tested acceptance (Recorded debts #7: the safety net
## recovers it, corner geometry does not prevent it outright) -- a bare
## floor here would make this test flaky against that already-accepted
## behavior instead of strengthening real coverage.
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
	# R4 Task 1 tightening: the respawn OR-branch used to accept ANY kart
	# whose stuck-respawn fired at all and then crawled just respawn_drop_
	# gap_m (ai.tres: 4.0m) past its own worst point -- "wedge, then a
	# single 4m nudge" -- with no requirement it ever actually covered
	# meaningful ground over the full 20s. A badly-degraded AI (e.g. a
	# regression that makes it wedge, crawl 4m, wedge again, repeat) could
	# pass that branch forever without ever demonstrating real progress.
	# _RECOVERY_FRACTION requires a recovered kart's own FINAL total to
	# still clear a fraction of the healthy floor -- half of it, i.e. a
	# quarter of the full loop -- so "recovered" means "got meaningfully far
	# despite needing the safety net once," not "technically wasn't at the
	# exact same spot it started at." Half was picked (documented here, per
	# the brief's own example) as the midpoint between the two extremes this
	# branch has to tell apart: a kart that is basically healthy but dipped
	# into ONE stuck-respawn cycle (which should still clear most of the
	# healthy floor) and a kart that is genuinely broken (which a bare
	# wedge+4m floor let through with arbitrarily little real progress).
	const _RECOVERY_FRACTION := 0.5
	var recovery_floor_m := healthy_progress_m * _RECOVERY_FRACTION
	for slot_index: int in range(opponent_count):
		var final_total := float(race.call("ai_kart_total_progress_m", slot_index))
		var respawn_count := int(race.call("ai_agent", slot_index).call("respawn_count"))
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
				+ "of total progress over 20 real seconds, OR demonstrably "
				+ "recover via its own stuck-respawn safety net AND still "
				+ "clear %s m (%s x the healthy floor) of real final "
				+ "progress: gained=%s m final_total=%s m healthy_floor=%s m "
				+ "recovery_floor=%s m respawn_count=%s min_total_seen=%s"
			) % [
				slot_index + 1,
				healthy_progress_m,
				recovery_floor_m,
				_RECOVERY_FRACTION,
				gained,
				final_total,
				healthy_progress_m,
				recovery_floor_m,
				respawn_count,
				min_totals_seen[slot_index],
			]
		)


## Task 6 (CTR R3 verification): reviewer-mandated coverage gap folded in
## from Task 5's own review (see the SDD progress ledger's Task 5 entry --
## "MEDIUM coverage gap folded into Task 6: end-to-end freeze-chain test
## (AI mid-drive -> real finish -> 5s+ -> all frozen, no respawns)"). Every
## AI-freeze assertion above either force-finishes via the private
## _on_gate_body_entered handler (test_player_finish_freezes_every_ai_kart)
## or only checks the tick right after the finish -- neither proves the
## freeze SURVIVES several more real seconds of physics once the player
## finishes through the REAL gate-crossing chain while AI karts are
## genuinely mid-drive, not still sitting at spawn. This test closes that
## gap in four real-physics stages:
##   1. ~4 real seconds of every AI kart genuinely driving itself (steer/
##      hop/slide/rubber-band/stuck-respawn, the full Task 3/4 pipeline) --
##      so the freeze below has to actually STOP something in motion.
##   2. The REAL finish path: teleport the player's kart onto every
##      authored gate for all lap_count laps (the exact technique
##      test_crossing_every_gate_in_order_for_all_laps_completes_the_race
##      uses above -- a real Area3D overlap fires _on_gate_body_entered ->
##      _finish_race), NOT the private _force_finish() shortcut every other
##      finish test in this file takes.
##   3. Enough more real ticks for every AI kart to actually finish
##      decelerating under set_run_active(false)'s own decelerate_to_stop()
##      branch (kart_controller.gd) -- the same bounded-settle-time idiom
##      test_finishing_the_race_decelerates_the_kart_to_a_stop_and_it_stays_
##      stopped already establishes for the player, worst-cased here for an
##      AI kart's own possible rubber-band-boosted top speed (see
##      ai_kart_agent.gd's _max_follower_step_m() doc for why plain
##      top_speed_mps alone would underestimate it).
##   4. 5+ MORE real seconds, asserting every AI kart stayed frozen
##      (is_run_active() false), never respawned (respawn_count()
##      unchanged), and never moved (position unchanged within physics
##      epsilon) across that entire window -- proving AiKartAgent's own
##      RUN-ACTIVE GATE (Task 5 binding contract 1, see ai_kart_agent.gd's
##      class doc) holds under sustained real ticks, not a one-shot check.
func test_a_real_player_finish_freezes_every_ai_kart_for_several_more_real_seconds() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.set_physics_process(false)
	var opponent_count := int(_catalog.ai.opponent_count)
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	var physics_fps := float(Engine.physics_ticks_per_second)

	# Stage 1: ~4 real seconds of every AI kart genuinely driving itself,
	# before the player ever finishes.
	var warm_up_frames := int(round(4.0 * physics_fps))
	await wait_physics_frames(warm_up_frames)

	var any_ai_progress := false
	for slot_index: int in range(opponent_count):
		if float(race.call("ai_kart_total_progress_m", slot_index)) > 0.0:
			any_ai_progress = true
			break
	assert_true(
		any_ai_progress,
		(
			"fixture sanity: at least one AI kart must have made real "
			+ "forward progress before the finish"
		)
	)

	# Stage 2: the REAL finish path.
	for _lap: int in range(lap_count):
		for gate_index: int in range(gate_count):
			await _cross_gate(race, kart, gate_index)
	# One more gate-0 crossing closes the final lap -- see _cross_gate's own
	# comment above / test_crossing_every_gate_in_order_for_all_laps_
	# completes_the_race's identical final call.
	await _cross_gate(race, kart, 0)

	assert_true(
		bool(race.call("is_finished")),
		"the real gate-crossing chain must finish the race"
	)

	# Stage 3: let every AI kart actually finish decelerating.
	var worst_case_speed_mps := (
		(_kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps)
		* (1.0 + _catalog.ai.rubber_band_boost_max_ratio)
	)
	var settle_time_s: float = worst_case_speed_mps / _kart_tuning.brake_mps2
	var settle_margin_frames := 10
	var settle_frames := (
		int(ceil(settle_time_s * physics_fps)) + settle_margin_frames
	)
	await wait_physics_frames(settle_frames)

	var baseline_positions: Array[Vector3] = []
	var baseline_respawn_counts: Array[int] = []
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		var agent: Node = race.call("ai_agent", slot_index)
		assert_not_null(
			ai_kart, "fixture setup: AI kart at slot %d must exist" % (slot_index + 1)
		)
		assert_not_null(
			agent, "fixture setup: AI agent at slot %d must exist" % (slot_index + 1)
		)
		if ai_kart == null or agent == null:
			baseline_positions.append(Vector3.ZERO)
			baseline_respawn_counts.append(0)
			continue
		assert_false(
			bool(ai_kart.call("is_run_active")),
			(
				"AI kart at slot %d must already be frozen once settled "
				+ "after the finish"
			) % (slot_index + 1)
		)
		baseline_positions.append(ai_kart.global_position)
		baseline_respawn_counts.append(int(agent.call("respawn_count")))

	# Stage 4: the centerpiece -- 5+ MORE real seconds of physics after every
	# AI kart has settled. This is the reviewer-mandated coverage gap this
	# test exists to close: the freeze must survive sustained real ticks,
	# not just the instant of the finish.
	var post_settle_frames := int(round(5.5 * physics_fps))
	await wait_physics_frames(post_settle_frames)

	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		var agent: Node = race.call("ai_agent", slot_index)
		if ai_kart == null or agent == null:
			continue
		assert_false(
			bool(ai_kart.call("is_run_active")),
			(
				"AI kart at slot %d must stay frozen for 5+ more real "
				+ "seconds after the finish"
			) % (slot_index + 1)
		)
		assert_eq(
			int(agent.call("respawn_count")),
			baseline_respawn_counts[slot_index],
			"AI kart at slot %d must not respawn once frozen" % (slot_index + 1)
		)
		var drift_m := ai_kart.global_position.distance_to(
			baseline_positions[slot_index]
		)
		assert_lt(
			drift_m,
			0.05,
			(
				"AI kart at slot %d must not move at all once frozen and settled"
			) % (slot_index + 1)
		)


## Drives the session to race_complete by calling its own gate-crossing
## handler directly against the real authored gate nodes, instead of
## teleporting the kart through them under a real Area3D overlap. The
## sequencing/overlap-detection path this skips is already proven by
## test_crossing_every_gate_in_order_for_all_laps_completes_the_race; the
## point of these two tests is what happens to the kart's REAL, still-
## ticking physics once _finished flips true, which requires the kart's
## own _physics_process to stay enabled the whole time -- incompatible with
## the teleport technique's set_physics_process(false).
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
	# See _cross_gate's own comment: one more gate-0 crossing closes the
	# final lap.
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
	return _boot_race_with_catalog(_catalog)


## Item 3 (solo time-trial compatibility): lets a test override the tuning
## catalog (e.g. AiTuning.opponent_count) without touching the shared
## fixture _catalog every other test in this file relies on.
func _boot_race_with_catalog(catalog: GameplayTuning) -> Node:
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
	race.call("configure", catalog)
	return race
