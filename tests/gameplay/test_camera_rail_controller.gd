extends GutTest

const CONTROLLER_PATH := (
	"res://src/gameplay/camera/camera_rail_controller.gd"
)
const TUNING_PATH := "res://data/tuning/gameplay.tres"


# CRITICAL-1: game_root.gd (and phase0_game.gd) add a level to the tree
# BEFORE calling CameraRailController.configure() -- so _ready() always
# runs first, with _camera_tuning still null, and builds a zero-handle
# (dead-straight) polyline through the marker rail. configure() then calls
# _ensure_curve_from_markers() again, which must NOT early-return just
# because a curve already exists -- it must rebuild once the real tuning
# (and its rail_handle_length_factor) is available, or the tuning value
# never affects the runtime rail at all.
func test_configure_after_ready_rebuilds_the_rail_with_real_tuning() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return
	var camera_tuning: CameraTuning = catalog.camera.duplicate()
	camera_tuning.rail_handle_length_factor = 0.1667

	# An L-shaped rail with deliberately UNEQUAL marker spacing, mirroring
	# the real corner rails (a long straight run into a short arc slice).
	var points: Array[Vector3] = [
		Vector3(0, 0, 8),
		Vector3(0, 0, -96),
		Vector3(-6, 0, -102),
	]
	var polyline_length := (
		points[0].distance_to(points[1])
		+ points[1].distance_to(points[2])
	)

	var rail := Path3D.new()
	rail.name = "Rail"
	for point in points:
		var marker := Marker3D.new()
		marker.position = point
		rail.add_child(marker)

	var controller := Node3D.new()
	controller.set_script(load(CONTROLLER_PATH))
	controller.add_child(rail)

	# Entering the tree here fires _ready() with no tuning configured yet --
	# reproducing game_root.gd's real add-before-configure order.
	add_child_autofree(controller)

	assert_not_null(rail.curve, "the pre-configure _ready() build must run")
	assert_eq(
		rail.curve.get_point_out(1),
		Vector3.ZERO,
		"before configure(), the dead-wired build has zero-length handles"
	)

	var player := CharacterBody3D.new()
	add_child_autofree(player)
	player.global_position = Vector3(0, 0, 8)
	var camera := Camera3D.new()
	add_child_autofree(camera)

	controller.configure(
		player,
		rail,
		camera,
		camera_tuning,
		[],
		null
	)

	var interior_out := rail.curve.get_point_out(1)
	assert_ne(
		interior_out,
		Vector3.ZERO,
		"configure() must rebuild the rail using the real tuning's " +
		"rail_handle_length_factor, not keep the pre-tuning zero-handle build"
	)
	assert_ne(
		rail.curve.get_baked_length(),
		polyline_length,
		"a rail actually shaped by the handle factor bakes to a " +
		"different length than the raw marker polyline"
	)


# Drift bug: _update_input_corridor_axis used to unproject the corridor
# direction AT THE PLAYER'S POSITION. Under the closer camera.tres offset,
# the camera yaws to track the player as they strafe a corridor, so a
# player-anchored projection point rotates the on-screen axis mid-strafe --
# the gesture-axis slew then chases that rotating target and decomposes a
# held "up" input into phantom lateral input, which reads as steering drift.
# Anchoring the projection at the rail point (which does not move with the
# player) must keep the axis stable across the same strafe.
func test_input_corridor_axis_does_not_rotate_with_player_lateral_strafe() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog == null:
		return
	var camera_tuning: CameraTuning = catalog.camera

	var root := Node3D.new()
	add_child_autofree(root)
	var rail := Path3D.new()
	rail.name = "Rail"
	root.add_child(rail)
	for marker_position: Vector3 in [
		Vector3(0.0, 0.0, 50.0),
		Vector3(0.0, 0.0, -50.0),
	]:
		var marker := Marker3D.new()
		marker.position = marker_position
		rail.add_child(marker)
	# Parent the player before assigning global_position -- setting it on an
	# unparented Node3D reads a nonexistent parent transform and logs a
	# spurious "is_inside_tree" engine error even though it still lands on
	# the right value for a root-level child.
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.0, -20.0)
	var controller: Node3D = load(CONTROLLER_PATH).new()
	root.add_child(controller)
	var camera := Camera3D.new()
	controller.add_child(camera)
	var input_router := InputRouter.new()
	root.add_child(input_router)
	input_router.configure(catalog.input)

	controller.call(
		"configure",
		player,
		rail,
		camera,
		camera_tuning,
		[],
		input_router
	)
	# The camera's RenderingServer-side transform only syncs once a real
	# frame has been processed; unproject_position() reads stale/degenerate
	# data before that (verified against a hand-rolled projection). Settle
	# a couple of physics frames before trusting any unprojected reading,
	# same as the rig receives every physics frame during real play.
	await wait_physics_frames(2)
	controller.call("update_camera", 1.0 / 60.0)
	await wait_physics_frames(2)
	var axis_centered: Vector2 = input_router.corridor_axis()

	player.global_position = Vector3(3.0, 0.0, -20.0)
	controller.call("update_camera", 1.0 / 60.0)
	await wait_physics_frames(2)
	var axis_strafed: Vector2 = input_router.corridor_axis()

	var swing_degrees := rad_to_deg(axis_centered.angle_to(axis_strafed))
	print(
		"corridor axis swing across a 3m lateral strafe: %.2f degrees"
		% swing_degrees
	)
	# The rail-anchored projection still yaws a little with the camera
	# itself (the anchor tracks the rail, not the player, but the camera's
	# look-at basis still turns slightly toward the player as they strafe).
	# That residual is expected and harmless as long as it stays well
	# inside the corridor magnet cone that swallows small input-axis
	# jitter; a player-anchored projection blew straight through it.
	var magnet_cone_degrees: float = catalog.input.corridor_magnet_cone_degrees
	var max_allowed_swing_degrees := magnet_cone_degrees * 0.5
	assert_lt(
		absf(swing_degrees),
		max_allowed_swing_degrees,
		(
			"a lateral strafe alone must not rotate the corridor screen "
			+ "axis anywhere near the %.1f degree magnet cone -- measured "
			+ "%.2f degrees"
		) % [magnet_cone_degrees, swing_degrees]
	)
