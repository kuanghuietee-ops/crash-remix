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
const ITEM_BOX_SCENE_PATH := "res://scenes/racing/item_box.tscn"

var _catalog: GameplayTuning
var _kart_tuning: KartTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load")


## R5 Task 1: karts now spawn frozen and stay frozen through a real 3-2-1
## countdown before the race starts -- see race_session.gd's own COUNTDOWN +
## START BOOST class doc. Every test in this file is testing something else
## entirely (gate sequencing, wrong-way timing, AI integration, item rolls,
## register_hit precedence...) and needs the race actually RUNNING to
## exercise it -- none of them are testing the countdown/start-boost
## machinery itself (that's tests/racing/test_race_start_flow.gd's job, a
## dedicated file that drives the real countdown/judge/freeze mechanics this
## task adds). Feeding the session's own private _tick_countdown() one
## oversized synthetic delta_s, with the real InputRouter's HOP action left
## unpressed (the default, untouched, idle state every one of these
## fixtures already starts from), collapses the whole countdown to its GO
## transition in a single call: the judge samples hop_held=false for that
## whole span -> verdict &"none" -> _start_race() plainly unfreezes every
## kart, exactly the "everyone driving immediately" shape every test in this
## file was already written against, before this task existed. Calling a
## private method directly by name matches this suite's own established
## precedent for reaching a private handler on purpose (see _force_finish()'s
## own doc further down, which does the same for _on_gate_body_entered()).
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


## Task 1 (CTR R6, circuit polish): configure() wires the FX loop onto BOTH
## the player's kart and every AI kart -- see configure()'s own catalog.fx
## line and _spawn_ai_karts()'s identical ai_kart.get_node("Fx").call(
## "configure", ...) call, both added by this task.
##
## White-box read for BOTH karts (not just the AI one): _route_input()'s own
## per-tick _input_adapter.apply_move(_router.buffer.movement(), _kart) call
## (see its own doc) re-applies the ROUTER's held movement to the player
## kart's steer() every single physics tick -- driving a real slide-boost
## here by calling kart.call("steer", ...) directly gets silently overwritten
## the very next tick by that same real routing this suite's other tests
## exercise on purpose, the identical "a live controller keeps fighting a
## manually-forced input" shape the AI kart's own agent creates one section
## down. kart_fx.gd's own test_kart_fx.gd already proves the state-MAPPING
## behavior (stage -> color/amount, emitting flags) exhaustively through the
## real public API in a fixture with no competing live input driver; this
## test's only job is proving configure()/_spawn_ai_karts() actually reached
## both real Fx nodes with a real kart reference and real fx_tuning, which
## object identity + a real tuning value already proves conclusively.
func test_configure_wires_fx_onto_both_the_player_and_every_ai_kart() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var fx := kart.get_node_or_null("Fx")
	assert_not_null(fx, "the player kart's Fx node must exist -- it shares kart.tscn with every AI kart")
	if fx == null:
		return
	assert_eq(
		fx.get("_kart"),
		kart,
		"configure() must configure() the player kart's own Fx node with ITSELF, not leave it null/unwired"
	)
	var fx_tuning: FxTuning = fx.get("_tuning")
	assert_not_null(fx_tuning, "configure() must configure() the player kart's Fx node with real fx_tuning")
	if fx_tuning == null:
		return
	assert_eq(
		fx_tuning.spark_amount_stage0,
		_catalog.fx.spark_amount_stage0,
		"the player kart's own Fx node must have been configured with the real catalog.fx"
	)

	var opponent_count := int(_catalog.ai.opponent_count)
	assert_gt(opponent_count, 0, "fixture sanity: at least one AI kart must spawn by default")
	if opponent_count <= 0:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "an AI kart must exist at slot 0")
	if ai_kart == null:
		return
	var ai_fx := ai_kart.get_node_or_null("Fx")
	assert_not_null(ai_fx, "an AI kart's own Fx node must exist -- it shares kart.tscn with the player")
	if ai_fx == null:
		return
	# White-box read (mirrors this same file's kart.get("_motor")/kart.get(
	# "_drift") precedent above): a live AI kart is under its own AiKartAgent's
	# continuous steering, so forcing a real slide through the public API here
	# would just get overwritten by the agent's next tick -- the reliable
	# proof that _spawn_ai_karts() actually wired THIS kart's own Fx node
	# (not left it unconfigured, which forces every emitter off regardless
	# of state, see kart_fx.gd's own class doc) is that configure() actually
	# reached it: object identity for _kart, and a real value for _tuning.
	assert_eq(
		ai_fx.get("_kart"),
		ai_kart,
		"_spawn_ai_karts() must configure() this AI kart's own Fx node with ITSELF, not left null/unwired"
	)
	var ai_fx_tuning: FxTuning = ai_fx.get("_tuning")
	assert_not_null(ai_fx_tuning, "_spawn_ai_karts() must configure() this AI kart's Fx node with real fx_tuning")
	if ai_fx_tuning == null:
		return
	assert_eq(
		ai_fx_tuning.spark_amount_stage0,
		_catalog.fx.spark_amount_stage0,
		"the AI kart's own Fx node must have been configured with the real catalog.fx"
	)


# ---------------------------------------------------------------------------
# Task 3 (CTR R6, circuit polish): configure()/_spawn_ai_karts() mount the
# ONLY two likeness-gated character sources this repo has -- Crash on the
# player, a lab assistant on every AI kart -- and give every kart (player
# included) its own KartTuning-authored body tint. Mirrors the Fx wiring
# test immediately above this section: white-box reads of the real, live-
# wired state (object identity, real material colours), not a synthetic
# double.
# ---------------------------------------------------------------------------


func test_configure_mounts_crash_on_the_player_kart_with_its_own_tint() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	var mounted: Node3D = kart.call("mounted_character")
	assert_not_null(mounted, "configure() must seat the player kart with a real character")
	if mounted != null:
		var animation_players := mounted.find_children(
			"*", "AnimationPlayer", true, false
		)
		assert_eq(
			animation_players.size(),
			1,
			"the mounted player character must be the real Crash model, which carries one AnimationPlayer"
		)

	var visual := kart.get_node("Visual")
	var mesh_instances: Array[Node] = visual.find_children(
		"*", "MeshInstance3D", true, false
	)
	assert_gt(mesh_instances.size(), 0, "fixture sanity: the kart model must carry a mesh")
	if mesh_instances.is_empty():
		return
	var material := (
		(mesh_instances[0] as MeshInstance3D).material_override as StandardMaterial3D
	)
	assert_not_null(material, "configure() must apply a body tint material to the player kart")
	if material == null:
		return
	assert_eq(
		material.albedo_color,
		_kart_tuning.kart_tint_player,
		"the player kart's own tint must come from KartTuning.kart_tint_player"
	)


func test_spawn_ai_karts_mounts_lab_assistants_with_distinct_deterministic_tints() -> void:
	var race := _boot_race()
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_gt(opponent_count, 0, "fixture sanity: at least one AI kart must spawn by default")
	if opponent_count <= 0:
		return

	var player_kart := race.get_node("Kart") as CharacterBody3D
	var player_tint: Variant = _material_albedo(player_kart)
	assert_not_null(player_tint)

	var seen_tints: Array[Color] = []
	for index in range(opponent_count):
		var ai_kart := race.call("ai_kart", index) as CharacterBody3D
		assert_not_null(ai_kart, "an AI kart must exist at slot %d" % index)
		if ai_kart == null:
			continue

		var mounted: Node3D = ai_kart.call("mounted_character")
		assert_not_null(mounted, "_spawn_ai_karts() must seat every AI kart with a real character")

		var ai_tint: Variant = _material_albedo(ai_kart)
		assert_not_null(ai_tint, "_spawn_ai_karts() must apply a body tint to every AI kart")
		if ai_tint == null:
			continue
		assert_eq(
			ai_tint,
			_kart_tuning.tint_for_slot(index + 1),
			"AI slot %d's own tint must come from KartTuning.tint_for_slot(slot_index)" % (index + 1)
		)
		assert_ne(
			ai_tint,
			player_tint,
			"an AI kart must never share the player's own fixed identity colour"
		)
		assert_false(
			seen_tints.has(ai_tint),
			"two different AI slots must never land on the same tint (5 distinct slot colours)"
		)
		seen_tints.append(ai_tint)


## Reads the real material_override colour off a kart's own Visual mesh --
## the same white-box shape test_apply_body_tint_overrides_the_visual_
## meshes_with_the_given_color already proves works in test_kart_controller.
## gd, reused here as a small test-local helper since two tests in this
## section both need it.
func _material_albedo(kart: CharacterBody3D) -> Variant:
	var visual := kart.get_node_or_null("Visual")
	if visual == null:
		return null
	var mesh_instances: Array[Node] = visual.find_children(
		"*", "MeshInstance3D", true, false
	)
	if mesh_instances.is_empty():
		return null
	var material := (
		(mesh_instances[0] as MeshInstance3D).material_override as StandardMaterial3D
	)
	return material.albedo_color if material != null else null


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
# R4 Task 2 (CTR item loop): RaceSession routes a real ITEM press through the
# real InputRouter -> InputIntentBuffer -> _route_input()'s own edge-sampling
# -- the same "push a real intent through the real router, then let the
# session's own physics tick consume it" shape proves HOP's routing works
# end-to-end elsewhere in this repo (touch_controls/gamepad tests push
# through the router directly; this proves RaceSession's OWN _route_input()
# reaches the real kart). use_item() is Task 3's landing pad (kart_
# controller.gd) -- a no-op stub that always returns &"none" -- so
# item_use_count() (mirroring AiKartAgent's own respawn_count()) is the only
# way to observe the routing fired.
# ---------------------------------------------------------------------------


func test_synthetic_item_press_edge_reaches_the_kart_stub_once_per_press() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var router := race.get_node("Input/InputRouter")
	assert_eq(
		int(kart.call("item_use_count")),
		0,
		"fixture sanity: no ITEM press has happened yet"
	)

	router.call(
		"push_button",
		InputIntent.ACTION_ITEM,
		true,
		0.0,
		InputIntent.SOURCE_TOUCH
	)
	await wait_physics_frames(2)

	assert_eq(
		int(kart.call("item_use_count")),
		1,
		"a single ITEM press edge must reach the kart's use_item() stub exactly once"
	)

	# Holding the button (no release yet) must not re-fire on later ticks --
	# same edge-sampling contract _route_input() already uses for HOP.
	await wait_physics_frames(5)
	assert_eq(
		int(kart.call("item_use_count")),
		1,
		"holding ITEM must not repeatedly re-trigger use_item()"
	)

	router.call(
		"push_button",
		InputIntent.ACTION_ITEM,
		false,
		0.0,
		InputIntent.SOURCE_TOUCH
	)
	await wait_physics_frames(2)
	router.call(
		"push_button",
		InputIntent.ACTION_ITEM,
		true,
		0.0,
		InputIntent.SOURCE_TOUCH
	)
	await wait_physics_frames(2)

	assert_eq(
		int(kart.call("item_use_count")),
		2,
		"a second press edge after a release must fire use_item() again"
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
##
## Polish wave [LOW-1]: reads the player's own standings() position instead
## of the removed placement() getter -- see _player_standings_position()'s
## own doc.
func test_standings_position_is_first_when_every_ai_kart_is_behind_the_player() -> void:
	var race := _boot_race()
	if race == null:
		return
	_force_finish(race)

	assert_eq(
		_player_standings_position(race),
		1,
		"with every AI kart behind the player at the finish, standings position must be 1st"
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
## real, possibly-flaky AI driving physics to get there.
##
## Polish wave [LOW-1]: this is the exact scenario that proved the removed
## placement() getter WRONG. placement() compared raw total_progress_m()
## alone, so a still-driving, never-finished AI kart seeded numerically ahead
## used to push the player's own reported placement to 2nd. standings()
## disagrees, correctly: RaceRanking's own tier-1 rule ranks every FINISHED
## kart ahead of every unfinished one unconditionally (see race_session.gd's
## own AI FINISH RECORDING class-doc section), regardless of the unfinished
## kart's raw progress lead. The player finishes here and the AI kart never
## does, so the player's own standings position must stay 1st -- test_race_
## standings.gd's own five-kart test proves the identical rule at full scene
## scale; this pins the same rule against this file's own simpler fixture.
func test_standings_position_stays_first_despite_an_unfinished_ai_kart_seeded_ahead() -> void:
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
		_player_standings_position(race),
		1,
		"an unfinished AI kart's raw progress lead must NOT outrank the player's own real finish"
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

	assert_eq(
		_player_standings_position(race),
		1,
		"a solo race's own standings() must place the lone player 1st"
	)
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
	_skip_pre_race_countdown(race)

	assert_eq(
		int(race.call("ai_kart_count")),
		0,
		"spawn_opponents=false must spawn zero AI karts regardless of opponent_count"
	)

	_force_finish(race)

	assert_eq(
		_player_standings_position(race),
		1,
		"a spawn_opponents=false race's own standings() must place the lone player 1st"
	)
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
	_skip_pre_race_countdown(race)
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


# ---------------------------------------------------------------------------
# R4 Task 3 (CTR item loop): RaceSession discovers ItemBox instances under
# Track (the "gate pattern" -- see the class doc's own ITEM BOX WIRING
# section) and routes a pickup to the entering kart's own ItemSlot via a
# seeded RandomNumberGenerator. R4 Task 5 authors 6 real ItemBox instances
# into EACH real track (see track_graybox_loop.tscn/track_sanity_shores.
# tscn's own ItemBoxes container and the racing-track lint's own
# track_item_boxes rule) -- these tests still add a SYNTHETIC one under
# Track before configure() runs on top of those, exactly like the class
# doc's own "exercised only by tests that add a synthetic ItemBox" note
# describes, so item_box_count() below reads REAL_TRACK_BOX_COUNT (+1 for
# the synthetic one where a test adds one), not a bare literal.
# ---------------------------------------------------------------------------

# Task 5: track_graybox_loop.tscn's own two on-road lines of three (see its
# ItemBoxes container) -- race_time_trial.tscn's Track child, which every
# _boot_race()/_boot_race_with_synthetic_box() call in this file instances.
const REAL_TRACK_BOX_COUNT := 6


func test_the_real_graybox_loop_authors_six_item_boxes() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_eq(
		int(race.call("item_box_count")),
		REAL_TRACK_BOX_COUNT,
		"R4 Task 5 authors REAL_TRACK_BOX_COUNT boxes into the graybox loop -- see its own ItemBoxes container"
	)


func test_a_synthetic_item_box_under_track_is_discovered_and_configured() -> void:
	var setup := _boot_race_with_synthetic_box()
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	assert_eq(
		int(race.call("item_box_count")),
		REAL_TRACK_BOX_COUNT + 1,
		"discovery must find every REAL authored box PLUS this test's own synthetic one"
	)


## Task 1 fix round 1 (CTR R6, circuit polish reviewer [MEDIUM]): the ORIGINAL
## wire at this call site (race_session.gd's own item-box discovery loop
## inside configure()) called box.call("configure", _item_tuning) with NO
## fx_tuning argument at all -- fx_tuning is ItemBox.configure()'s own
## OPTIONAL trailing param (defaults to null), so every real box discovered
## through the real session silently stayed unconfigured for fx and never
## spun/bobbed, even though test_item_box.gd's own spin/bob tests all passed
## (they inject fx_tuning directly, bypassing this call site entirely). This
## is the session-level test that would have caught it: boot a real race
## with a synthetic box (discovered the same way every real authored box is),
## and prove the box's own VISUAL Mesh child actually advances over real
## physics ticks -- not a white-box field read, an observable behavior
## change, the same shape kart_fx.gd's own emitting-flag tests use.
func test_configure_wires_fx_onto_every_discovered_box_so_its_mesh_spins_and_bobs() -> void:
	var setup := _boot_race_with_synthetic_box()
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	var mesh := box.get_node("Mesh") as MeshInstance3D
	var base_rotation_y := mesh.rotation.y
	var base_position_y := mesh.position.y

	await wait_physics_frames(30)

	assert_ne(
		mesh.rotation.y,
		base_rotation_y,
		(
			"configure() must wire fx_tuning onto every discovered box -- an "
			+ "unconfigured box (fx_tuning == null) never spins, which is "
			+ "exactly the dead-wire this test guards against"
		)
	)
	assert_ne(
		mesh.position.y,
		base_position_y,
		"configure() must wire fx_tuning onto every discovered box so it bobs too"
	)


## Live tuning refresh (Task 1 fix round 1, mirrors the player kart's own Fx
## refresh_tuning() proof in test_race_session.gd's kart-refresh tests):
## refresh_tuning() must reach every discovered box too, not just the player
## kart's own Fx node -- ItemBox has no separate refresh_tuning() of its own,
## so race_session.gd's own fix reuses configure() (idempotent, see item_
## box.gd's own doc). Proven by a value actually changing: a shrunk item_box_
## spin_degrees_per_s must visibly slow the real box's own rotation rate.
func test_refresh_tuning_reaches_every_discovered_box_and_changes_its_spin_rate() -> void:
	var setup := _boot_race_with_synthetic_box()
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	var mesh := box.get_node("Mesh") as MeshInstance3D
	var initial_rotation_y := mesh.rotation.y

	await wait_physics_frames(5)
	var rotation_before_refresh := mesh.rotation.y
	assert_ne(
		rotation_before_refresh,
		initial_rotation_y,
		"fixture sanity: the box must have been spinning at all before the refresh landed"
	)

	# duplicate(true) deep-duplicates every stored Resource property,
	# including the fx sub-resource -- mirrors tuning_service.gd's own
	# _clone_catalog() precedent for why a deep duplicate is required here:
	# mutating .fx in place on the SHARED _catalog fixture every other test
	# in this file also reads would leak this test's own edit into them.
	var slowed_catalog: GameplayTuning = _catalog.duplicate(true)
	slowed_catalog.fx.item_box_spin_degrees_per_s = 0.0001
	race.call("refresh_tuning", slowed_catalog)

	var rotation_at_refresh := mesh.rotation.y
	await wait_physics_frames(30)

	assert_almost_eq(
		mesh.rotation.y,
		rotation_at_refresh,
		0.001,
		(
			"refresh_tuning() must reach the real ItemBox and apply the new, "
			+ "near-zero spin rate immediately -- a stale pre-refresh rate "
			+ "would keep visibly turning the mesh here"
		)
	)


func test_player_kart_entering_a_synthetic_box_rolls_and_lands_its_item_slot() -> void:
	var setup := _boot_race_with_synthetic_box()
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot, "the player's real KartController must expose a real item slot")
	if slot == null:
		return
	assert_eq(slot.call("state"), &"empty", "fixture sanity: no roll yet")

	# Brief teleport-detection window with the kart's own physics disabled
	# (the same technique _cross_gate() below uses for gates) so the real
	# Area3D overlap fires cleanly.
	kart.set_physics_process(false)
	kart.global_position = box.global_position
	await wait_physics_frames(2)

	assert_eq(
		slot.call("state"),
		&"rolling",
		"entering an active box must start the player's own real roll"
	)

	# Re-enable the kart's own physics so its _physics_process (and
	# therefore ItemSlot.tick(), see kart_controller.gd) resumes advancing
	# the real roll toward held.
	kart.set_physics_process(true)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)

	assert_eq(slot.call("state"), &"held")
	assert_ne(
		slot.call("held_item"),
		&"none",
		"a held slot must report a real item, not none"
	)


## Binding-contract-2-style identity routing (the same "route by WHICH BODY
## entered, never a hardcoded player assumption" shape gate crossings
## already use): an AI kart's own pickup must roll ITS OWN slot, never the
## player's, and vice versa.
func test_ai_kart_entering_a_synthetic_box_rolls_its_own_item_slot_not_the_players() -> void:
	# A position well clear of the player's own KartSpawn (see _boot_race_
	# with_synthetic_box()'s own doc for why this test specifically cannot
	# reuse the default KartSpawn-anchored box every other test here does):
	# the player's kart keeps ticking normally throughout this test, so a
	# box anywhere near its actual spawn would be picked up by the player
	# too, for real -- defeating the isolation this test exists to prove.
	var setup := _boot_race_with_synthetic_box(0, Vector3(200.0, 0.0, 200.0))
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var ai_slot: Object = ai_kart.call("item_slot")
	var player_slot: Object = (race.get_node("Kart") as CharacterBody3D).call("item_slot")
	assert_not_null(ai_slot)
	assert_not_null(player_slot)
	if ai_slot == null or player_slot == null:
		return

	# The AI kart's own AiKartAgent keeps ticking (a separate Node,
	# unaffected by this call) but only ever writes steer/brake/speed_scale
	# onto a KartController whose own _physics_process never runs to consume
	# them, so the teleported position holds for the few frames this test
	# needs -- the exact same technique test_ai_kart_gate_crossing_routes_
	# to_its_own_validator_not_the_players above already establishes.
	ai_kart.set_physics_process(false)
	ai_kart.global_position = box.global_position
	await wait_physics_frames(2)

	assert_eq(
		ai_slot.call("state"),
		&"rolling",
		"an AI kart entering an active box must start ITS OWN real roll"
	)
	assert_eq(
		player_slot.call("state"),
		&"empty",
		"the player's own slot must be completely untouched by an AI kart's pickup"
	)


## End-to-end proof through the REAL production wiring, driven entirely
## through Task 5's own AI decision path -- not a synthetic dispatch_item_
## use() call, and not a forced start_roll(): the item itself comes from a
## REAL box overlap and a REAL seeded roll. A seeded AI kart enters a real
## ItemBox, rolls to &"held" over the real roulette window, and its own
## AiKartAgent decides to use it through the SAME session dispatch the
## player uses (use_item_for() -> dispatch_item_use()).
##
## item_rng_seed=1 is pinned (empirically, via a throwaway
## RandomNumberGenerator probe against this exact Godot version) to roll
## &"shield" on the very first randf() call -- the one heuristic that fires
## unconditionally the instant it is held (see ai_driver.gd's own ITEM USE
## HEURISTICS doc: shield is used immediately, no cornering/leading/target
## state has to line up), so this test's timing does not also depend on
## wherever the AI kart happens to be pointed.
##
## ai_kart.set_physics_process(false) suppresses the KART's OWN _physics_
## process -- which owns BOTH the CharacterBody3D movement code AND the
## item roulette timer (kart_controller.gd: "_item_slot.tick(delta_s)" is
## called from inside it, gated on _run_active alongside the drift/motor
## tick beside it) -- so it is only held off for the brief teleport-then-
## confirm window below, then turned back on before the roll is given any
## time to land (same sequence test_item_rng_seed_nonzero_reproduces_the_
## same_first_roll_across_two_sessions above already establishes).
## AiKartAgent is a SEPARATE Node (a child of the kart) with its own
## independent _physics_process, driven by RaceSession's own is_run_
## active() flag, not Godot's per-node processing flag, so it keeps
## deciding throughout this whole test regardless of the kart's own flag --
## it just has nothing to act on (held_item stays &"none") until the
## roulette timer, now running again, actually lands the roll.
func test_seeded_ai_kart_picks_up_a_box_rolls_and_uses_a_shield_through_real_dispatch() -> void:
	var setup := _boot_race_with_synthetic_box(1, Vector3(200.0, 0.0, 200.0))
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var ai_slot: Object = ai_kart.call("item_slot")
	assert_not_null(ai_slot)
	if ai_slot == null:
		return
	assert_false(bool(ai_kart.call("is_shielded")), "fixture sanity: not shielded before any of this runs")

	# Real pickup: teleport onto the box (movement disabled so the physical
	# position holds through the overlap -- see this function's own doc for
	# why the AI's own decision loop keeps running regardless).
	ai_kart.set_physics_process(false)
	ai_kart.global_position = box.global_position
	await wait_physics_frames(2)
	assert_eq(ai_slot.call("state"), &"rolling", "fixture setup: the pickup must have started a real roll")

	# The roulette timer only advances inside KartController's OWN _physics_
	# process (kart_controller.gd: "_item_slot.tick(delta_s)", gated on
	# _run_active the same as the drift/motor tick beside it) -- re-enable it
	# now that the pickup itself has registered, the same "teleport with
	# physics off, then turn it back on before waiting on the roll" sequence
	# test_item_rng_seed_nonzero_reproduces_the_same_first_roll_across_two_
	# sessions above already establishes. This also resumes the kart's own
	# real movement, which does not matter here -- only the item STATE
	# transitions are under test.
	ai_kart.set_physics_process(true)

	# Real roulette + real decision: this window is generous enough
	# (roulette_duration_s plus a real buffer, not just a handful of raw
	# frames) for BOTH the roll to land AND the agent's own next tick to
	# consume it -- item_cooldown_ready starts already-true at configure()
	# time (see ai_kart_agent.gd's own ITEM WIRING doc), so nothing else has
	# to settle first.
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 10
	await wait_physics_frames(frames_needed)

	assert_true(
		bool(ai_kart.call("is_shielded")),
		(
			"the AI's own real roll must have landed &\"shield\" (item_rng_seed=1's "
			+ "own first randf() call, per this function's own doc) and its own "
			+ "decide() -> use_item edge must have reached the REAL use_item_for() "
			+ "-> dispatch_item_use() session path -- the SAME shared entry point "
			+ "the player's own ITEM press uses"
		)
	)
	assert_eq(
		ai_slot.call("state"),
		&"empty",
		"a real use() must clear the slot back to empty, same as any other use"
	)


## See the class doc's SOLO TIME TRIAL DOES NOT ROLL section: spawn_
## opponents = false must suppress item rolls entirely, even off a real box
## pickup.
func test_solo_session_never_rolls_even_after_a_real_synthetic_box_pickup() -> void:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("spawn_opponents", false)
	var track := race.get_node("Track") as Node3D
	var spawn := track.get_node("KartSpawn") as Marker3D
	var box_packed := load(ITEM_BOX_SCENE_PATH) as PackedScene
	assert_not_null(box_packed)
	if box_packed == null:
		return
	var box := box_packed.instantiate() as Area3D
	# LOCAL position (spawn.position, relative to their shared parent
	# `track`), set BEFORE track.add_child(box) -- see _boot_race_with_
	# synthetic_box()'s identical fix below for why: a body/area added to
	# the tree at its (0,0,0) default and repositioned only AFTER can still
	# register a transient, permanently-sticky overlap against anything
	# already sitting at that origin, discovered empirically while chasing
	# a flaky false pickup in test_item_box.gd.
	box.position = spawn.position
	track.add_child(box)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)

	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return

	kart.set_physics_process(false)
	kart.global_position = box.global_position
	await wait_physics_frames(2)
	kart.set_physics_process(true)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)

	assert_eq(
		slot.call("state"),
		&"empty",
		(
			"a solo (spawn_opponents=false) session must never start an item "
			+ "roll, even after a real box pickup"
		)
	)


func test_refresh_tuning_reaches_the_player_kart_item_slot() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), &"rolling", "fixture setup: the roll must have started")

	var tuning_variant: GameplayTuning = _catalog.duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	)
	# Far smaller than even a single real physics tick's own delta_s, unlike
	# the stale (1.2s) duration the fixture's own roll started under -- see
	# test_kart_controller.gd's identical test for the item slot in
	# isolation for the same reasoning.
	tuning_variant.items.roulette_duration_s = 0.001

	race.call("refresh_tuning", tuning_variant)
	await wait_physics_frames(2)

	assert_eq(
		slot.call("state"),
		&"held",
		"refresh_tuning() must reach the real player kart's own item slot"
	)


## See the class doc's ITEM RNG section: a non-zero item_rng_seed must
## reproduce the EXACT same first roll across two entirely independent
## sessions -- the only way this can hold is if the exported seed genuinely
## reaches a real RandomNumberGenerator.seed and both sessions' first
## randf() call after configure() lines up deterministically.
##
## CTR R6 Task 5: opponent_count pinned to 0.0 (spawn_opponents stays at its
## own default true, so items are still enabled -- see _items_allowed()'s
## own doc, and the established test_solo_race_with_zero_opponents_spawns_
## no_ai_and_places_first_alone precedent one section up for this exact
## "opponent_count=0, items still on" shape) -- this pins field_size() to
## exactly 1 in BOTH sessions, which _position_ratio_for() reads as the
## sentinel "no live position known" case (see its own doc), keeping the
## roll a pure function of rng_value alone, the ONLY thing this test's own
## name claims to prove. Two SEPARATE scene instances racing side-by-side in
## the SAME shared World3D (both add_child_autofree()'d into this one test)
## were never a rigorous guarantee of identical live RANKING between them --
## before the weighted roulette existed that never mattered (the old roll
## never read position at all); leaving field_size() at its real multi-kart
## value here would make this specifically-scoped RNG-reproducibility test
## flaky on whichever of the two sessions' ranks happened to diverge, a
## DIFFERENT and already-separately-covered concern (see this file's own
## test_on_box_body_entered_threads_the_live_position_ratio_into_the_
## weighted_roll).
func test_item_rng_seed_nonzero_reproduces_the_same_first_roll_across_two_sessions() -> void:
	var solo_field_catalog: GameplayTuning = _catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	solo_field_catalog.ai.opponent_count = 0.0
	var seed_value := 918273
	var first := _boot_race_with_synthetic_box(seed_value, null, solo_field_catalog)
	var second := _boot_race_with_synthetic_box(seed_value, null, solo_field_catalog)
	var race_a: Node = first.get("race")
	var box_a: Area3D = first.get("box")
	var race_b: Node = second.get("race")
	var box_b: Area3D = second.get("box")
	if race_a == null or box_a == null or race_b == null or box_b == null:
		return

	var kart_a := race_a.get_node("Kart") as CharacterBody3D
	var kart_b := race_b.get_node("Kart") as CharacterBody3D
	var slot_a: Object = kart_a.call("item_slot")
	var slot_b: Object = kart_b.call("item_slot")
	assert_not_null(slot_a)
	assert_not_null(slot_b)
	if slot_a == null or slot_b == null:
		return

	kart_a.set_physics_process(false)
	kart_a.global_position = box_a.global_position
	kart_b.set_physics_process(false)
	kart_b.global_position = box_b.global_position
	await wait_physics_frames(2)

	assert_eq(slot_a.call("state"), &"rolling", "fixture setup: session A's pickup must have registered")
	assert_eq(slot_b.call("state"), &"rolling", "fixture setup: session B's pickup must have registered")

	kart_a.set_physics_process(true)
	kart_b.set_physics_process(true)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)

	assert_eq(slot_a.call("state"), &"held")
	assert_eq(slot_b.call("state"), &"held")
	assert_eq(
		slot_a.call("held_item"),
		slot_b.call("held_item"),
		"the same item_rng_seed must reproduce the exact same FIRST roll across two independent sessions"
	)


# ---------------------------------------------------------------------------
# R4 Task 4 (CTR item loop): register_hit() -- the shared hit-routing
# priority order (shield block > invulnerability > real spin_out).
# ---------------------------------------------------------------------------


func test_register_hit_applies_spin_out_by_default() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_false(bool(kart.call("is_spinning_out")), "fixture sanity")

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"spin_out")
	assert_true(bool(kart.call("is_spinning_out")))
	assert_true(bool(kart.call("is_invulnerable")), "apply_spin_out() must also start the invulnerable window")


func test_register_hit_on_a_shielded_kart_blocks_and_consumes_the_shield_early() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.call("set_shielded", _catalog.items.shield_duration_s)
	assert_true(bool(kart.call("is_shielded")), "fixture sanity")

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"blocked")
	assert_false(bool(kart.call("is_spinning_out")), "a blocked hit must not also spin the kart out")
	assert_false(bool(kart.call("is_shielded")), "a block must consume the shield early, not run out its own remaining duration")


## See the class doc's ITEM RNG... no -- see register_hit()'s own doc: the
## brief's own exact phrasing, "shield blocks exactly one hit then gone".
func test_register_hit_shield_blocks_exactly_one_hit_then_the_next_is_a_real_spin_out() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.call("set_shielded", _catalog.items.shield_duration_s)

	var first: StringName = race.call("register_hit", kart)
	var second: StringName = race.call("register_hit", kart)

	assert_eq(first, &"blocked")
	assert_eq(second, &"spin_out")


func test_register_hit_on_an_invulnerable_kart_returns_invulnerable_and_does_not_restack_the_stun() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	motor.set("_forward_speed_mps", _catalog.kart.top_speed_mps)

	race.call("register_hit", kart)
	assert_true(bool(kart.call("is_invulnerable")), "fixture setup: the first hit must start the invulnerable window")
	var speed_after_first_hit: float = float(motor.call("forward_speed_mps"))

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"invulnerable")
	# apply_spin_out() dumps forward speed by spin_out_speed_keep_ratio EVERY
	# time it is called -- if the second hit had wrongly re-applied it, the
	# speed would have been multiplied down again. It must not have moved.
	assert_almost_eq(
		float(motor.call("forward_speed_mps")),
		speed_after_first_hit,
		0.0001,
		"a second hit landing during the invulnerable window must not re-apply spin_out"
	)


## Fix round 1 [MEDIUM]: precedence must be invulnerable > blocked >
## spin_out -- checking shield BEFORE invulnerability let a kart that
## activates a held shield during its own post-hit invuln window lose that
## shield to a hit invulnerability alone would already have absorbed for
## free. A kart invulnerable AND shielded at once must read &"invulnerable"
## and keep the shield untouched; only once the invuln window has expired
## does that same still-active shield block the next hit.
func test_register_hit_precedence_invulnerable_beats_an_active_shield() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_gt(
		_catalog.items.shield_duration_s,
		_catalog.kart.invulnerable_after_hit_s,
		"fixture assumption: the shield must outlast the invulnerable window for this test's second half to mean anything"
	)

	# First hit: a real spin_out, starting the invulnerable window.
	race.call("register_hit", kart)
	assert_true(bool(kart.call("is_invulnerable")), "fixture setup: the first hit must start the invulnerable window")

	# The kart picks up and uses a shield WHILE still invulnerable.
	kart.call("set_shielded", _catalog.items.shield_duration_s)
	assert_true(bool(kart.call("is_shielded")), "fixture setup: the kart must now also be shielded")

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"invulnerable", "invulnerability must take precedence over an active shield")
	assert_true(
		bool(kart.call("is_shielded")),
		"a hit absorbed by invulnerability must leave an unrelated shield completely untouched"
	)

	# Wait out ONLY the (shorter) invulnerable window -- the shield's own
	# (longer) duration must still have time left.
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	motor.call(
		"tick",
		_catalog.kart.invulnerable_after_hit_s + 0.01,
		0.0,
		false,
		false,
		false,
		0
	)
	assert_false(bool(kart.call("is_invulnerable")), "fixture setup: the invulnerable window must have expired")
	assert_true(bool(kart.call("is_shielded")), "fixture setup: the shield must still be active on its own longer timer")

	var outcome_after_invuln_expires: StringName = race.call("register_hit", kart)

	assert_eq(
		outcome_after_invuln_expires,
		&"blocked",
		"once invulnerability has expired, the still-active shield must block the next hit"
	)
	assert_false(bool(kart.call("is_shielded")), "that block must consume the shield")


## Fix round 1 [LOW-a]: proves the Task-1 drift-cancel survives THROUGH
## this routing layer -- register_hit() calling apply_spin_out() (not a
## test calling apply_spin_out() directly, which test_kart_controller.gd's
## own test_apply_spin_out_mid_slide_ends_the_slide_and_zeroes_accrued_
## boost already covers in isolation) must still end a real, live slide and
## forfeit its accrued boost stage, through the REAL dispatch path a
## missile/beaker hit actually uses in production.
func test_register_hit_mid_slide_ends_the_slide_and_zeroes_accrued_boost_through_real_dispatch() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# See test_finishing_mid_slide_ends_the_slide_with_no_further_rotation's
	# own doc for why the SESSION's own input-routing tick is disabled here
	# (it would fight this test's manual steer()/hop_pressed() calls) while
	# the KART's own _physics_process stays fully enabled the whole time.
	race.set_physics_process(false)

	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup: the kart must be grounded before sliding")

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(1)
	assert_true(bool(kart.call("is_sliding")), "fixture setup: the kart must land inside a slide")

	await wait_physics_frames(
		int(ceil(_kart_tuning.boost_window_open_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_eq(
		String(kart.call("boost_tap")),
		"fired",
		"fixture setup: the tap must land inside the window and actually accrue boost"
	)

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"spin_out")
	assert_false(
		bool(kart.call("is_sliding")),
		(
			"register_hit()'s real spin_out must end a live slide through "
			+ "the whole routing layer, not only when apply_spin_out() is "
			+ "called directly"
		)
	)

	var drift: RefCounted = kart.get("_drift")
	assert_not_null(drift, "the controller must still own its private drift FSM")
	if drift == null:
		return
	assert_eq(
		int(drift.call("boost_stage")),
		0,
		"the hit must forfeit the accrued boost stage through the real dispatch path"
	)
	assert_eq(
		float(drift.call("consume_boost")),
		0.0,
		"any boost accrued before the hit must have been zeroed through the real dispatch path, not merely left orphaned for the next poll"
	)


## ORDER-AWARENESS pin (see register_hit()'s own doc): a boost already
## forwarded to the motor THIS SAME TICK (KartController's own unconditional
## consume_boost() -> add_boost() forward, see kart_controller.gd's BINDING
## CONTRACT doc) must survive a hit landing the same tick -- an INTENTIONAL,
## strict-CTR ruling, not a bug apply_spin_out() should "fix" by also
## zeroing boost.
func test_register_hit_does_not_cancel_a_same_frame_boost_already_forwarded_to_the_motor() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor, "the controller must still own its private motor")
	if motor == null:
		return
	motor.call("add_boost", _catalog.kart.boost_duration_s)
	assert_true(bool(motor.call("is_boosting")), "fixture sanity: the boost must really be active before the hit")

	var outcome: StringName = race.call("register_hit", kart)

	assert_eq(outcome, &"spin_out")
	assert_true(
		bool(motor.call("is_boosting")),
		(
			"a boost already forwarded to the motor this same tick must "
			+ "survive a hit landing the same tick -- INTENTIONAL, strict-CTR "
			+ "ruling (see register_hit()'s own doc)"
		)
	)


# ---------------------------------------------------------------------------
# R4 Task 4: item-use dispatch -- turbo/shield apply directly, missile/
# beaker spawn a real, configured scene instance under the session.
# ---------------------------------------------------------------------------


func test_dispatch_item_use_turbo_applies_boost_immediately_to_the_kart() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_false(bool(motor.call("is_boosting")), "fixture sanity")

	race.call("dispatch_item_use", kart, &"turbo")

	assert_true(bool(motor.call("is_boosting")), "a turbo use must apply boost immediately, not on some later tick")
	assert_almost_eq(float(motor.call("boost_time_remaining_s")), _catalog.items.turbo_boost_s, 0.01)


func test_dispatch_item_use_shield_sets_the_kart_shielded() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_false(bool(kart.call("is_shielded")), "fixture sanity")

	race.call("dispatch_item_use", kart, &"shield")

	assert_true(bool(kart.call("is_shielded")))


func test_dispatch_item_use_none_spawns_and_applies_nothing() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	race.call("dispatch_item_use", kart, &"none")

	assert_null(
		race.get_node_or_null("ItemHazards"),
		"an unheld/none item use must never even create the hazards container"
	)


func test_dispatch_item_use_missile_spawns_a_configured_missile_under_the_session() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	race.call("dispatch_item_use", kart, &"missile")
	await wait_physics_frames(1)

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(hazards, "a spawned missile must be parented under the session's own hazards container")
	if hazards == null:
		return
	assert_eq(hazards.get_child_count(), 1)


func test_dispatch_item_use_beaker_drops_behind_the_launcher_by_one_kart_length() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# A known, axis-aligned facing so the expected drop point is easy to
	# compute independently of wherever the graybox loop's own KartSpawn
	# happens to be authored.
	kart.global_transform = Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 10.0))
	var collision := kart.get_node("CollisionShape3D") as CollisionShape3D
	assert_not_null(collision)
	if collision == null:
		return
	var box := collision.shape as BoxShape3D
	assert_not_null(box)
	if box == null:
		return
	var kart_length_m := box.size.z
	var launcher_forward := -kart.global_transform.basis.z

	race.call("dispatch_item_use", kart, &"beaker")

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(hazards)
	if hazards == null:
		return
	assert_eq(hazards.get_child_count(), 1)
	var beaker := hazards.get_child(0) as Node3D
	var expected := kart.global_position - launcher_forward * kart_length_m
	assert_almost_eq(beaker.global_position.x, expected.x, 0.01)
	assert_almost_eq(beaker.global_position.z, expected.z, 0.01)


# ---------------------------------------------------------------------------
# CTR R6 Task 5: dispatch for the three new items -- bomb/tnt_stick spawn a
# real scene instance the same way missile/beaker do above; triple_turbo
# applies boost immediately the same way turbo does.
# ---------------------------------------------------------------------------


func test_dispatch_item_use_triple_turbo_applies_boost_immediately_to_the_kart() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_false(bool(motor.call("is_boosting")), "fixture sanity")

	race.call("dispatch_item_use", kart, &"triple_turbo")

	assert_true(bool(motor.call("is_boosting")), "a triple_turbo use must apply boost immediately, same as turbo")
	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		_catalog.items.turbo_boost_s,
		0.01,
		"one triple_turbo charge applies exactly one turbo_boost_s -- no separate tuning field"
	)


func test_dispatch_item_use_bomb_spawns_a_configured_bomb_under_the_session() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	race.call("dispatch_item_use", kart, &"bomb")
	await wait_physics_frames(1)

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(hazards, "a spawned bomb must be parented under the session's own hazards container")
	if hazards == null:
		return
	assert_eq(hazards.get_child_count(), 1)


func test_dispatch_item_use_tnt_stick_drops_behind_the_launcher_by_one_kart_length() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	kart.global_transform = Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 10.0))
	var collision := kart.get_node("CollisionShape3D") as CollisionShape3D
	assert_not_null(collision)
	if collision == null:
		return
	var box := collision.shape as BoxShape3D
	assert_not_null(box)
	if box == null:
		return
	var kart_length_m := box.size.z
	var launcher_forward := -kart.global_transform.basis.z

	race.call("dispatch_item_use", kart, &"tnt_stick")

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(hazards)
	if hazards == null:
		return
	assert_eq(hazards.get_child_count(), 1)
	var stick := hazards.get_child(0) as Node3D
	var expected := kart.global_position - launcher_forward * kart_length_m
	assert_almost_eq(stick.global_position.x, expected.x, 0.01)
	assert_almost_eq(stick.global_position.z, expected.z, 0.01)


# ---------------------------------------------------------------------------
# CTR R6 Task 5: weighted roulette -- _position_ratio_for() and its wiring
# into _on_box_body_entered().
# ---------------------------------------------------------------------------


func test_position_ratio_for_matches_the_documented_formula_against_live_ranking() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# One real tick so _refresh_rank_snapshot() has populated a live order --
	# see race_session.gd's own LIVE RANKING doc.
	await wait_physics_frames(2)

	var field := int(race.call("field_size"))
	assert_gt(field, 1, "fixture sanity: the default race must spawn a real multi-kart field")
	var position := int(race.call("player_position"))
	var expected_ratio := float(position - 1) / float(field - 1)

	assert_almost_eq(
		float(race.call("_position_ratio_for", kart)),
		expected_ratio,
		0.0001
	)


func test_position_ratio_for_returns_the_uniform_sentinel_for_a_field_of_one() -> void:
	var solo_catalog: GameplayTuning = _catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	solo_catalog.ai.opponent_count = 0.0
	var race := _boot_race_with_catalog(solo_catalog)
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	await wait_physics_frames(2)

	assert_eq(int(race.call("field_size")), 1, "fixture sanity: a solo field is exactly one kart")
	assert_lt(
		float(race.call("_position_ratio_for", kart)),
		0.0,
		"field_size() <= 1 must never divide by zero -- returns ItemSlot's own uniform sentinel instead"
	)


## Proves _on_box_body_entered() actually THREADS a real, LIVE position
## ratio into the weighted roll (not just that the pure formula above is
## correct in isolation). Directly overwrites the session's own _current_
## rank_order cache -- the SAME private-state-reach convention this suite
## already uses elsewhere (e.g. kart.get("_motor")) -- rather than trying to
## force a real position change through the clamped SpineFollower.update()
## real driving would go through (see _update_player_follower()'s own
## max_step_m clamp doc: a raw teleport is NOT reflected in total_progress_m()
## within a couple of ticks, so this is the only fast, deterministic way to
## pin kart_position()/field_size() for a test). A catalog where every
## item's own weight is zeroed except weight_front_shield and weight_back_
## bomb makes the outcome deterministic regardless of the actual rng draw
## (see item_slot.gd's own test suite for the identical "isolate one item's
## weight" technique) -- so a real box pickup while the cache reports the
## player LEADING must land on shield, and the SAME kart's SAME slot,
## picking up again while the cache reports the player TRAILING, must land
## on bomb.
func test_on_box_body_entered_threads_the_live_position_ratio_into_the_weighted_roll() -> void:
	var catalog: GameplayTuning = _catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for item_name: StringName in ItemSlot.ITEM_NAMES:
		catalog.items.set("weight_front_" + String(item_name), 0.0)
		catalog.items.set("weight_back_" + String(item_name), 0.0)
	catalog.items.weight_front_shield = 1.0
	catalog.items.weight_back_bomb = 1.0

	var race := _boot_race_with_catalog(catalog)
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	var ai_kart_count := int(race.call("ai_kart_count"))
	assert_gt(ai_kart_count, 0, "fixture sanity: the default race must spawn real AI karts to rank against")
	var ai_karts: Array = []
	for index in range(ai_kart_count):
		ai_karts.append(race.call("ai_kart", index))

	# LEADING: player first in the cached rank order.
	race.set("_current_rank_order", [kart] + ai_karts)
	assert_eq(int(race.call("player_position")), 1, "fixture sanity: the forced cache must read the player as leading")

	race.call("_on_box_body_entered", kart)
	await wait_physics_frames(
		int(ceil(catalog.items.roulette_duration_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_eq(slot.call("held_item"), &"shield", "leading (ratio 0.0) must land on the front-only-weighted item")
	slot.call("use")

	# TRAILING: player last in the cached rank order.
	race.set("_current_rank_order", ai_karts + [kart])
	assert_eq(
		int(race.call("player_position")),
		int(race.call("field_size")),
		"fixture sanity: the forced cache must read the player as trailing"
	)

	race.call("_on_box_body_entered", kart)
	await wait_physics_frames(
		int(ceil(catalog.items.roulette_duration_s * float(Engine.physics_ticks_per_second))) + 2
	)
	assert_eq(slot.call("held_item"), &"bomb", "trailing (ratio 1.0) must land on the back-only-weighted item")


## End-to-end proof through the REAL production wiring (not a synthetic
## dispatch_item_use() call): a real ITEM press on a kart holding a real
## rolled &"turbo" reaches KartController.use_item() via RacingInputAdapter,
## and the returned name reaches dispatch_item_use() via _route_input() --
## see race_session.gd's own doc on why this replaces the Task-3 return-
## name-only path.
func test_a_real_item_press_on_a_held_turbo_reaches_dispatch_and_applies_boost() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	# rng_value=0.3 maps to turbo -- see item_slot.gd's own N-WAY UNIFORM
	# MAPPING doc / test_item_slot.gd's identical boundary test.
	slot.call("start_roll", 0.3)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_eq(slot.call("state"), &"held", "fixture setup: the roll must have landed")
	assert_eq(slot.call("held_item"), &"turbo", "fixture setup: rng_value=0.3 must roll turbo")

	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_false(bool(motor.call("is_boosting")), "fixture sanity: no boost yet")

	var router := race.get_node("Input/InputRouter")
	router.call("push_button", InputIntent.ACTION_ITEM, true, 0.0, InputIntent.SOURCE_TOUCH)
	await wait_physics_frames(2)

	assert_true(
		bool(motor.call("is_boosting")),
		"a real ITEM press on a held turbo must reach dispatch_item_use() and apply boost"
	)


# ---------------------------------------------------------------------------
# R4 Task 4 (CARRIED MEDIUM fix, item 6): _spawn_ai_karts() must build each
# kart's transform BEFORE add_child() -- a freshly-instantiated kart
# entering the tree still at its Transform3D.IDENTITY default registers a
# real, one-instant physics-server snapshot at that position, which an
# origin-adjacent Area3D could catch as a permanently-sticky false trigger.
# ---------------------------------------------------------------------------


## NOT a plain "configure() then check the box" test: the PLAYER's own Kart
## node is a SCENE-FILE child of race_time_trial.tscn with no authored
## transform of its own, so it ALSO sits at Transform3D.IDENTITY (this
## fixture's own world origin) from the instant add_child_autofree(race)
## runs, until configure()'s own _seed_kart_transform() moves it -- a
## SEPARATE, pre-existing flash risk this task was not asked to fix (only
## _spawn_ai_karts() was). This test isolates the AI-kart mechanism
## SPECIFICALLY by: (1) letting a normal boot settle for several real
## physics ticks BEFORE the synthetic box even exists, so any broadphase
## residue from the PLAYER's own historical origin visit (or anything else
## about a fresh boot) has fully cleared and cannot be mistaken for what
## this test actually probes; (2) only THEN adding the box at _ai_root's
## own resting point and confirming it starts genuinely clean; (3) only
## THEN re-running JUST _spawn_ai_karts() (the same idempotent rebuild the
## real retry path already exercises -- see that function's own RETRY /
## RE-CONFIGURE SAFETY doc), so a failure past this point can only come
## from THIS SPECIFIC call's own kart-spawning mechanism, never a stale
## signal from the unrelated player-kart flash. (Confirmed empirically
## while writing this test: skipping the settle step and adding the box
## immediately after _boot_race() makes the box read inactive before
## _spawn_ai_karts() is ever called a second time at all -- purely the
## player's own pre-existing, out-of-scope origin flash, not this fix.)
func test_spawning_ai_karts_does_not_flash_a_kart_through_the_track_origin() -> void:
	var race := _boot_race()
	if race == null:
		return
	# Let the boot's own one-time transients (including the player kart's
	# own pre-existing, separate origin-flash -- see this function's own
	# doc) fully settle before the box under test ever exists.
	await wait_physics_frames(10)

	var ai_root := race.get_node_or_null("AiKarts")
	assert_not_null(ai_root, "fixture setup: a normal boot must have already created the AI karts container")
	if ai_root == null:
		return

	var box_packed := load(ITEM_BOX_SCENE_PATH) as PackedScene
	assert_not_null(box_packed)
	if box_packed == null:
		return
	var box := box_packed.instantiate() as Area3D
	# LOCAL position under `race` itself, set BEFORE add_child (see item_
	# box.gd's own tests for why position-before-add_child matters for a
	# freshly-added Area3D's own entry too) -- matching _ai_root's own
	# CURRENT global position exactly, whatever it actually is in this
	# fixture (never assumed to be the literal world origin).
	box.position = race.to_local(ai_root.global_position)
	race.add_child(box)
	await wait_physics_frames(3)
	assert_true(
		bool(box.call("is_active")),
		"fixture setup: a freshly-added box, well after the boot itself has settled, must start active"
	)

	race.call("_spawn_ai_karts")
	await wait_physics_frames(5)

	assert_true(
		bool(box.call("is_active")),
		(
			"an AI kart's spawn-transform flash through _ai_root's own "
			+ "resting point must never trigger a nearby box pickup -- each "
			+ "kart's real transform must be built BEFORE it ever enters "
			+ "the tree, not seeded on a later tick after it already "
			+ "flashed there"
		)
	)


## Instantiates the real race_time_trial.tscn, adds a synthetic ItemBox
## under Track (a location already proven grounded, see the fixture
## rationale on every other test in this file), then configures it -- the
## "add a synthetic ItemBox under Track before configure() runs" fixture the
## class doc's own ITEM BOX WIRING section describes as the only way to
## exercise this wiring on the current (box-less) real tracks.
## local_position (relative to Track, same frame KartSpawn/GridSlotN already
## use) defaults to null, meaning "use the player's own KartSpawn marker
## position" -- the common case every test but one in this file wants. The
## AI-kart isolation test passes an explicit position well clear of
## KartSpawn instead: since the player spawns AT KartSpawn and keeps ticking
## normally throughout that test (nothing disables the player's own physics
## there), a box placed AT KartSpawn would be a fixture bug, not a
## production one -- the player's real kart would legitimately pick it up
## too, defeating the very isolation the test is trying to prove.
## catalog defaults to null (this suite's own shared _catalog) -- CTR R6
## Task 5's own test_item_rng_seed_nonzero_reproduces_the_same_first_roll_
## across_two_sessions is the one caller that overrides it (to ai.
## opponent_count = 0.0, see that test's own updated doc for why).
func _boot_race_with_synthetic_box(
	item_rng_seed: int = 0, local_position: Variant = null, catalog: GameplayTuning = null
) -> Dictionary:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return {}
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return {}
	var race := packed.instantiate()
	add_child_autofree(race)
	if item_rng_seed != 0:
		race.set("item_rng_seed", item_rng_seed)
	var track := race.get_node("Track") as Node3D
	var spawn := track.get_node("KartSpawn") as Marker3D
	var box_packed := load(ITEM_BOX_SCENE_PATH) as PackedScene
	assert_not_null(box_packed)
	if box_packed == null:
		return {}
	var box := box_packed.instantiate() as Area3D
	# LOCAL position (relative to their shared parent `track`), set BEFORE
	# track.add_child(box) -- a node added to the tree at its (0,0,0)
	# default and repositioned only AFTER can still register a transient,
	# permanently-sticky body_entered against anything already sitting at
	# that origin (discovered empirically while chasing a flaky false
	# pickup in test_item_box.gd -- see that suite's own _new_kart_body()
	# doc for the full mechanism).
	box.position = local_position if local_position != null else spawn.position
	track.add_child(box)
	race.call("configure", catalog if catalog != null else _catalog)
	_skip_pre_race_countdown(race)
	return {"race": race, "box": box}


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


## Polish wave [LOW-1]: the removed placement()/placement_out_of() pair's
## single-value getter is gone (placement() computed a naive raw-progress
## comparison that disagreed with standings()'s own correct finished-before-
## unfinished ranking -- see standings()'s own class doc). Every test that
## used to read placement() now reads the player's own row out of
## standings() instead -- the real, currently-correct results source race_
## hud.gd's own finish panel reads.
func _player_standings_position(race: Node) -> int:
	var standings: Array = race.call("standings")
	for entry: Variant in standings:
		var row := entry as Dictionary
		if bool(row.get("is_player")):
			return int(row.get("position"))
	return 0


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
	_skip_pre_race_countdown(race)
	return race


# ---------------------------------------------------------------------------
# R4 Task 6: RaceHUD's held-item display gains two small RaceSession-level
# reads -- items_enabled() (a public wrapper on the private _items_allowed()
# solo gate) and player_item_slot() (the player's own real ItemSlot) -- so
# the HUD's own duck-typed session.call() polling never has to reach past
# this session into a private field it does not own.
# ---------------------------------------------------------------------------


func test_items_enabled_is_true_by_default() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_true(
		bool(race.call("items_enabled")),
		"an ordinary (spawn_opponents=true) race must report items enabled"
	)


func test_items_enabled_is_false_in_a_solo_session() -> void:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("spawn_opponents", false)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	assert_false(
		bool(race.call("items_enabled")),
		"a solo (spawn_opponents=false) session must report items disabled -- see _items_allowed()'s own doc"
	)


func test_player_item_slot_exposes_the_real_kart_slot() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_eq(
		race.call("player_item_slot"),
		kart.call("item_slot"),
		"player_item_slot() must be the exact same ItemSlot instance the player's own KartController owns"
	)


# ---------------------------------------------------------------------------
# R4 Task 6: RaceHUD's held-item display -- text/visibility driven off
# RaceSession.items_enabled()/player_item_slot() every _refresh() tick, the
# same "poll the session every frame" pattern lap/timer/wrong-way already
# use (see race_hud.gd's own _refresh()).
# ---------------------------------------------------------------------------


func test_hud_item_label_is_hidden_when_the_player_slot_is_empty() -> void:
	var race := _boot_race()
	if race == null:
		return
	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	assert_not_null(item_label, "fixture setup: race_hud.tscn must author the Item label")
	if item_label == null:
		return
	await wait_process_frames(1)
	assert_false(
		item_label.visible,
		"an empty item slot must not show the held-item label"
	)


func test_hud_item_label_shows_the_roulette_flicker_while_rolling() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.0)
	assert_eq(slot.call("state"), &"rolling", "fixture setup: the roll must be in progress")

	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	await wait_process_frames(1)

	assert_true(
		item_label.visible,
		"a rolling slot must show the flicker, not stay hidden"
	)
	assert_eq(
		item_label.text,
		"ITEM  " + String(slot.call("rolling_display_item")).to_upper(),
		"the flicker text must track ItemSlot.rolling_display_item() every poll"
	)


func test_hud_item_label_shows_the_held_item_name_once_a_roll_lands() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	# rng_value=0.8 maps to tnt_stick -- see item_slot.gd's own N-WAY UNIFORM
	# MAPPING doc / test_item_slot.gd's identical boundary test. Doubles as
	# the underscore-to-space LABEL TEXT proof (see race_hud.gd's own doc):
	# &"tnt_stick" must render "TNT STICK", not a raw underscore.
	slot.call("start_roll", 0.8)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_eq(slot.call("state"), &"held", "fixture setup: the roll must have landed")
	assert_eq(slot.call("held_item"), &"tnt_stick", "fixture setup: rng_value=0.8 must roll tnt_stick")

	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	await wait_process_frames(1)

	assert_true(item_label.visible, "a held item must show the label")
	assert_eq(item_label.text, "ITEM  TNT STICK")


## CTR R6 Task 5: charges display -- see race_hud.gd's own LABEL TEXT/
## CHARGES doc. A freshly-landed triple_turbo (still carrying every one of
## its ItemTuning.triple_turbo_charges) must show the "xN" suffix.
func test_hud_item_label_shows_the_charge_count_for_a_freshly_landed_triple_turbo() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	# 6.0 / 7.0 maps to triple_turbo (ITEM_NAMES' own last entry) under the
	# N-WAY UNIFORM mapping -- see item_slot.gd's own boundary doc.
	slot.call("start_roll", 6.0 / 7.0)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_eq(slot.call("held_item"), &"triple_turbo", "fixture setup: 6/7 must roll triple_turbo")

	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	await wait_process_frames(1)

	assert_eq(
		item_label.text,
		"ITEM  TRIPLE TURBO x%d" % int(_catalog.items.triple_turbo_charges),
		"a freshly-landed triple_turbo must announce its full charge count"
	)


## Once only ONE charge remains, the "xN" suffix must disappear entirely --
## reads exactly like an ordinary single-use item's own label, per race_hud.
## gd's own doc ("the suffix only appears once there is more than one to
## announce").
func test_hud_item_label_omits_the_charge_suffix_once_only_one_charge_remains() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 6.0 / 7.0)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_eq(slot.call("held_item"), &"triple_turbo", "fixture setup: 6/7 must roll triple_turbo")

	var charge_count := int(_catalog.items.triple_turbo_charges)
	for _use_index in range(charge_count - 1):
		slot.call("use")
	assert_eq(int(slot.call("charges_remaining")), 1, "fixture setup: exactly one charge must remain")

	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	await wait_process_frames(1)

	assert_eq(item_label.text, "ITEM  TRIPLE TURBO", "with one charge left, the label must match an ordinary item's own")


## Solo semantics (R4 Task 6, item 4): items_enabled() must gate the HUD
## display as an INDEPENDENT check, not merely inherit "hidden" for free
## from "a solo session never rolls" (test_solo_session_never_rolls_even_
## after_a_real_synthetic_box_pickup above already proves that half). This
## test forces the underlying slot into a real &"held" state directly
## (bypassing the box-pickup gate entirely -- the same white-box ItemSlot
## access every other item test in this file already uses) so a future
## regression that somehow let a solo slot roll would still be caught by
## the HUD's own gate, rather than silently passing because the slot
## happened to stay empty anyway.
func test_hud_item_label_stays_hidden_in_a_solo_session_even_with_a_real_held_item() -> void:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("spawn_opponents", false)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	assert_false(
		bool(race.call("items_enabled")),
		"fixture sanity: solo must read items disabled"
	)

	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	slot.call("start_roll", 0.9)
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)
	assert_eq(
		slot.call("state"),
		&"held",
		"fixture setup: a directly-forced roll still lands regardless of solo-ness"
	)

	var hud := race.get_node("UI/RaceHUD")
	var item_label := hud.get_node("SafeArea/Stats/Margin/Rows/Item") as Label
	await wait_process_frames(1)

	assert_false(
		item_label.visible,
		"a solo session's HUD must hide the item label even with a real, forced held item"
	)


# ---------------------------------------------------------------------------
# R4 Task 6 (full combat-loop integration): a seeded 6-kart graybox race
# where a real box pickup rolls a missile, a real ITEM press dispatches it
# through the production RaceSession.dispatch_item_use() -> _spawn_missile()
# path, the missile's own real _physics_process flies it and hits a real
# target kart, and register_hit()'s own real spin-out + drift-cancel land on
# that target -- every step through the SAME production wiring the rest of
# this file already proves piecemeal (box roll, item-press dispatch, missile
# flight, register_hit's mid-slide cancel), now chained together as ONE
# story instead of four isolated ones.
# ---------------------------------------------------------------------------

# item_rng_seed=13 is pinned (empirically, via the same throwaway
# RandomNumberGenerator probe technique test_seeded_ai_kart_picks_up_a_box_
# rolls_and_uses_a_shield_through_real_dispatch's own doc describes) to roll
# &"missile" on the very first randf() call -- see item_slot.gd's own
# FOUR-WAY MAPPING doc: [0, 0.25) is the missile bucket, and seed 13's first
# draw lands at ~0.062.
const MISSILE_TEST_RNG_SEED := 13
# 12m: comfortably past the arm-distance (missile_arm_delay_s *
# missile_speed_mps = 0.25 * 26.0 = 6.5m) with real room to spare before the
# hit-radius check trips, and well inside missile_lifetime_s's own travel
# budget.
const MISSILE_TEST_TARGET_DISTANCE_M := 12.0
# A fixed spine-progress offset used only to separate "strictly ahead" from
# "strictly behind" the player for the seeded-follower target-lock fixture
# below -- large enough that no real AI driving during this test's own short
# setup window could plausibly close it, small enough it carries no
# particular racing meaning of its own.
const MISSILE_TEST_FOLLOWER_MARGIN_M := 1000.0


func test_seeded_six_kart_race_a_fired_missile_hits_and_spins_out_a_mid_slide_target_through_the_real_path() -> void:
	var setup := _boot_race_with_synthetic_box(MISSILE_TEST_RNG_SEED)
	var race: Node = setup.get("race")
	var box: Area3D = setup.get("box")
	if race == null or box == null:
		return
	assert_eq(
		int(race.call("ai_kart_count")) + 1,
		6,
		"fixture sanity: this must be a real 6-kart race (player + 5 AI)"
	)

	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return

	# Real box pickup (same teleport-then-confirm technique every other real
	# pickup test in this file uses).
	kart.set_physics_process(false)
	kart.global_position = box.global_position
	await wait_physics_frames(2)
	assert_eq(
		slot.call("state"),
		&"rolling",
		"fixture setup: the pickup must have started a real roll"
	)
	kart.set_physics_process(true)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var roulette_frames := int(ceil(_catalog.items.roulette_duration_s * physics_fps)) + 5
	await wait_physics_frames(roulette_frames)
	assert_eq(slot.call("state"), &"held")
	assert_eq(
		slot.call("held_item"),
		&"missile",
		"item_rng_seed=%d's own first randf() call must roll missile" % MISSILE_TEST_RNG_SEED
	)

	# --- Arrange a target AI kart mid-slide, at a known, reachable position
	# directly ahead of the player, with every OTHER kart's own progress
	# pinned strictly behind the player -- deterministic target-lock and
	# deterministic missile flight, not a hope that real race driving lines
	# up in time. See test_placement_reflects_an_ai_kart_seeded_strictly_
	# ahead_of_the_player's own doc for the _follower.reset() technique
	# reused here.
	var player_progress := float(race.call("player_total_progress_m"))
	var opponent_count := int(_catalog.ai.opponent_count)
	var target := race.call("ai_kart", 0) as CharacterBody3D
	var target_agent: Object = race.call("ai_agent", 0)
	assert_not_null(target)
	assert_not_null(target_agent)
	if target == null or target_agent == null:
		return
	for other_index in range(1, opponent_count):
		var other_agent: Object = race.call("ai_agent", other_index)
		var other_follower: RefCounted = other_agent.get("_follower") if other_agent != null else null
		if other_follower != null:
			other_follower.reset(player_progress - MISSILE_TEST_FOLLOWER_MARGIN_M)

	# Stop the target's own AI decision loop before manually arming a slide
	# on it -- otherwise its own AiDriver keeps calling steer()/hop_pressed()/
	# hop_released() every tick and fights these manual calls, the same
	# reason every other white-box drift-arming test in this suite disables
	# whatever else drives steer/hop first.
	target_agent.set_physics_process(false)
	await wait_physics_frames(5)
	assert_true(
		target.is_on_floor(),
		"fixture setup: the target AI kart must be grounded before sliding"
	)
	target.call("steer", _kart_tuning.slide_min_steer)
	target.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(
		bool(target.call("is_sliding")),
		"fixture setup: the target AI kart must really be sliding before the hit"
	)

	# Freeze the target's own physics now that it is mid-slide (latches
	# is_sliding() exactly there -- nothing left ticking to end it on its
	# own), then place it at a known, reachable point directly ahead of the
	# player's own about-to-be-frozen launch pose, and seed its own
	# SpineFollower total strictly ahead of the player's so the missile's
	# launch-time target lock (nearest kart with a strictly positive
	# progress margin) picks it uniquely.
	target.set_physics_process(false)
	var launch_position := Vector3(400.0, 0.0, 400.0)
	var target_position := (
		launch_position + Vector3(0.0, 0.0, -MISSILE_TEST_TARGET_DISTANCE_M)
	)
	target.global_transform = Transform3D(Basis.IDENTITY, target_position)
	var target_follower: RefCounted = target_agent.get("_follower")
	assert_not_null(target_follower)
	if target_follower == null:
		return
	target_follower.reset(player_progress + MISSILE_TEST_FOLLOWER_MARGIN_M)

	assert_false(bool(target.call("is_invulnerable")), "fixture sanity: no prior hit")
	assert_false(bool(target.call("is_spinning_out")), "fixture sanity: no prior hit")

	# Freeze the player's own pose at a known, axis-aligned launch point
	# facing -Z (the same Transform3D.IDENTITY convention test_dispatch_
	# item_use_beaker_drops_behind_the_launcher_by_one_kart_length already
	# uses) so the missile spawns from a known position/facing.
	kart.set_physics_process(false)
	kart.global_transform = Transform3D(Basis.IDENTITY, launch_position)

	# Real ITEM press through the real InputRouter -> RaceSession._route_
	# input() -> KartController.use_item() -> dispatch_item_use() ->
	# _spawn_missile() path -- the SAME real dispatch test_a_real_item_
	# press_on_a_held_turbo_reaches_dispatch_and_applies_boost already proves
	# for turbo, now proven for missile.
	var router := race.get_node("Input/InputRouter")
	router.call("push_button", InputIntent.ACTION_ITEM, true, 0.0, InputIntent.SOURCE_TOUCH)
	await wait_physics_frames(1)

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(
		hazards,
		"a real ITEM press on a held missile must reach dispatch_item_use() and spawn a real missile under the session"
	)
	if hazards == null:
		return
	assert_eq(hazards.get_child_count(), 1, "exactly one missile must have spawned")

	# Real flight: enough real physics ticks for the missile to actually
	# travel the fixed distance to the target at missile_speed_mps, arm
	# (missile_arm_delay_s), and detect the real hit-radius overlap -- not a
	# synthetic register_hit() call.
	var flight_s := MISSILE_TEST_TARGET_DISTANCE_M / _catalog.items.missile_speed_mps
	var flight_frames := int(ceil(flight_s * physics_fps)) + 20
	await wait_physics_frames(flight_frames)

	assert_eq(
		hazards.get_child_count(),
		0,
		"the missile must have hit its target and despawned by now"
	)
	assert_true(
		bool(target.call("is_spinning_out")),
		"the real missile flight must have reached register_hit() and applied a real spin_out"
	)
	assert_true(
		bool(target.call("is_invulnerable")),
		"apply_spin_out() must also have started the target's own invulnerable window"
	)
	assert_false(
		bool(target.call("is_sliding")),
		(
			"register_hit()'s real spin_out must cancel the target's own live "
			+ "slide through the WHOLE missile-flight path, not only when "
			+ "register_hit() is called directly"
		)
	)
