extends GutTest

const LOGIC_PATH := "res://src/gameplay/crates/crate_logic.gd"
const STANDARD_SCENE := "res://scenes/props/crate_standard.tscn"
const BOUNCE_SCENE := "res://scenes/props/crate_bounce.tscn"
const IRON_SCENE := "res://scenes/props/crate_iron.tscn"
const CHECKPOINT_SCENE := "res://scenes/props/crate_checkpoint.tscn"
const TNT_SCENE := "res://scenes/props/crate_tnt.tscn"
const AKU_SCENE := "res://scenes/props/crate_aku.tscn"
const TIME_SCENE := "res://scenes/props/crate_time.tscn"
const WUMPA_SCENE := "res://scenes/props/wumpa.tscn"

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
			_economy.bounce_crate_wumpa_per_bounce
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
		0.0,
		_economy,
		_move,
		_input
	)
	var expected_speed := JumpKinematics.upward_speed_for_height(
		_economy.bounce_launch_height_m,
		_move
	)

	assert_almost_eq(actual_speed, expected_speed, 0.0001)


func test_high_bounce_branch_consumes_live_bounce_timing_window() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	var press_offset_s := (
		_input.bounce_timing_s + _input.bounce_timing_s
	)

	var outside_speed: float = logic.call(
		"bounce_launch_speed",
		press_offset_s,
		_economy,
		_move,
		_input
	)
	var widened_input := _input.duplicate(true) as InputTuning
	widened_input.bounce_timing_s = press_offset_s
	var inside_speed: float = logic.call(
		"bounce_launch_speed",
		press_offset_s,
		_economy,
		_move,
		widened_input
	)

	assert_almost_eq(
		outside_speed,
		JumpKinematics.upward_speed_for_height(
			_move.jump_full_height_m,
			_move
		),
		0.0001
	)
	assert_almost_eq(
		inside_speed,
		JumpKinematics.upward_speed_for_height(
			_economy.bounce_launch_height_m,
			_move
		),
		0.0001
	)
	assert_ne(outside_speed, inside_speed)


func test_tnt_spin_detonates_while_touch_and_bounce_start_full_fuse() -> void:
	var logic := _logic_script()
	if logic == null:
		return

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
		assert_eq(contact["fuse_s"], _economy.tnt_fuse_s)
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
	crate.call("apply_verb", &"spin", _economy.tnt_fuse_s)
	assert_eq(detonations.size(), 1)


func test_tnt_fuse_uses_simulated_clock_and_exact_tuned_boundary() -> void:
	var logic := _logic_script()
	if logic == null:
		return
	var started_at_s := _economy.tnt_blast_radius_m
	var deadline_s: float = logic.call(
		"tnt_fuse_deadline",
		started_at_s,
		_economy
	)

	assert_eq(
		deadline_s,
		started_at_s + _economy.tnt_fuse_s
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
	var radius := _economy.tnt_blast_radius_m
	var positions: Dictionary = {
		1: Vector3(radius - _input.bounce_timing_s, 0.0, 0.0),
		2: Vector3(radius, 0.0, 0.0),
		3: Vector3(radius + radius, 0.0, 0.0),
	}

	var affected: Array = logic.call(
		"blast_crate_ids",
		Vector3.ZERO,
		positions,
		_economy
	)

	assert_eq(affected, [1, 2])


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
	add_child_autofree(crate)
	crate.call("configure", _economy, _move, _input)
	var blast_time_s := _economy.tnt_blast_radius_m
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
		blast_time_s + _economy.tnt_fuse_s
	)
	assert_false(crate.call(
		"advance_fuse",
		blast_time_s + _economy.tnt_fuse_s - _input.bounce_timing_s
	))
	assert_true(crate.call(
		"advance_fuse",
		blast_time_s + _economy.tnt_fuse_s
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
	add_child_autofree(normal_crate)
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


func test_graybox_scenes_keep_type_and_identity_on_live_node_glue() -> void:
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
