extends GutTest

const LOGIC_PATH := "res://src/gameplay/crates/crate_logic.gd"
const LEVEL_SESSION_PATH := "res://src/gameplay/run/level_session.gd"
const STANDARD_SCENE := "res://scenes/props/crate_standard.tscn"
const BOUNCE_SCENE := "res://scenes/props/crate_bounce.tscn"
const IRON_SCENE := "res://scenes/props/crate_iron.tscn"
const CHECKPOINT_SCENE := "res://scenes/props/crate_checkpoint.tscn"
const TNT_SCENE := "res://scenes/props/crate_tnt.tscn"
const AKU_SCENE := "res://scenes/props/crate_aku.tscn"
const TIME_SCENE := "res://scenes/props/crate_time.tscn"
const WUMPA_SCENE := "res://scenes/props/wumpa.tscn"
const LIVE_BOUNCE_WUMPA_PROBE := 7
const LIVE_TNT_FUSE_PROBE_S := 4.25
const LIVE_TNT_RADIUS_PROBE_M := 3.25
const CLOCK_ORIGIN_PROBE_S := 11.0

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _move: MoveTuning
var _input: InputTuning


func before_each() -> void:
	_catalog = load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	_economy = _catalog.economy
	_move = _catalog.move
	_input = _catalog.input


func test_catalog_copy_isolates_nested_authored_tuning_resources() -> void:
	var authored := load(
		"res://data/tuning/gameplay.tres"
	) as GameplayTuning
	var authored_fuse_s := authored.economy.tnt_fuse_s

	_catalog.economy.tnt_fuse_s = authored_fuse_s + 1.0
	var value_after_copy_mutation := authored.economy.tnt_fuse_s
	_catalog.economy.tnt_fuse_s = authored_fuse_s

	assert_eq(
		value_after_copy_mutation,
		authored_fuse_s,
		"mutating a test catalog must not poison the cached authored resource"
	)
	assert_ne(_catalog.economy, authored.economy)


func test_standard_breaks_to_each_attack_and_pays_tuned_wumpa() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	_economy.wumpa_per_standard_crate += (
		_economy.wumpa_per_standard_crate
	)

	for verb: StringName in [
		&"spin",
		&"jump_under",
		&"slam",
		&"slide",
	]:
		var result: Dictionary = logic.call(
			"break_result",
			&"standard",
			verb,
			_economy
		)
		assert_true(result["breaks"])
		assert_eq(
			result["wumpa"],
			_economy.wumpa_per_standard_crate
		)
		assert_false(result["detonates"])
		assert_false(result["bounces_player"])


func test_iron_never_breaks_but_top_contact_bounces_player() -> void:
	var logic := _logic_script()
	if logic == null:
		return

	for verb: StringName in [
		&"spin",
		&"jump_under",
		&"slam",
		&"slide",
		&"bounce",
	]:
		var result: Dictionary = logic.call(
			"break_result",
			&"iron",
			verb,
			_economy
		)
		assert_false(result["breaks"])
		assert_eq(result["wumpa"], 0)
		assert_false(result["detonates"])
		assert_eq(result["bounces_player"], verb == &"bounce")


func test_bounce_crate_pays_each_bounce_and_breaks_at_tuned_limit() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	_economy.bounce_crate_wumpa_per_bounce = (
		LIVE_BOUNCE_WUMPA_PROBE
	)
	var bounce_count := 0

	while bounce_count < _economy.bounce_crate_max_bounces:
		bounce_count += 1
		var result: Dictionary = logic.call(
			"bounce_step",
			bounce_count,
			_economy
		)
		assert_eq(
			result["wumpa"],
			LIVE_BOUNCE_WUMPA_PROBE
		)
		assert_eq(
			result["breaks"],
			bounce_count == _economy.bounce_crate_max_bounces
		)


func test_timed_bounce_launch_reaches_the_tuned_height() -> void:
	var logic := _logic_script()
	if logic == null:
		return

	var actual_speed: float = logic.call(
		"bounce_launch_speed",
		true,
		_economy,
		_move
	)
	var expected_speed := JumpKinematics.upward_speed_for_height(
		_economy.bounce_launch_height_m,
		_move
	)

	assert_almost_eq(actual_speed, expected_speed, 0.0001)


func test_bounce_launch_uses_explicit_normal_and_high_heights() -> void:
	var logic := _logic_script()
	if logic == null:
		return

	var normal_speed: float = logic.call(
		"bounce_launch_speed",
		false,
		_economy,
		_move
	)
	var high_speed: float = logic.call(
		"bounce_launch_speed",
		true,
		_economy,
		_move
	)

	assert_almost_eq(
		normal_speed,
		JumpKinematics.upward_speed_for_height(
			_move.jump_full_height_m,
			_move
		),
		0.0001
	)
	assert_almost_eq(
		high_speed,
		JumpKinematics.upward_speed_for_height(
			_economy.bounce_launch_height_m,
			_move
		),
		0.0001
	)
	assert_ne(normal_speed, high_speed)


func test_tnt_spin_detonates_while_touch_and_bounce_start_full_fuse() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	_economy.tnt_fuse_s = LIVE_TNT_FUSE_PROBE_S

	var spin: Dictionary = logic.call(
		"break_result",
		&"tnt",
		&"spin",
		_economy
	)
	assert_true(spin["breaks"])
	assert_true(spin["detonates"])

	for verb: StringName in [&"touch", &"bounce"]:
		var contact: Dictionary = logic.call(
			"tnt_contact_result",
			verb,
			_economy
		)
		assert_true(contact["starts_fuse"])
		assert_false(contact["detonates"])
		assert_eq(contact["fuse_s"], LIVE_TNT_FUSE_PROBE_S)
	assert_true(
		logic.call(
			"tnt_contact_result",
			&"bounce",
			_economy
		)["bounces_player"]
	)

	var crate := _instantiate(TNT_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)
	var detonations: Array[int] = []
	crate.connect(
		&"detonated",
		func(crate_id: int, _origin: Vector3) -> void:
			detonations.append(crate_id)
	)
	crate.call("apply_verb", &"spin", LIVE_TNT_FUSE_PROBE_S)
	assert_eq(detonations.size(), 1)


func test_tnt_fuse_uses_simulated_clock_and_exact_tuned_boundary() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	_economy.tnt_fuse_s = LIVE_TNT_FUSE_PROBE_S
	var started_at_s := CLOCK_ORIGIN_PROBE_S
	var deadline_s: float = logic.call(
		"tnt_fuse_deadline",
		started_at_s,
		_economy
	)

	assert_eq(
		deadline_s,
		started_at_s + LIVE_TNT_FUSE_PROBE_S
	)
	assert_false(
		logic.call(
			"tnt_fuse_elapsed",
			started_at_s,
			deadline_s - _input.bounce_timing_s,
			_economy
		)
	)
	assert_true(
		logic.call(
			"tnt_fuse_elapsed",
			started_at_s,
			deadline_s,
			_economy
		)
	)


func test_tnt_blast_set_uses_tuned_radius_and_inclusive_boundary() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	_economy.tnt_blast_radius_m = LIVE_TNT_RADIUS_PROBE_M
	var positions: Dictionary = {
		1: Vector3(
			LIVE_TNT_RADIUS_PROBE_M - _input.bounce_timing_s,
			0.0,
			0.0
		),
		2: Vector3(LIVE_TNT_RADIUS_PROBE_M, 0.0, 0.0),
		3: Vector3(
			LIVE_TNT_RADIUS_PROBE_M + LIVE_TNT_RADIUS_PROBE_M,
			0.0,
			0.0
		),
	}

	var affected: Array = logic.call(
		"blast_crate_ids",
		Vector3.ZERO,
		positions,
		_economy
	)

	assert_eq(affected, [1, 2])


func test_real_tnt_blast_respects_occlusion_and_all_three_axes() -> void:
	var session_script := load(LEVEL_SESSION_PATH) as Script
	assert_not_null(session_script)
	if session_script == null or not session_script.can_instantiate():
		return
	_economy.tnt_blast_radius_m = LIVE_TNT_RADIUS_PROBE_M
	var session := session_script.new() as Node
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var radius := LIVE_TNT_RADIUS_PROBE_M
	var inside_offset := radius - _input.bounce_timing_s
	var outside_offset := radius + _input.bounce_timing_s
	var source := _instantiate(TNT_SCENE) as StaticBody3D
	var visible_x := _instantiate(STANDARD_SCENE) as StaticBody3D
	var occluded_z := _instantiate(STANDARD_SCENE) as StaticBody3D
	var inside_y := _instantiate(STANDARD_SCENE) as StaticBody3D
	var outside_y := _instantiate(STANDARD_SCENE) as StaticBody3D
	var outside_z := _instantiate(STANDARD_SCENE) as StaticBody3D
	var crates: Array[StaticBody3D] = [
		source,
		visible_x,
		occluded_z,
		inside_y,
		outside_y,
		outside_z,
	]
	for crate: StaticBody3D in crates:
		assert_not_null(crate)
		if crate == null:
			return
		session.add_child(crate)
	for crate_index: int in range(crates.size()):
		crates[crate_index].set("crate_id", crate_index + 1)
	visible_x.position = Vector3(inside_offset, 0.0, 0.0)
	occluded_z.position = Vector3(0.0, 0.0, inside_offset)
	inside_y.position = Vector3(0.0, inside_offset, 0.0)
	outside_y.position = Vector3(0.0, -outside_offset, 0.0)
	outside_z.position = Vector3(0.0, 0.0, -outside_offset)

	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 0.0, inside_offset * 0.5)
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(
		radius,
		radius,
		_input.bounce_timing_s
	)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	session.add_child(wall)

	add_child_autofree(session)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = crates.size()
	assert_true(session.call(
		"configure",
		meta,
		&"normal",
		_economy,
		null,
		_move,
		_input
	))
	await wait_physics_frames(2)

	source.call("apply_verb", &"spin", CLOCK_ORIGIN_PROBE_S)

	assert_true(source.call("is_broken"))
	assert_true(visible_x.call("is_broken"))
	assert_true(inside_y.call("is_broken"))
	assert_false(
		occluded_z.call("is_broken"),
		"solid world geometry must block the blast"
	)
	assert_false(
		outside_y.call("is_broken"),
		"the radius must include the Y axis"
	)
	assert_false(
		outside_z.call("is_broken"),
		"the radius must include the Z axis"
	)


func test_blast_broken_crates_report_collected_and_chain_tnt_refuses() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	for crate_type: StringName in [
		&"standard",
		&"bounce",
		&"checkpoint",
		&"aku",
		&"time",
	]:
		var result: Dictionary = logic.call(
			"blast_result",
			crate_type,
			_economy
		)
		assert_true(result["breaks"])
		assert_true(result["collected"])
		assert_false(result["starts_fuse"])

	var chained_tnt: Dictionary = logic.call(
		"blast_result",
		&"tnt",
		_economy
	)
	assert_false(chained_tnt["breaks"])
	assert_false(chained_tnt["collected"])
	assert_true(chained_tnt["starts_fuse"])


func test_chained_tnt_runs_its_own_full_fuse_from_blast_time() -> void:
	var crate := _instantiate(TNT_SCENE)
	if crate == null:
		return
	_economy.tnt_fuse_s = LIVE_TNT_FUSE_PROBE_S
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)
	var blast_time_s := CLOCK_ORIGIN_PROBE_S
	var detonations: Array[int] = []
	crate.connect(
		&"detonated",
		func(crate_id: int, _origin: Vector3) -> void:
			detonations.append(crate_id)
	)

	var blast: Dictionary = crate.call("apply_blast", blast_time_s)

	assert_true(blast["starts_fuse"])
	assert_true(crate.call("tnt_fuse_active"))
	assert_eq(
		crate.call("tnt_fuse_deadline_s"),
		blast_time_s + LIVE_TNT_FUSE_PROBE_S
	)
	assert_false(crate.call(
		"advance_fuse",
		blast_time_s + LIVE_TNT_FUSE_PROBE_S - _input.bounce_timing_s
	))
	assert_true(crate.call(
		"advance_fuse",
		blast_time_s + LIVE_TNT_FUSE_PROBE_S
	))
	assert_eq(detonations.size(), 1)


func test_checkpoint_break_emits_exactly_once() -> void:
	var crate := _instantiate(CHECKPOINT_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.set("crate_id", _economy.mercy_mask_death_threshold)
	crate.call("configure", _economy, _move, _input)
	var reached: Array[int] = []
	crate.connect(
		&"checkpoint_reached",
		func(crate_id: int) -> void:
			reached.append(crate_id)
	)

	crate.call("apply_verb", &"spin")
	crate.call("apply_verb", &"slam")

	assert_eq(
		reached,
		[_economy.mercy_mask_death_threshold]
	)


func test_aku_break_emits_one_mask_grant() -> void:
	var crate := _instantiate(AKU_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)
	var grants: Array[int] = []
	crate.connect(
		&"mask_granted",
		func(amount: int) -> void:
			grants.append(amount)
	)

	crate.call("apply_verb", &"jump_under")
	crate.call("apply_verb", &"spin")

	assert_eq(grants, [1])


func test_time_crate_refuses_normal_mode_and_awards_tuning_in_relic_mode() -> void:
	var normal_crate := _instantiate(TIME_SCENE)
	if normal_crate == null:
		return
	assert_false(
		normal_crate.call("is_armed"),
		"a time crate must be disarmed before tree entry or configuration"
	)
	add_child_autofree(normal_crate)
	await wait_physics_frames(1)
	assert_false(normal_crate.get_node("Mesh").visible)
	assert_true(
		normal_crate.get_node("CollisionShape3D").disabled,
		"default-disarmed time crates must not retain live collision"
	)
	normal_crate.call("configure", _economy, _move, _input, false)

	assert_false(normal_crate.call("is_armed"))
	assert_false(normal_crate.call("apply_verb", &"spin")["breaks"])

	var relic_crate := _instantiate(TIME_SCENE)
	if relic_crate == null:
		return
	add_child_autofree(relic_crate)
	relic_crate.call("configure", _economy, _move, _input, true)
	var awards: Array[float] = []
	relic_crate.connect(
		&"time_awarded",
		func(seconds: float) -> void:
			awards.append(seconds)
	)

	assert_true(relic_crate.call("is_armed"))
	assert_true(relic_crate.call("apply_verb", &"spin")["breaks"])
	assert_eq(awards, [_economy.time_crate_small_s])

	var logic := _logic_script()
	assert_eq(
		logic.call("time_bonus_s", &"medium", _economy),
		_economy.time_crate_medium_s
	)
	assert_eq(
		logic.call("time_bonus_s", &"large", _economy),
		_economy.time_crate_large_s
	)


func test_crate_scenes_keep_type_and_identity_on_live_node_glue() -> void:
	for scene_case: Array in [
		[STANDARD_SCENE, &"standard"],
		[BOUNCE_SCENE, &"bounce"],
		[IRON_SCENE, &"iron"],
		[CHECKPOINT_SCENE, &"checkpoint"],
		[TNT_SCENE, &"tnt"],
		[AKU_SCENE, &"aku"],
		[TIME_SCENE, &"time"],
	]:
		var crate := _instantiate(scene_case[0])
		if crate == null:
			return
		add_child_autofree(crate)
		assert_eq(crate.get("crate_type"), scene_case[1])
		assert_eq(crate.get("crate_id"), 0)
		assert_eq(crate.get("segment_group"), &"")

	var wumpa := _instantiate(WUMPA_SCENE)
	if wumpa == null:
		return
	add_child_autofree(wumpa)
	assert_true(wumpa is Area3D)


func test_standard_crate_art_matches_the_graybox_collision_bounds() -> void:
	var crate := _instantiate(STANDARD_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)

	var visual_root := crate.get_node("Mesh") as MeshInstance3D
	assert_not_null(visual_root)
	assert_null(
		visual_root.mesh,
		"the standard crate must replace, not overlap, the BoxMesh placeholder"
	)
	var model := visual_root.get_node_or_null("Model") as Node3D
	assert_not_null(model)
	if model == null:
		return
	var imported_meshes := model.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)
	assert_eq(imported_meshes.size(), 1)
	if imported_meshes.size() != 1:
		return
	var imported_mesh := imported_meshes[0] as MeshInstance3D
	var model_aabb := imported_mesh.get_aabb()
	assert_true(
		model_aabb.position.is_equal_approx(Vector3(-0.5, 0.0, -0.5))
	)
	assert_true(model_aabb.size.is_equal_approx(Vector3.ONE))
	assert_true(model.position.is_equal_approx(Vector3(0.0, -0.5, 0.0)))
	assert_true(
		(model_aabb.position + model.position).is_equal_approx(
			Vector3(-0.5, -0.5, -0.5)
		),
		"the contact-origin GLB must be offset onto the centered gameplay body"
	)
	assert_eq(imported_mesh.mesh.get_surface_count(), 1)


func test_every_remaining_crate_variant_has_matching_art_and_collision_bounds() -> void:
	for scene_case: Array in [
		[BOUNCE_SCENE, "SM_crate_bounce"],
		[TNT_SCENE, "SM_crate_tnt"],
		[CHECKPOINT_SCENE, "SM_crate_checkpoint"],
		[IRON_SCENE, "SM_crate_iron"],
		[AKU_SCENE, "SM_crate_aku"],
		[TIME_SCENE, "SM_crate_time"],
	]:
		var crate := _instantiate(scene_case[0])
		if crate == null:
			return
		add_child_autofree(crate)

		var visual_root := crate.get_node("Mesh") as MeshInstance3D
		assert_not_null(visual_root)
		assert_null(
			visual_root.mesh,
			"%s must replace, not overlap, the BoxMesh placeholder" % scene_case[0]
		)
		var model := visual_root.get_node_or_null("Model") as Node3D
		assert_not_null(model, "%s must mount its imported GLB" % scene_case[0])
		if model == null:
			return
		var imported_meshes := model.find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		)
		assert_eq(
			imported_meshes.size(),
			1,
			"%s must stay one draw-call surface" % scene_case[0]
		)
		if imported_meshes.size() != 1:
			return
		var imported_mesh := imported_meshes[0] as MeshInstance3D
		assert_eq(imported_mesh.name, scene_case[1])
		var model_aabb := imported_mesh.get_aabb()
		assert_true(
			model_aabb.position.is_equal_approx(Vector3(-0.5, 0.0, -0.5))
		)
		assert_true(model_aabb.size.is_equal_approx(Vector3.ONE))
		assert_true(model.position.is_equal_approx(Vector3(0.0, -0.5, 0.0)))
		assert_true(
			(model_aabb.position + model.position).is_equal_approx(
				Vector3(-0.5, -0.5, -0.5)
			)
		)
		assert_eq(imported_mesh.mesh.get_surface_count(), 1)


func test_standard_node_emits_tuned_break_payload_once() -> void:
	var crate := _instantiate(STANDARD_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.set("crate_id", _economy.bounce_crate_max_bounces)
	crate.call("configure", _economy, _move, _input)
	var emissions: Array[Array] = []
	crate.connect(
		&"broken",
		func(crate_id: int, wumpa: int) -> void:
			emissions.append([crate_id, wumpa])
	)

	var first: Dictionary = crate.call("apply_verb", &"spin")
	var second: Dictionary = crate.call("apply_verb", &"spin")

	assert_true(first["breaks"])
	assert_false(second["breaks"])
	assert_eq(
		emissions,
		[[
			_economy.bounce_crate_max_bounces,
			_economy.wumpa_per_standard_crate,
		]]
	)


func test_finish_break_guard_blocks_a_second_broken_emission() -> void:
	# apply_verb/apply_bounce/apply_blast/_detonate all already check
	# _broken before ever reaching _finish_break, so this backstop guard
	# is never exercised through the public API. Calling it directly
	# proves the guard itself holds independent of those outer checks --
	# load-bearing for any future caller (e.g. a re-sync path) that
	# reaches _finish_break without going through them.
	var crate := _instantiate(STANDARD_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)
	var emissions: Array[int] = []
	crate.connect(
		&"broken",
		func(_crate_id: int, wumpa: int) -> void:
			emissions.append(wumpa)
	)

	crate.call("_finish_break", 5)
	crate.call("_finish_break", 9)

	assert_eq(
		emissions,
		[5],
		"_finish_break's own guard must block a second emission on repeat calls"
	)


func test_sync_break_state_honestly_marks_broken_and_rearms() -> void:
	var crate := _instantiate(BOUNCE_SCENE)
	if crate == null:
		return
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)

	crate.call("sync_break_state", true, false)
	await wait_physics_frames(1)
	assert_true(crate.call("is_broken"))
	assert_true(crate.get_node("CollisionShape3D").disabled)
	assert_false(crate.get_node("Mesh").visible)
	assert_false(
		crate.call("apply_bounce", false)["breaks"],
		"an already-broken crate must not pay out or break again"
	)

	crate.call("sync_break_state", false, false)
	await wait_physics_frames(1)
	assert_false(
		crate.call("is_broken"),
		"the honest re-arm path must clear the broken flag"
	)
	assert_false(
		crate.get_node("CollisionShape3D").disabled,
		"a re-armed crate must regain live collision"
	)
	assert_true(
		crate.get_node("Mesh").visible,
		"a re-armed crate must regain its visible mesh"
	)

	# The bounce counter must be genuinely reset, not just the broken flag --
	# a fresh first bounce after re-arming must pay out exactly like a
	# brand-new crate, proving _bounce_count was really cleared rather
	# than just flipping _broken back to false.
	var fresh := _instantiate(BOUNCE_SCENE)
	if fresh == null:
		return
	add_child_autofree(fresh)
	fresh.call("configure", _economy, _move, _input)
	var fresh_first: Dictionary = fresh.call("apply_bounce", false)
	var rearmed_first: Dictionary = crate.call("apply_bounce", false)
	assert_eq(rearmed_first["wumpa"], fresh_first["wumpa"])
	assert_false(rearmed_first["breaks"])


func _logic_script() -> Script:
	assert_true(
		ResourceLoader.exists(LOGIC_PATH),
		"CrateLogic implementation must exist"
	)
	return load(LOGIC_PATH) as Script if ResourceLoader.exists(LOGIC_PATH) else null


func _instantiate(path: String) -> Node:
	assert_true(ResourceLoader.exists(path), path + " must exist")
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	assert_not_null(packed)
	return packed.instantiate() if packed != null else null
