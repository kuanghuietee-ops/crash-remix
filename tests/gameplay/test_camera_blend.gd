extends GutTest

const BLEND_SCRIPT_PATH := "res://src/gameplay/camera/camera_blend.gd"
const TUNING_PATH := "res://data/tuning/gameplay.tres"
const FRAME_DELTA_S := 1.0 / 60.0
const VECTOR_TOLERANCE := 0.0001

var _camera: CameraTuning


func before_all() -> void:
	var catalog: GameplayTuning = load(TUNING_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_camera = catalog.camera


func test_overlapping_regions_average_their_camera_offsets() -> void:
	var script: Script = load(BLEND_SCRIPT_PATH)
	assert_not_null(script, "CameraBlend implementation must exist")
	if script == null:
		return
	var first := Vector3(2.0, 4.0, 8.0)
	var second := Vector3(8.0, 2.0, 4.0)

	var resolved: Vector3 = script.call(
		"resolve_offset", _camera.default_offset, [first, second]
	)

	assert_eq(resolved, Vector3(5.0, 3.0, 6.0))


func test_region_blend_makes_partial_frame_scaled_progress() -> void:
	var script: Script = load(BLEND_SCRIPT_PATH)
	assert_not_null(script, "CameraBlend implementation must exist")
	if script == null:
		return
	var target := Vector3(8.0, 3.0, 1.0)

	var blended: Vector3 = script.call(
		"offset_at_elapsed",
		_camera.default_offset,
		target,
		FRAME_DELTA_S,
		_camera
	)
	var expected: Vector3 = _camera.default_offset.lerp(
		target,
		FRAME_DELTA_S / _camera.region_blend_s
	)

	assert_almost_eq(blended.x, expected.x, VECTOR_TOLERANCE)
	assert_almost_eq(blended.y, expected.y, VECTOR_TOLERANCE)
	assert_almost_eq(blended.z, expected.z, VECTOR_TOLERANCE)
	assert_ne(blended, target)


func test_region_blend_reaches_target_at_authored_duration() -> void:
	var script: Script = load(BLEND_SCRIPT_PATH)
	assert_not_null(script, "CameraBlend implementation must exist")
	if script == null:
		return
	var target := Vector3(8.0, 3.0, 1.0)

	var halfway: Vector3 = script.call(
		"offset_at_elapsed",
		_camera.default_offset,
		target,
		_camera.region_blend_s / 2.0,
		_camera
	)
	var complete: Vector3 = script.call(
		"offset_at_elapsed",
		_camera.default_offset,
		target,
		_camera.region_blend_s,
		_camera
	)

	assert_eq(halfway, _camera.default_offset.lerp(target, 0.5))
	assert_eq(complete, target)


func test_every_phase_zero_camera_offset_clears_depth_readability_rule() -> void:
	var script: Script = load(BLEND_SCRIPT_PATH)
	assert_not_null(script, "CameraBlend implementation must exist")
	if script == null:
		return
	var offsets := [
		_camera.default_offset,
		_camera.close_offset,
		_camera.side_on_offset,
	]
	for offset: Vector3 in offsets:
		var depression: float = script.call("depression_degrees", offset)
		assert_gte(
			depression,
			_camera.minimum_jump_depression_degrees,
			"Every required-jump camera archetype must keep landings readable"
		)
