extends GutTest

const CONTROLLER_SCRIPT_PATH := "res://src/gameplay/player/player_controller.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"

var _move: MoveTuning
var _input: InputTuning
var _depth: DepthTuning


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_move = catalog.move
		_input = catalog.input
		_depth = catalog.depth


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


func test_double_jump_release_uses_its_own_tap_height() -> void:
	var setup := _new_controller()
	if setup.is_empty():
		return
	var controller: CharacterBody3D = setup["controller"]
	var buffer: InputIntentBuffer = setup["buffer"]
	var move_variant: MoveTuning = _move.duplicate()
	move_variant.double_jump_tap_height_m = 1.3
	controller.call("configure", move_variant, _input, _depth, buffer)
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
	controller.call("configure", _move, _input, _depth, buffer)
	return {
		"controller": controller,
		"collision_shape": collision_shape,
		"hurtbox_shape": hurtbox_shape,
		"spin_shape": spin_shape,
		"slam_area": slam_area,
		"slam_shape": slam_shape,
		"visual": visual,
		"buffer": buffer,
	}
