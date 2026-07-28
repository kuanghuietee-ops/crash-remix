extends GutTest

const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const CRAB_SCRIPT_PATH := "res://src/gameplay/enemies/enemy_crab.gd"
const SKINK_SCRIPT_PATH := "res://src/gameplay/enemies/enemy_skink.gd"
const PLANT_SCRIPT_PATH := "res://src/gameplay/enemies/enemy_plant.gd"
const CRAB_SCENE_PATH := "res://scenes/enemies/crab.tscn"
const CRAB_MODEL_PATH := "res://assets/models/enemies/SK_crab.glb"


func test_crab_patrol_stays_inside_authored_span_and_pauses_at_turn() -> void:
	var setup := _new_enemy(CRAB_SCRIPT_PATH, &"enemy_crab")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node3D
	var tuning := setup["tuning"] as Resource
	var start_s := 10.0
	var edge_travel_s := (
		float(tuning.get("patrol_span_m"))
		* 0.5
		/ float(tuning.get("patrol_speed_mps"))
	)
	var half_span_m := float(tuning.get("patrol_span_m")) * 0.5

	enemy.call("advance_logic", start_s, Vector3.ZERO)
	enemy.call(
		"advance_logic",
		start_s + edge_travel_s,
		Vector3.ZERO
	)
	assert_almost_eq(enemy.position.x, half_span_m, 0.001)
	var turn_position := enemy.position

	enemy.call(
		"advance_logic",
		(
			start_s
			+ edge_travel_s
			+ float(tuning.get("turn_pause_s")) * 0.5
		),
		Vector3.ZERO
	)
	assert_true(
		enemy.position.is_equal_approx(turn_position),
		"the crab must visibly pause at its authored patrol turn"
	)
	enemy.call(
		"advance_logic",
		(
			start_s
			+ edge_travel_s
			+ float(tuning.get("turn_pause_s"))
			+ 0.25
		),
		Vector3.ZERO
	)
	assert_lt(
		enemy.position.x,
		half_span_m,
		"the crab must reverse after the tuned turn pause"
	)

	for sample_index: int in range(1, 101):
		enemy.call(
			"advance_logic",
			start_s + float(sample_index) * 0.1,
			Vector3.ZERO
		)
		assert_lte(
			absf(enemy.position.x),
			half_span_m + 0.001,
			"patrol movement must never leave the authored span"
		)


func test_crab_scene_plays_attack_and_finishes_its_defeat_reaction() -> void:
	assert_true(ResourceLoader.exists(CRAB_MODEL_PATH))
	var packed := load(CRAB_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var enemy := packed.instantiate() as Node3D
	add_child_autofree(enemy)
	await wait_process_frames(1)
	var driver := enemy.get_node_or_null("VisualDriver")
	var proxy := enemy.get_node_or_null("Visual") as MeshInstance3D
	var attack_burst := enemy.get_node_or_null(
		"VisualDriver/AttackBurst"
	) as GPUParticles3D
	var defeat_burst := enemy.get_node_or_null(
		"VisualDriver/DefeatBurst"
	) as GPUParticles3D
	var animation_players := enemy.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	assert_not_null(driver)
	assert_not_null(proxy)
	assert_false(proxy.visible, "the graybox must become a bounds proxy only")
	assert_not_null(attack_burst)
	assert_not_null(defeat_burst)
	assert_eq(animation_players.size(), 1)
	if (
		driver == null
		or attack_burst == null
		or defeat_burst == null
		or animation_players.size() != 1
	):
		return
	var animation_player := animation_players[0] as AnimationPlayer
	var catalog := _catalog()
	if catalog == null:
		return
	enemy.call("configure", catalog.get("enemy_crab"), catalog.move)
	assert_eq(animation_player.current_animation, "A_crab_walk")

	var touch: Dictionary = enemy.call("resolve_contact", &"touch", 1.0)
	assert_true(bool(touch.get("player_hit", false)))
	assert_eq(animation_player.current_animation, "A_crab_attack")
	assert_true(attack_burst.emitting)

	enemy.call("reset_to_authored_spawn")
	var defeated: Dictionary = enemy.call("resolve_contact", &"spin", 2.0)
	assert_true(bool(defeated.get("enemy_defeated", false)))
	assert_true(enemy.visible, "the reaction must play before the crab hides")
	assert_eq(animation_player.current_animation, "A_crab_hit")
	assert_true(defeat_burst.emitting)

	animation_player.animation_finished.emit(&"A_crab_hit")
	assert_eq(animation_player.current_animation, "A_crab_defeat")
	animation_player.animation_finished.emit(&"A_crab_defeat")
	await wait_process_frames(1)
	assert_false(enemy.visible)

	enemy.call("reset_to_authored_spawn")
	assert_true(enemy.visible)
	assert_eq(animation_player.current_animation, "A_crab_walk")


func test_skink_trigger_telegraph_dart_and_cooldown_use_simulated_clock() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node3D
	var tuning := setup["tuning"] as Resource
	var start_s := 20.0
	var far_player := Vector3.BACK * (
		float(tuning.get("trigger_range_m")) + 1.0
	)
	var player_outside_authored_edge := Vector3.LEFT

	enemy.call("advance_logic", start_s, far_player)
	assert_eq(enemy.call("behavior_state"), &"dormant")

	var trigger_s := start_s + 1.0
	enemy.call(
		"advance_logic",
		trigger_s,
		player_outside_authored_edge
	)
	assert_eq(enemy.call("behavior_state"), &"telegraph")

	var active_s := trigger_s + float(tuning.get("telegraph_s"))
	enemy.call(
		"advance_logic",
		active_s,
		player_outside_authored_edge
	)
	assert_eq(enemy.call("behavior_state"), &"active")
	enemy.call(
		"advance_logic",
		active_s + float(tuning.get("attack_active_s")) * 0.5,
		player_outside_authored_edge
	)
	assert_gt(
		enemy.position.x,
		0.0,
		(
			"the skink's authored +X dash must cross into the "
			+ "corridor even when the player approaches from outside"
		)
	)

	var cooldown_s := (
		active_s + float(tuning.get("attack_active_s"))
	)
	enemy.call("advance_logic", cooldown_s, Vector3.ZERO)
	assert_eq(enemy.call("behavior_state"), &"cooldown")
	var dart_end_position_x := enemy.position.x
	assert_gt(
		dart_end_position_x,
		0.0,
		"the skink must not teleport home when its dart ends"
	)
	enemy.call(
		"advance_logic",
		(
			cooldown_s
			+ float(tuning.get("attack_active_s")) * 0.5
		),
		far_player
	)
	assert_between(
		enemy.position.x,
		0.0,
		dart_end_position_x,
		"the skink must visibly travel home during cooldown"
	)

	var dormant_s := (
		cooldown_s + float(tuning.get("attack_cooldown_s"))
	)
	enemy.call("advance_logic", dormant_s, far_player)
	assert_eq(enemy.call("behavior_state"), &"dormant")
	assert_true(
		enemy.position.is_equal_approx(Vector3.ZERO),
		"the skink must return to its authored start after the cycle"
	)


func test_skink_dart_covers_full_authored_span() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node3D
	var tuning := setup["tuning"] as Resource
	var trigger_s := 24.0
	var active_s := trigger_s + float(tuning.get("telegraph_s"))
	var dart_end_s := active_s + float(tuning.get("attack_active_s"))
	var physics_step_s := enemy.get_physics_process_delta_time()

	enemy.call("advance_logic", trigger_s, Vector3.ZERO)
	enemy.call("advance_logic", active_s, Vector3.ZERO)
	var sample_s := active_s
	while sample_s < dart_end_s:
		sample_s = minf(sample_s + physics_step_s, dart_end_s)
		enemy.call("advance_logic", sample_s, Vector3.ZERO)

	assert_almost_eq(
		enemy.position.x,
		float(tuning.get("patrol_span_m")),
		0.001,
		(
			"the skink must cover its full authored span so the "
			+ "edge-authored dart crosses the running line"
		)
	)


func test_skink_hitch_does_not_move_more_than_one_physics_step() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node3D
	var tuning := setup["tuning"] as Resource
	var trigger_s := 26.0
	var active_s := trigger_s + float(tuning.get("telegraph_s"))
	var dart_end_s := active_s + float(tuning.get("attack_active_s"))
	var physics_step_s := enemy.get_physics_process_delta_time()

	enemy.call("advance_logic", trigger_s, Vector3.ZERO)
	enemy.call("advance_logic", active_s, Vector3.ZERO)
	var sample_s := active_s
	while sample_s < dart_end_s:
		sample_s = minf(sample_s + physics_step_s, dart_end_s)
		enemy.call("advance_logic", sample_s, Vector3.ZERO)
	assert_almost_eq(
		enemy.position.x,
		float(tuning.get("patrol_span_m")),
		0.001,
		"the normal 60 Hz path must still finish the full dart"
	)

	var return_s := dart_end_s + physics_step_s
	enemy.call("advance_logic", return_s, Vector3.ZERO)
	var before_hitch_x := enemy.position.x
	var hitch_s := 0.4
	enemy.call(
		"advance_logic",
		return_s + hitch_s,
		Vector3.ZERO
	)
	var hitch_delta_m := absf(enemy.position.x - before_hitch_x)
	var maximum_frame_move_m := (
		float(tuning.get("patrol_speed_mps")) * physics_step_s
	)
	assert_lte(
		hitch_delta_m,
		maximum_frame_move_m + 0.001,
		(
			"a wall-clock hitch must not teleport the skink farther "
			+ "than one fixed physics step"
		)
	)


func test_skink_edge_placement_detects_centerline_before_player_is_abreast() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node
	var tuning := setup["tuning"] as Resource
	var trigger_range_m := float(tuning.get("trigger_range_m"))
	var trigger_lateral_m := float(
		tuning.get("trigger_lateral_m")
	)
	var centerline_player := Vector3(
		trigger_lateral_m,
		0.0,
		trigger_range_m
	)

	enemy.call("advance_logic", 25.0, centerline_player)

	assert_eq(
		enemy.call("behavior_state"),
		&"telegraph",
		(
			"the edge-authored skink must use forward corridor range; "
			+ "a spherical range can miss the centerline entirely"
		)
	)


func test_skink_trigger_rejects_far_lateral_and_overhead_players() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node
	var tuning := setup["tuning"] as Resource
	var trigger_range_m := float(tuning.get("trigger_range_m"))

	enemy.call(
		"advance_logic",
		27.0,
		Vector3.RIGHT * trigger_range_m
	)
	assert_eq(
		enemy.call("behavior_state"),
		&"dormant",
		"the skink must not attack across the far corridor edge"
	)

	enemy.call("reset_to_authored_spawn")
	enemy.call(
		"advance_logic",
		28.0,
		Vector3.UP * trigger_range_m
	)
	assert_eq(
		enemy.call("behavior_state"),
		&"dormant",
		"the skink must not attack a player directly overhead"
	)


func test_skink_trigger_lead_covers_its_full_run_speed_response() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var tuning := setup["tuning"] as Resource
	var catalog := _catalog()
	if catalog == null:
		return
	var full_dart_s := (
		float(tuning.get("patrol_span_m"))
		/ float(tuning.get("patrol_speed_mps"))
	)
	var full_response_s := (
		float(tuning.get("telegraph_s")) + full_dart_s
	)
	var run_distance_during_response_m := (
		catalog.move.run_speed_mps * full_response_s
	)

	assert_gte(
		float(tuning.get("trigger_range_m")),
		run_distance_during_response_m,
		(
			"the skink must react early enough to finish its dart "
			+ "before a full-speed runner reaches its crossing plane"
		)
	)


func test_skink_active_window_can_cover_full_authored_dart() -> void:
	var setup := _new_enemy(SKINK_SCRIPT_PATH, &"enemy_skink")
	if setup.is_empty():
		return
	var tuning := setup["tuning"] as Resource
	var reachable_distance_m := (
		float(tuning.get("attack_active_s"))
		* float(tuning.get("patrol_speed_mps"))
	)

	assert_gte(
		reachable_distance_m,
		float(tuning.get("patrol_span_m")),
		(
			"attack_active_s must let the skink physically cover its "
			+ "full authored dart without an end-of-window snap"
		)
	)


func test_plant_cycle_windows_use_simulated_clock() -> void:
	var setup := _new_enemy(PLANT_SCRIPT_PATH, &"enemy_plant")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node3D
	var tuning := setup["tuning"] as Resource
	var trigger_s := 30.0

	enemy.call("advance_logic", trigger_s, Vector3.ZERO)
	assert_eq(enemy.call("behavior_state"), &"telegraph")
	assert_false(enemy.call("attack_is_active"))

	var active_s := trigger_s + float(tuning.get("telegraph_s"))
	enemy.call("advance_logic", active_s, Vector3.ZERO)
	assert_eq(enemy.call("behavior_state"), &"active")
	assert_true(enemy.call("attack_is_active"))

	var cooldown_s := (
		active_s + float(tuning.get("attack_active_s"))
	)
	enemy.call("advance_logic", cooldown_s, Vector3.ZERO)
	assert_eq(enemy.call("behavior_state"), &"cooldown")
	assert_false(enemy.call("attack_is_active"))

	var next_cycle_s := (
		cooldown_s + float(tuning.get("attack_cooldown_s"))
	)
	enemy.call("advance_logic", next_cycle_s, Vector3.ZERO)
	assert_eq(
		enemy.call("behavior_state"),
		&"telegraph",
		"a nearby player must begin the next tuned bite cycle"
	)


func test_every_enemy_has_at_least_two_one_hit_verb_answers() -> void:
	var expected_answers := {
		CRAB_SCRIPT_PATH: [
			&"spin",
			&"jump",
			&"slide",
			&"slam",
		],
		SKINK_SCRIPT_PATH: [
			&"spin",
			&"jump",
		],
		PLANT_SCRIPT_PATH: [
			&"spin",
			&"slam",
		],
	}
	var tuning_sections := {
		CRAB_SCRIPT_PATH: &"enemy_crab",
		SKINK_SCRIPT_PATH: &"enemy_skink",
		PLANT_SCRIPT_PATH: &"enemy_plant",
	}
	for script_path: String in expected_answers:
		var setup := _new_enemy(
			script_path,
			tuning_sections[script_path]
		)
		if setup.is_empty():
			continue
		var enemy := setup["enemy"] as Node
		var answers: Array = enemy.call("accepted_verbs")
		assert_eq(answers, expected_answers[script_path])
		assert_gte(
			answers.size(),
			2,
			"every enemy must be answerable by at least two verbs"
		)
		assert_false(
			_script_property_names(enemy).has(&"hit_points"),
			"difficulty must come from composition, never enemy HP"
		)
		for verb: StringName in answers:
			enemy.call("reset_to_authored_spawn")
			var result: Dictionary = enemy.call(
				"apply_verb",
				verb,
				40.0
			)
			assert_true(
				bool(result.get("enemy_defeated", false)),
				"%s must defeat in one hit with %s"
				% [script_path.get_file(), verb]
			)


func test_plant_top_contact_kills_during_bite_and_bounces_while_closed() -> void:
	var setup := _new_enemy(PLANT_SCRIPT_PATH, &"enemy_plant")
	if setup.is_empty():
		return
	var enemy := setup["enemy"] as Node
	var tuning := setup["tuning"] as Resource

	var closed: Dictionary = enemy.call(
		"resolve_contact",
		&"jump",
		50.0
	)
	assert_false(bool(closed.get("player_hit", false)))
	assert_true(
		bool(closed.get("player_bounce", false)),
		"a closed plant must be a safe bounce"
	)
	assert_false(enemy.call("is_defeated"))

	enemy.call("advance_logic", 51.0, Vector3.ZERO)
	var active_s := 51.0 + float(tuning.get("telegraph_s"))
	enemy.call("advance_logic", active_s, Vector3.ZERO)
	var biting: Dictionary = enemy.call(
		"resolve_contact",
		&"jump",
		active_s
	)
	assert_true(
		bool(biting.get("player_hit", false)),
		"landing on the plant during attack_active_s must hit the player"
	)
	assert_false(bool(biting.get("player_bounce", false)))


func test_enemy_hurt_and_attack_shapes_use_global_move_ratios() -> void:
	assert_true(
		ResourceLoader.exists(CRAB_SCENE_PATH),
		"the crab graybox scene must exist"
	)
	if not ResourceLoader.exists(CRAB_SCENE_PATH):
		return
	var packed := load(CRAB_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var enemy := packed.instantiate() as Node3D
	assert_not_null(enemy)
	if enemy == null:
		return
	add_child_autofree(enemy)
	await wait_process_frames(1)
	var catalog := _catalog()
	if catalog == null:
		return
	enemy.call("configure", catalog.get("enemy_crab"), catalog.move)

	var visual := enemy.get_node("Visual") as MeshInstance3D
	var hurt_shape := (
		enemy.get_node("CollisionShape3D").shape as BoxShape3D
	)
	var attack_shape := (
		enemy.get_node("AttackArea/CollisionShape3D").shape
		as BoxShape3D
	)
	assert_not_null(visual)
	assert_not_null(hurt_shape)
	assert_not_null(attack_shape)
	if visual == null or hurt_shape == null or attack_shape == null:
		return
	var visual_bounds := visual.transform * visual.mesh.get_aabb()
	assert_true(
		hurt_shape.size.is_equal_approx(
			visual_bounds.size * catalog.move.hurtbox_visual_ratio
		),
		"enemy hurt sizing must use move.hurtbox_visual_ratio"
	)
	assert_true(
		attack_shape.size.is_equal_approx(
			visual_bounds.size * catalog.move.attack_visual_ratio
		),
		"enemy attack sizing must use move.attack_visual_ratio"
	)
	assert_eq(
		(enemy as CollisionObject3D).collision_layer & 2,
		2,
		"player spin/slam areas must detect the enemy body"
	)
	assert_true(enemy.is_in_group(&"enemy"))


func _new_enemy(
	script_path: String,
	tuning_section: StringName
) -> Dictionary:
	assert_true(
		ResourceLoader.exists(script_path),
		"%s must exist" % script_path
	)
	if not ResourceLoader.exists(script_path):
		return {}
	var script := load(script_path) as Script
	assert_not_null(script)
	if script == null:
		return {}
	var enemy := script.new() as Node3D
	assert_not_null(enemy)
	if enemy == null:
		return {}
	add_child_autofree(enemy)
	var catalog := _catalog()
	if catalog == null:
		return {}
	var tuning := catalog.get(tuning_section) as Resource
	assert_not_null(
		tuning,
		"%s must reach the live catalog" % tuning_section
	)
	if tuning == null:
		return {}
	enemy.call("configure", tuning, catalog.move)
	return {
		"enemy": enemy,
		"tuning": tuning,
	}


func _catalog() -> GameplayTuning:
	var catalog := load(BASE_CATALOG_PATH) as GameplayTuning
	assert_not_null(catalog)
	return catalog


func _script_property_names(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property_info: Dictionary in object.get_property_list():
		if int(property_info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property_info["name"])
	return names
