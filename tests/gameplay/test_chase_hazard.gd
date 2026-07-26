extends GutTest

const CHASE_SCRIPT_PATH := (
	"res://src/gameplay/chase/chase_hazard.gd"
)
const CHASE_TUNING_PATH := "res://data/tuning/chase.tres"
const GAMEPLAY_TUNING_PATH := (
	"res://data/tuning/gameplay.tres"
)
const BOULDERS_SCENE_PATH := (
	"res://scenes/levels/wr1_boulders.tscn"
)
const PROGRESS_TOLERANCE_M := 0.0001


func test_real_start_trigger_preserves_authored_boulder_gap() -> void:
	var packed := load(BOULDERS_SCENE_PATH) as PackedScene
	var tuning := load(CHASE_TUNING_PATH) as Resource
	assert_not_null(packed)
	assert_not_null(tuning)
	if packed == null or tuning == null:
		return
	var level := packed.instantiate() as Node3D
	add_child_autofree(level)
	await wait_process_frames(1)
	var hazard := level.get_node_or_null(
		"ChaseHazard"
	) as Node3D
	var path := level.get_node_or_null(
		"ChaseHazard/Path"
	) as Path3D
	var trigger := level.get_node_or_null(
		"ChaseHazard/StartTrigger"
	) as Area3D
	var player := level.get_node_or_null(
		"Player"
	) as Node3D
	assert_not_null(hazard)
	assert_not_null(path)
	assert_not_null(trigger)
	assert_not_null(player)
	if (
		hazard == null
		or path == null
		or path.curve == null
		or trigger == null
		or player == null
	):
		return
	var trigger_shape := trigger.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	assert_not_null(trigger_shape)
	assert_true(
		trigger_shape.shape is BoxShape3D,
		"the real start trigger must expose its leading face"
	)
	if (
		trigger_shape == null
		or not trigger_shape.shape is BoxShape3D
	):
		return
	var trigger_progress_m := float(hazard.call(
		"progress_for_position",
		trigger.global_position
	))
	var sample_before := path.curve.sample_baked(
		maxf(trigger_progress_m - 1.0, 0.0)
	)
	var sample_after := path.curve.sample_baked(
		minf(
			trigger_progress_m + 1.0,
			path.curve.get_baked_length()
		)
	)
	var chase_forward := (
		path.to_global(sample_after)
		- path.to_global(sample_before)
	).normalized()
	var box := trigger_shape.shape as BoxShape3D
	var half_extent_m := (
		absf(chase_forward.dot(trigger_shape.global_basis.x.normalized()))
		* box.size.x
		+ absf(chase_forward.dot(trigger_shape.global_basis.y.normalized()))
		* box.size.y
		+ absf(chase_forward.dot(trigger_shape.global_basis.z.normalized()))
		* box.size.z
	) * 0.5
	player.global_position = (
		trigger_shape.global_position
		- chase_forward * half_extent_m
	)
	var player_progress_m := float(hazard.call(
		"progress_for_position",
		player.global_position
	))
	hazard.call("configure_logic", tuning)
	hazard.call("start_at_progress", player_progress_m)

	assert_almost_eq(
		float(hazard.call(
			"gap_to_progress_m",
			player_progress_m
		)),
		float(tuning.get("boulder_start_gap_m")),
		PROGRESS_TOLERANCE_M,
		"the real trigger face must leave the full authored start gap"
	)


func test_unusable_path_fails_loud_without_catching_player() -> void:
	var script := load(CHASE_SCRIPT_PATH) as Script
	var tuning := load(CHASE_TUNING_PATH) as Resource
	assert_not_null(script)
	assert_not_null(tuning)
	if script == null or tuning == null:
		return
	var hazard := script.new() as Node
	hazard.name = "BrokenPathHazard"
	add_child_autofree(hazard)
	hazard.call("configure_logic", tuning)

	hazard.call("start_at_progress", 0.0)
	assert_push_error(
		"%s cannot start without a usable chase path"
		% hazard.get_path()
	)
	var outcome: Dictionary = hazard.call(
		"advance_progress",
		0.0,
		0.0
	)

	assert_false(
		bool(outcome.get(&"active", true)),
		"a broken authoring path must fail closed"
	)
	assert_false(
		bool(outcome.get(&"caught", true)),
		"a broken path must never instant-kill the player"
	)


func test_real_boulder_visual_does_not_lead_kill_boundary() -> void:
	var packed := load(BOULDERS_SCENE_PATH) as PackedScene
	var tuning := load(CHASE_TUNING_PATH) as Resource
	assert_not_null(packed)
	assert_not_null(tuning)
	if packed == null or tuning == null:
		return
	var level := packed.instantiate() as Node3D
	add_child_autofree(level)
	await wait_process_frames(1)
	var path := level.get_node_or_null(
		"ChaseHazard/Path"
	) as Path3D
	var visual := level.get_node_or_null(
		"ChaseHazard/BoulderVisual"
	) as Node3D
	assert_not_null(path)
	assert_not_null(visual)
	if path == null or path.curve == null or visual == null:
		return
	var chase_forward := (
		path.to_global(path.curve.sample_baked(1.0))
		- path.to_global(path.curve.sample_baked(0.0))
	).normalized()
	var kill_distance_m := float(
		tuning.get("boulder_kill_distance_m")
	)
	var rock := visual.get_node_or_null(
		"Rock"
	) as MeshInstance3D
	assert_not_null(rock)
	if rock != null:
		assert_true(
			rock.mesh is SphereMesh,
			"the graybox rock must expose an authored radius"
		)
		if rock.mesh is SphereMesh:
			assert_almost_eq(
				(rock.mesh as SphereMesh).radius,
				kill_distance_m,
				PROGRESS_TOLERANCE_M,
				"the authored rock radius must match the lethal plane"
			)
		assert_lte(
			_mesh_forward_extent_m(
				visual,
				rock,
				chase_forward
			),
			kill_distance_m + PROGRESS_TOLERANCE_M,
			"the rendered rock face must not lead the lethal plane"
		)
	for cue_name: StringName in [
		&"WarningBand",
		&"Shadow",
	]:
		var cue := visual.get_node_or_null(
			NodePath(cue_name)
		) as MeshInstance3D
		assert_not_null(cue)
		if cue == null:
			continue
		assert_lte(
			_mesh_forward_extent_m(
				visual,
				cue,
				chase_forward
			),
			kill_distance_m + PROGRESS_TOLERANCE_M,
			"%s must not warn ahead of the lethal plane"
			% cue_name
		)


func test_real_path_progress_tracks_authored_marker_distance() -> void:
	var setup: Dictionary = await _new_real_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var path := setup[&"path"] as Path3D
	var chase_start := path.get_node_or_null(
		"ChaseStart"
	) as Marker3D
	var gate_end := path.get_node_or_null(
		"GateEnd"
	) as Marker3D
	assert_not_null(chase_start)
	assert_not_null(gate_end)
	if chase_start == null or gate_end == null:
		return

	assert_almost_eq(
		float(hazard.call(
			"progress_for_position",
			chase_start.global_position
		)),
		0.0,
		PROGRESS_TOLERANCE_M,
		"the first real path marker must be progress zero"
	)
	assert_almost_eq(
		float(hazard.call(
			"progress_for_position",
			gate_end.global_position
		)),
		chase_start.global_position.distance_to(
			gate_end.global_position
		),
		PROGRESS_TOLERANCE_M,
		"the real straight chase leg must report world-space distance"
	)


func test_real_checkpoint_resets_restore_full_gap_at_both_checkpoints() -> void:
	var setup: Dictionary = await _new_real_hazard()
	if setup.is_empty():
		return
	var level := setup[&"level"] as Node3D
	var hazard := setup[&"hazard"] as Node
	var catalog := setup[&"catalog"] as GameplayTuning
	var tuning := setup[&"tuning"] as Resource
	for checkpoint_path: NodePath in [
		NodePath("Segments/ChaseGate/Checkpoint8"),
		NodePath("Segments/ChaseBreather/Checkpoint24"),
	]:
		var checkpoint := level.get_node_or_null(
			checkpoint_path
		) as Node3D
		assert_not_null(checkpoint)
		if checkpoint == null:
			continue
		var respawn_transform := checkpoint.global_transform
		respawn_transform.origin += (
			respawn_transform.basis
			* catalog.economy.checkpoint_respawn_offset
		)

		hazard.call(
			"reset_for_player_position",
			respawn_transform.origin
		)

		assert_true(
			hazard.call("is_active"),
			"%s must restart an active mid-chase hazard"
			% checkpoint.name
		)
		assert_almost_eq(
			float(hazard.call(
				"gap_to_position_m",
				respawn_transform.origin
			)),
			float(tuning.get("boulder_start_gap_m")),
			PROGRESS_TOLERANCE_M,
			"%s must restore the full authored gap"
			% checkpoint.name
		)


func test_real_trigger_signals_start_and_stop_only_for_player() -> void:
	var setup: Dictionary = await _new_real_hazard()
	if setup.is_empty():
		return
	var level := setup[&"level"] as Node3D
	var hazard := setup[&"hazard"] as Node
	var player := setup[&"player"] as Node3D
	var start_trigger := level.get_node_or_null(
		"ChaseHazard/StartTrigger"
	) as Area3D
	var stop_trigger := level.get_node_or_null(
		"ChaseHazard/StopTrigger"
	) as Area3D
	assert_not_null(start_trigger)
	assert_not_null(stop_trigger)
	if start_trigger == null or stop_trigger == null:
		return
	var bystander := Node3D.new()
	level.add_child(bystander)
	hazard.call("reset_before_start")

	start_trigger.emit_signal(
		&"body_entered",
		bystander
	)
	assert_false(
		hazard.call("is_active"),
		"an unrelated body must not start the chase"
	)
	player.global_position = start_trigger.global_position
	start_trigger.emit_signal(
		&"body_entered",
		player
	)
	assert_true(
		hazard.call("is_active"),
		"the real start-trigger callback must activate the chase"
	)
	player.global_position = stop_trigger.global_position
	stop_trigger.emit_signal(
		&"body_entered",
		player
	)
	assert_false(
		hazard.call("is_active"),
		"the real stop-trigger callback must stop the chase"
	)


func test_chase_hazard_exposes_no_test_only_signals() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node

	for signal_name: StringName in [
		&"player_caught",
		&"chase_started",
		&"chase_stopped",
	]:
		assert_false(
			hazard.has_signal(signal_name),
			"%s has no production consumer" % signal_name
		)


func test_boulder_closes_at_tuned_speed_without_rubber_band() -> void:
	var slow_setup := _new_hazard()
	var fast_setup := _new_hazard()
	if slow_setup.is_empty() or fast_setup.is_empty():
		return
	var slow_hazard := slow_setup[&"hazard"] as Node
	var fast_hazard := fast_setup[&"hazard"] as Node
	var tuning := slow_setup[&"tuning"] as Resource
	var player_start_m := 20.0
	var elapsed_s := 0.5

	slow_hazard.call("start_at_progress", player_start_m)
	fast_hazard.call("start_at_progress", player_start_m)
	var slow_initial_boulder_m := float(
		slow_hazard.call("boulder_progress_m")
	)
	var fast_initial_boulder_m := float(
		fast_hazard.call("boulder_progress_m")
	)
	var initial_gap_m := float(
		slow_hazard.call("gap_to_progress_m", player_start_m)
	)
	var equal_speed_player_m := (
		player_start_m
		+ float(tuning.get("boulder_speed_mps")) * elapsed_s
	)
	var slow_outcome: Dictionary = slow_hazard.call(
		"advance_progress",
		elapsed_s,
		player_start_m
	)
	var fast_outcome: Dictionary = fast_hazard.call(
		"advance_progress",
		elapsed_s,
		player_start_m
		+ float(tuning.get("boulder_start_gap_m")) * 10.0
	)
	var slow_advance_m := (
		float(slow_hazard.call("boulder_progress_m"))
		- slow_initial_boulder_m
	)
	var fast_advance_m := (
		float(fast_hazard.call("boulder_progress_m"))
		- fast_initial_boulder_m
	)

	assert_almost_eq(
		slow_advance_m,
		float(tuning.get("boulder_speed_mps")) * elapsed_s,
		PROGRESS_TOLERANCE_M,
		"the boulder must advance only by tuned speed × delta"
	)
	assert_almost_eq(
		slow_advance_m,
		fast_advance_m,
		PROGRESS_TOLERANCE_M,
		"the same elapsed time must advance the boulder identically "
		+ "against very different player progressions"
	)
	assert_almost_eq(
		float(slow_hazard.call(
			"gap_to_progress_m",
			equal_speed_player_m
		)),
		initial_gap_m,
		PROGRESS_TOLERANCE_M,
		"equal player and boulder progress must preserve a constant gap"
	)
	assert_false(
		bool(slow_outcome.get(&"caught", true)),
		"the slow-player sample must remain outside the lethal plane"
	)
	assert_false(
		bool(fast_outcome.get(&"caught", true)),
		"the distant player must remain safe without changing boulder speed"
	)


func test_boulder_kills_at_the_tuned_distance_and_not_before() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var tuning := setup[&"tuning"] as Resource
	var player_start_m := 20.0
	hazard.call("start_at_progress", player_start_m)
	var boulder_m := float(hazard.call("boulder_progress_m"))
	var kill_distance_m := float(
		tuning.get("boulder_kill_distance_m")
	)

	var safe: Dictionary = hazard.call(
		"advance_progress",
		0.0,
		boulder_m + kill_distance_m + PROGRESS_TOLERANCE_M
	)
	assert_false(
		bool(safe.get(&"caught", true)),
		"a player outside the tuned kill distance must remain safe"
	)

	hazard.call("start_at_progress", player_start_m)
	boulder_m = float(hazard.call("boulder_progress_m"))
	var caught: Dictionary = hazard.call(
		"advance_progress",
		0.0,
		boulder_m + kill_distance_m
	)
	assert_true(
		bool(caught.get(&"caught", false)),
		"the tuned kill distance must be the exact catch boundary"
	)


func test_start_and_stop_segment_events_control_chase_state() -> void:
	var setup := _new_hazard()
	if setup.is_empty():
		return
	var hazard := setup[&"hazard"] as Node
	var tuning := setup[&"tuning"] as Resource

	hazard.call(
		"handle_segment_event",
		&"start",
		30.0
	)
	assert_true(hazard.call("is_active"))
	assert_almost_eq(
		float(hazard.call(
			"gap_to_progress_m",
			30.0
		)),
		float(tuning.get("boulder_start_gap_m")),
		PROGRESS_TOLERANCE_M
	)

	hazard.call(
		"handle_segment_event",
		&"stop",
		30.0
	)
	assert_false(hazard.call("is_active"))


func _new_hazard() -> Dictionary:
	assert_true(
		ResourceLoader.exists(CHASE_SCRIPT_PATH),
		"Wave C must provide the chase hazard script"
	)
	assert_true(
		ResourceLoader.exists(CHASE_TUNING_PATH),
		"Wave C must provide authored chase tuning"
	)
	if (
		not ResourceLoader.exists(CHASE_SCRIPT_PATH)
		or not ResourceLoader.exists(CHASE_TUNING_PATH)
	):
		return {}
	var script := load(CHASE_SCRIPT_PATH) as Script
	var tuning := load(CHASE_TUNING_PATH) as Resource
	assert_not_null(script)
	assert_not_null(tuning)
	if script == null or tuning == null:
		return {}
	var hazard := script.new() as Node
	assert_not_null(hazard)
	if hazard == null:
		return {}
	var path := Path3D.new()
	path.name = "Path"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0.0, 0.0, -100.0))
	hazard.add_child(path)
	hazard.set("chase_path_path", NodePath("Path"))
	add_child_autofree(hazard)
	assert_true(
		hazard.has_method("configure_logic"),
		"the headless chase contract must stay separate from scene glue"
	)
	if not hazard.has_method("configure_logic"):
		return {}
	hazard.call("configure_logic", tuning)
	return {
		&"hazard": hazard,
		&"tuning": tuning,
	}


func _new_real_hazard() -> Dictionary:
	var packed := load(BOULDERS_SCENE_PATH) as PackedScene
	var catalog := load(GAMEPLAY_TUNING_PATH) as GameplayTuning
	assert_not_null(packed)
	assert_not_null(catalog)
	if packed == null or catalog == null:
		return {}
	var level := packed.instantiate() as Node3D
	add_child_autofree(level)
	await wait_process_frames(1)
	var hazard := level.get_node_or_null(
		"ChaseHazard"
	) as Node
	var path := level.get_node_or_null(
		"ChaseHazard/Path"
	) as Path3D
	var player := level.get_node_or_null(
		"Player"
	) as Node3D
	assert_not_null(hazard)
	assert_not_null(path)
	assert_not_null(player)
	if hazard == null or path == null or player == null:
		return {}
	hazard.call(
		"configure",
		catalog.chase,
		player
	)
	return {
		&"level": level,
		&"hazard": hazard,
		&"path": path,
		&"player": player,
		&"catalog": catalog,
		&"tuning": catalog.chase,
	}


func _mesh_forward_extent_m(
	visual: Node3D,
	mesh_instance: MeshInstance3D,
	chase_forward: Vector3
) -> float:
	var bounds := mesh_instance.get_aabb()
	var maximum_extent_m := -INF
	for endpoint_index: int in range(8):
		var world_point := (
			mesh_instance.global_transform
			* bounds.get_endpoint(endpoint_index)
		)
		maximum_extent_m = maxf(
			maximum_extent_m,
			(world_point - visual.global_position).dot(
				chase_forward
			)
		)
	return maximum_extent_m
