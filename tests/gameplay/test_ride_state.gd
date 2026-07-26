extends GutTest

const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"
const FSM_SCRIPT_PATH := (
	"res://src/gameplay/player/player_state_machine.gd"
)
const MOTOR_SCRIPT_PATH := (
	"res://src/gameplay/player/player_motor.gd"
)
const FRAME_DECISION_SCRIPT_PATH := (
	"res://src/gameplay/player/player_frame_decision.gd"
)
const HOG_MOUNT_SCRIPT_PATH := (
	"res://src/gameplay/ride/hog_mount.gd"
)
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const FRAME_DELTA_S := 1.0 / 60.0
const FLOAT_TOLERANCE := 0.0001

var _catalog: Resource
var _move: Resource
var _input: Resource
var _hog: Resource


func before_all() -> void:
	_catalog = load(BASE_CATALOG_PATH)
	assert_not_null(_catalog)
	if _catalog == null:
		return
	_move = _catalog.get("move")
	_input = _catalog.get("input")
	_hog = _catalog.get("hog")


func test_ride_state_accepts_jump_and_keeps_every_other_verb_inert() -> void:
	var fsm_script := load(FSM_SCRIPT_PATH) as Script
	var decision_script := load(FRAME_DECISION_SCRIPT_PATH) as Script
	assert_not_null(fsm_script)
	assert_not_null(decision_script)
	assert_not_null(
		_hog,
		"Wave D needs an authored, typed hog tuning section"
	)
	if (
		fsm_script == null
		or decision_script == null
		or _hog == null
	):
		return
	var fsm := fsm_script.new() as RefCounted
	var buffer := InputIntentBuffer.new()
	assert_true(
		fsm.has_method("enter_ride"),
		"the player FSM needs one explicit mounted state"
	)
	if not fsm.has_method("enter_ride"):
		return
	fsm.call("enter_ride", 1.0)
	buffer.push(InputIntent.button(
		InputIntent.ACTION_SPIN,
		true,
		1.01,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_DOWN,
		true,
		1.01,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		1.01,
		InputIntent.SOURCE_TOUCH
	))

	var jump: RefCounted = fsm.call(
		"step",
		1.01,
		true,
		float(_hog.get("ride_speed_mps")),
		buffer,
		_move,
		_input,
		false
	)

	assert_eq(jump.get("state"), &"ride")
	assert_eq(jump.get("impulse"), &"ride_jump")
	assert_false(fsm.get("is_spinning"))
	assert_eq(
		decision_script.get_script_constant_map().get(
			"IMPULSE_RIDE_JUMP"
		),
		&"ride_jump"
	)

	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		false,
		1.02,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		1.03,
		InputIntent.SOURCE_TOUCH
	))
	var airborne_attempt: RefCounted = fsm.call(
		"step",
		1.03,
		false,
		float(_hog.get("ride_speed_mps")),
		buffer,
		_move,
		_input,
		false
	)
	assert_eq(airborne_attempt.get("state"), &"ride")
	assert_eq(
		airborne_attempt.get("impulse"),
		&"none",
		"a mounted jump must not turn into a double jump"
	)

	var landing: RefCounted = fsm.call(
		"step",
		2.0,
		true,
		float(_hog.get("ride_speed_mps")),
		buffer,
		_move,
		_input,
		false
	)
	assert_eq(landing.get("state"), &"ride")


func test_ride_motor_forces_forward_and_steers_only_laterally() -> void:
	var motor := load(MOTOR_SCRIPT_PATH) as Script
	assert_not_null(motor)
	assert_not_null(
		_hog,
		"Wave D needs an authored, typed hog tuning section"
	)
	if motor == null or _hog == null:
		return
	var corridor_forward := Vector3(
		1.0,
		0.0,
		-1.0
	).normalized()
	var corridor_right := corridor_forward.cross(
		Vector3.UP
	).normalized()

	for ignored_forward_input: float in [-1.0, 0.0, 1.0]:
		var velocity: Vector3 = motor.call(
			"horizontal_velocity",
			Vector3(20.0, 0.0, 20.0),
			Vector2(0.5, ignored_forward_input),
			&"ride",
			FRAME_DELTA_S,
			corridor_forward,
			_move,
			_hog
		)
		assert_almost_eq(
			velocity.dot(corridor_forward),
			float(_hog.get("ride_speed_mps")),
			FLOAT_TOLERANCE,
			"ride forward speed must ignore stick.y"
		)
		assert_almost_eq(
			velocity.dot(corridor_right),
			float(_hog.get("steer_lateral_speed_mps")) * 0.5,
			FLOAT_TOLERANCE,
			"ride steering must remain analog and lateral"
		)


func test_ride_jump_uses_hog_height_through_jump_kinematics() -> void:
	var motor := load(MOTOR_SCRIPT_PATH) as Script
	assert_not_null(motor)
	assert_not_null(_hog)
	if motor == null or _hog == null:
		return
	var launch: Vector3 = motor.call(
		"impulse_velocity",
		&"ride_jump",
		-Vector3.FORWARD * float(_hog.get("ride_speed_mps")),
		Vector3.FORWARD,
		_move,
		_hog
	)

	assert_almost_eq(
		launch.y,
		JumpKinematics.upward_speed_for_height(
			float(_hog.get("hog_jump_height_m")),
			_move
		),
		FLOAT_TOLERANCE
	)
	assert_almost_eq(
		Vector2(launch.x, launch.z).length(),
		float(_hog.get("ride_speed_mps")),
		FLOAT_TOLERANCE,
		"jumping must preserve the ride's forced-run momentum"
	)


func test_exit_ride_distinguishes_grounded_and_airborne_transitions() -> void:
	var fsm_script := load(FSM_SCRIPT_PATH) as Script
	assert_not_null(fsm_script)
	if fsm_script == null:
		return
	var fsm := fsm_script.new() as RefCounted
	fsm.call("enter_ride", 1.0)

	fsm.call("exit_ride", 1.1, true)

	assert_eq(fsm.get("state"), &"grounded")
	assert_true(fsm.get("_ground_jump_available"))
	assert_true(fsm.get("_double_jump_available"))
	assert_true(fsm.get("_air_spin_available"))
	fsm.call("enter_ride", 2.0)

	fsm.call("exit_ride", 2.1, false)

	assert_eq(fsm.get("state"), &"airborne")
	assert_false(fsm.get("_ground_jump_available"))
	assert_true(fsm.get("_double_jump_available"))
	assert_true(fsm.get("_air_spin_available"))


func test_controller_mounts_and_dismounts_while_airborne() -> void:
	assert_not_null(_hog)
	if _hog == null:
		return
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody3D
	add_child_autofree(player)
	await wait_process_frames(1)
	player.call(
		"configure",
		_catalog.get("move"),
		_catalog.get("input"),
		_catalog.get("depth"),
		_catalog.get("wall_run"),
		_catalog.get("grind"),
		_catalog.get("swing"),
		InputIntentBuffer.new(),
		_catalog.get("economy"),
		true,
		_hog
	)
	assert_false(
		player.is_on_floor(),
		"the transition fixture must remain airborne"
	)

	player.call("mount_hog")

	assert_true(player.call("is_hog_mounted"))
	assert_eq(player.call("current_state"), &"ride")

	player.call("dismount_hog")

	assert_false(player.call("is_hog_mounted"))
	assert_eq(player.call("current_state"), &"airborne")


func test_controller_mounts_and_respawns_still_mounted() -> void:
	assert_not_null(_hog)
	if _hog == null:
		return
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var player := packed.instantiate() as CharacterBody3D
	add_child_autofree(player)
	await wait_process_frames(1)
	var buffer := InputIntentBuffer.new()
	player.call(
		"configure",
		_catalog.get("move"),
		_catalog.get("input"),
		_catalog.get("depth"),
		_catalog.get("wall_run"),
		_catalog.get("grind"),
		_catalog.get("swing"),
		buffer,
		_catalog.get("economy"),
		true,
		_hog
	)
	assert_true(
		player.has_method("mount_hog"),
		"the real controller must expose the mount transition"
	)
	assert_true(
		player.has_method("dismount_hog"),
		"the real controller must expose the finish transition"
	)
	if (
		not player.has_method("mount_hog")
		or not player.has_method("dismount_hog")
	):
		return

	player.call("mount_hog")
	assert_true(player.call("is_hog_mounted"))
	assert_eq(player.call("current_state"), &"ride")
	PhaseState.configure(_catalog.get("phase"))
	PhaseState.reset_to_authored_set()
	var phase_before := PhaseState.active_set()
	buffer.push(InputIntent.button(
		InputIntent.ACTION_PHASE,
		true,
		2.99,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_SPIN,
		true,
		2.99,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.button(
		InputIntent.ACTION_DOWN,
		true,
		2.99,
		InputIntent.SOURCE_TOUCH
	))
	buffer.push(InputIntent.move(
		Vector2(0.5, 1.0),
		3.0,
		InputIntent.SOURCE_TOUCH
	))
	player.call(
		"advance_logic",
		3.0,
		true,
		FRAME_DELTA_S,
		Vector3.FORWARD
	)
	assert_almost_eq(
		player.velocity.dot(Vector3.FORWARD),
		float(_hog.get("ride_speed_mps")),
		FLOAT_TOLERANCE
	)
	assert_eq(
		PhaseState.active_set(),
		phase_before,
		"ride mode must consume Phase without toggling world state"
	)
	assert_false(
		player.call("is_spinning"),
		"ride mode must keep Spin inert"
	)
	assert_eq(player.call("current_state"), &"ride")
	buffer.push(InputIntent.button(
		InputIntent.ACTION_JUMP,
		true,
		3.01,
		InputIntent.SOURCE_TOUCH
	))
	var jump: RefCounted = player.call(
		"advance_logic",
		3.01,
		true,
		FRAME_DELTA_S,
		Vector3.FORWARD
	)
	assert_eq(jump.get("impulse"), &"ride_jump")
	assert_almost_eq(
		player.velocity.y,
		JumpKinematics.upward_speed_for_height(
			float(_hog.get("hog_jump_height_m")),
			_move
		),
		FLOAT_TOLERANCE
	)

	player.call("respawn")

	assert_true(
		player.call("is_hog_mounted"),
		"a death during the ride must restore mounted control"
	)
	assert_eq(player.call("current_state"), &"ride")
	player.call("dismount_hog")
	assert_false(player.call("is_hog_mounted"))
	assert_ne(player.call("current_state"), &"ride")


func test_hog_mount_glue_exists_as_a_real_runtime_node() -> void:
	assert_true(
		ResourceLoader.exists(HOG_MOUNT_SCRIPT_PATH),
		"Task 20 requires the runtime mount/dismount node"
	)
	if not ResourceLoader.exists(HOG_MOUNT_SCRIPT_PATH):
		return
	var script := load(HOG_MOUNT_SCRIPT_PATH) as Script
	assert_not_null(script)
	if script == null:
		return
	var mount := script.new() as Node3D
	assert_not_null(mount)
	if mount == null:
		return
	add_child_autofree(mount)
	assert_true(mount.has_method("configure"))
	assert_true(mount.has_method("reset_for_player_position"))
