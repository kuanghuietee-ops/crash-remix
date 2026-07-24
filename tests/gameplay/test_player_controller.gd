extends GutTest

const CONTROLLER_SCRIPT_PATH := "res://src/gameplay/player/player_controller.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _move: MoveTuning
var _input: InputTuning
var _depth: DepthTuning
var _wall_run: WallRunTuning
var _grind: GrindTuning
var _swing: SwingTuning
var _economy: EconomyTuning


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.move
		_input = catalog.input
		_depth = catalog.depth
		_wall_run = catalog.wall_run
		_grind = catalog.grind
		_swing = catalog.swing
		_economy = catalog.economy


func test_controller_binds_run_and_jump_decisions_to_character_velocity() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.call("advance_logic", 1.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.move(Vector2.UP, 1.01, &"touch"))
	controller.call(
		"advance_logic",
		1.01,
		true,
		_move.run_time_to_speed_s,
		Vector3.FORWARD
	)
	assert_almost_eq(
		Vector2(controller.velocity.x, controller.velocity.z).length(),
		_move.run_speed_mps,
		0.0001
	)

	buffer.push(InputIntent.button(&"jump", true, 1.02, &"touch"))
	var decision: RefCounted = controller.call(
		"advance_logic", 1.02, true, 0.0, Vector3.FORWARD
	)
	assert_eq(decision.get("impulse"), &"jump")
	assert_almost_eq(
		controller.velocity.y,
		JumpKinematics.upward_speed_for_height(_move.jump_full_height_m, _move),
		0.0001
	)


func test_controller_applies_variable_release_and_terminal_fall_speed() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.call("advance_logic", 10.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 10.01, &"touch"))
	controller.call("advance_logic", 10.01, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", false, 10.06, &"touch"))
	controller.call("advance_logic", 10.06, false, 0.0, Vector3.FORWARD)
	assert_almost_eq(
		controller.velocity.y,
		JumpKinematics.upward_speed_for_height(_move.jump_tap_height_m, _move),
		0.0001
	)

	controller.velocity = Vector3.ZERO
	controller.call("advance_logic", 20.0, false, 10.0, Vector3.FORWARD)
	assert_eq(controller.velocity.y, -_move.maximum_fall_speed_mps)


func test_bounce_contact_accepts_jump_held_before_timing_window() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var press_s := 15.0
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		press_s,
		InputIntent.SOURCE_TOUCH
	))
	controller.call(
		"advance_logic",
		press_s,
		true,
		0.0,
		Vector3.FORWARD
	)
	controller.call(
		"advance_logic",
		press_s + _input.bounce_timing_s + _input.bounce_timing_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_true(
		controller.call(
			"consume_bounce_contact_intent",
			press_s
				+ _input.bounce_timing_s
				+ _input.bounce_timing_s
		),
		"a held JUMP must still request a high bounce after the timing window"
	)


func test_post_contact_jump_upgrades_bounce_at_tuned_boundary() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var contact_s := 20.0
	var ordinary_speed := JumpKinematics.upward_speed_for_height(
		_move.jump_full_height_m,
		_move
	)
	controller.velocity.y = ordinary_speed
	controller.call(
		"begin_bounce_timing_window",
		contact_s,
		false
	)
	var press_s := contact_s + _input.bounce_timing_s
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		press_s,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		false,
		press_s,
		InputIntent.SOURCE_TOUCH
	))
	var decision: RefCounted = controller.call(
		"advance_logic",
		press_s,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(decision.get("impulse"), &"none")
	assert_almost_eq(
		controller.velocity.y,
		JumpKinematics.upward_speed_for_height(
			_economy.bounce_launch_height_m,
			_move
		),
		0.0001,
		"a JUMP at +bounce_timing_s must reach the authored high apex"
	)
	assert_null(buffer.consume_pressed(
		InputIntent.ACTION_JUMP,
		press_s,
		_input.bounce_timing_s
	))


func test_double_jump_release_uses_its_own_tap_height() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var move_variant: MoveTuning = _move.duplicate()
	move_variant.double_jump_tap_height_m = 1.3
	controller.call(
		"configure",
		move_variant,
		_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		buffer
	)
	controller.call("advance_logic", 25.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 25.01, &"touch"))
	controller.call("advance_logic", 25.01, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", false, 25.02, &"touch"))
	controller.call("advance_logic", 25.02, false, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 25.03, &"touch"))
	var double_jump: RefCounted = controller.call(
		"advance_logic", 25.03, false, 0.0, Vector3.FORWARD
	)
	buffer.push(InputIntent.button(&"jump", false, 25.04, &"touch"))
	controller.call("advance_logic", 25.04, false, 0.0, Vector3.FORWARD)

	assert_eq(double_jump.get("impulse"), &"double_jump")
	assert_almost_eq(
		controller.velocity.y,
		JumpKinematics.upward_speed_for_height(
			move_variant.double_jump_tap_height_m,
			move_variant
		),
		0.0001
	)
	assert_ne(
		controller.velocity.y,
		JumpKinematics.upward_speed_for_height(
			move_variant.jump_tap_height_m,
			move_variant
		)
	)


func test_high_jump_ignores_early_release_and_keeps_authored_height() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.call("advance_logic", 26.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"down", true, 26.01, &"touch"))
	controller.call("advance_logic", 26.01, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 26.02, &"touch"))
	var high_jump: RefCounted = controller.call(
		"advance_logic", 26.02, true, 0.0, Vector3.FORWARD
	)
	var launch_speed := JumpKinematics.upward_speed_for_height(
		_move.high_jump_height_m,
		_move
	)
	buffer.push(InputIntent.button(&"jump", false, 26.03, &"touch"))
	controller.call("advance_logic", 26.03, false, 0.0, Vector3.FORWARD)

	assert_eq(high_jump.get("impulse"), &"high_jump")
	assert_almost_eq(controller.velocity.y, launch_speed, 0.0001)


func test_slide_jump_ignores_early_release_and_keeps_authored_height() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.velocity = Vector3.FORWARD * _move.run_speed_mps
	controller.call("advance_logic", 27.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"down", true, 27.01, &"touch"))
	controller.call("advance_logic", 27.01, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 27.02, &"touch"))
	var slide_jump: RefCounted = controller.call(
		"advance_logic", 27.02, true, 0.0, Vector3.FORWARD
	)
	var launch_speed := JumpKinematics.upward_speed_for_height(
		_move.slide_jump_height_m,
		_move
	)
	buffer.push(InputIntent.button(&"jump", false, 27.03, &"touch"))
	controller.call("advance_logic", 27.03, false, 0.0, Vector3.FORWARD)

	assert_eq(slide_jump.get("impulse"), &"slide_jump")
	assert_almost_eq(controller.velocity.y, launch_speed, 0.0001)


func test_controller_updates_crouch_shape_and_commits_body_slam() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var collision_shape: CollisionShape3D = setup["collision_shape"]
	var hurtbox_shape: CollisionShape3D = setup["hurtbox_shape"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.call("advance_logic", 30.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"down", true, 30.01, &"touch"))
	var crouch: RefCounted = controller.call(
		"advance_logic", 30.01, true, 0.0, Vector3.FORWARD
	)
	assert_eq(crouch.get("state"), &"crouched")
	assert_almost_eq(
		(collision_shape.shape as CylinderShape3D).height,
		_move.player_height_m
			* _move.crouch_hurtbox_height_ratio,
		0.0001
	)
	assert_almost_eq(
		(hurtbox_shape.shape as CylinderShape3D).height,
		_move.player_height_m
			* _move.crouch_hurtbox_height_ratio
			* _move.hurtbox_visual_ratio,
		0.0001
	)

	buffer.push(InputIntent.button(&"down", false, 30.02, &"touch"))
	controller.call("advance_logic", 30.02, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 30.03, &"touch"))
	controller.call("advance_logic", 30.03, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"down", true, 30.04, &"touch"))
	var slam: RefCounted = controller.call(
		"advance_logic", 30.04, false, 0.0, Vector3.FORWARD
	)
	assert_eq(slam.get("state"), &"body_slam")
	assert_eq(controller.velocity.y, -_move.body_slam_speed_mps)
	var impact: RefCounted = controller.call(
		"advance_logic", 30.05, true, 0.0, Vector3.FORWARD
	)
	var slam_area: Area3D = setup["slam_area"]
	var slam_shape: CollisionShape3D = setup["slam_shape"]
	assert_eq(impact.get("state"), &"slam_recovery")
	assert_true(slam_area.monitoring)
	assert_almost_eq(
		(slam_shape.shape as SphereShape3D).radius,
		_move.body_slam_shockwave_radius_m,
		0.0001
	)


func test_controller_applies_global_fair_hitbox_ratios() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var collision_shape: CollisionShape3D = setup["collision_shape"]
	var hurtbox_shape: CollisionShape3D = setup["hurtbox_shape"]
	var spin_shape: CollisionShape3D = setup["spin_shape"]
	var visual: Node3D = setup["visual"]

	assert_almost_eq(
		(collision_shape.shape as CylinderShape3D).height,
		_move.player_height_m,
		0.0001
	)
	assert_almost_eq(
		(hurtbox_shape.shape as CylinderShape3D).height,
		_move.player_height_m * _move.hurtbox_visual_ratio,
		0.0001
	)
	assert_almost_eq(visual.scale.y, 1.0, 0.0001)
	assert_almost_eq(
		(spin_shape.shape as SphereShape3D).radius,
		_move.spin_radius_m * _move.attack_visual_ratio,
		0.0001
	)


func test_spin_rotates_visual_pivot_and_resets_at_authored_end_time() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var spin_pivot: Node3D = setup["spin_pivot"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var spin_started_s := 35.01
	controller.call("advance_logic", 35.0, true, 0.0, Vector3.FORWARD)
	buffer.push(
		InputIntent.button(
			InputIntent.ACTION_SPIN,
			true,
			spin_started_s,
			&"touch"
		)
	)

	controller.call(
		"advance_logic",
		spin_started_s,
		true,
		_move.spin_active_s * 0.5,
		Vector3.FORWARD
	)

	assert_true(controller.call("is_spinning"))
	assert_ne(spin_pivot.rotation.y, 0.0)

	controller.call(
		"advance_logic",
		spin_started_s + _move.spin_active_s,
		true,
		0.0,
		Vector3.FORWARD
	)

	assert_false(controller.call("is_spinning"))
	assert_almost_eq(spin_pivot.rotation.y, 0.0, 0.0001)


func test_phase_intent_is_ignored_when_disabled_and_honored_when_enabled() -> void:
	var catalog := load(TUNING_PATH) as GameplayTuning
	PhaseState.configure(catalog.phase)
	for phase_enabled: bool in [false, true]:
		var setup := _new_controller()
		if setup.is_empty():
			return
		var controller: CharacterBody3D = setup["controller"]
		var has_phase_flag := false
		for property: Dictionary in controller.get_property_list():
			if property.get("name") == &"_phase_enabled":
				has_phase_flag = true
				break
		assert_true(
			has_phase_flag,
			"PlayerController needs the runtime PHASE consumption gate"
		)
		if not has_phase_flag:
			return
		var buffer: InputIntentBuffer = setup["buffer"]
		controller.call(
			"configure",
			_move,
			_input,
			_depth,
			_wall_run,
			_grind,
			_swing,
			buffer,
			null,
			phase_enabled
		)
		PhaseState.reset_to_authored_set()
		var before := PhaseState.active_set()
		buffer.push(InputIntent.button(
			InputIntent.ACTION_PHASE,
			true,
			60.0,
			InputIntent.SOURCE_GAMEPAD
		))

		controller.call(
			"advance_logic",
			60.0,
			false,
			0.0,
			Vector3.FORWARD
		)

		if phase_enabled:
			assert_ne(PhaseState.active_set(), before)
		else:
			assert_eq(PhaseState.active_set(), before)


func test_phase_tuning_master_blocks_gamepad_at_player_choke_point() -> void:
	var catalog := load(TUNING_PATH) as GameplayTuning
	PhaseState.configure(catalog.phase)
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var locked_input := _input.duplicate(true)
	locked_input.phase_button_unlocked = false
	controller.call(
		"configure",
		_move,
		locked_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		buffer,
		null,
		true
	)
	PhaseState.reset_to_authored_set()
	var before := PhaseState.active_set()
	buffer.push(InputIntent.button(
		InputIntent.ACTION_PHASE,
		true,
		61.0,
		InputIntent.SOURCE_GAMEPAD
	))

	controller.call(
		"advance_logic",
		61.0,
		false,
		0.0,
		Vector3.FORWARD
	)

	assert_eq(
		PhaseState.active_set(),
		before,
		"tuning master must gate gamepad at the shared player choke point"
	)


func test_respawn_waits_for_authored_delay_and_accepts_exact_boundary() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	controller.global_position = Vector3(3.0, -5.0, 2.0)
	controller.call("request_respawn", 40.0)

	assert_true(controller.call("is_respawning"))
	assert_false(controller.call(
		"advance_respawn",
		40.0 + _move.respawn_delay_s - 0.001
	))
	assert_true(controller.call(
		"advance_respawn",
		40.0 + _move.respawn_delay_s
	))
	assert_eq(controller.global_position, Vector3.ZERO)
	assert_false(controller.call("is_respawning"))


func test_respawn_restores_default_jump_release_profile() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	controller.call("advance_logic", 41.0, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"down", true, 41.01, &"touch"))
	controller.call("advance_logic", 41.01, true, 0.0, Vector3.FORWARD)
	buffer.push(InputIntent.button(&"jump", true, 41.02, &"touch"))
	var high_jump: RefCounted = controller.call(
		"advance_logic", 41.02, true, 0.0, Vector3.FORWARD
	)

	assert_eq(high_jump.get("impulse"), &"high_jump")
	assert_eq(controller.get("_active_jump_tap_height_m"), 0.0)

	controller.call("respawn")

	assert_eq(
		controller.get("_active_jump_tap_height_m"),
		_move.jump_tap_height_m
	)


func test_edge_nudge_directions_are_corridor_relative_and_bias_against_travel() -> void:
	var script: Script = load(CONTROLLER_SCRIPT_PATH)
	assert_not_null(script, "PlayerController implementation must exist")
	if script == null:
		return
	var corridor_forward := Vector3(1.0, 0.0, -1.0).normalized()
	var travel := corridor_forward * 3.0

	var directions: Array = script.call(
		"edge_nudge_directions",
		corridor_forward,
		travel
	)

	assert_eq(directions.size(), 8)
	assert_almost_eq(
		(directions[0] as Vector3).dot(-travel.normalized()),
		1.0,
		0.0001
	)
	assert_true(directions.has(corridor_forward.cross(Vector3.UP).normalized()))


func test_controller_receives_every_traversal_tuning_resource() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]

	controller.call(
		"configure",
		_move,
		_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		buffer
	)

	assert_eq(controller.get("_wall_run_tuning"), _wall_run)
	assert_eq(controller.get("_grind_tuning"), _grind)
	assert_eq(controller.get("_swing_tuning"), _swing)


func test_spline_states_suppress_gravity_and_use_floating_motion() -> void:
	for state: StringName in [&"grind", &"wall_run", &"swing"]:
		var setup := _new_controller()
		if setup.is_empty():
			return
		var controller: CharacterBody3D = setup["controller"]
		var state_machine: RefCounted = controller.get("_state_machine")
		state_machine.set("state", state)
		controller.velocity = Vector3(5.0, 3.0, 2.0)

		var decision: RefCounted = controller.call(
			"advance_logic",
			50.0,
			false,
			0.5,
			Vector3.FORWARD
		)

		assert_eq(decision.get("state"), state)
		assert_eq(controller.velocity, Vector3(0.0, 3.0, 0.0))
		assert_eq(
			controller.motion_mode,
			CharacterBody3D.MOTION_MODE_FLOATING
		)

		state_machine.set("state", &"airborne")
		controller.call(
			"advance_logic",
			50.1,
			false,
			0.0,
			Vector3.FORWARD
		)
		assert_eq(
			controller.motion_mode,
			CharacterBody3D.MOTION_MODE_GROUNDED,
			"leaving %s must restore the ordinary body mode" % state
		)


func _new_controller() -> Dictionary:
	var script: Script = load(CONTROLLER_SCRIPT_PATH)
	assert_not_null(script, "PlayerController implementation must exist")
	if script == null or not script.can_instantiate():
		return {}
	var controller: CharacterBody3D = script.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = CylinderShape3D.new()
	controller.add_child(collision_shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	var spin_pivot := Node3D.new()
	spin_pivot.name = "SpinPivot"
	visual.add_child(spin_pivot)
	controller.add_child(visual)
	var hurtbox := Area3D.new()
	hurtbox.name = "Hurtbox"
	var hurtbox_shape := CollisionShape3D.new()
	hurtbox_shape.name = "CollisionShape3D"
	hurtbox_shape.shape = CylinderShape3D.new()
	hurtbox.add_child(hurtbox_shape)
	controller.add_child(hurtbox)
	var spin_area := Area3D.new()
	spin_area.name = "SpinArea"
	var spin_shape := CollisionShape3D.new()
	spin_shape.name = "CollisionShape3D"
	spin_shape.shape = SphereShape3D.new()
	spin_area.add_child(spin_shape)
	controller.add_child(spin_area)
	var slam_area := Area3D.new()
	slam_area.name = "SlamArea"
	slam_area.monitoring = false
	var slam_shape := CollisionShape3D.new()
	slam_shape.name = "CollisionShape3D"
	slam_shape.shape = SphereShape3D.new()
	slam_area.add_child(slam_shape)
	controller.add_child(slam_area)
	add_child_autofree(controller)
	var buffer := InputIntentBuffer.new()
	controller.call(
		"configure",
		_move,
		_input,
		_depth,
		_wall_run,
		_grind,
		_swing,
		buffer,
		_economy
	)
	return {
		"controller": controller,
		"collision_shape": collision_shape,
		"hurtbox_shape": hurtbox_shape,
		"spin_shape": spin_shape,
		"slam_area": slam_area,
		"slam_shape": slam_shape,
		"visual": visual,
		"spin_pivot": spin_pivot,
		"buffer": buffer,
	}
