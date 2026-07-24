extends GutTest

const LOGIC_PATH := "res://src/gameplay/crates/crate_logic.gd"
const STANDARD_SCENE := "res://scenes/props/crate_standard.tscn"
const BOUNCE_SCENE := "res://scenes/props/crate_bounce.tscn"
const IRON_SCENE := "res://scenes/props/crate_iron.tscn"
const WUMPA_SCENE := "res://scenes/props/wumpa.tscn"

var _catalog: GameplayTuning
var _economy: EconomyTuning
var _move: MoveTuning
var _input: InputTuning


func before_each() -> void:
	_catalog = load(
		"res://data/tuning/gameplay.tres"
	).duplicate(true) as GameplayTuning
	_economy = _catalog.economy
	_move = _catalog.move
	_input = _catalog.input


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


func test_graybox_scenes_keep_type_and_identity_on_live_node_glue() -> void:
	for scene_case: Array in [
		[STANDARD_SCENE, &"standard"],
		[BOUNCE_SCENE, &"bounce"],
		[IRON_SCENE, &"iron"],
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
