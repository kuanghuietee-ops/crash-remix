extends GutTest

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LEVEL_SESSION_PATH := "res://src/gameplay/run/level_session.gd"
const CHECKPOINT_SCENE := "res://scenes/props/crate_checkpoint.tscn"
const WUMPA_SCENE := "res://scenes/props/wumpa.tscn"

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _meta: LevelMeta


func before_each() -> void:
	_catalog = load(
		"res://data/tuning/gameplay.tres"
	).duplicate(true) as GameplayTuning
	_economy = _catalog.economy
	_meta = load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	_meta.crate_count = _economy.mask_stack_maximum


func test_hundred_wumpa_auto_summons_mask_and_rolls_counter() -> void:
	var setup := _new_session()
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	assert_true(
		session.has_method("collect_wumpa"),
		"LevelSession must own the wumpa-to-mask conversion"
	)
	assert_true(
		player.has_method("mask_count"),
		"PlayerController must expose its live mask count"
	)
	if (
		not session.has_method("collect_wumpa")
		or not player.has_method("mask_count")
	):
		return

	session.call(
		"collect_wumpa",
		_economy.wumpa_mask_threshold - 1,
		10.0
	)
	var run_state: RefCounted = session.get("run_state")
	assert_eq(
		run_state.get("wumpa_run"),
		_economy.wumpa_mask_threshold - 1
	)
	assert_eq(run_state.get("masks"), 0)

	session.call("collect_wumpa", 1, 10.1)

	assert_eq(run_state.get("wumpa_run"), 0)
	assert_eq(run_state.get("masks"), 1)
	assert_eq(player.call("mask_count"), 1)


func test_placed_wumpa_uses_live_radius_and_collects_once() -> void:
	var setup := _new_session(false, true)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	var pickup := setup["wumpa"] as Area3D
	var shape_node := (
		pickup.get_node("CollisionShape3D")
		as CollisionShape3D
	)
	var shape := shape_node.shape as SphereShape3D

	assert_almost_eq(
		shape.radius,
		_economy.wumpa_collect_radius_m,
		0.0001
	)
	pickup.body_entered.emit(player)
	pickup.body_entered.emit(player)

	var run_state: RefCounted = session.get("run_state")
	assert_eq(
		run_state.get("wumpa_run"),
		_economy.wumpa_per_standard_crate
	)
	assert_false(pickup.visible)


func test_mask_absorbs_exactly_one_hit_before_one_hit_death() -> void:
	var setup := _new_session()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	for method_name: StringName in [
		&"grant_mask",
		&"mask_count",
		&"receive_hit",
	]:
		assert_true(player.has_method(method_name))
		if not player.has_method(method_name):
			return

	player.call("grant_mask", 20.0)

	assert_false(player.call("receive_hit", 20.1))
	assert_eq(player.call("mask_count"), 0)
	assert_false(player.call("is_respawning"))

	assert_true(player.call("receive_hit", 20.2))
	assert_true(player.call("is_respawning"))


func test_third_mask_starts_tuned_invincibility_and_keeps_stack_capped() -> void:
	var setup := _new_session()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	for method_name: StringName in [
		&"grant_mask",
		&"mask_count",
		&"receive_hit",
		&"is_invincible",
		&"invincibility_remaining_s",
	]:
		assert_true(player.has_method(method_name))
		if not player.has_method(method_name):
			return
	var started_at_s := 30.0
	for _mask: int in range(_economy.mask_stack_maximum):
		assert_false(player.call("grant_mask", started_at_s))

	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum
	)
	assert_true(player.call("grant_mask", started_at_s))
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum
	)
	assert_almost_eq(
		player.call(
			"invincibility_remaining_s",
			started_at_s
		),
		_economy.invincibility_duration_s,
		0.0001
	)

	var during_s := (
		started_at_s
		+ _economy.invincibility_duration_s * 0.5
	)
	assert_false(player.call("receive_hit", during_s))
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum
	)
	assert_false(player.call("is_respawning"))

	var expiry_s := (
		started_at_s
		+ _economy.invincibility_duration_s
	)
	assert_false(player.call("is_invincible", expiry_s))
	assert_false(player.call("receive_hit", expiry_s))
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum - 1
	)


func test_third_checkpoint_death_grants_visible_mercy_mask_at_respawn() -> void:
	var setup := _new_session(true)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	assert_true(
		session.has_signal(&"mercy_granted"),
		"Mercy must be surfaced instead of hidden"
	)
	if not session.has_signal(&"mercy_granted"):
		return
	var grants: Array[int] = []
	session.connect(
		&"mercy_granted",
		func(mask_count: int) -> void:
			grants.append(mask_count)
	)
	var first_checkpoint: Node = setup["first_checkpoint"]
	first_checkpoint.call("apply_verb", &"spin")

	_advance_deaths(
		player,
		_economy.mercy_mask_death_threshold
	)

	var run_state: RefCounted = session.get("run_state")
	assert_eq(grants, [1])
	assert_eq(run_state.get("masks"), 1)
	assert_eq(player.call("mask_count"), 1)


func test_skip_offer_repeats_and_acceptance_moves_to_next_checkpoint() -> void:
	var setup := _new_session(true)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	assert_true(
		session.has_signal(&"skip_offered"),
		"Mercy skip must be surfaced instead of hidden"
	)
	assert_true(session.has_method("accept_mercy_skip"))
	if (
		not session.has_signal(&"skip_offered")
		or not session.has_method("accept_mercy_skip")
	):
		return
	var offers: Array[int] = []
	session.connect(
		&"skip_offered",
		func(checkpoint_id: int) -> void:
			offers.append(checkpoint_id)
	)
	var first_checkpoint: Node = setup["first_checkpoint"]
	var second_checkpoint: Node3D = setup["second_checkpoint"]
	first_checkpoint.call("apply_verb", &"spin")

	_advance_deaths(
		player,
		_economy.mercy_skip_death_threshold
	)
	_advance_deaths(player, 1, 1000.0)

	assert_eq(offers, [2, 2])
	assert_true(session.call("accept_mercy_skip"))

	var run_state: RefCounted = session.get("run_state")
	assert_eq(run_state.get("checkpoint_id"), 2)
	assert_eq(run_state.get("deaths_at_checkpoint"), 0)
	assert_true(run_state.get("gem_void"))
	assert_true(run_state.get("relic_void"))
	assert_eq(
		player.global_transform,
		second_checkpoint.get_node("Spawn").global_transform
	)


func _new_session(
	with_checkpoints: bool = false,
	with_wumpa: bool = false
) -> Dictionary:
	var session_script := load(LEVEL_SESSION_PATH) as Script
	assert_not_null(session_script)
	if session_script == null or not session_script.can_instantiate():
		return {}
	var session := session_script.new() as Node
	var first_checkpoint: Node
	var second_checkpoint: Node3D
	if with_checkpoints:
		first_checkpoint = _instantiate(CHECKPOINT_SCENE)
		second_checkpoint = _instantiate(CHECKPOINT_SCENE) as Node3D
		if first_checkpoint == null or second_checkpoint == null:
			return {}
		first_checkpoint.set("crate_id", 1)
		second_checkpoint.set("crate_id", 2)
		second_checkpoint.position = Vector3(
			_economy.tnt_blast_radius_m,
			0.0,
			0.0
		)
		session.add_child(first_checkpoint)
		session.add_child(second_checkpoint)

	var wumpa: Area3D
	if with_wumpa:
		wumpa = _instantiate(WUMPA_SCENE) as Area3D
		if wumpa == null:
			return {}
		session.add_child(wumpa)

	var player := _instantiate(PLAYER_SCENE) as CharacterBody3D
	if player == null:
		return {}
	session.add_child(player)
	add_child_autofree(session)
	_configure_player(player)
	session.call(
		"configure",
		_meta,
		&"normal",
		_economy,
		player,
		_catalog.move,
		_catalog.input
	)
	return {
		"session": session,
		"player": player,
		"first_checkpoint": first_checkpoint,
		"second_checkpoint": second_checkpoint,
		"wumpa": wumpa,
	}


func _configure_player(player: CharacterBody3D) -> void:
	var supports_economy := false
	for method: Dictionary in player.get_method_list():
		if method.get("name") == &"configure":
			var arguments: Array = method.get("args", [])
			supports_economy = arguments.size() >= 8
			break
	assert_true(
		supports_economy,
		"PlayerController.configure must receive live EconomyTuning"
	)
	var arguments: Array = [
		_catalog.move,
		_catalog.input,
		_catalog.depth,
		_catalog.wall_run,
		_catalog.grind,
		_catalog.swing,
		InputIntentBuffer.new(),
	]
	if supports_economy:
		arguments.append(_economy)
	player.callv("configure", arguments)


func _advance_deaths(
	player: CharacterBody3D,
	count: int,
	clock_origin_s: float = 100.0
) -> void:
	for death_index: int in range(count):
		var requested_at_s := (
			clock_origin_s
			+ float(death_index)
			* (_catalog.move.respawn_delay_s + 1.0)
		)
		player.call("request_respawn", requested_at_s)
		assert_true(player.call(
			"advance_respawn",
			requested_at_s + _catalog.move.respawn_delay_s
		))


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null
