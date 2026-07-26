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
