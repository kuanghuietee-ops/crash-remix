extends GutTest

# Task 1 (CTR R7, discharges spec debt #2): RaceSession's own PAD WIRING --
# discovery, per-pad bound handlers, the real apply_boost()/launch() hand-
# off, and the pad's own try_consume() cooldown reached through the real
# session. Mirrors test_race_session.gd's own ITEM BOX section shape almost
# exactly (see race_session.gd's own PAD WIRING class doc for the two real
# differences: a per-pad bound handler, and no per-kart routing table).
#
# Split into its own file the same way test_race_session_sanity_shores.gd
# is split off -- this is a new, self-contained concern (pads), not a
# regression risk against the already-large item/gate suite in test_race_
# session.gd.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const BOOST_PAD_SCENE_PATH := "res://scenes/racing/boost_pad.tscn"
const JUMP_PAD_SCENE_PATH := "res://scenes/racing/jump_pad.tscn"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


# R5 Task 1: see test_race_session.gd's identical helper for the full
# rationale -- karts spawn frozen through a real pre-race countdown.
const _COUNTDOWN_SKIP_DELTA_S := 1000.0


func _skip_pre_race_countdown(race: Node) -> void:
	race.call("_tick_countdown", _COUNTDOWN_SKIP_DELTA_S)


# ---------------------------------------------------------------------------
# Discovery: pre-Task-4, the real graybox loop authored zero pads --
# _discover_boost_pads()/_discover_jump_pads() had to degrade cleanly, and a
# synthetic pad under Track had to be picked up the same way a synthetic
# ItemBox already is (still true, still proven below). Task 4 (CTR R7)
# retrofitted ONE boost strip onto the real graybox loop's own main straight
# (no jump pad -- spec keeps jump pads Temple-Twilight-only), so the "zero"
# expectation this test's own name/docstring used to pin is updated here,
# not weakened: the discovery mechanism is proven the same way, just against
# the new real count instead of a placeholder zero.
# ---------------------------------------------------------------------------


func test_the_real_graybox_loop_authors_one_boost_pad_and_zero_jump_pads() -> void:
	var race := _boot_race()
	if race == null:
		return
	assert_eq(
		int(race.call("boost_pad_count")),
		1,
		"Task 4 (CTR R7) retrofitted one boost strip onto the graybox loop's own main straight"
	)
	assert_eq(
		int(race.call("jump_pad_count")),
		0,
		"jump pads stay Temple-Twilight-only per spec -- no track other than Temple authors one"
	)


func test_a_synthetic_boost_pad_under_track_is_discovered_and_configured() -> void:
	var setup := _boot_race_with_synthetic_pads()
	var race: Node = setup.get("race")
	if race == null:
		return
	# Task 4 (CTR R7): the real graybox loop now authors its own one real
	# boost pad (see test_the_real_graybox_loop_authors_one_boost_pad_and_
	# zero_jump_pads above) -- this test's own synthetic pad is a SECOND
	# boost pad discovered on top of that real one, so the expected count
	# is 2, not 1. The jump pad count stays 1: the real track authors zero,
	# this test's own synthetic jump pad is the only one.
	assert_eq(int(race.call("boost_pad_count")), 2)
	assert_eq(int(race.call("jump_pad_count")), 1)


# ---------------------------------------------------------------------------
# Firing: a real pad overlap reaches the real kart's own motor.
# ---------------------------------------------------------------------------


func test_player_kart_entering_a_synthetic_boost_pad_boosts_the_real_motor() -> void:
	var setup := _boot_race_with_synthetic_pads()
	var race: Node = setup.get("race")
	var boost_pad: Area3D = setup.get("boost_pad")
	if race == null or boost_pad == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_false(bool(motor.call("is_boosting")), "fixture sanity: no boost yet")

	# Brief teleport-detection window with the kart's own physics disabled,
	# the exact same technique test_race_session.gd's own item-box pickup
	# test uses so the real Area3D overlap fires cleanly without the
	# motor's own tick immediately starting to decay the boost mid-test.
	kart.set_physics_process(false)
	kart.global_position = boost_pad.global_position
	await wait_physics_frames(2)

	assert_true(
		bool(motor.call("is_boosting")),
		"a real overlap with an active boost pad must apply boost to the real motor"
	)
	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		_catalog.race.pad_boost_s,
		0.1
	)


func test_player_kart_entering_a_synthetic_jump_pad_launches_the_real_motor() -> void:
	var setup := _boot_race_with_synthetic_pads()
	var race: Node = setup.get("race")
	var jump_pad: Area3D = setup.get("jump_pad")
	if race == null or jump_pad == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return
	assert_almost_eq(
		float(motor.call("vertical_speed_mps")),
		0.0,
		0.01,
		"fixture sanity: a settled kart must have no residual vertical speed"
	)

	kart.set_physics_process(false)
	kart.global_position = jump_pad.global_position
	await wait_physics_frames(2)

	assert_gt(
		float(motor.call("vertical_speed_mps")),
		0.0,
		"a real overlap with an active jump pad must launch the real motor upward"
	)


## Binding-contract-2-style identity routing (the same "route by WHICH BODY
## entered, never a hardcoded player assumption" shape gate/box routing
## already prove): an AI kart's own overlap must boost ITS OWN motor, never
## the player's.
func test_ai_kart_entering_a_synthetic_boost_pad_boosts_its_own_motor_not_the_players() -> void:
	var setup := _boot_race_with_synthetic_pads(Vector3(200.0, 0.0, 200.0))
	var race: Node = setup.get("race")
	var boost_pad: Area3D = setup.get("boost_pad")
	if race == null or boost_pad == null:
		return
	var ai_kart := race.call("ai_kart", 0) as CharacterBody3D
	assert_not_null(ai_kart, "fixture setup: slot 1's AI kart must exist")
	if ai_kart == null:
		return
	var ai_motor: RefCounted = ai_kart.get("_motor")
	var player_motor: RefCounted = (race.get_node("Kart") as CharacterBody3D).get("_motor")
	assert_not_null(ai_motor)
	assert_not_null(player_motor)
	if ai_motor == null or player_motor == null:
		return

	ai_kart.set_physics_process(false)
	ai_kart.global_position = boost_pad.global_position
	await wait_physics_frames(2)

	assert_true(
		bool(ai_motor.call("is_boosting")),
		"an AI kart entering an active boost pad must boost ITS OWN real motor"
	)
	assert_false(
		bool(player_motor.call("is_boosting")),
		"the player's own motor must be completely untouched by an AI kart's pad hit"
	)


# ---------------------------------------------------------------------------
# Cooldown: reached through the real session-owned pad, driven via a direct
# handler call (the exact same "call the session's own connected handler
# directly, synthetically" technique test_race_start_flow.gd's own pre-GO
# tests use for gates/boxes) -- proves the SAME pad, hit twice in immediate
# succession, only actually fires once through the real session wiring.
# ---------------------------------------------------------------------------


func test_a_boost_pad_hit_twice_in_immediate_succession_only_fires_once() -> void:
	var setup := _boot_race_with_synthetic_pads()
	var race: Node = setup.get("race")
	var boost_pad: Area3D = setup.get("boost_pad")
	if race == null or boost_pad == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	var motor: RefCounted = kart.get("_motor")
	assert_not_null(motor)
	if motor == null:
		return

	race.call("_on_boost_pad_body_entered", kart, boost_pad)
	var boost_after_first_hit := float(motor.call("boost_time_remaining_s"))
	assert_almost_eq(
		boost_after_first_hit,
		_catalog.race.pad_boost_s,
		0.1,
		"fixture setup: the first hit must apply a full pad_boost_s"
	)

	race.call("_on_boost_pad_body_entered", kart, boost_pad)

	assert_almost_eq(
		float(motor.call("boost_time_remaining_s")),
		boost_after_first_hit,
		0.1,
		(
			"an immediate second hit within pad_refire_cooldown_s must not "
			+ "stack a second pad_boost_s onto the motor's own boost budget"
		)
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _boot_race() -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
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


## Boots a real race with one synthetic BoostPad and one synthetic JumpPad
## under Track -- mirrors test_race_session.gd's own _boot_race_with_
## synthetic_box() shape (LOCAL position set BEFORE track.add_child(), see
## that helper's own doc for the full "a node added to the tree at its
## (0,0,0) default can still register a transient, permanently-sticky
## body_entered" rationale this reuses unchanged). Both pads default to the
## player's own KartSpawn position (only ever reached by a test that
## explicitly teleports a kart onto one); an explicit override is used by
## the AI-routing test above, which must sit well clear of that spawn so
## the still-ticking player kart never also overlaps it for real.
func _boot_race_with_synthetic_pads(local_position: Variant = null) -> Dictionary:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH))
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return {}
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return {}
	var race := packed.instantiate()
	add_child_autofree(race)
	var track := race.get_node("Track") as Node3D
	var spawn := track.get_node("KartSpawn") as Marker3D
	var position: Vector3 = local_position if local_position != null else spawn.position

	var boost_packed := load(BOOST_PAD_SCENE_PATH) as PackedScene
	assert_not_null(boost_packed)
	var jump_packed := load(JUMP_PAD_SCENE_PATH) as PackedScene
	assert_not_null(jump_packed)
	if boost_packed == null or jump_packed == null:
		return {}
	var boost_pad := boost_packed.instantiate() as Area3D
	boost_pad.position = position
	track.add_child(boost_pad)
	var jump_pad := jump_packed.instantiate() as Area3D
	# Offset well clear of the boost pad so the same teleport never overlaps
	# both at once -- each test's own kart placement targets exactly one.
	jump_pad.position = position + Vector3(50.0, 0.0, 50.0)
	track.add_child(jump_pad)

	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	return {"race": race, "boost_pad": boost_pad, "jump_pad": jump_pad}
