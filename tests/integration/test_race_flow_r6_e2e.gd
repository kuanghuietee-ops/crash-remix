extends GutTest

# CTR R6 Task 6: END-TO-END R6 integration coverage -- the whole R6 circuit-
# polish loop chained together against the REAL packed Sanity Shores race
# scene, the way an actual play session experiences it: a real 3-2-1
# countdown ticked through real physics frames to GO, the real apex-line
# AiDriver/AiKartAgent pair (Task 4) driving real AI karts under real
# physics, a real ItemBox pickup rolling a REAL weighted item through
# ItemSlot's real WEIGHTED MAPPING (Task 5) and firing it through the real
# RaceSession.use_item_for() -> dispatch_item_use() -> _spawn_bomb() path,
# the real KartFx drift-spark wiring (Task 1) proven live on a genuinely
# sliding AI kart, both character sources (Task 3) actually mounted, and the
# player teleport-finishing to a real standings() split -- all inside ONE
# bounded, seeded run, with zero unhandled push_error/engine-error calls
# anywhere in it.
#
# Every individual mechanic exercised here already has its own dedicated
# headless coverage (test_kart_fx.gd, test_item_box.gd, test_item_slot.gd,
# test_ai_driver.gd, test_ai_kart_agent.gd, test_race_session.gd's own R6
# additions) -- this file's job, same as R5's test_race_flow_e2e.gd before
# it, is different: prove the REAL, WHOLE R6 pipeline holds together end to
# end on the real Sanity Shores scene, not re-prove any one piece's own edge
# cases in isolation.
#
# SEEDED ITEM ROLL (the "guarantee a bomb or TNT roll" ask). RaceSession
# owns exactly ONE seeded RandomNumberGenerator for the whole race
# (item_rng_seed, see race_session.gd's own ITEM RNG doc) and draws from it
# once per real box pickup, in pickup order -- so pinning item_rng_seed also
# pins the FIRST real pickup's outcome, as long as that pickup really is the
# first randf() draw of the run (this test freezes every AI kart's own
# _physics_process the instant GO fires, before doing anything else, so no
# AI can reach a box first -- see step 2 below).
#
# _SEED_RNG_FIRST_DRAW (computed empirically via a throwaway
# RandomNumberGenerator probe against this exact Godot version, the same
# technique test_race_session.gd's own MISSILE_TEST_RNG_SEED/item_rng_seed=1
# comments describe): seed 2's first randf() call reads ~0.702882349491119.
# Proven algebraically (not just empirically) to land on &"bomb" under EVERY
# mapping ItemSlot._weights_for_ratio() can produce for this pickup, not
# just the one this fixture happens to hit:
#   - WEIGHTED, ratio=0.0 (race leader, pure front weights, items.tres):
#     missile/shield/turbo/beaker/bomb/tnt_stick/triple_turbo cumulative
#     bounds over total 8.5 put bomb at [5.5/8.5, 6.5/8.5) = [0.64706, 0.76471).
#   - WEIGHTED, ratio=1.0 (last place, pure back weights): bomb's own
#     cumulative bound over total 10.5 is [5.5/10.5, 7.5/10.5) =
#     [0.52381, 0.71429).
#   - Every ratio in [0.0, 1.0] blends LINEARLY between those two extremes
#     (ItemSlot._weights_for_ratio()'s own per-item lerp, see its class
#     doc) -- both this pickup's own lower boundary (start of bomb's own
#     bucket) and upper boundary (start of tnt_stick's own bucket, one past
#     bomb) are each an AFFINE function of ratio, and an affine function
#     that is positive at both ends of an interval cannot cross zero inside
#     it (a straight line between two same-signed values stays that sign
#     throughout) -- so "0.702882... lands inside bomb's own bucket" being
#     true at ratio=0.0 AND at ratio=1.0 is already sufficient to prove it
#     for every ratio in between, with no need to enumerate them.
#   - UNIFORM fallback (position_ratio<0.0 or an unconfigured slot -- the
#     path a field_size()<=1 pickup would take): bomb is ITEM_NAMES[4] of 7,
#     bucket [4/7, 5/7) = [0.57143, 0.71429) -- 0.702882... still lands
#     inside it.
# So this seed lands &"bomb" regardless of which of those three code paths
# the real pickup below actually takes -- this fixture does not have to
# fight (or even know) the live rank snapshot's exact state at pickup time.
const _SEED := 2

const RACE_SCENE_PATH := "res://scenes/racing/race_sanity_shores.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const CRASH_CHARACTER_SCENE_PATH := "res://assets/models/characters/SK_crash.glb"
const LAB_ASSISTANT_CHARACTER_SCENE_PATH := "res://assets/models/enemies/SK_lab_assistant.glb"
## Task 5 (characters/select/classes): papu's own DriverEntry now resolves
## for real (data/racing/drivers/papu.tres) instead of falling back to the
## lab assistant like every other still-gated driver below.
const PAPU_SEATED_CHARACTER_SCENE_PATH := "res://assets/models/bosses/SK_papu_seated.glb"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


func _boot_race() -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH), "%s must exist" % RACE_SCENE_PATH)
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.set("item_rng_seed", _SEED)
	race.call("configure", _catalog)
	return race


## Frame-exact "wait for real GO" -- the same shape test_race_flow_e2e.gd's
## own copy (itself mirroring test_race_start_flow.gd's own
## _wait_until_race_started()) already establishes; GUT test scripts don't
## share private helpers across files (established convention, see that
## file's own identical note), so this is a local copy, not a reach into
## another suite's file.
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


## Same teleport-onto-every-real-gate technique test_race_flow_e2e.gd's own
## _teleport_finish_player() uses (itself test_race_session.gd's own
## _cross_gate() technique) -- physics disabled first so the kart's own
## auto-throttle can't fight the teleport.
func _teleport_finish_player(
	race: Node, kart: CharacterBody3D, gate_count: int, lap_count: int
) -> void:
	kart.set_physics_process(false)
	for _lap in range(lap_count):
		for gate_index in range(gate_count):
			var gate := race.get_node("Track/Gates/Gate%d" % gate_index) as Area3D
			kart.global_position = gate.global_position
			await wait_physics_frames(2)
	var start_gate := race.get_node("Track/Gates/Gate0") as Area3D
	kart.global_position = start_gate.global_position
	await wait_physics_frames(2)


# ---------------------------------------------------------------------------
# The one comprehensive flow. Every R6 workstream is proven inside this
# single seeded, bounded run rather than four unrelated fixtures, the same
# "one real story, not four isolated ones" shape
# test_seeded_six_kart_race_a_fired_missile_hits_and_spins_out_a_mid_slide_
# target_through_the_real_path (test_race_session.gd, R4 Task 6) already
# established for R4's own combat loop.
# ---------------------------------------------------------------------------


func test_r6_seeded_sanity_shores_full_flow_fx_items_characters_apex_ai_and_standings() -> void:
	var race := _boot_race()
	if race == null:
		return
	await wait_physics_frames(1)

	# ------------------------------------------------------------------
	# 1. CHARACTERS MOUNTED (Task 3): player Crash + 5 lab-assistant AI.
	# ------------------------------------------------------------------
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_eq(opponent_count, 5, "fixture sanity: R6 Sanity Shores fields 5 AI opponents")
	assert_eq(int(race.call("ai_kart_count")), opponent_count)

	var player_kart := race.get_node("Kart") as CharacterBody3D
	var player_mount := player_kart.call("mounted_character") as Node3D
	assert_not_null(player_mount, "the player kart must have a real mounted character")
	if player_mount != null:
		assert_eq(
			player_mount.scene_file_path,
			CRASH_CHARACTER_SCENE_PATH,
			"the player must ride the real likeness-gated Crash model, not a stand-in"
		)

	# Task 5 (characters/select/classes): AI fill walks DriverRegistry.
	# entries() in its own fixed ROSTER ORDER minus the player's pick
	# (_ai_fill_driver_ids()'s own doc) -- with the player defaulting to
	# crash (this fixture never picks), that order is papu, cortex, coco,
	# ripper_roo, lab_assistant, so opponent_index 0 is always papu's own
	# slot. His DriverEntry now resolves for real instead of falling back
	# to the shared lab-assistant mesh every OTHER still-gated driver here
	# still does -- see PAPU_SEATED_CHARACTER_SCENE_PATH's own doc.
	const _PAPU_AI_SLOT := 0
	for opponent_index in range(opponent_count):
		var ai_kart := race.call("ai_kart", opponent_index) as CharacterBody3D
		assert_not_null(ai_kart, "AI kart %d must exist" % opponent_index)
		if ai_kart == null:
			continue
		var ai_mount := ai_kart.call("mounted_character") as Node3D
		assert_not_null(ai_mount, "AI kart %d must have a real mounted character" % opponent_index)
		if ai_mount != null:
			var expected_scene_path := (
				PAPU_SEATED_CHARACTER_SCENE_PATH
				if opponent_index == _PAPU_AI_SLOT
				else LAB_ASSISTANT_CHARACTER_SCENE_PATH
			)
			assert_eq(
				ai_mount.scene_file_path,
				expected_scene_path,
				(
					"AI kart %d must ride the real papu-seated model"
					if opponent_index == _PAPU_AI_SLOT
					else "AI kart %d must ride the real lab-assistant model"
				) % opponent_index
			)

	# ------------------------------------------------------------------
	# 2. FX WIRING LIVE -- box visual spin (Task 1). Runs unconditionally
	# in ItemBox._physics_process regardless of race/countdown state (see
	# item_box.gd's own _tick_spin_and_bob() doc), so this is checkable
	# immediately, pre-GO.
	# ------------------------------------------------------------------
	var pickup_box := race.get_node("Track/ItemBoxes/ItemBoxEast1") as Area3D
	assert_not_null(pickup_box, "fixture setup: Sanity Shores must author ItemBoxEast1")
	var box_mesh := pickup_box.get_node("Mesh") as MeshInstance3D
	assert_not_null(box_mesh, "fixture setup: an ItemBox must carry a Mesh child")
	var box_rotation_before := box_mesh.rotation.y
	await wait_physics_frames(15)
	assert_ne(
		box_mesh.rotation.y,
		box_rotation_before,
		"the item box's own crate-style visual must be spinning (fx.item_box_spin_degrees_per_s live)"
	)

	# ------------------------------------------------------------------
	# 3. Real countdown -> GO.
	# ------------------------------------------------------------------
	assert_eq(race.call("countdown_phase"), &"three", "fixture setup: countdown starts at three")
	assert_false(bool(race.call("is_race_started")))
	await _wait_until_race_started(race)
	assert_almost_eq(
		float(race.call("elapsed_s")),
		0.0,
		0.05,
		"the race timer must read essentially zero right at GO"
	)

	# Freeze every AI kart's own _physics_process THE INSTANT GO fires,
	# before any other awaits -- guarantees no AI kart's own movement can
	# reach a box first and consume the seeded RNG's first draw ahead of
	# the controlled player pickup below (see this file's own _SEED doc).
	# A frozen CharacterBody3D never calls move_and_slide, so its own
	# Area3D overlaps genuinely cannot advance while this holds.
	for opponent_index in range(opponent_count):
		var frozen_ai_kart := race.call("ai_kart", opponent_index) as CharacterBody3D
		if frozen_ai_kart != null:
			frozen_ai_kart.set_physics_process(false)

	# ------------------------------------------------------------------
	# 4. NEW ITEM THROUGH REAL DISPATCH (Task 5): a real ItemBox pickup
	# rolls the seeded &"bomb" via the real weighted ItemSlot, and a real
	# use_item_for() call fires it through the real dispatch_item_use()
	# -> _spawn_bomb() path -- the SAME entry point a live ITEM press
	# uses.
	#
	# The roulette's own elapsed-time wait is driven by ONE direct
	# slot.tick(roulette_duration_s) call rather than re-enabling the
	# kart's own _physics_process and waiting out real frames (the shape
	# test_seeded_ai_kart_picks_up_a_box_rolls_and_uses_a_shield_through_
	# real_dispatch uses) -- deliberately: re-enabling movement here would
	# let the kart auto-throttle off toward ItemBoxEast1's own position
	# (430, 1, 297) uncontrolled for over a second, risking an incidental
	# real gate crossing that would desync LapValidator's own "next
	# expected gate" state ahead of this same test's own teleport-finish
	# sequence in step 7. ItemSlot.tick() is plain, self-contained pure
	# logic (see its own class doc: "no signals... reads state back
	# through getters") with no coupling to KartController's motor tick,
	# so calling it directly on the REAL ItemSlot instance
	# item_slot() exposes is exactly as real a proof of the roulette
	# timing as accumulating the same total delta over many small
	# physics-frame calls would be -- the outcome itself was already
	# locked in by start_roll() the instant the real pickup below
	# registers, before this call ever runs (see item_slot.gd's own RNG
	# INJECTION doc: "decided at the rng draw, merely hidden until
	# &held").
	# ------------------------------------------------------------------
	player_kart.set_physics_process(false)
	player_kart.global_position = pickup_box.global_position
	await wait_physics_frames(2)
	var player_slot: Object = player_kart.call("item_slot")
	assert_not_null(player_slot)
	if player_slot == null:
		return
	assert_eq(
		player_slot.call("state"),
		&"rolling",
		"fixture setup: the real pickup must have started a real roll"
	)

	player_slot.call("tick", _catalog.items.roulette_duration_s)
	assert_eq(player_slot.call("state"), &"held")
	assert_eq(
		player_slot.call("held_item"),
		&"bomb",
		"item_rng_seed=%d's own first randf() call must roll bomb (see this file's own _SEED doc)" % _SEED
	)

	var used_item: StringName = race.call("use_item_for", player_kart)
	assert_eq(used_item, &"bomb", "the real use_item_for() dispatch must hand back the held item")
	assert_eq(
		player_slot.call("state"),
		&"empty",
		"a real use() must clear the slot back to empty"
	)

	var hazards := race.get_node_or_null("ItemHazards")
	assert_not_null(hazards, "a real bomb use must spawn the ItemHazards root")
	if hazards != null:
		assert_eq(hazards.get_child_count(), 1, "exactly one hazard must have spawned")
		if hazards.get_child_count() > 0:
			var spawned_hazard := hazards.get_child(0)
			assert_eq(
				spawned_hazard.name,
				"Bomb",
				"the real dispatch must have spawned a real bomb.tscn instance, not a stand-in"
			)

	# ------------------------------------------------------------------
	# 5. APEX-LINE AI DRIVING (Task 4): thaw every AI kart and let the
	# real AiDriver/AiKartAgent pair drive real physics for a bounded
	# window -- the exact same "generously short of a lap, long enough to
	# prove real forward motion" window test_race_flow_e2e.gd's own R5
	# coverage already established as safe on this exact track (90 frames
	# @ 60Hz = 1.5s). Apex offset math itself (curvature-derived lateral
	# blend, steer damping, personality scalars) is unit-proven in
	# test_ai_driver.gd/test_ai_kart_agent.gd; this step's own job is
	# proving THAT driver, unmodified, is what is actually moving these
	# karts in a real race scene.
	# ------------------------------------------------------------------
	for opponent_index in range(opponent_count):
		var thawed_ai_kart := race.call("ai_kart", opponent_index) as CharacterBody3D
		if thawed_ai_kart != null:
			thawed_ai_kart.set_physics_process(true)

	var ai_drive_frames := 90
	await wait_physics_frames(ai_drive_frames)

	var any_ai_progressed := false
	for opponent_index in range(opponent_count):
		if float(race.call("ai_kart_total_progress_m", opponent_index)) > 0.0:
			any_ai_progressed = true
			break
	assert_true(
		any_ai_progressed,
		"at least one AI kart must show real forward progress from real post-GO apex-line driving"
	)
	assert_false(bool(race.call("is_finished")), "fixture sanity: nobody has finished yet")

	# ------------------------------------------------------------------
	# 6. FX WIRING LIVE -- drift sparks during a real AI slide (Task 1).
	# Same "stop the agent's own decision loop, then arm a real slide
	# directly through the kart's own real KartController" technique
	# test_seeded_six_kart_race_a_fired_missile_hits_and_spins_out_a_mid_
	# slide_target_through_the_real_path (test_race_session.gd) already
	# established for forcing a deterministic mid-slide target -- steer()/
	# hop_pressed() mutate the real DriftStateMachine this controller
	# owns, and KartFx (kart_fx.gd) reads that SAME real is_sliding()/
	# boost_stage() every physics tick to drive Sparks.emitting/.color,
	# so this is the real production wiring end to end, not a synthetic
	# double.
	# ------------------------------------------------------------------
	var slide_ai_index := 0
	var slide_ai_kart := race.call("ai_kart", slide_ai_index) as CharacterBody3D
	var slide_ai_agent: Object = race.call("ai_agent", slide_ai_index)
	assert_not_null(slide_ai_kart)
	assert_not_null(slide_ai_agent)
	if slide_ai_kart == null or slide_ai_agent == null:
		return

	slide_ai_agent.call("set_physics_process", false)
	await wait_physics_frames(2)
	assert_true(
		slide_ai_kart.is_on_floor(),
		"fixture setup: the AI kart must be grounded before sliding"
	)
	slide_ai_kart.call("steer", _catalog.kart.slide_min_steer)
	slide_ai_kart.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(
		bool(slide_ai_kart.call("is_sliding")),
		"fixture setup: the AI kart must really be sliding through its own real DriftStateMachine"
	)

	var slide_ai_fx := slide_ai_kart.get_node("Fx")
	var slide_ai_sparks := slide_ai_fx.get_node("Sparks") as GPUParticles3D
	assert_true(
		slide_ai_sparks.emitting,
		"KartFx must be emitting real drift sparks while this AI kart is really sliding"
	)
	var sparks_material := slide_ai_sparks.process_material as ParticleProcessMaterial
	assert_not_null(sparks_material)
	if sparks_material != null:
		assert_eq(
			sparks_material.color,
			_catalog.fx.spark_color_stage1,
			"a fresh slide (boost_stage 0) must show stage 1's own spark color (the CTR exhaust language)"
		)

	# Freeze this kart as a static prop for the rest of the run -- mirrors
	# the missile e2e precedent's own "freeze once armed" shape; it plays
	# no further part in the finish/standings proof below.
	slide_ai_kart.set_physics_process(false)

	# ------------------------------------------------------------------
	# 7. Player teleport-finishes -> real standings() split, with zero
	# genuine AI finishers (same bounded-window reasoning
	# test_race_flow_e2e.gd's own R5 coverage documents: no AI kart could
	# possibly finish a real lap of Sanity Shores within this test's own
	# short drive windows).
	# ------------------------------------------------------------------
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	assert_eq(gate_count, 12, "fixture sanity: Sanity Shores authors 12 gates")
	await _teleport_finish_player(race, player_kart, gate_count, lap_count)

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
			"no AI kart could have genuinely finished inside this test's own bounded drive windows"
		)
		unfinished_count += 1
	assert_eq(unfinished_count, opponent_count, "every AI kart must land as an unfinished standings row")

	var hud := race.get_node("UI/RaceHUD")
	var standings_label := hud.get_node("SafeArea/FinishPanel/Margin/Rows/Standings") as Label
	await wait_process_frames(1)
	assert_true(standings_label.visible, "the finish panel must show the standings list for a race")
	assert_true(standings_label.text.contains("YOU"), "the standings text must include the player's own row")

	# ------------------------------------------------------------------
	# 8. NO ERROR SPAM: zero unhandled push_error/engine-error calls
	# anywhere across this whole seeded run. GUT already fails a test on
	# any unhandled error by default (error_tracker.treat_push_error_as ==
	# TREAT_AS.FAILURE, see addons/gut/error_tracker.gd) -- this assertion
	# makes that contract explicit and visible rather than relying on it
	# silently, per this task's own "capture push_error count = 0" ask.
	#
	# CTR R8 Task 2 (characters/select/classes): the default AI fill (player
	# defaults to &"crash") includes still-fallback-active drivers (cortex/
	# coco/ripper_roo -- their own likeness gates land in Tasks 6-8; papu's
	# own Task 5 flip below moved him out of this set), each producing
	# exactly one push_warning() from DriverRegistry.
	# character_scene()'s own documented FALLBACK path (driver_registry.gd's
	# own class doc) -- an intentional, harmless diagnostic, never a
	# push_error/engine error, and never auto-fails a test on its own (GUT's
	# error_tracker.gd has no push_warning branch in _is_error_failable()).
	# get_errors().size() itself does not consult `handled` at all (that flag
	# only gates GUT's OWN auto-fail check, should_test_fail_from_errors() --
	# a plain .size() on the raw list counts every tracked error regardless),
	# so these expected warnings are excluded from the count below instead.
	#
	# Fix round 2 (reviewer [IMPORTANT]): the exclusion is bounded two ways,
	# not a blanket "any DriverRegistry.character_scene warning" match --
	# that generic match would ALSO have swallowed a future regression where
	# crash or lab_assistant (which must NEVER fall back -- both ship real,
	# gated paths) started falling back, since the warning text is identical
	# regardless of which driver id triggered it. (1) the match string pins
	# the exact driver id right after "driver " for each of the STILL-
	# fallback-active ids only -- a crash/lab_assistant fallback produces a
	# warning that matches NONE of these strings, so it lands in
	# unexpected_errors and fails the assertion below. (2) a second
	# assertion pins the exact expected COUNT (one warning per fallback-
	# active driver for this test's own single race), so losing or
	# gaining a warning among the same ids is caught too, not only an
	# id outside the set.
	#
	# Task 5 (characters/select/classes): papu REMOVED from this list --
	# his DriverEntry now flips to a real gated scene (data/racing/drivers/
	# papu.tres, SK_papu_seated.glb), so DriverRegistry.character_scene()
	# resolves him for real and never reaches _fallback_scene() -- he no
	# longer produces this warning at all. This is tightening the bound to
	# the new honest count (4 -> 3), not weakening it: a regression that
	# made papu fall back again would now show up as an UNEXPECTED warning
	# (id not in the list below) and fail this test loudly.
	# ------------------------------------------------------------------
	const _EXPECTED_FALLBACK_DRIVER_IDS := ["cortex", "coco", "ripper_roo"]
	var unexpected_errors: Array = []
	var expected_fallback_warning_count := 0
	for tracked_error: GutTrackedError in get_errors():
		var matched_expected_fallback := false
		if tracked_error.is_push_warning():
			for expected_id: String in _EXPECTED_FALLBACK_DRIVER_IDS:
				if tracked_error.contains_text(
					"DriverRegistry.character_scene: driver %s " % expected_id
				):
					matched_expected_fallback = true
					break
		if matched_expected_fallback:
			expected_fallback_warning_count += 1
		else:
			unexpected_errors.append(tracked_error)
	assert_eq(
		unexpected_errors.size(),
		0,
		"zero push_error/engine-error calls must occur across the whole seeded R6 run"
	)
	assert_eq(
		expected_fallback_warning_count,
		3,
		(
			"exactly one fallback push_warning per still-fallback-active AI "
			+ "driver (cortex/coco/ripper_roo) for this test's single "
			+ "race -- a different count means either a fallback-active "
			+ "driver went real (update this bound) or a NEW driver started "
			+ "falling back unexpectedly (a real regression)"
		)
	)
