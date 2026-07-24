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
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	_economy = _catalog.economy
	_meta = load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	_meta.crate_count = _economy.mask_stack_maximum


func test_placed_wumpa_auto_summons_mask_and_rolls_counter() -> void:
	var pickup_value := _economy.mercy_mask_death_threshold
	var threshold := _economy.wumpa_mask_threshold
	assert_gt(pickup_value, 0)
	assert_lt(
		pickup_value,
		threshold,
		"The pickup value must permit a nonzero rollover remainder"
	)
	assert_ne(
		threshold % pickup_value,
		0,
		"The final real pickup must cross the threshold with surplus"
	)
	if (
		pickup_value <= 0
		or pickup_value >= threshold
		or threshold % pickup_value == 0
	):
		return
	_economy.wumpa_per_standard_crate = pickup_value
	var pickup_count := ceili(
		float(threshold) / float(pickup_value)
	)
	var expected_total := pickup_count * pickup_value
	var expected_remainder := expected_total % threshold
	var expected_masks := expected_total / threshold
	assert_gt(
		expected_remainder,
		0,
		"The scenario must distinguish rollover from reset"
	)

	var setup := _new_session(false, true, pickup_count)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	assert_true(
		player.has_method("mask_count"),
		"PlayerController must expose its live mask count"
	)
	if not player.has_method("mask_count"):
		return

	for pickup: Area3D in setup["wumpa_pickups"]:
		pickup.body_entered.emit(player)

	var run_state: RefCounted = session.get("run_state")
	assert_eq(
		run_state.get("wumpa_run"),
		expected_remainder
	)
	assert_eq(run_state.get("masks"), expected_masks)
	assert_eq(player.call("mask_count"), expected_masks)


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


func test_real_fall_death_clears_the_player_mask_stack() -> void:
	_economy.wumpa_per_standard_crate = (
		_economy.wumpa_mask_threshold
	)
	var setup := _new_session(false, true)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	var pickup := setup["wumpa"] as Area3D
	var respawns: Array[bool] = []
	player.respawned.connect(
		func() -> void:
			respawns.append(true)
	)

	pickup.body_entered.emit(player)

	var run_state: RefCounted = session.get("run_state")
	assert_eq(player.call("mask_count"), 1)
	assert_eq(run_state.get("masks"), 1)

	player.global_position.y = (
		_catalog.move.respawn_floor_y_m
		- _catalog.move.player_height_m
	)
	await wait_physics_frames(2)
	assert_true(
		player.call("is_respawning"),
		"The real floor threshold must request the respawn"
	)
	var frame_limit := ceili(
		_catalog.move.respawn_delay_s
		* Engine.physics_ticks_per_second
	) + Engine.physics_ticks_per_second
	for _frame_index: int in range(frame_limit):
		if not respawns.is_empty():
			break
		await wait_physics_frames(1)

	assert_eq(
		respawns.size(),
		1,
		"The real player must complete one fall respawn"
	)
	assert_eq(run_state.get("deaths_at_checkpoint"), 1)
	assert_eq(player.call("mask_count"), 0)
	assert_eq(run_state.get("masks"), 0)


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

	var absorbed_at_s := 20.1
	assert_false(player.call("receive_hit", absorbed_at_s))
	assert_eq(player.call("mask_count"), 0)
	assert_false(player.call("is_respawning"))

	assert_false(player.call(
		"receive_hit",
		absorbed_at_s
		+ _economy.mask_hit_invulnerability_s * 0.5
	))
	assert_false(player.call("is_respawning"))
	assert_true(player.call(
		"receive_hit",
		absorbed_at_s + _economy.mask_hit_invulnerability_s
	))
	assert_true(player.call("is_respawning"))


func test_one_contact_instant_cannot_drain_the_mask_stack() -> void:
	var tuned_hit_grace_s := 0.75
	_economy.mask_hit_invulnerability_s = tuned_hit_grace_s
	var setup := _new_session()
	if setup.is_empty():
		return
	var player: CharacterBody3D = setup["player"]
	var contact_at_s := 20.0
	for _mask_index: int in range(_economy.mask_stack_maximum):
		player.call("grant_mask", contact_at_s)
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum
	)

	assert_false(player.call("receive_hit", contact_at_s))
	assert_false(player.call("receive_hit", contact_at_s))
	assert_false(player.call("receive_hit", contact_at_s))

	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum - 1,
		"one contact instant must consume exactly one mask"
	)
	assert_false(
		player.call("is_respawning"),
		"repeat callbacks from one contact must not kill the player"
	)
	assert_true(
		player.call(
			"is_invincible",
			contact_at_s + tuned_hit_grace_s * 0.5
		),
		"the absorbed hit must open the tuned grace window"
	)
	assert_false(player.call(
		"receive_hit",
		contact_at_s + tuned_hit_grace_s * 0.5
	))
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum - 1
	)
	assert_false(player.call(
		"receive_hit",
		contact_at_s + tuned_hit_grace_s
	))
	assert_eq(
		player.call("mask_count"),
		_economy.mask_stack_maximum - 2,
		"the exact tuned boundary must permit the next distinct hit"
	)


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


func test_skip_follows_authored_checkpoint_link_when_ids_descend() -> void:
	var setup := _new_session(true, false, 1, true)
	if setup.is_empty():
		return
	var session: Node = setup["session"]
	var player: CharacterBody3D = setup["player"]
	var first_checkpoint: Node = setup["first_checkpoint"]
	var second_checkpoint: Node3D = setup["second_checkpoint"]
	var offers: Array[int] = []
	session.skip_offered.connect(
		func(checkpoint_id: int) -> void:
			offers.append(checkpoint_id)
	)
	first_checkpoint.call("apply_verb", &"spin")

	_advance_deaths(
		player,
		_economy.mercy_skip_death_threshold
	)

	assert_eq(
		offers,
		[1],
		"mercy progression must follow the authored checkpoint link"
	)
	assert_true(session.call("accept_mercy_skip"))
	var run_state: RefCounted = session.get("run_state")
	assert_eq(run_state.get("checkpoint_id"), 1)
	assert_eq(
		player.global_transform,
		second_checkpoint.get_node("Spawn").global_transform
	)


func _new_session(
	with_checkpoints: bool = false,
	with_wumpa: bool = false,
	wumpa_count: int = 1,
	descending_checkpoint_ids: bool = false
) -> Dictionary:
	var session_script := load(LEVEL_SESSION_PATH) as Script
	assert_not_null(session_script)
	if session_script == null or not session_script.can_instantiate():
		return {}
	var session := session_script.new() as Node
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var first_checkpoint: Node
	var second_checkpoint: Node3D
	if with_checkpoints:
		first_checkpoint = _instantiate(CHECKPOINT_SCENE)
		second_checkpoint = _instantiate(CHECKPOINT_SCENE) as Node3D
		if first_checkpoint == null or second_checkpoint == null:
			return {}
		var first_checkpoint_id := (
			2 if descending_checkpoint_ids else 1
		)
		var second_checkpoint_id := (
			1 if descending_checkpoint_ids else 2
		)
		first_checkpoint.set("crate_id", first_checkpoint_id)
		first_checkpoint.set_meta(
			&"next_checkpoint_id",
			second_checkpoint_id
		)
		second_checkpoint.set("crate_id", second_checkpoint_id)
		second_checkpoint.position = Vector3(
			_economy.tnt_blast_radius_m,
			0.0,
			0.0
		)
		session.add_child(first_checkpoint)
		session.add_child(second_checkpoint)

	var wumpa: Area3D
	var wumpa_pickups: Array[Area3D] = []
	if with_wumpa:
		for _pickup_index: int in range(wumpa_count):
			var pickup := _instantiate(WUMPA_SCENE) as Area3D
			if pickup == null:
				return {}
			session.add_child(pickup)
			wumpa_pickups.append(pickup)
			wumpa = wumpa if wumpa != null else pickup

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
		"wumpa_pickups": wumpa_pickups,
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
