extends GutTest

# R5 Task 2: session + HUD level coverage for the live "POS n / m" ranking
# system -- race_session.gd's real wiring of RaceRanking against the real
# graybox loop scene (AI-finishes-first freezing its own rank slot while it
# keeps driving, player_position()/field_size() correctness in a seeded
# multi-kart arrangement) and race_hud.gd's own live display (updates as
# positions change, hidden pre-GO/solo/post-finish). The pure composite-sort
# contract itself is test_race_ranking.gd's own job -- this file proves the
# REAL scene wiring, the same "boot the real scene, drive it via its real
# API" shape every other race_session-level suite in this codebase uses.

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


func _catalog_with_opponent_count(count: int) -> GameplayTuning:
	var variant: GameplayTuning = _catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	variant.ai.opponent_count = float(count)
	return variant


## Same shape as test_race_session.gd's own _boot_race_with_catalog(), just
## redefined locally -- GUT test scripts don't share private helpers across
## files.
func _boot_race(catalog: GameplayTuning) -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", catalog)
	race.call("_tick_countdown", 1000.0)
	return race


## Deliberately does NOT skip the countdown -- for the pre-GO hidden test.
func _boot_race_pre_go(catalog: GameplayTuning) -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
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


## Same technique as test_race_session.gd's own _force_finish(), generalized
## to any kart (not just the player) -- one full lap_count laps' worth of
## crossings plus the final gate-0 closing crossing, driven directly through
## the session's own private gate-crossing handler rather than a real Area3D
## overlap.
func _cross_all_gates_for_kart(
	race: Node, kart: Node, lap_count: int, gate_count: int
) -> void:
	for _lap in range(lap_count):
		for gate_index in range(gate_count):
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


func _position_label(race: Node) -> Label:
	var hud := race.get_node("UI/RaceHUD")
	return hud.get_node("SafeArea/Stats/Margin/Rows/Position") as Label


## Same nested loop _cross_all_gates_for_kart() above uses, but WITHOUT the
## trailing gate-0 closing crossing -- leaves the given kart's own validator
## waiting on exactly one more gate-0 crossing to complete the race, so a
## test can fire that final crossing itself (for two different karts, back
## to back, with no await between the calls) to pin an exact same-tick
## dispatch order.
func _drive_kart_to_final_gate(
	race: Node, kart: Node, lap_count: int, gate_count: int
) -> void:
	for _lap in range(lap_count):
		for gate_index in range(gate_count):
			race.call(
				"_on_gate_body_entered",
				kart,
				race.get_node("Track/Gates/Gate%d" % gate_index)
			)


# ---------------------------------------------------------------------------
# AI-finishes-first: its own finish order/elapsed get recorded, and its own
# live rank freezes at 1st even though the kart keeps being driven (more
# laps banked) afterward.
# ---------------------------------------------------------------------------


func test_ai_finishing_first_freezes_its_own_rank_while_it_keeps_driving() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))

	# A couple of real ticks first so elapsed_s() has actually advanced past
	# 0.0 by the time the synthetic finish below records it -- crossing the
	# gates on the very same tick the countdown was skipped would record a
	# fixture-artifact 0.0, not a real elapsed reading.
	await wait_physics_frames(2)

	assert_eq(
		int(race.call("finish_order_of", ai_kart)),
		-1,
		"fixture sanity: the AI kart must not be finished yet"
	)

	_cross_all_gates_for_kart(race, ai_kart, lap_count, gate_count)
	await wait_physics_frames(2)

	assert_eq(
		int(race.call("finish_order_of", ai_kart)),
		1,
		"the AI kart's own first race_complete crossing must record finish order 1"
	)
	assert_gt(
		float(race.call("finish_elapsed_s_of", ai_kart)),
		0.0,
		"the AI kart's own finish elapsed_s must have been recorded as a real, positive time"
	)
	assert_eq(
		int(race.call("kart_position", ai_kart)),
		1,
		"a finished kart with nobody finished ahead of it must rank 1st"
	)
	assert_gt(
		int(race.call("player_position")),
		1,
		"the still-unfinished player must not outrank a kart that has already finished"
	)
	assert_false(bool(race.call("is_finished")), "the SESSION itself must not be finished -- only the player's own crossing ends the race")

	# The AI kart keeps being "driven" -- several more full laps' worth of
	# gate crossings, each of which reports &"race_complete" again
	# (LapValidator's own _laps_completed has no upper clamp, see lap_
	# validator.gd's SEQUENCE doc) -- none of this may ever move its own
	# rank or overwrite its recorded finish order/elapsed.
	var recorded_elapsed := float(race.call("finish_elapsed_s_of", ai_kart))
	for _extra_lap in range(3):
		_cross_all_gates_for_kart(race, ai_kart, 1, gate_count)
	await wait_physics_frames(2)

	assert_eq(
		int(race.call("finish_order_of", ai_kart)),
		1,
		"finish_order_of() must stay pinned at the kart's TRUE first finish"
	)
	assert_eq(
		float(race.call("finish_elapsed_s_of", ai_kart)),
		recorded_elapsed,
		"finish_elapsed_s_of() must never be overwritten by a later race_complete report from the same kart"
	)
	assert_eq(
		int(race.call("kart_position", ai_kart)),
		1,
		"the AI kart's own rank must stay frozen at 1st even after banking several more laps post-finish"
	)


# ---------------------------------------------------------------------------
# player_position()/field_size() correctness in a seeded 6-kart mid-race
# arrangement (1 player + 5 AI, every kart's own total_progress_m pinned by
# seeding its follower directly and freezing its own agent so nothing drifts
# while the assertions run).
# ---------------------------------------------------------------------------


func test_player_position_in_a_seeded_six_kart_arrangement() -> void:
	var race := _boot_race(_catalog_with_opponent_count(5))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# Freeze the player's own kart so its total_progress_m stays pinned at
	# spawn for the whole test -- karts auto-throttle forward under their
	# own set_run_active(true) motor tick otherwise (see race_session.gd's
	# own _finish_race() doc: "driving into the walls... under its own
	# auto-throttle").
	kart.set_physics_process(false)

	var player_progress := float(race.call("player_total_progress_m"))
	# ai0 furthest ahead ... ai4 furthest behind, straddling the player.
	var offsets_m: Array[float] = [50.0, 30.0, 10.0, -10.0, -30.0]
	var ai_karts: Array[CharacterBody3D] = []
	for index in range(offsets_m.size()):
		var ai_kart := race.call("ai_kart", index) as CharacterBody3D
		var agent: Object = race.call("ai_agent", index)
		assert_not_null(ai_kart)
		assert_not_null(agent)
		if ai_kart == null or agent == null:
			return
		ai_karts.append(ai_kart)
		# Freeze this agent's own ticking so its seeded follower total below
		# never drifts back toward its real (unmoved) spawn position -- see
		# the class doc-equivalent rationale test_race_session.gd's own
		# placement tests already establish for this exact white-box
		# technique (agent.get("_follower")).
		(agent as Node).set_physics_process(false)
		var follower: RefCounted = agent.get("_follower")
		assert_not_null(follower)
		if follower == null:
			return
		follower.reset(player_progress + offsets_m[index])

	await wait_physics_frames(2)

	assert_eq(int(race.call("field_size")), 6, "1 player + 5 AI karts")
	assert_eq(
		int(race.call("player_position")),
		4,
		"with two AI karts ahead (offsets +50/+30/+10 -- three ahead) and two behind (-10/-30), the player must rank exactly where its own total_progress_m falls in the sorted field"
	)
	assert_eq(int(race.call("kart_position", ai_karts[0])), 1)
	assert_eq(int(race.call("kart_position", ai_karts[1])), 2)
	assert_eq(int(race.call("kart_position", ai_karts[2])), 3)
	assert_eq(int(race.call("kart_position", ai_karts[3])), 5)
	assert_eq(int(race.call("kart_position", ai_karts[4])), 6)


# ---------------------------------------------------------------------------
# Live HUD: the "POS n / m" line updates as the player overtakes an AI kart,
# driven by a real teleport plus enough real physics ticks for SpineFollower's
# own rate limiter to ramp the change through (not a synthetic one-shot read).
# ---------------------------------------------------------------------------


func test_hud_position_label_updates_live_as_the_player_overtakes_an_ai_kart() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	var agent: Object = race.call("ai_agent", 0)
	var spine := race.get_node("Track/Spine") as TrackSpine
	assert_not_null(ai_kart)
	assert_not_null(agent)
	assert_not_null(spine)
	if ai_kart == null or agent == null or spine == null:
		return
	var label := _position_label(race)
	assert_not_null(label, "fixture setup: race_hud.tscn must author the Position label")
	if label == null:
		return

	# Freeze the AI kart's own agent so its seeded lead below stays pinned
	# while the player's own follower ramps below -- see the six-kart test's
	# own identical rationale.
	(agent as Node).set_physics_process(false)
	var follower: RefCounted = agent.get("_follower")
	assert_not_null(follower)
	if follower == null:
		return
	var gap_m := 5.0
	var ahead_progress: float = float(race.call("player_total_progress_m")) + gap_m
	follower.reset(ahead_progress)

	await wait_physics_frames(2)
	await wait_process_frames(1)

	assert_true(
		label.visible,
		"the live position line must show once the field has more than one kart, post-GO"
	)
	assert_eq(
		label.text,
		"POS  2 / 2",
		"the player must read 2nd while the AI kart leads it in total_progress_m"
	)

	# Teleport the player past the AI kart's own seeded lead, then let real
	# physics ticks run -- SpineFollower.update() rate-limits how much of a
	# single jump registers per tick (see spine_follower.gd's own ALGORITHM
	# doc), so this waits a generously bounded number of REAL ticks for the
	# player's own follower to ramp all the way up rather than asserting on
	# the very next tick.
	kart.set_physics_process(false)
	var overtake_margin_m := 5.0
	var target_progress := ahead_progress + overtake_margin_m
	var wrapped_target := fposmod(target_progress, spine.length_m())
	kart.global_position = spine.point_at_progress(wrapped_target)

	var travel_m: float = target_progress - float(race.call("player_total_progress_m"))
	var max_step_m: float = (
		(_kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps)
		/ float(Engine.physics_ticks_per_second)
	)
	var margin_frames := 20
	var frames_needed := int(ceil(travel_m / max_step_m)) + margin_frames
	await wait_physics_frames(frames_needed)
	await wait_process_frames(1)

	assert_eq(
		int(race.call("player_position")),
		1,
		"fixture sanity: the player must have actually overtaken the AI kart's own seeded progress by now"
	)
	assert_eq(
		label.text,
		"POS  1 / 2",
		"the HUD's live position line must track the overtake once the player's own live ranking flips to 1st"
	)


# ---------------------------------------------------------------------------
# Hidden pre-GO, hidden for a solo race, hidden again once the race finishes.
# ---------------------------------------------------------------------------


func test_hud_position_label_is_hidden_pre_go() -> void:
	var race := _boot_race_pre_go(_catalog)
	if race == null:
		return
	var label := _position_label(race)
	assert_not_null(label)
	if label == null:
		return

	await wait_process_frames(1)

	assert_false(
		bool(race.call("is_race_started")),
		"fixture sanity: still pre-GO"
	)
	assert_false(
		label.visible,
		"the live position line must stay hidden before GO"
	)


func test_hud_position_label_is_hidden_for_a_solo_race() -> void:
	var race := _boot_race(_catalog_with_opponent_count(0))
	if race == null:
		return
	var label := _position_label(race)
	assert_not_null(label)
	if label == null:
		return

	await wait_process_frames(1)

	assert_eq(int(race.call("field_size")), 1, "fixture sanity: nobody to rank the player against")
	assert_false(
		label.visible,
		"a solo race has nobody to rank against -- the live position line must stay hidden"
	)


func test_hud_position_label_hides_again_once_the_race_finishes() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var label := _position_label(race)
	assert_not_null(label)
	if label == null:
		return
	await wait_process_frames(1)
	assert_true(label.visible, "fixture sanity: visible mid-race with a real field")

	var kart := race.get_node("Kart")
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	_cross_all_gates_for_kart(race, kart, lap_count, gate_count)
	await wait_process_frames(1)

	assert_true(bool(race.call("is_finished")), "fixture setup: the player must have finished")
	assert_false(
		label.visible,
		"the live position line must hide again once the race is finished -- the FINISHED panel takes over"
	)


# ---------------------------------------------------------------------------
# Fix round 1, reviewer [MEDIUM]: same-tick photo finish. The player and an
# AI kart both cross their own final gate in the SAME physics dispatch --
# calling the private handler directly, back to back with no await between
# the two calls, pins the exact dispatch order deterministically (this is
# exactly what a real same-tick Area3D dispatch looks like from the
# session's own point of view: two callbacks running one after the other,
# no ticks in between). Before this fix, a player-first ordering silently
# dropped the AI's own already-in-flight race_complete -- _finished flipped
# true inside the player's own callback, and the AI's callback (dispatched
# second, this identical tick) hit the unconditional `if _finished: return`
# guard and never reached its own validator at all.
# ---------------------------------------------------------------------------


func test_same_tick_photo_finish_player_first_still_records_the_ai() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var kart := race.get_node("Kart")
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	var gate0 := race.get_node("Track/Gates/Gate0")

	await wait_physics_frames(2)
	_drive_kart_to_final_gate(race, kart, lap_count, gate_count)
	_drive_kart_to_final_gate(race, ai_kart, lap_count, gate_count)
	assert_false(
		bool(race.call("is_finished")),
		"fixture sanity: neither kart has crossed its own FINAL gate yet"
	)

	# The player's own callback dispatches first this "tick".
	race.call("_on_gate_body_entered", kart, gate0)
	assert_true(
		bool(race.call("is_finished")),
		"fixture setup: the player's own crossing must have ended the race"
	)
	var player_elapsed := float(race.call("finish_elapsed_s_of", kart))
	assert_eq(int(race.call("finish_order_of", kart)), 1)

	# The AI's own already-in-flight crossing dispatches second, this SAME
	# tick -- must still be recorded, not silently dropped by _finished now
	# being true.
	race.call("_on_gate_body_entered", ai_kart, gate0)

	assert_eq(
		int(race.call("finish_order_of", ai_kart)),
		2,
		"the AI's own same-tick crossing must still be recorded, one slot behind the player -- this is the bug this fix closes"
	)
	assert_eq(
		float(race.call("finish_elapsed_s_of", ai_kart)),
		player_elapsed,
		"a genuine same-tick photo finish must capture the identical elapsed_s() for both karts -- no real time passed between the two calls"
	)


func test_same_tick_photo_finish_ai_first_still_orders_correctly() -> void:
	var race := _boot_race(_catalog_with_opponent_count(1))
	if race == null:
		return
	var kart := race.get_node("Kart")
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var gate_count := int(race.call("gate_count"))
	var lap_count := int(race.call("lap_count"))
	var gate0 := race.get_node("Track/Gates/Gate0")

	await wait_physics_frames(2)
	_drive_kart_to_final_gate(race, kart, lap_count, gate_count)
	_drive_kart_to_final_gate(race, ai_kart, lap_count, gate_count)

	# Mirror ordering: the AI's own callback dispatches FIRST this "tick" --
	# the pre-existing, unmodified-by-this-fix path (the AI finishes before
	# _finished is ever set, same as the earlier AI-finishes-first test),
	# pinned here to prove the fix did not disturb it.
	race.call("_on_gate_body_entered", ai_kart, gate0)
	assert_false(
		bool(race.call("is_finished")),
		"fixture sanity: an AI kart finishing on its own does not end the session"
	)
	assert_eq(int(race.call("finish_order_of", ai_kart)), 1)
	var ai_elapsed := float(race.call("finish_elapsed_s_of", ai_kart))

	# The player's own crossing dispatches second, this SAME tick.
	race.call("_on_gate_body_entered", kart, gate0)

	assert_true(bool(race.call("is_finished")))
	assert_eq(
		int(race.call("finish_order_of", kart)),
		2,
		"the player's own crossing arriving second this same tick must still record it as 2nd, behind the AI"
	)
	assert_eq(
		float(race.call("finish_elapsed_s_of", kart)),
		ai_elapsed,
		"a genuine same-tick photo finish must capture the identical elapsed_s() for both karts"
	)
