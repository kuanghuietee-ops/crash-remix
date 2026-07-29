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
