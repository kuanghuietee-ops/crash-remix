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
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const WALL_RUN_SEGMENT_PATH := (
	"res://scenes/segments/seg_wall_run_canyon.tscn"
)
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const FRAME_DELTA_S := 1.0 / 60.0
const SCREEN_TOLERANCE := 0.02
const BASIS_TOLERANCE := 0.0001
const NONZERO_ATTACH_DISTANCE_M := 4.0
const MAXIMUM_COMFORT_ROLL_DEGREES := 10.0
const TOWARD_CAMERA_MINIMUM_DEPRESSION_DEGREES := 30.0
const TOWARD_CAMERA_MAXIMUM_DEPRESSION_DEGREES := 35.0
const TOWARD_CAMERA_OPPOSITION_DOT := -0.9

var _catalog: GameplayTuning
var _camera: CameraTuning
var _depth: DepthTuning


class FakeTraversalPlayer:
	extends CharacterBody3D

	var traversal_state := &"airborne"
	var traversal_tangent := Vector3.ZERO
	var traversal_normal := Vector3.ZERO
	var traversal_position := Vector3.ZERO
	var corridor_forward := Vector3.FORWARD

	func current_state() -> StringName:
		return traversal_state

	func traversal_camera_context() -> Dictionary:
		return {
			&"state": traversal_state,
			&"tangent": traversal_tangent,
			&"normal": traversal_normal,
			&"position": traversal_position,
		}

	func set_corridor_forward(value: Vector3) -> void:
		corridor_forward = value


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_catalog = catalog
		_camera = catalog.camera
		_depth = catalog.depth


func test_wall_run_camera_keeps_a_level_down_the_slot_horizon() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis_for_view"
	)
	if script == null:
		return

	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT]:
		var view_direction := _settled_live_view_direction(
			&"wall_run",
			Vector3.ZERO,
			Vector3.BACK,
			normal
		)
		var basis: Basis = script.call(
			"wall_run_basis_for_view",
			Vector3.BACK,
			normal,
			view_direction,
			_camera
		)
		var tangent_on_screen := basis.inverse() * Vector3.BACK

		assert_almost_eq(
			basis.x.dot(Vector3.UP),
			0.0,
			SCREEN_TOLERANCE,
			"the down-the-slot shot must keep a level world horizon"
		)
		assert_gt(
			absf(tangent_on_screen.z),
			absf(tangent_on_screen.x),
			"wall-run ships the §5.5 down-the-slot shot; "
			+ "a side-on camera here is a spec change, not a tuning tweak"
		)
		assert_gt((-basis.z).dot(view_direction.normalized()), 0.999)
		assert_almost_eq(basis.determinant(), 1.0, BASIS_TOLERANCE)


func test_wall_run_bank_tuning_reaches_the_live_camera_basis() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis_for_view"
	)
	if script == null:
		return
	var view_direction := _settled_live_view_direction(
		&"wall_run",
		Vector3.ZERO,
		Vector3.BACK,
		Vector3.RIGHT
	)
	var level_tuning: CameraTuning = _camera.duplicate()
	level_tuning.wall_run_bank_degrees = 0.0
	var banked_tuning: CameraTuning = _camera.duplicate()
	banked_tuning.wall_run_bank_degrees = 7.0
	var level_basis: Basis = script.call(
		"wall_run_basis_for_view",
		Vector3.BACK,
		Vector3.RIGHT,
		view_direction,
		level_tuning
	)
	var banked_basis: Basis = script.call(
		"wall_run_basis_for_view",
		Vector3.BACK,
		Vector3.RIGHT,
		view_direction,
		banked_tuning
	)

	assert_almost_eq(
		level_basis.y.angle_to(banked_basis.y),
		deg_to_rad(banked_tuning.wall_run_bank_degrees),
		BASIS_TOLERANCE,
		"wall_run_bank_degrees must reach the live camera behavior"
	)


func test_wall_run_camera_derives_its_side_from_the_surface_normal() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis_for_view"
	)
	if script == null:
		return

	var right_view_direction := _settled_live_view_direction(
		&"wall_run",
		Vector3.ZERO,
		Vector3.BACK,
		Vector3.RIGHT
	)
	var left_view_direction := _settled_live_view_direction(
		&"wall_run",
		Vector3.ZERO,
		Vector3.BACK,
		Vector3.LEFT
	)

	assert_gt(right_view_direction.dot(Vector3.RIGHT), 0.0)
	assert_gt(left_view_direction.dot(Vector3.LEFT), 0.0)
	assert_almost_eq(
		right_view_direction.x,
		-left_view_direction.x,
		BASIS_TOLERANCE
	)
	for wall: Array in [
		[Vector3.RIGHT, right_view_direction],
		[Vector3.LEFT, left_view_direction],
	]:
		var basis: Basis = script.call(
			"wall_run_basis_for_view",
			Vector3.BACK,
			wall[0],
			wall[1],
			_camera
		)
		assert_gt((-basis.z).dot((wall[1] as Vector3).normalized()), 0.999)


func test_wall_run_camera_stays_upright_on_both_wall_sides() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis_for_view"
	)
	if script == null:
		return

	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT]:
		var view_direction := _settled_live_view_direction(
			&"wall_run",
			Vector3.ZERO,
			Vector3.FORWARD,
			normal
		)
		var basis: Basis = script.call(
			"wall_run_basis_for_view",
			Vector3.FORWARD,
			normal,
			view_direction,
			_camera
		)
		assert_gt(
			basis.y.dot(Vector3.UP),
			0.0,
			"alternating canyon walls must not invert the camera"
		)


func test_live_wall_run_camera_is_upright_and_right_handed_on_both_walls() -> void:
	var frames: Array[Dictionary] = await _live_wall_run_camera_frames()
	assert_eq(frames.size(), 2)

	for frame: Dictionary in frames:
		var basis: Basis = frame[&"basis"]
		assert_gt(
			basis.y.dot(Vector3.UP),
			0.0,
			"%s live camera must remain upright" % frame[&"strip_name"]
		)
		assert_almost_eq(
			basis.determinant(),
			1.0,
			BASIS_TOLERANCE,
			"%s live camera must remain right-handed"
			% frame[&"strip_name"]
		)


func test_live_wall_run_camera_keeps_the_horizon_inside_the_comfort_band() -> void:
	var frames: Array[Dictionary] = await _live_wall_run_camera_frames()
	assert_eq(frames.size(), 2)
	var minimum_up_alignment := cos(
		deg_to_rad(MAXIMUM_COMFORT_ROLL_DEGREES)
	)

	for frame: Dictionary in frames:
		var basis: Basis = frame[&"basis"]
		assert_gte(
			basis.y.dot(Vector3.UP),
			minimum_up_alignment,
			"%s wall-run camera exceeds the device comfort roll"
			% frame[&"strip_name"]
		)


func test_wall_run_camera_is_unoccluded_on_both_real_canyon_walls() -> void:
	var frames: Array[Dictionary] = await _live_wall_run_camera_frames()
	assert_eq(frames.size(), 2)

	for frame: Dictionary in frames:
		var root: Node3D = frame[&"root"]
		var player: CharacterBody3D = frame[&"player"]
		var camera: Camera3D = frame[&"camera"]
		var query := PhysicsRayQueryParameters3D.create(
			camera.global_position,
			player.global_position
		)
		query.exclude = [player.get_rid()]
		query.collide_with_areas = false
		var hit: Dictionary = (
			root.get_world_3d().direct_space_state.intersect_ray(query)
		)

		assert_true(
			hit.is_empty(),
			"%s camera sightline is blocked by %s"
			% [frame[&"strip_name"], hit.get("collider")]
		)


func test_wall_region_keeps_preattach_approach_camera_inside_the_canyon() -> void:
	var segment_packed: PackedScene = load(WALL_RUN_SEGMENT_PATH)
	var controller_script := _load_script_with_method(
		CAMERA_CONTROLLER_SCRIPT_PATH,
		&"update_camera"
	)
	assert_not_null(segment_packed)
	if segment_packed == null or controller_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var segment := segment_packed.instantiate() as Node3D
	root.add_child(segment)
	var player := FakeTraversalPlayer.new()
	player.position = Vector3(0.0, 0.05, 3.0)
	root.add_child(player)
	var rail := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 8.0))
	curve.add_point(Vector3(0.0, 0.0, -40.0))
	rail.curve = curve
	root.add_child(rail)
	var controller: Node3D = controller_script.new()
	root.add_child(controller)
	var camera := Camera3D.new()
	controller.add_child(camera)
	var region := segment.get_node("WallRunCameraRegion") as Area3D
	controller.call(
		"configure",
		player,
		rail,
		camera,
		_camera,
		[region]
	)
	var initial_lateral_distance := absf(
		camera.global_position.x - player.global_position.x
	)
	controller.call("_on_region_body_entered", player, region)
	controller.call("update_camera", FRAME_DELTA_S)
	assert_lte(
		absf(camera.global_position.x - player.global_position.x),
		initial_lateral_distance,
		"opening wall blend must move inward from its default camera lane"
	)
	controller.call("update_camera", 1.0)
	await wait_physics_frames(1)
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		player.global_position
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	var hit: Dictionary = (
		root.get_world_3d().direct_space_state.intersect_ray(query)
	)

	assert_almost_eq(
		camera.global_position.x,
		player.global_position.x,
		BASIS_TOLERANCE,
		"wall offset x is trail distance before attach, not lateral distance"
	)
	assert_true(
		hit.is_empty(),
		"opening camera sightline is blocked by %s" % hit.get("collider")
	)


func test_wall_run_detach_target_is_visible_before_detach_on_both_walls() -> void:
	var frames: Array[Dictionary] = await _live_wall_run_camera_frames()
	assert_eq(frames.size(), 2)

	for frame: Dictionary in frames:
		var player: CharacterBody3D = frame[&"player"]
		var camera: Camera3D = frame[&"camera"]
		var detach_target: Vector3 = frame[&"detach_target"]

		assert_eq(
			player.call("current_state"),
			&"wall_run",
			"%s visibility must be established before detaching"
			% frame[&"strip_name"]
		)
		assert_almost_eq(
			frame[&"attach_distance_m"],
			NONZERO_ATTACH_DISTANCE_M,
			BASIS_TOLERANCE
		)
		assert_true(
			camera.is_position_in_frustum(detach_target),
			"%s must frame the authored detach target at a non-zero attach"
			% frame[&"strip_name"]
		)


func test_grind_camera_keeps_the_rail_tangent_horizontal() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"grind_basis_for_view"
	)
	if script == null:
		return

	var tangent := Vector3(1.0, 0.0, 1.0).normalized()
	var view_direction := _settled_live_view_direction(
		&"grind",
		Vector3.ZERO,
		tangent,
		Vector3.UP
	)
	var basis: Basis = script.call(
		"grind_basis_for_view",
		tangent,
		Vector3.UP,
		view_direction
	)
	var tangent_on_screen := basis.inverse() * tangent

	assert_almost_eq(
		tangent_on_screen.y,
		0.0,
		SCREEN_TOLERANCE
	)
	assert_gt(
		absf(tangent_on_screen.z),
		absf(tangent_on_screen.x),
		"grind ships along the rail depth axis; "
		+ "a side-on camera here changes the authored shot"
	)
	assert_gt((-basis.z).dot(view_direction.normalized()), 0.999)
	assert_almost_eq(basis.determinant(), 1.0, BASIS_TOLERANCE)


func test_toward_camera_shot_faces_back_down_the_corridor() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"toward_camera_basis_for_view"
	)
	if script == null:
		return
	assert_true(
		_resource_has_property(
			_camera,
			&"toward_camera_offset"
		),
		"CameraTuning must author a dedicated toward-camera offset"
	)
	if not _resource_has_property(
		_camera,
		&"toward_camera_offset"
	):
		return
	var corridor_forward := Vector3.FORWARD
	var offset := (
		_camera.get(&"toward_camera_offset") as Vector3
	)
	var view_direction := _toward_camera_view_direction(
		corridor_forward,
		offset
	)
	var basis: Basis = script.call(
		"toward_camera_basis_for_view",
		corridor_forward,
		view_direction
	)

	assert_true(
		_toward_camera_contract_holds(
			corridor_forward,
			view_direction
		),
		"the authored chase shot must look back against corridor progress"
	)
	assert_false(
		_toward_camera_contract_holds(
			corridor_forward,
			_toward_camera_view_direction(
				corridor_forward,
				_camera.default_offset
			)
		),
		"the ordinary chase-behind offset must fail this exact assertion"
	)
	assert_gt(
		(-basis.z).dot(view_direction.normalized()),
		0.999,
		"the live toward-camera basis must face its real view direction"
	)
	assert_almost_eq(basis.determinant(), 1.0, BASIS_TOLERANCE)


func test_swing_camera_is_side_on_to_the_pendulum_plane() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"swing_basis_for_view"
	)
	if script == null:
		return

	var view_direction := _settled_live_view_direction(
		&"swing",
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.RIGHT
	)
	var basis: Basis = script.call(
		"swing_basis_for_view",
		Vector3.FORWARD,
		Vector3.RIGHT,
		view_direction
	)
	var tangent_on_screen := basis.inverse() * Vector3.FORWARD

	assert_almost_eq(
		tangent_on_screen.y,
		0.0,
		SCREEN_TOLERANCE
	)
	assert_gt(
		absf(tangent_on_screen.x),
		absf(tangent_on_screen.z),
		"swing ships side-on to its pendulum plane; "
		+ "a depth-axis camera here changes the authored shot"
	)
	assert_almost_eq(
		view_direction.dot(Vector3.FORWARD),
		0.0,
		SCREEN_TOLERANCE
	)
	assert_lt(view_direction.dot(Vector3.RIGHT), 0.0)
	assert_gt((-basis.z).dot(view_direction.normalized()), 0.999)


func test_swing_camera_holds_the_rope_frame_while_player_crosses_the_arc() -> void:
	var controller_script := _load_script_with_method(
		CAMERA_CONTROLLER_SCRIPT_PATH,
		&"update_camera"
	)
	var region_script := _load_script_with_method(
		CAMERA_REGION_SCRIPT_PATH,
		&"offset_for"
	)
	if controller_script == null or region_script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var frame_center := Vector3(0.0, 2.0, -5.0)
	var player := FakeTraversalPlayer.new()
	player.position = frame_center
	player.traversal_state = &"swing"
	player.traversal_tangent = Vector3.FORWARD
	player.traversal_normal = Vector3.RIGHT
	player.traversal_position = frame_center
	root.add_child(player)
	var rail := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 10.0))
	curve.add_point(Vector3(0.0, 0.0, -20.0))
	rail.curve = curve
	root.add_child(rail)
	var controller: Node3D = controller_script.new()
	root.add_child(controller)
	var camera := Camera3D.new()
	controller.add_child(camera)
	var region: Area3D = region_script.new()
	region.set("camera_mode", &"swing")
	root.add_child(region)
	controller.call(
		"configure",
		player,
		rail,
		camera,
		_camera,
		[region]
	)
	controller.call("_on_region_body_entered", player, region)
	controller.call("update_camera", 1.0)
	var initial_camera_transform := camera.global_transform
	var initial_player_screen := camera.unproject_position(
		player.global_position
	)
	var swing_angle_rad := TAU / 5.0
	var rope_start_offset := (
		Vector3.DOWN * _catalog.swing.rope_length_m
	)
	var rope_arc_offset := (
		Vector3.DOWN * cos(swing_angle_rad)
		+ Vector3.FORWARD * sin(swing_angle_rad)
	) * _catalog.swing.rope_length_m
	player.global_position = (
		frame_center
		+ rope_arc_offset
		- rope_start_offset
	)

	controller.call("update_camera", 1.0)
	var moved_player_screen := camera.unproject_position(
		player.global_position
	)

	assert_true(
		camera.global_transform.is_equal_approx(initial_camera_transform),
		"the rope shot must frame the pendulum instead of chasing its player"
	)
	assert_gt(
		moved_player_screen.distance_to(initial_player_screen),
		get_viewport().get_visible_rect().size.x * 0.1,
		"the swing arc must remain visible as motion across the screen"
	)
	assert_true(camera.is_position_in_frustum(player.global_position))


func test_camera_archetypes_expose_only_the_live_basis_entry_points() -> void:
	var script := _load_script_with_method(
		ARCHETYPES_SCRIPT_PATH,
		&"wall_run_basis_for_view"
	)
	if script == null:
		return

	for dead_method: StringName in [
		&"wall_run_basis",
		&"grind_basis",
		&"swing_basis",
		&"toward_camera_basis",
	]:
		assert_false(
			_script_has_method(script, dead_method),
			"%s duplicates the controller's live basis path" % dead_method
		)
	var controller_script := load(
		CAMERA_CONTROLLER_SCRIPT_PATH
	) as Script
	assert_not_null(controller_script)
	if controller_script != null:
		assert_string_contains(
			controller_script.source_code,
			"toward_camera_basis_for_view",
			"the toward-camera helper must be consumed by the live rig"
		)


func test_camera_regions_resolve_all_traversal_offsets() -> void:
	var script := _load_script_with_method(
		CAMERA_REGION_SCRIPT_PATH,
		&"offset_for"
	)
	if script == null:
		return
	assert_true(
		_resource_has_property(_camera, &"toward_camera_offset")
	)
	if not _resource_has_property(_camera, &"toward_camera_offset"):
		return
	var constants := script.get_script_constant_map()
	for expectation: Array in [
		[&"MODE_GRIND", &"grind", _camera.grind_offset],
		[&"MODE_WALL_RUN", &"wall_run", _camera.wall_run_offset],
		[&"MODE_SWING", &"swing", _camera.swing_offset],
		[
			&"MODE_TOWARD_CAMERA",
			&"toward_camera",
			_camera.get(&"toward_camera_offset"),
		],
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


func test_player_context_reports_the_fixed_swing_frame_center() -> void:
	var script := _load_script_with_method(
		PLAYER_SCRIPT_PATH,
		&"traversal_camera_context"
	)
	if script == null:
		return
	var root := Node3D.new()
	add_child_autofree(root)
	var player: CharacterBody3D = script.new()
	root.add_child(player)
	player.call(
		"configure",
		_catalog.move,
		_catalog.input,
		_catalog.depth,
		_catalog.wall_run,
		_catalog.grind,
		_catalog.swing,
		InputIntentBuffer.new(),
		null,
		false
	)
	var anchor := SwingAnchor.new()
	anchor.swing_tuning = _catalog.swing
	anchor.position = Vector3(0.0, 6.0, -2.0)
	root.add_child(anchor)
	player.position = Vector3(0.0, 3.0, -4.0)
	player.get("_state_machine").set("state", &"swing")
	player.set("_active_swing_anchor", anchor)

	var context: Dictionary = player.call("traversal_camera_context")

	assert_eq(
		context.get(&"position"),
		anchor.call("catch_position", _catalog.swing),
		"camera frame belongs to the rope, not the moving player"
	)


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


func test_rig_blends_through_wall_attach_and_detach_without_roll() -> void:
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

	var maximum_roll_sine := sin(
		deg_to_rad(MAXIMUM_COMFORT_ROLL_DEGREES)
	)
	var partial_basis := initial_basis
	var blend_frame_count := ceili(
		_camera.region_blend_s / FRAME_DELTA_S
	)
	for frame_index: int in range(blend_frame_count):
		controller.call("update_camera", FRAME_DELTA_S)
		partial_basis = camera.global_basis
		assert_lte(
			absf(partial_basis.x.dot(Vector3.UP)),
			maximum_roll_sine,
			"wall camera exceeds the comfort roll during blend frame %d"
			% frame_index
		)

	assert_false(
		partial_basis.is_equal_approx(initial_basis),
		"the scaled frames must make orientation progress"
	)
	assert_almost_eq(
		partial_basis.x.dot(Vector3.UP),
		0.0,
		SCREEN_TOLERANCE,
		"the completed wall shot must settle on a level horizon"
	)

	player.traversal_state = &"airborne"
	player.traversal_tangent = Vector3.ZERO
	player.traversal_normal = Vector3.ZERO
	controller.call("_on_region_body_exited", player, region)
	for frame_index: int in range(blend_frame_count):
		controller.call("update_camera", FRAME_DELTA_S)
		assert_lte(
			absf(camera.global_basis.x.dot(Vector3.UP)),
			maximum_roll_sine,
			"camera exceeds the comfort roll during detach frame %d"
			% frame_index
		)


func _live_wall_run_camera_frames() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var segment_packed: PackedScene = load(WALL_RUN_SEGMENT_PATH)
	var player_packed: PackedScene = load(PLAYER_SCENE_PATH)
	var controller_script := _load_script_with_method(
		CAMERA_CONTROLLER_SCRIPT_PATH,
		&"update_camera"
	)
	assert_not_null(segment_packed)
	assert_not_null(player_packed)
	if (
		segment_packed == null
		or player_packed == null
		or controller_script == null
	):
		return frames
	var root := Node3D.new()
	add_child_autofree(root)
	var segment := segment_packed.instantiate() as Node3D
	root.add_child(segment)
	await wait_physics_frames(2)
	var region := segment.get_node("WallRunCameraRegion") as Area3D

	for strip_name: String in ["LeftStrip", "RightStrip"]:
		var strip := segment.get_node(strip_name) as Path3D
		var player := player_packed.instantiate() as CharacterBody3D
		root.add_child(player)
		var buffer := InputIntentBuffer.new()
		player.call(
			"configure",
			_catalog.move,
			_catalog.input,
			_catalog.depth,
			_catalog.wall_run,
			_catalog.grind,
			_catalog.swing,
			buffer,
			null,
			false
		)
		var sample: TraversalSample = strip.call(
			"sample_at_distance",
			NONZERO_ATTACH_DISTANCE_M
		)
		assert_not_null(sample)
		if sample == null:
			continue
		assert_almost_eq(
			sample.distance_along_m,
			NONZERO_ATTACH_DISTANCE_M,
			BASIS_TOLERANCE
		)
		player.global_position = (
			sample.position
			+ sample.normal
			* _catalog.wall_run.surface_stick_distance_m
		)
		player.velocity = sample.tangent * 6.0
		assert_true(
			player.call(
				"try_wall_attach",
				strip,
				10.0 + float(root.get_child_count())
			)
		)
		var rail := Path3D.new()
		var curve := Curve3D.new()
		curve.add_point(Vector3(0.0, 0.0, 8.0))
		curve.add_point(Vector3(0.0, 0.0, -40.0))
		rail.curve = curve
		root.add_child(rail)
		var controller: Node3D = controller_script.new()
		root.add_child(controller)
		var camera := Camera3D.new()
		controller.add_child(camera)
		controller.call(
			"configure",
			player,
			rail,
			camera,
			_camera,
			[region]
		)
		controller.call("_on_region_body_entered", player, region)
		controller.call("update_camera", 1.0)
		frames.append({
			&"root": root,
			&"strip_name": strip_name,
			&"player": player,
			&"camera": camera,
			&"basis": camera.global_basis,
			&"attach_distance_m": sample.distance_along_m,
			&"detach_target": (
				segment.get_node("LandingPad") as Node3D
			).global_position,
			&"view_direction": _settled_live_view_direction(
				&"wall_run",
				player.global_position,
				sample.tangent,
				sample.normal
			),
		})
	return frames


# Mirrors CameraRailController.update_camera after its position/region blends
# have settled, so conformance tests exercise the view the live path receives.
func _settled_live_view_direction(
	mode: StringName,
	player_position: Vector3,
	context_tangent: Vector3,
	context_normal: Vector3
) -> Vector3:
	var camera_forward := context_tangent.normalized()
	var camera_up := Vector3.UP
	var camera_right := camera_forward.cross(camera_up).normalized()
	var offset := _camera.default_offset
	if mode == &"grind":
		camera_up = context_normal.slide(camera_forward).normalized()
		if camera_up.is_zero_approx():
			camera_up = Vector3.UP
		camera_right = camera_forward.cross(camera_up).normalized()
		offset = _camera.grind_offset
	elif mode == &"wall_run":
		camera_right = context_normal.slide(camera_forward).normalized()
		if camera_right.is_zero_approx():
			camera_right = camera_forward.cross(Vector3.UP).normalized()
		camera_up = camera_forward.cross(camera_right).normalized()
		if camera_up.dot(Vector3.UP) < 0.0:
			camera_up = -camera_up
		if camera_up.is_zero_approx():
			camera_up = Vector3.UP
		offset = _camera.wall_run_offset
	elif mode == &"swing":
		camera_right = context_normal.slide(camera_forward).normalized()
		if camera_right.is_zero_approx():
			camera_right = camera_forward.cross(Vector3.UP).normalized()
		camera_up = camera_right.cross(camera_forward).normalized()
		if camera_up.is_zero_approx():
			camera_up = Vector3.UP
		offset = _camera.swing_offset
	if camera_right.is_zero_approx():
		camera_right = Vector3.RIGHT

	var camera_position: Vector3
	if mode == &"wall_run":
		camera_position = (
			player_position
			+ camera_right * offset.z
			+ camera_up * offset.y
			- camera_forward * offset.x
		)
	else:
		camera_position = (
			player_position
			+ camera_right * offset.x
			+ camera_up * offset.y
			- camera_forward * offset.z
		)
	var look_forward := camera_forward
	if mode == &"swing":
		look_forward = Vector3.ZERO
	var look_target := (
		player_position
		+ look_forward * _camera.look_ahead_m
		+ camera_up * _camera.look_at_height_m
		+ camera_right * _camera.player_screen_left_bias_m
	)
	return look_target - camera_position


func _script_has_method(script: Script, method_name: StringName) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if StringName(method.get("name", &"")) == method_name:
			return true
	return false


func _resource_has_property(
	resource: Resource,
	property_name: StringName
) -> bool:
	for property_info: Dictionary in resource.get_property_list():
		if StringName(property_info.get("name", &"")) == property_name:
			return true
	return false


func _toward_camera_view_direction(
	corridor_forward: Vector3,
	offset: Vector3
) -> Vector3:
	var forward := corridor_forward.normalized()
	var up := Vector3.UP
	var right := forward.cross(up).normalized()
	var camera_position := (
		right * offset.x
		+ up * offset.y
		- forward * offset.z
	)
	var look_target := (
		forward * _camera.look_ahead_m
		+ up * _camera.look_at_height_m
		+ right * _camera.player_screen_left_bias_m
	)
	return look_target - camera_position


func _toward_camera_contract_holds(
	corridor_forward: Vector3,
	view_direction: Vector3
) -> bool:
	var horizontal_view := Vector3(
		view_direction.x,
		0.0,
		view_direction.z
	).normalized()
	var depression_degrees := rad_to_deg(atan2(
		-view_direction.y,
		Vector2(
			view_direction.x,
			view_direction.z
		).length()
	))
	return (
		horizontal_view.dot(corridor_forward.normalized())
		<= TOWARD_CAMERA_OPPOSITION_DOT
		and depression_degrees
		>= TOWARD_CAMERA_MINIMUM_DEPRESSION_DEGREES
		and depression_degrees
		<= TOWARD_CAMERA_MAXIMUM_DEPRESSION_DEGREES
	)


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
	var has_method := _script_has_method(script, method_name)
	assert_true(
		has_method,
		"%s must expose %s" % [path, method_name]
	)
	return script if has_method else null
