extends GutTest

const FLOAT_TOLERANCE := 0.0001


class HogPlayerStub:
	extends Node3D

	var mounted: bool
	var mount_calls: int
	var dismount_calls: int
	var accepts_mount := true


	func mount_hog() -> void:
		mounted = accepts_mount
		mount_calls += 1


	func dismount_hog() -> void:
		mounted = false
		dismount_calls += 1


	func is_hog_mounted() -> bool:
		return mounted


func test_marker_path_mounts_player_and_moves_visual_as_one_contract() -> void:
	var fixture := _new_mount_fixture()
	var mount: HogMount = fixture["mount"]
	var path: Path3D = fixture["path"]
	var visual: Node3D = fixture["visual"]
	var player := HogPlayerStub.new()
	player.position = Vector3(0.0, 0.0, -10.0)
	add_child_autofree(player)
	watch_signals(mount)

	mount.configure(player)

	assert_not_null(path.curve)
	assert_eq(path.curve.point_count, 3)
	assert_almost_eq(path.curve.get_baked_length(), 20.0, FLOAT_TOLERANCE)
	assert_almost_eq(
		mount.progress_for_position(player.global_position),
		10.0,
		FLOAT_TOLERANCE
	)
	assert_true(mount.is_mounted())
	assert_true(player.is_hog_mounted())
	assert_eq(player.mount_calls, 1)
	assert_eq(visual.get_parent(), player)
	assert_eq(visual.position, mount.mounted_visual_offset)
	assert_signal_emit_count(mount, "mounted", 1)

	mount.call("_set_mounted", false)

	assert_false(mount.is_mounted())
	assert_false(player.is_hog_mounted())
	assert_eq(player.dismount_calls, 1)
	assert_eq(visual.get_parent(), mount)
	assert_signal_emit_count(mount, "dismounted", 1)


func test_refused_player_mount_keeps_mount_signal_and_visual_inactive() -> void:
	var fixture := _new_mount_fixture()
	var mount: HogMount = fixture["mount"]
	var visual: Node3D = fixture["visual"]
	var player := HogPlayerStub.new()
	player.accepts_mount = false
	player.position = Vector3(0.0, 0.0, -10.0)
	add_child_autofree(player)
	watch_signals(mount)

	mount.configure(player)

	assert_eq(player.mount_calls, 1)
	assert_false(player.is_hog_mounted())
	assert_false(mount.is_mounted())
	assert_eq(visual.get_parent(), mount)
	assert_signal_emit_count(mount, "mounted", 0)


func test_reset_before_and_past_ride_preserves_each_visual_policy() -> void:
	var before_fixture := _new_mount_fixture()
	var before_mount: HogMount = before_fixture["mount"]
	var before_visual: Node3D = before_fixture["visual"]
	var before_player := HogPlayerStub.new()
	before_player.position = Vector3(0.0, 0.0, -10.0)
	add_child_autofree(before_player)
	before_mount.configure(before_player)
	assert_true(before_mount.is_mounted())

	before_mount.reset_for_player_position(Vector3.ZERO)

	assert_false(before_mount.is_mounted())
	assert_false(before_player.is_hog_mounted())
	assert_eq(before_visual.get_parent(), before_mount)
	assert_eq(
		before_visual.transform,
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)),
		"before the mount line, the hog must return to its authored home"
	)

	var past_fixture := _new_mount_fixture()
	var past_mount: HogMount = past_fixture["mount"]
	var past_visual: Node3D = past_fixture["visual"]
	var past_player := HogPlayerStub.new()
	past_player.position = Vector3(0.0, 0.0, -10.0)
	add_child_autofree(past_player)
	past_mount.configure(past_player)
	assert_true(past_mount.is_mounted())
	var mounted_world_transform := past_visual.global_transform

	past_mount.reset_for_player_position(
		Vector3(0.0, 0.0, -20.0)
	)

	assert_false(past_mount.is_mounted())
	assert_false(past_player.is_hog_mounted())
	assert_eq(past_visual.get_parent(), past_mount)
	assert_eq(
		past_visual.global_transform,
		mounted_world_transform,
		"past the dismount line, the hog must stay where the ride ended"
	)


func test_empty_curve_forces_safe_dismount_and_zero_progress() -> void:
	var fixture := _new_mount_fixture()
	var mount: HogMount = fixture["mount"]
	var path: Path3D = fixture["path"]
	var visual: Node3D = fixture["visual"]
	var player := HogPlayerStub.new()
	player.position = Vector3(0.0, 0.0, -10.0)
	add_child_autofree(player)
	mount.configure(player)
	assert_true(mount.is_mounted())
	path.curve = Curve3D.new()

	mount.reset_for_player_position(player.global_position)

	assert_false(mount.is_mounted())
	assert_false(player.is_hog_mounted())
	assert_eq(visual.get_parent(), mount)
	assert_eq(
		visual.transform,
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0))
	)
	assert_eq(
		mount.progress_for_position(player.global_position),
		0.0
	)


func test_trigger_handlers_ignore_non_player_bodies() -> void:
	var fixture := _new_mount_fixture()
	var mount: HogMount = fixture["mount"]
	var player := HogPlayerStub.new()
	player.position = Vector3.ZERO
	add_child_autofree(player)
	var other_body := Node3D.new()
	add_child_autofree(other_body)
	mount.configure(player)
	assert_false(mount.is_mounted())

	mount.call("_on_mount_trigger_body_entered", other_body)

	assert_false(mount.is_mounted())
	assert_eq(player.mount_calls, 0)
	mount.call("_on_mount_trigger_body_entered", player)
	assert_true(mount.is_mounted())
	assert_eq(player.mount_calls, 1)
	var dismount_calls_before := player.dismount_calls

	mount.call("_on_dismount_trigger_body_entered", other_body)

	assert_true(mount.is_mounted())
	assert_true(player.is_hog_mounted())
	assert_eq(player.dismount_calls, dismount_calls_before)


func _new_mount_fixture() -> Dictionary:
	var mount := HogMount.new()
	mount.name = "HogMount"
	mount.mounted_visual_offset = Vector3(0.0, 0.5, -0.25)

	var path := Path3D.new()
	path.name = "Path"
	for marker_position: Vector3 in [
		Vector3.ZERO,
		Vector3(0.0, 0.0, -10.0),
		Vector3(0.0, 0.0, -20.0),
	]:
		var marker := Marker3D.new()
		marker.position = marker_position
		path.add_child(marker)
	mount.add_child(path)

	var mount_trigger := Area3D.new()
	mount_trigger.name = "MountTrigger"
	mount_trigger.position = Vector3(0.0, 0.0, -2.0)
	mount.add_child(mount_trigger)

	var dismount_trigger := Area3D.new()
	dismount_trigger.name = "DismountTrigger"
	dismount_trigger.position = Vector3(0.0, 0.0, -18.0)
	mount.add_child(dismount_trigger)

	var visual := Node3D.new()
	visual.name = "HogVisual"
	visual.position = Vector3(1.0, 0.0, 0.0)
	mount.add_child(visual)

	mount.ride_path_path = NodePath("Path")
	mount.mount_trigger_path = NodePath("MountTrigger")
	mount.dismount_trigger_path = NodePath("DismountTrigger")
	mount.hog_visual_path = NodePath("HogVisual")
	add_child_autofree(mount)

	return {
		"mount": mount,
		"path": path,
		"visual": visual,
	}
