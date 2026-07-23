extends GutTest

const ARCHETYPES_SCRIPT_PATH := (
	"res://src/gameplay/camera/camera_archetypes.gd"
)
const CAMERA_REGION_SCRIPT_PATH := (
	"res://src/gameplay/camera/camera_region.gd"
)
const CAMERA_CONTROLLER_SCRIPT_PATH := (
	"res://src/gameplay/camera/camera_rail_controller.gd"
)
const BLOB_SHADOW_SCRIPT_PATH := (
	"res://src/gameplay/depth/blob_shadow.gd"
)
const PLAYER_SCRIPT_PATH := (
	"res://src/gameplay/player/player_controller.gd"
)
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const FRAME_DELTA_S := 1.0 / 60.0
const SCREEN_TOLERANCE := 0.02
const BASIS_TOLERANCE := 0.0001

var _camera: CameraTuning
var _depth: DepthTuning


class FakeTraversalPlayer:
	extends CharacterBody3D

	var traversal_state := &"airborne"
	var traversal_tangent := Vector3.ZERO
	var traversal_normal := Vector3.ZERO
	var corridor_forward := Vector3.FORWARD

	func current_state() -> StringName:
		return traversal_state

	func traversal_camera_context() -> Dictionary:
		return {
			&"state": traversal_state,
			&"tangent": traversal_tangent,
			&"normal": traversal_normal,
			&"position": global_position,
		}

	func set_corridor_forward(value: Vector3) -> void:
		corridor_forward = value


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_camera = catalog.camera
		_depth = catalog.depth


func test_wall_run_camera_holds_the_surface_tangent_horizontal() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis"
	)
	if script == null:
		return

	var basis: Basis = script.call(
		"wall_run_basis",
		Vector3.BACK,
		Vector3.RIGHT,
		_camera
	)
	var tangent_on_screen := basis.inverse() * Vector3.BACK

	assert_almost_eq(
		tangent_on_screen.y,
		0.0,
		SCREEN_TOLERANCE,
		"the run surface must read as ground — tangent horizontal on screen"
	)
	assert_almost_eq(basis.determinant(), 1.0, BASIS_TOLERANCE)


func test_wall_run_camera_derives_its_side_from_the_surface_normal() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis"
	)
	if script == null:
		return

	var right_wall: Basis = script.call(
		"wall_run_basis",
		Vector3.BACK,
		Vector3.RIGHT,
		_camera
	)
	var left_wall: Basis = script.call(
		"wall_run_basis",
		Vector3.BACK,
		Vector3.LEFT,
		_camera
	)
	var right_view := -right_wall.z
	var left_view := -left_wall.z

	assert_lt(right_view.dot(Vector3.RIGHT), 0.0)
	assert_lt(left_view.dot(Vector3.LEFT), 0.0)
	assert_gt(right_view.dot(left_view), -1.0)


func test_grind_camera_keeps_the_rail_tangent_horizontal() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"grind_basis"
	)
	if script == null:
		return

	var tangent := Vector3(1.0, 0.0, 1.0).normalized()
	var basis: Basis = script.call("grind_basis", tangent, _camera)
	var tangent_on_screen := basis.inverse() * tangent

	assert_almost_eq(
		tangent_on_screen.y,
		0.0,
		SCREEN_TOLERANCE
	)
	assert_almost_eq(basis.determinant(), 1.0, BASIS_TOLERANCE)


func test_swing_camera_is_side_on_to_the_pendulum_plane() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"swing_basis"
	)
	if script == null:
		return

	var basis: Basis = script.call(
		"swing_basis",
		Vector3.FORWARD,
		Vector3.RIGHT,
		_camera
	)
	var view_direction := -basis.z

	assert_almost_eq(
		view_direction.dot(Vector3.FORWARD),
		0.0,
		SCREEN_TOLERANCE
	)
	assert_lt(view_direction.dot(Vector3.RIGHT), 0.0)


func test_camera_regions_resolve_all_traversal_offsets() -> void:
	var script := _load_script_with_method(
		CAMERA_REGION_SCRIPT_PATH,
		&"offset_for"
	)
	if script == null:
		return
	var constants := script.get_script_constant_map()
	for expectation: Array in [
		[&"MODE_GRIND", &"grind", _camera.grind_offset],
		[&"MODE_WALL_RUN", &"wall_run", _camera.wall_run_offset],
		[&"MODE_SWING", &"swing", _camera.swing_offset],
	]:
		assert_true(
			constants.has(expectation[0]),
			"CameraRegion must declare %s" % expectation[0]
		)
		if not constants.has(expectation[0]):
			continue
		assert_eq(constants[expectation[0]], expectation[1])
		var region: Area3D = script.new()
		region.set("camera_mode", expectation[1])
		assert_eq(region.call("offset_for", _camera), expectation[2])
		region.free()


func test_wall_run_blob_shadow_projects_toward_the_active_surface() -> void:
	var script := _load_script_with_method(
		BLOB_SHADOW_SCRIPT_PATH,
		&"projection_direction"
	)
	if script == null:
		return

	assert_eq(
		script.call(
			"projection_direction",
			&"wall_run",
			Vector3.RIGHT
		),
		Vector3.LEFT
	)
	assert_eq(
		script.call(
			"projection_direction",
			&"airborne",
			Vector3.RIGHT
		),
		Vector3.DOWN
	)


func test_player_exposes_one_named_traversal_camera_context_channel() -> void:
	var script := _load_script_with_method(
		PLAYER_SCRIPT_PATH,
		&"traversal_camera_context"
	)
	if script == null:
		return
	var player: CharacterBody3D = script.new()

	var context: Dictionary = player.call("traversal_camera_context")

	assert_eq(context.get(&"state"), &"airborne")
	assert_eq(context.get(&"tangent"), Vector3.ZERO)
	assert_eq(context.get(&"normal"), Vector3.ZERO)
	player.free()


func test_player_context_reports_the_live_wall_sample() -> void:
	var script := _load_script_with_method(
		PLAYER_SCRIPT_PATH,
		&"traversal_camera_context"
	)
	if script == null:
		return
	var player: CharacterBody3D = script.new()
	var sample := TraversalSample.new()
	sample.position = Vector3(2.0, 3.0, 4.0)
	sample.tangent = Vector3.BACK
	sample.normal = Vector3.RIGHT
	player.get("_state_machine").set("state", &"wall_run")
	player.set("_active_wall_sample", sample)

	var context: Dictionary = player.call("traversal_camera_context")

	assert_eq(context.get(&"state"), &"wall_run")
	assert_eq(context.get(&"position"), sample.position)
	assert_eq(context.get(&"tangent"), sample.tangent)
	assert_eq(context.get(&"normal"), sample.normal)
	player.free()


func test_blob_shadow_runtime_uses_the_wall_context_channel() -> void:
	var blob_script := _load_script_with_method(
		BLOB_SHADOW_SCRIPT_PATH,
		&"configure"
	)
	if blob_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var player := FakeTraversalPlayer.new()
	player.position = Vector3(1.0, 1.0, 0.0)
	player.traversal_state = &"wall_run"
	player.traversal_tangent = Vector3.BACK
	player.traversal_normal = Vector3.RIGHT
	root.add_child(player)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.2, 4.0, 4.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	root.add_child(wall)
	var blob: Node3D = blob_script.new()
	root.add_child(blob)
	blob.call("configure", player, _depth)

	await wait_physics_frames(2)

	assert_true(blob.visible)
	assert_gt(blob.global_basis.y.dot(Vector3.RIGHT), 0.99)


func test_rig_blends_into_wall_basis_instead_of_snapping() -> void:
	var controller_script := _load_script_with_method(
		CAMERA_CONTROLLER_SCRIPT_PATH,
		&"update_camera"
	)
	if controller_script == null:
		return
	var region_script := _load_script_with_method(
		CAMERA_REGION_SCRIPT_PATH,
		&"offset_for"
	)
	if region_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var player := FakeTraversalPlayer.new()
	player.position = Vector3.ZERO
	root.add_child(player)
	var rail := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3.BACK * 10.0)
	curve.add_point(Vector3.FORWARD * 10.0)
	rail.curve = curve
	root.add_child(rail)
	var controller: Node3D = controller_script.new()
	root.add_child(controller)
	var camera := Camera3D.new()
	controller.add_child(camera)
	var region: Area3D = region_script.new()
	region.set("camera_mode", &"wall_run")
	root.add_child(region)
	controller.call(
		"configure",
		player,
		rail,
		camera,
		_camera,
		[region]
	)
	var initial_basis := camera.global_basis
	player.traversal_state = &"wall_run"
	player.traversal_tangent = Vector3.FORWARD
	player.traversal_normal = Vector3.RIGHT
	controller.call("_on_region_body_entered", player, region)

	controller.call("update_camera", FRAME_DELTA_S)
	var partial_basis := camera.global_basis
	controller.call(
		"update_camera",
		_camera.region_blend_s - FRAME_DELTA_S
	)
	var complete_basis := camera.global_basis
	var initial_error := absf(
		(initial_basis.inverse() * player.traversal_tangent).y
	)
	var partial_error := absf(
		(partial_basis.inverse() * player.traversal_tangent).y
	)
	var complete_error := absf(
		(complete_basis.inverse() * player.traversal_tangent).y
	)

	assert_gt(initial_error, SCREEN_TOLERANCE)
	assert_gt(partial_error, SCREEN_TOLERANCE)
	assert_false(
		partial_basis.is_equal_approx(initial_basis),
		"the first scaled frame must begin orientation progress"
	)
	assert_almost_eq(complete_error, 0.0, SCREEN_TOLERANCE)


func _load_script_with_method(
	path: String,
	method_name: StringName
) -> Script:
	assert_true(ResourceLoader.exists(path), "%s must exist" % path)
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	assert_not_null(script)
	if script == null:
		return null
	var has_method := false
	for method: Dictionary in script.get_script_method_list():
		if StringName(method.get("name", &"")) == method_name:
			has_method = true
			break
	assert_true(
		has_method,
		"%s must expose %s" % [path, method_name]
	)
	return script if has_method else null
