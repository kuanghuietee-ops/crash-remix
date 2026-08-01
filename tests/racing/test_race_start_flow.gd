extends GutTest

# CTR R5 Task 1: the countdown + start-boost SESSION-LEVEL integration
# coverage -- karts spawning frozen, staying frozen (and quiescent) through a
# real 3-2-1 countdown, the race timer starting at GO, the three start-boost
# verdicts actually reaching a real kart, pause-correctness, and retry
# resetting the whole flow. The pure phase/verdict math itself is
# test_countdown_timer.gd's/test_start_boost_judge.gd's own job -- this file
# proves race_session.gd's real wiring of those two pure classes against the
# real graybox loop scene, the same "boot the REAL scene, drive it via its
# real API" shape test_race_session.gd already establishes.
#
# Every OTHER race test in this codebase now boots through a countdown-skip
# helper (see test_race_session.gd's own _skip_pre_race_countdown()) so it
# can get straight to whatever it's actually testing -- this file
# deliberately does NOT skip; driving the real countdown for real is the
# whole point here.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func _boot_race_no_skip() -> Node:
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


## Ticks one real physics frame at a time until is_race_started() first
## reads true, then returns immediately -- gives frame-exact control over
## "right at GO" without having to hand-compute how many frames a countdown
## of a given tuning takes to cross it (fragile arithmetic once a test also
## needs to reason about time relative to GO afterward, e.g. the bog
## penalty's own countdown). Bounded well past any real countdown length so
## a regression that never reaches GO fails loudly instead of hanging.
func _wait_until_race_started(race: Node) -> void:
	var physics_fps := float(Engine.physics_ticks_per_second)
	var max_frames := int(ceil(_catalog.race.countdown_step_s * physics_fps)) * 10
	var frames_waited := 0
	while not bool(race.call("is_race_started")) and frames_waited < max_frames:
		await wait_physics_frames(1)
		frames_waited += 1
	assert_true(
		bool(race.call("is_race_started")),
		"fixture setup: the countdown must reach GO within a generous bound"
	)


# ---------------------------------------------------------------------------
# Spawn state: every kart frozen, countdown at &"three", race not started.
# ---------------------------------------------------------------------------


func test_race_spawns_with_every_kart_frozen_and_countdown_at_three() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	assert_eq(race.call("countdown_phase"), &"three")
	assert_false(bool(race.call("is_race_started")))
	assert_false(
		bool(kart.call("is_run_active")),
		"the player must spawn frozen, same as every AI kart"
	)
	var opponent_count := int(_catalog.ai.opponent_count)
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		assert_not_null(ai_kart)
		if ai_kart == null:
			continue
		assert_false(
			bool(ai_kart.call("is_run_active")),
			"AI kart at slot %d must spawn frozen too" % (slot_index + 1)
		)


# ---------------------------------------------------------------------------
# Frozen pre-GO: real physics through a real countdown must produce zero
# displacement for every kart and zero AI stuck respawns, even under
# real attempted input (steer, HOP-hold -- which would otherwise apply a
# real vertical impulse, see kart_controller.gd's own hop_pressed() doc).
# ---------------------------------------------------------------------------


func test_one_second_of_physics_during_the_countdown_produces_zero_displacement_and_zero_respawns() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var router := race.get_node("Input/InputRouter")
	var opponent_count := int(_catalog.ai.opponent_count)

	# A handful of settle frames first -- even a fully frozen kart's own
	# decelerate_to_stop() still integrates real gravity every tick (see
	# kart_motor.gd's own doc), so a kart authored slightly above the floor
	# legitimately drops a few centimeters settling onto it on its very
	# first ticks, same as any other fixture in this suite. Capturing the
	# "start" position only AFTER that one-time settle keeps this test's own
	# zero-displacement window free of that unrelated, expected artifact.
	var settle_frames := 10
	await wait_physics_frames(settle_frames)

	var start_position := kart.global_position
	var ai_start_positions: Array[Vector3] = []
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		ai_start_positions.append(ai_kart.global_position if ai_kart != null else Vector3.ZERO)

	# A real, sustained attempt to move: hard steer plus a held HOP, exactly
	# the input a player mashing the controls during the countdown would
	# produce -- routed nowhere pre-GO (see race_session.gd's own class doc:
	# _route_input() never runs while _race_started is false), so none of
	# this should move a single kart a single millimeter.
	router.call("push_move", Vector2(1.0, 0.0), 0.0, InputIntent.SOURCE_TOUCH)
	router.call(
		"push_button", InputIntent.ACTION_JUMP, true, 0.0, InputIntent.SOURCE_TOUCH
	)

	# Comfortably over a full second, comfortably short of the ~3s full
	# countdown -- real sustained physics that never crosses into GO.
	var physics_fps := float(Engine.physics_ticks_per_second)
	await wait_physics_frames(int(ceil(physics_fps)) + 5 - settle_frames)

	assert_eq(
		race.call("countdown_phase"),
		&"two",
		"fixture sanity: a bit over one countdown_step_s must have advanced the phase by exactly one step"
	)
	assert_false(bool(race.call("is_race_started")))

	assert_almost_eq(
		kart.global_position.distance_to(start_position),
		0.0,
		0.001,
		"the player's own kart must not move at all while frozen pre-GO, even under a real held HOP + steer attempt"
	)
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		if ai_kart == null:
			continue
		assert_almost_eq(
			ai_kart.global_position.distance_to(ai_start_positions[slot_index]),
			0.0,
			0.001,
			"AI kart at slot %d must not move at all while frozen pre-GO" % (slot_index + 1)
		)
		var agent: Node = race.call("ai_agent", slot_index)
		assert_eq(
			int(agent.call("respawn_count")),
			0,
			"AI kart at slot %d must never respawn while deliberately frozen pre-GO -- its own is_run_active() gate must keep the stuck window from ever accumulating" % (slot_index + 1)
		)


# ---------------------------------------------------------------------------
# Wrong-way + stuck detection quiescent pre-GO.
# ---------------------------------------------------------------------------


func test_wrong_way_never_raises_pre_go_even_under_sustained_backward_velocity() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# Disables only the KART's own _physics_process (mirroring test_race_
	# session.gd's identical wrong-way fixtures) so this raw velocity isn't
	# immediately overwritten by KartMotor's own decelerate_to_stop() the
	# very next tick -- the SESSION's own _physics_process (a separate node)
	# still runs normally and is what this test is really probing.
	kart.set_physics_process(false)
	kart.velocity = Vector3(-5.0, 0.0, 0.0)

	var grace_s: float = _catalog.race.wrong_way_grace_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(grace_s * physics_fps)) + 5
	await wait_physics_frames(frames_needed)

	assert_false(
		bool(race.call("is_wrong_way")),
		"sustained backward velocity pre-GO must never raise the wrong-way flag -- _update_wrong_way() must simply never run before GO"
	)
	assert_false(bool(race.call("is_race_started")), "fixture sanity: still pre-GO")


# ---------------------------------------------------------------------------
# Fix round 1, reviewer [LOW-2]: gate/box signal paths quiescent pre-GO.
# Neither is REACHABLE through real play before this fix either (a frozen
# kart can never physically enter a gate/box trigger before GO), but both
# handlers were left ungated -- a caller reaching them directly (as this
# suite's own _force_finish()-style helpers do) got no protection from the
# session itself. Made structural: _on_gate_body_entered()/_on_box_body_
# entered() now early-return pre-GO, proven here by calling them directly,
# synthetically, before GO -- exactly the shape a bug (or a stray real
# overlap somehow reaching one) would have to go through.
# ---------------------------------------------------------------------------


func test_gate_crossing_is_a_no_op_pre_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var gate := race.get_node("Track/Gates/Gate0")
	assert_false(bool(race.call("is_race_started")), "fixture sanity: still pre-GO")

	race.call("_on_gate_body_entered", kart, gate)

	assert_eq(
		int(race.call("progress_gates")),
		0,
		"a synthetic gate crossing pre-GO must not advance the validator at all"
	)
	assert_false(bool(race.call("is_finished")))


func test_box_pickup_is_a_no_op_pre_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var slot: Object = kart.call("item_slot")
	assert_not_null(slot)
	if slot == null:
		return
	assert_eq(slot.call("state"), &"empty", "fixture sanity: no roll yet")
	assert_false(bool(race.call("is_race_started")), "fixture sanity: still pre-GO")

	race.call("_on_box_body_entered", kart)

	assert_eq(
		slot.call("state"),
		&"empty",
		"a synthetic box pickup pre-GO must never start a real roll"
	)


## Task 1 (CTR R7, discharges spec debt #2): pad signal paths quiescent
## pre-GO -- see the two tests immediately above's own doc for the full
## rationale (a frozen kart can never physically reach a pad before GO
## either, but the session's own connected handler is still gated
## structurally). The pad instance itself is never configure()'d or added
## to the track -- irrelevant here, since the pre-GO early-return in
## _on_boost_pad_body_entered()/_on_jump_pad_body_entered() fires BEFORE
## either handler ever touches the pad at all (see race_session.gd's own
## PAD WIRING doc).
func test_boost_pad_crossing_is_a_no_op_pre_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	var pad: Area3D = load("res://src/racing/track/boost_pad.gd").new()
	add_child_autofree(pad)
	assert_false(bool(race.call("is_race_started")), "fixture sanity: still pre-GO")

	race.call("_on_boost_pad_body_entered", kart, pad)

	assert_false(
		bool(motor.call("is_boosting")),
		"a synthetic boost pad crossing pre-GO must never apply boost"
	)


func test_jump_pad_crossing_is_a_no_op_pre_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	var pad: Area3D = load("res://src/racing/track/jump_pad.gd").new()
	add_child_autofree(pad)
	assert_false(bool(race.call("is_race_started")), "fixture sanity: still pre-GO")

	race.call("_on_jump_pad_body_entered", kart, pad)

	assert_almost_eq(
		float(motor.call("vertical_speed_mps")),
		0.0,
		0.01,
		"a synthetic jump pad crossing pre-GO must never launch the kart"
	)


# ---------------------------------------------------------------------------
# The race timer starts AT GO, not at spawn.
# ---------------------------------------------------------------------------


func test_elapsed_s_stays_zero_through_the_countdown_and_starts_advancing_at_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return

	var physics_fps := float(Engine.physics_ticks_per_second)
	await wait_physics_frames(int(round(physics_fps)))

	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.0001,
		"the race timer must not advance at all pre-GO"
	)

	# Collapse the rest of the countdown in one synthetic tick (same
	# technique test_race_session.gd's own _skip_pre_race_countdown() uses),
	# then let a few more REAL ticks run.
	race.call("_tick_countdown", 1000.0)
	assert_true(bool(race.call("is_race_started")))
	await wait_physics_frames(5)

	assert_gt(
		float(race.call("elapsed_s")),
		0.0,
		"the race timer must start advancing once the race is actually running"
	)


# ---------------------------------------------------------------------------
# Countdown phase progression through real, wall-clock-driven ticks.
# ---------------------------------------------------------------------------


func test_countdown_phase_advances_through_real_ticks_toward_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 3

	assert_eq(race.call("countdown_phase"), &"three")

	await wait_physics_frames(int(ceil(step_s * physics_fps)) + margin_frames)
	assert_eq(race.call("countdown_phase"), &"two")

	await wait_physics_frames(int(ceil(step_s * physics_fps)))
	assert_eq(race.call("countdown_phase"), &"one")

	await wait_physics_frames(int(ceil(step_s * physics_fps)) + margin_frames)
	assert_true(
		bool(race.call("is_race_started")),
		"the third full step must carry the countdown all the way to GO"
	)


# ---------------------------------------------------------------------------
# Start-boost verdicts, driven through the real InputRouter.
# ---------------------------------------------------------------------------


func test_a_hop_held_into_the_boost_window_applies_the_launch_boost_at_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var router := race.get_node("Input/InputRouter")
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return

	# Three timed pre-GO phases (three/two/one) of countdown_step_s each --
	# see countdown_timer.gd's own class doc for why that count isn't a
	# tuning field of its own.
	var total_s: float = 3.0 * _catalog.race.countdown_step_s
	var window_s: float = _catalog.race.start_boost_window_s
	var physics_fps := float(Engine.physics_ticks_per_second)

	# Wait until comfortably (half the window) short of GO, then press and
	# hold HOP the rest of the way through -- _wait_until_race_started()
	# below gives frame-exact control over "right at GO" so this test never
	# has to hand-compute how much real decay a fixed frame margin would
	# have introduced by the time it reads the motor.
	var press_lead_s: float = window_s * 0.5
	var frames_before_press := int(floor((total_s - press_lead_s) * physics_fps))
	await wait_physics_frames(frames_before_press)
	router.call(
		"push_button", InputIntent.ACTION_JUMP, true, 0.0, InputIntent.SOURCE_TOUCH
	)
	await _wait_until_race_started(race)

	assert_true(
		bool(kart.call("is_run_active")),
		"a &\"boost\" verdict must unfreeze the player's own kart immediately"
	)
	assert_true(
		bool(motor.call("is_boosting")),
		"a &\"boost\" verdict must apply the real launch boost the same tick as GO"
	)
	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		_catalog.kart.boost_duration_s,
		# _wait_until_race_started() returns on the very first tick GO reads
		# true, so at most one physics tick's worth of real decay separates
		# apply_boost() firing from this read.
		(1.0 / physics_fps) * 2.0,
		"the launch boost must reuse KartTuning.boost_duration_s -- no separate field exists for it"
	)


func test_a_hop_held_from_before_the_window_bogs_the_player_while_ai_unfreezes_plainly() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var router := race.get_node("Input/InputRouter")

	# Held from the very start of the countdown, well before the window
	# opens, all the way through GO.
	router.call(
		"push_button", InputIntent.ACTION_JUMP, true, 0.0, InputIntent.SOURCE_TOUCH
	)
	await _wait_until_race_started(race)

	# No extra settle wait here (unlike the zero-displacement test) -- this
	# kart has already been sitting frozen through the ENTIRE ~3s countdown
	# before this point, so any initial gravity-settle is long over. Any
	# further wait here would eat into the bog penalty's own countdown
	# (post-race-start ticks decrement _bog_remaining_s every physics tick,
	# same as elapsed_s()), so the very next assertions run on the exact GO
	# frame itself.
	assert_false(
		bool(kart.call("is_run_active")),
		"a &\"bog\" verdict must leave the player's own kart frozen right at GO"
	)
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_true(
		bool(ai_kart.call("is_run_active")),
		"AI must unfreeze plainly at GO regardless of the player's own bog penalty"
	)
	# NOT a tight zero-displacement claim like the pre-GO freeze test above --
	# by now every AI kart is genuinely driving (GO already fired for them),
	# starting from GridSlot markers authored physically behind the player's
	# own KartSpawn (see race_session.gd's own _spawn_ai_karts() doc), so
	# real incidental contact against the still-parked player kart is
	# possible and not itself a violation of "frozen" -- "frozen" means this
	# kart's OWN controller isn't driving it (is_run_active() false, steer/
	# hop routing gated off, asserted below), not "physically inert against
	# every other body on the track". A loose bound here still catches the
	# catastrophic regression case (a wrongly-unfrozen kart under its own
	# auto-throttle would cover many meters in under a second at kart.tres
	# speeds) without failing on ordinary neighbor-traffic jitter.
	var frozen_position := kart.global_position

	var bog_s: float = _catalog.race.start_bog_penalty_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	var under_margin_frames := 5
	await wait_physics_frames(
		maxi(int(floor(bog_s * physics_fps)) - under_margin_frames, 0)
	)
	assert_false(
		bool(kart.call("is_run_active")),
		"the bog penalty must not lift a moment early"
	)
	assert_lt(
		kart.global_position.distance_to(frozen_position),
		1.0,
		"a bogged kart must not have gone anywhere under its own power -- it has no controller driving it while frozen"
	)

	var over_margin_frames := 10
	await wait_physics_frames(under_margin_frames + over_margin_frames)
	assert_true(
		bool(kart.call("is_run_active")),
		"the bog penalty must lift once start_bog_penalty_s has elapsed"
	)


func test_no_hop_held_reads_none_and_unfreezes_plainly_with_no_boost() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return

	await _wait_until_race_started(race)

	assert_true(
		bool(kart.call("is_run_active")),
		"a &\"none\" verdict must unfreeze the player's own kart plainly, same as AI"
	)
	assert_false(
		bool(motor.call("is_boosting")),
		"a &\"none\" verdict must never apply a launch boost"
	)


# ---------------------------------------------------------------------------
# Pause mid-countdown freezes the countdown itself.
# ---------------------------------------------------------------------------


func test_pausing_mid_countdown_freezes_the_countdown_itself() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)

	await wait_physics_frames(int(round(step_s * physics_fps * 0.2)))
	assert_eq(
		race.call("countdown_phase"),
		&"three",
		"fixture sanity: still well inside the first step"
	)

	# Simulated pause (same technique test_race_session.gd's own
	# test_elapsed_s_excludes_time_the_race_session_is_not_processing uses):
	# comfortably longer than a full step -- if the pause did not actually
	# freeze the countdown, this alone would already cross into &"two".
	race.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 10)
	race.process_mode = Node.PROCESS_MODE_PAUSABLE

	assert_eq(
		race.call("countdown_phase"),
		&"three",
		"the countdown must not advance at all while the session isn't processing"
	)

	await wait_physics_frames(int(ceil(step_s * physics_fps)))
	assert_eq(
		race.call("countdown_phase"),
		&"two",
		"the countdown must resume advancing once processing resumes"
	)


# ---------------------------------------------------------------------------
# Retry resets the whole flow.
# ---------------------------------------------------------------------------


func test_reconfigure_resets_the_whole_flow_back_to_a_frozen_pre_go_state() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D

	race.call("_tick_countdown", 1000.0)
	assert_true(bool(race.call("is_race_started")), "fixture setup: the first race must have started")
	assert_true(bool(kart.call("is_run_active")), "fixture setup: the first race's kart must be active")

	# The real retry path frees and reinstantiates the whole scene (see
	# race_session.gd's own retry_requested doc); this suite's own
	# established stand-in for that (test_race_session.gd's identical
	# test_reconfigure_rebuilds_ai_karts_without_leaking_old_instances) is
	# calling configure() again on the SAME instance.
	race.call("configure", _catalog)
	var kart_after := race.get_node("Kart") as CharacterBody3D

	assert_false(
		bool(race.call("is_race_started")),
		"a reconfigure must reset the flow all the way back to not-yet-started"
	)
	assert_eq(
		race.call("countdown_phase"),
		&"three",
		"a reconfigure must reset the countdown back to its very first phase"
	)
	assert_false(
		bool(kart_after.call("is_run_active")),
		"a reconfigure must spawn the kart frozen again, pre-GO"
	)
	var opponent_count := int(_catalog.ai.opponent_count)
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		assert_not_null(ai_kart)
		if ai_kart == null:
			continue
		assert_false(
			bool(ai_kart.call("is_run_active")),
			"AI kart at slot %d must spawn frozen again after a reconfigure too" % (slot_index + 1)
		)


# ---------------------------------------------------------------------------
# HUD countdown display + boost hint.
# ---------------------------------------------------------------------------


func test_hud_shows_countdown_and_boost_hint_pre_go() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var hud := race.get_node("UI/RaceHUD")
	var countdown_label := hud.get_node("SafeArea/Countdown") as Label
	var boost_hint_label := hud.get_node("SafeArea/BoostHint") as Label
	assert_not_null(countdown_label, "fixture setup: race_hud.tscn must author the Countdown label")
	assert_not_null(boost_hint_label, "fixture setup: race_hud.tscn must author the BoostHint label")
	if countdown_label == null or boost_hint_label == null:
		return

	await wait_process_frames(1)
	assert_true(countdown_label.visible, "the countdown must be visible pre-GO")
	assert_eq(countdown_label.text, "3")
	assert_true(boost_hint_label.visible, "the boost hint must be visible pre-GO")


## Polish wave [MEDIUM]: the hint text itself must teach the REAL mechanic,
## not the losing one. StartBoostJudge's own VERDICT section (start_boost_
## judge.gd) is unambiguous: holding HOP continuously from early in the
## countdown (e.g. from the "3") rides held_duration_s past start_boost_
## window_s and reads as &"bog", while a hold that only BEGINS within the
## last start_boost_window_s before GO reads as &"boost". A hint that says
## "HOLD HOP" with no timing qualifier instructs exactly the losing input --
## this asserts the authored copy names both halves of the real mechanic
## (hold it late, right before GO; holding it early bogs) so a future
## regression back to "just hold it" cannot ship without this test noticing.
func test_boost_hint_text_teaches_the_real_late_hold_mechanic() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var hud := race.get_node("UI/RaceHUD")
	var boost_hint_label := hud.get_node("SafeArea/BoostHint") as Label
	assert_not_null(boost_hint_label, "fixture setup: race_hud.tscn must author the BoostHint label")
	if boost_hint_label == null:
		return

	assert_true(
		boost_hint_label.text.contains("BEFORE GO"),
		"the hint must tell the player to hold right BEFORE GO, not from the start of the countdown"
	)
	assert_true(
		boost_hint_label.text.contains("EARLY"),
		"the hint must warn that holding EARLY is the losing input (it bogs), not the boost input"
	)


## Fix round 1, reviewer [LOW-1]: the countdown label used to hide the SAME
## tick is_race_started() flipped true, which made "GO!" unrenderable by
## construction -- is_race_started() and the real unfreeze/boost effects
## land on the exact same tick (see race_session.gd's own _start_race()
## doc), so a HUD gated on that flag alone never had a tick where it was
## both true AND still worth showing anything for. This pins the fixed
## behavior: "GO!" renders right at GO and stays up for one more
## countdown_step_s (the same per-phase beat every 3/2/1 digit already got),
## then clears. The boost hint is NOT part of this flash -- it hides
## immediately at GO, unchanged from before this fix.
func test_hud_shows_go_text_at_go_then_clears_after_one_countdown_step() -> void:
	var race := _boot_race_no_skip()
	if race == null:
		return
	var hud := race.get_node("UI/RaceHUD")
	var countdown_label := hud.get_node("SafeArea/Countdown") as Label
	var boost_hint_label := hud.get_node("SafeArea/BoostHint") as Label
	if countdown_label == null or boost_hint_label == null:
		return

	race.call("_tick_countdown", 1000.0)
	assert_true(bool(race.call("is_race_started")), "fixture setup: the race must have started")
	await wait_process_frames(1)

	assert_true(
		countdown_label.visible,
		"the GO flash must actually render -- it must not hide the same tick is_race_started() flips true"
	)
	assert_eq(countdown_label.text, "GO!")
	assert_false(
		boost_hint_label.visible,
		"the boost hint must still hide immediately at GO -- only the countdown label flashes GO"
	)

	var step_s: float = _catalog.race.countdown_step_s
	var physics_fps := float(Engine.physics_ticks_per_second)
	await wait_physics_frames(int(ceil(step_s * physics_fps)) + 5)

	assert_false(
		countdown_label.visible,
		"the GO flash must clear once its own one-countdown_step_s window has elapsed"
	)
