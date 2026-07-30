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
