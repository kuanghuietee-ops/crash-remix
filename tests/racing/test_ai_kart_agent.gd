extends GutTest

# Task 4 (CTR R3: AI opponents) -- AiKartAgent is the Node glue that owns a
# real KartController + TrackSpine + SpineFollower + AiDriver and drives the
# kart every physics tick through the SAME KartController API a human uses
# (steer()/set_brake()/hop_pressed()/hop_released()/boost_tap()/
# set_speed_scale()). See ai_kart_agent.gd's class doc and .superpowers/sdd/
# 2026-07-30-ctr-r3-ai-karts/task-4-brief.md.
#
# Mirrors this suite's existing "real scene, real physics" testing style
# (test_kart_controller.gd, test_race_session.gd) rather than mocking the
# controller -- AiKartAgent's whole point is driving the REAL pipeline.

const AGENT_SCRIPT_PATH := "res://src/racing/ai/ai_kart_agent.gd"
const KART_SCENE_PATH := "res://scenes/racing/kart.tscn"
const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const SPINE_SCRIPT_PATH := "res://src/racing/track/track_spine.gd"

# The same L-shaped closed loop test_track_spine.gd uses -- straight legs
# make hand-reasoned expectations (which leg a given progress sits on, what
# its tangent must be) exact, and corner B (offset 100, leg A->B -> leg B->C)
# is a >90-degree bend, comfortably past ai.tres's slide_trigger_curvature
# over a short lookahead.
const _L_SHAPED_POINTS: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(0, 0, -100),
	Vector3(50, 0, -100),
	Vector3(50, 0, -50),
	Vector3(100, 0, -50),
	Vector3(100, 0, 0),
]

var _catalog: GameplayTuning
var _ai_tuning: AiTuning
var _kart_tuning: KartTuning
var _race_tuning: RaceTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")
	_ai_tuning = _catalog.ai
	_kart_tuning = _catalog.kart
	_race_tuning = _catalog.race


# ---------------------------------------------------------------------------
# Centerpiece 1: a real, agent-driven kart on the real graybox loop drives
# ITSELF around the first corner -- real physics, no teleporting. Follower
# total progress must strictly increase (sampled at intervals, not
# tick-by-tick -- see the assertion loop's own comment) and clear a
# meaningful distance threshold, proving it actually rounded the corner
# rather than crept forward a few centimeters.
# ---------------------------------------------------------------------------


func test_agent_drives_a_real_kart_around_the_graybox_loops_first_corner() -> void:
	var boot := _boot_real_race()
	if boot.is_empty():
		return
	var kart: CharacterBody3D = boot["kart"]
	var spine: TrackSpine = boot["spine"]

	var agent := _new_agent()
	agent.call(
		"configure",
		kart,
		spine,
		_ai_tuning,
		_kart_tuning,
		_race_tuning,
		3,
		func() -> float: return 0.0
	)

	# Window chosen to comfortably clear the East turn's own entry arc (real
	# physics traced by hand while writing this test: the kart accelerates
	# down the south straight, hops into a slide around x=40, and tracks the
	# turn's own inner curve cleanly through this whole window) while
	# staying short of where a LONG sustained slide through this
	# particular, fairly gentle-radius turn starts to fight this graybox
	# loop's inner-wall clearance -- a real, separate finding about this
	# corner's geometry vs. the shipped AiDriver/DriftStateMachine tuning
	# (see the task report), not a wiring bug: the same oscillation appears
	# regardless of lateral slot offset, and this agent's own stuck-respawn
	# correctly recovers from it a few seconds later. This test's job is
	# proving the agent drives itself for real, not grading the racing line.
	var samples: Array[float] = [float(agent.call("total_progress_m"))]
	var batch_frames := 30
	var batches := 10
	for _batch_index in range(batches):
		await wait_physics_frames(batch_frames)
		samples.append(float(agent.call("total_progress_m")))

	for sample_index in range(1, samples.size()):
		assert_gt(
			samples[sample_index],
			samples[sample_index - 1],
			(
				"follower total progress must strictly increase every ~0.5s "
				+ "sample (index %d): %s -> %s"
			) % [sample_index, samples[sample_index - 1], samples[sample_index]]
		)

	assert_gt(
		samples[-1] - samples[0],
		50.0,
		(
			"the agent must have covered a meaningful distance under its own "
			+ "steering -- well into the first corner, not just crept forward -- "
			+ "got %s m over %s s"
		) % [samples[-1] - samples[0], float(batch_frames * batches) / float(Engine.physics_ticks_per_second)]
	)


# ---------------------------------------------------------------------------
# Centerpiece 2: speed_scale must reach the REAL motor. A kart that never
# calls set_speed_scale() can never exceed its own tuned top_speed_mps (
# move_toward never overshoots) -- so any sustained overspeed here is only
# possible if AiDriver's rubber-band output genuinely made it through
# AiKartAgent -> KartController.set_speed_scale() -> KartMotor.
# ---------------------------------------------------------------------------


func test_speed_scale_reaches_the_real_motor_when_rubber_banding_far_behind() -> void:
	var spine := _new_l_shaped_spine()
	# 20m down the long A->B leg (straight, tangent (0,0,-1)) -- far from
	# either corner so cornering/braking never interferes with this test's
	# pure speed measurement.
	var kart := _spawn_kart_on_floor(Vector3(0.0, 0.2, -20.0))
	if kart == null:
		return

	var agent := _new_agent()
	# A constant, enormous "player progress" keeps band_gap_m saturated at
	# rubber_band_full_gap_m (or beyond) for the whole run regardless of how
	# far this kart itself travels -- the AI must rubber-band at its capped
	# maximum the entire time.
	agent.call(
		"configure",
		kart,
		spine,
		_ai_tuning,
		_kart_tuning,
		_race_tuning,
		1,
		func() -> float: return 100000.0
	)

	await wait_physics_frames(180)

	assert_gt(
		float(kart.call("speed_mps")),
		_kart_tuning.top_speed_mps,
		(
			"a rubber-banding-far-behind AI kart must exceed its own tuned "
			+ "top_speed_mps -- impossible unless set_speed_scale() reached "
			+ "the real KartMotor"
		)
	)


# ---------------------------------------------------------------------------
# Centerpiece 3: a kart with zero real velocity for respawn_stuck_after_s
# must teleport onto the centerline (progress - respawn_drop_gap_m), at
# RaceTuning.respawn_drop_height_m above it, facing the tangent -- and the
# motor's own speed must be reset, not carried over.
# ---------------------------------------------------------------------------


func test_stuck_kart_teleports_onto_the_centerline_facing_the_tangent() -> void:
	var spine := _new_l_shaped_spine()
	var kart := _spawn_kart_on_floor(Vector3(0.0, 0.2, -30.0))
	if kart == null:
		return
	# Freezes the kart's OWN _physics_process entirely -- velocity stays
	# pinned at Vector3.ZERO (CharacterBody3D's own default) for the whole
	# test, the simplest deterministic stand-in for "physically wedged
	# against scenery, motor trying but real velocity reads ~0".
	kart.set_physics_process(false)

	var agent := _new_agent()
	agent.call(
		"configure",
		kart,
		spine,
		_ai_tuning,
		_kart_tuning,
		_race_tuning,
		1,
		func() -> float: return 0.0
	)
	var progress_before: float = agent.call("total_progress_m")
	assert_almost_eq(
		progress_before,
		30.0,
		0.5,
		"fixture sanity: configure() must seed the follower from the kart's real spawn progress"
	)

	var physics_fps := float(Engine.physics_ticks_per_second)
	var frames_needed := int(ceil(_ai_tuning.respawn_stuck_after_s * physics_fps)) + 15
	await wait_physics_frames(frames_needed)

	var expected_target_progress := progress_before - _ai_tuning.respawn_drop_gap_m
	assert_almost_eq(
		float(agent.call("total_progress_m")),
		expected_target_progress,
		0.5,
		"the follower's own total must be reset to (progress - respawn_drop_gap_m)"
	)
	assert_almost_eq(
		kart.global_position.x,
		0.0,
		0.5,
		"the respawn point must sit back on leg A->B's centerline (x=0)"
	)
	assert_almost_eq(
		kart.global_position.z,
		-expected_target_progress,
		0.5,
		"the respawn point must sit expected_target_progress meters down leg A->B"
	)
	assert_almost_eq(
		kart.global_position.y,
		_race_tuning.respawn_drop_height_m,
		0.05,
		"the respawn drop height must come from RaceTuning.respawn_drop_height_m"
	)
	var actual_forward: Vector3 = -kart.global_transform.basis.z
	assert_true(
		actual_forward.is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"the respawned kart must face the spine's own tangent direction, got %s" % actual_forward
	)
	assert_almost_eq(
		float(kart.call("speed_mps")),
		0.0,
		0.0001,
		"reset_speed() must have zeroed the real motor's forward speed"
	)


# ---------------------------------------------------------------------------
# Hop edge routing: a sharp corner must fire a real hop_pressed() edge that
# starts the REAL DriftStateMachine's slide, and the held latch must release
# again within a few ticks (not stay pressed forever).
# ---------------------------------------------------------------------------


func test_hop_edge_starts_a_real_slide_on_a_sharp_corner_and_releases_the_latch() -> void:
	var spine := _new_l_shaped_spine()
	# 10m before corner B (offset 100) on leg A->B -- close enough that the
	# tuned lookahead comfortably reaches past the corner.
	var kart := _spawn_kart_on_floor(Vector3(0.0, 0.2, -90.0))
	if kart == null:
		return

	var agent := _new_agent()
	agent.call(
		"configure",
		kart,
		spine,
		_ai_tuning,
		_kart_tuning,
		_race_tuning,
		1,
		func() -> float: return 0.0
	)

	var became_sliding := false
	for _attempt in range(30):
		await wait_physics_frames(1)
		if bool(kart.call("is_sliding")):
			became_sliding = true
			break
	assert_true(
		became_sliding,
		"the agent must hop into a real slide as it approaches this >90-degree corner"
	)

	var drift: RefCounted = kart.get("_drift")
	assert_not_null(drift, "fixture introspection: the controller must still own its private drift FSM")
	if drift == null:
		return
	var released := false
	for _attempt in range(10):
		await wait_physics_frames(1)
		if not bool(drift.get("_hop_held")):
			released = true
			break
	assert_true(
		released,
		"hop_released() must fire within a few ticks of the press -- the latch must not stay held forever"
	)


# ---------------------------------------------------------------------------
# Lateral slot centering: pure calculation, no physics ticks needed.
# ---------------------------------------------------------------------------


func test_lateral_target_centers_across_opponent_count_plus_one_total_karts() -> void:
	var spine := _new_l_shaped_spine()
	var kart := CharacterBody3D.new()
	add_child_autofree(kart)

	var low_slot_agent := _new_agent()
	low_slot_agent.call(
		"configure", kart, spine, _ai_tuning, _kart_tuning, _race_tuning, 1, func() -> float: return 0.0
	)
	var high_slot_agent := _new_agent()
	high_slot_agent.call(
		"configure", kart, spine, _ai_tuning, _kart_tuning, _race_tuning, 5, func() -> float: return 0.0
	)

	var total_karts := _ai_tuning.opponent_count + 1.0
	var expected_low := (1.0 - (total_karts - 1.0) / 2.0) * _ai_tuning.lateral_slot_spacing_m
	var expected_high := (5.0 - (total_karts - 1.0) / 2.0) * _ai_tuning.lateral_slot_spacing_m

	assert_almost_eq(
		float(low_slot_agent.get("_lateral_target_m")),
		expected_low,
		0.0001
	)
	assert_almost_eq(
		float(high_slot_agent.get("_lateral_target_m")),
		expected_high,
		0.0001
	)
	assert_true(
		float(low_slot_agent.get("_lateral_target_m")) < float(high_slot_agent.get("_lateral_target_m")),
		"a higher slot index must sit further to the centered field's other side"
	)


# ---------------------------------------------------------------------------
# Fail-closed: a physics tick before configure() must not crash.
# ---------------------------------------------------------------------------


func test_physics_process_is_a_no_op_before_configure() -> void:
	var agent := _new_agent()

	await wait_physics_frames(3)

	assert_almost_eq(
		float(agent.call("total_progress_m")),
		0.0,
		0.0001,
		"an unconfigured agent must report zero progress and never error"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_agent() -> Node:
	var script: Script = load(AGENT_SCRIPT_PATH)
	assert_not_null(script, "AiKartAgent implementation must exist")
	var agent: Node = script.new()
	add_child_autofree(agent)
	return agent


func _new_l_shaped_spine() -> Node:
	var spine: Node = load(SPINE_SCRIPT_PATH).new()
	for point in _L_SHAPED_POINTS:
		var marker := Marker3D.new()
		marker.position = point
		spine.add_child(marker)
	add_child_autofree(spine)
	return spine


func _spawn_kart_on_floor(origin: Vector3) -> CharacterBody3D:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null

	var root := Node3D.new()
	add_child_autofree(root)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor)

	var kart := packed.instantiate() as CharacterBody3D
	assert_not_null(kart)
	if kart == null:
		return null
	kart.position = origin
	root.add_child(kart)
	kart.call("configure", _kart_tuning)
	return kart


## Boots the REAL race_time_trial.tscn (mirrors test_race_session.gd's own
## _boot_race()) and disables the session's OWN input-routing tick so it
## doesn't fight AiKartAgent's steer()/set_brake() calls on the same real
## Kart node -- the session's gate/lap/HUD wiring is irrelevant to this
## suite and is left fully intact, only its per-tick _route_input() is
## silenced (race.set_physics_process(false), the exact technique test_race_
## session.gd's own H2 fix-round tests already establish for isolating a
## kart's real physics from the session's input routing).
func _boot_real_race() -> Dictionary:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH), "race_time_trial.tscn must exist")
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return {}
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return {}
	var race := packed.instantiate()
	add_child_autofree(race)
	race.call("configure", _catalog)
	race.set_physics_process(false)

	var kart := race.get_node("Kart") as CharacterBody3D
	var spine := race.get_node("Track/Spine") as TrackSpine
	return {"race": race, "kart": kart, "spine": spine}
