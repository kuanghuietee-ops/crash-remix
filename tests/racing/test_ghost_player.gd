extends GutTest

# CTR R7 Task 6 (stretch, time-trial ghost): GhostPlayer is the PLAYBACK
# half -- see ghost_player.gd's own class doc and
# .superpowers/sdd/2026-08-01-ctr-r7-second-circuit/task-6-brief.md. This
# file covers the pure replay-interpolation math (no instance/tree needed --
# interpolate_pose() is a static func) and the "pure visual, no collision"
# structural proof. File persistence (round-trip/corruption) is proved
# separately in test_ghost_file_format.gd.

const GhostPlayerType := preload("res://src/racing/flow/ghost_player.gd")


func _frame(t: float, position: Vector3, yaw_degrees: float) -> Dictionary:
	return {"t": t, "position": position, "yaw_degrees": yaw_degrees}


# ---------------------------------------------------------------------------
# interpolate_pose(): pure math, callable with no scene tree at all.
# ---------------------------------------------------------------------------


func test_interpolate_pose_on_empty_keyframes_returns_empty() -> void:
	var frames: Array[Dictionary] = []

	var pose := GhostPlayerType.interpolate_pose(frames, 1.0)

	assert_true(pose.is_empty())


func test_interpolate_pose_before_the_first_keyframe_clamps_to_it() -> void:
	var frames: Array[Dictionary] = [
		_frame(1.0, Vector3(10.0, 0.0, 0.0), 0.0),
		_frame(2.0, Vector3(20.0, 0.0, 0.0), 0.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 0.0)

	assert_eq(pose["position"], Vector3(10.0, 0.0, 0.0))


func test_interpolate_pose_after_the_last_keyframe_clamps_to_it() -> void:
	var frames: Array[Dictionary] = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(1.0, Vector3(10.0, 0.0, 0.0), 0.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 5.0)

	assert_eq(pose["position"], Vector3(10.0, 0.0, 0.0))


func test_interpolate_pose_at_the_midpoint_lerps_position() -> void:
	var frames: Array[Dictionary] = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(1.0, Vector3(10.0, 0.0, 20.0), 0.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 0.5)

	assert_eq(pose["position"], Vector3(5.0, 0.0, 10.0))


func test_interpolate_pose_at_a_quarter_point_lerps_position() -> void:
	var frames: Array[Dictionary] = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(4.0, Vector3(8.0, 0.0, 0.0), 0.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 1.0)

	assert_eq(pose["position"], Vector3(2.0, 0.0, 0.0))


func test_interpolate_pose_finds_the_bracketing_pair_across_many_keyframes() -> void:
	var frames: Array[Dictionary] = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(0.1, Vector3(1.0, 0.0, 0.0), 0.0),
		_frame(0.2, Vector3(2.0, 0.0, 0.0), 0.0),
		_frame(0.3, Vector3(3.0, 0.0, 0.0), 0.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 0.25)

	assert_eq(pose["position"], Vector3(2.5, 0.0, 0.0))


func test_interpolate_pose_lerps_yaw_the_short_way_across_the_wrap() -> void:
	var frames: Array[Dictionary] = [
		_frame(0.0, Vector3.ZERO, 170.0),
		_frame(1.0, Vector3.ZERO, -170.0),
	]

	var pose := GhostPlayerType.interpolate_pose(frames, 0.5)

	# The short way from 170deg to -170deg passes through 180deg/-180deg (a
	# 20-degree turn), never back through 0deg (which a naive raw-degree
	# lerp -- (170 + -170) / 2 -- would produce).
	var yaw: float = pose["yaw_degrees"]
	assert_true(
		is_equal_approx(absf(yaw), 180.0),
		"expected the short way around the wrap (+/-180deg), got %s" % yaw
	)


func test_interpolate_pose_on_a_single_keyframe_always_returns_it() -> void:
	var frames: Array[Dictionary] = [
		_frame(3.0, Vector3(7.0, 0.0, 0.0), 45.0),
	]

	assert_eq(
		GhostPlayerType.interpolate_pose(frames, 0.0)["position"],
		Vector3(7.0, 0.0, 0.0)
	)
	assert_eq(
		GhostPlayerType.interpolate_pose(frames, 100.0)["position"],
		Vector3(7.0, 0.0, 0.0)
	)


# ---------------------------------------------------------------------------
# Structural proof: a pure visual, no physics of any kind.
# ---------------------------------------------------------------------------


func test_ghost_visual_has_no_collision_object_anywhere_in_its_subtree() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)

	var stack: Array[Node] = [player]
	var collision_object_found := false
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject3D:
			collision_object_found = true
		for child: Node in node.get_children():
			stack.append(child)

	assert_false(
		collision_object_found,
		"the ghost kart must never contain an Area3D/body -- pure visual only"
	)


func test_ghost_visual_carries_at_least_one_mesh_instance() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)

	var mesh_instances := player.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)

	assert_gt(mesh_instances.size(), 0)


func test_ghost_visual_is_hidden_until_start_replay() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)

	assert_false(player.visible)


# ---------------------------------------------------------------------------
# Replay lifecycle: start/advance/hide-at-end, driven purely by a pushed
# elapsed_s clock (no internal timer, no _process ticking required).
# ---------------------------------------------------------------------------


func test_start_replay_without_a_loaded_ghost_stays_hidden() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)

	player.start_replay()

	assert_false(player.visible)
	assert_false(player.has_ghost())


func test_advance_moves_the_visual_to_the_interpolated_pose() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)
	player._keyframes = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(1.0, Vector3(10.0, 0.0, 0.0), 0.0),
	]

	player.start_replay()
	assert_true(player.visible)

	player.advance(0.5)

	# advance() moves THIS node (self), never _visual's own transform
	# directly -- see advance()'s own doc for why.
	assert_eq(player.global_position, Vector3(5.0, 0.0, 0.0))


## Regression: advance() used to write the replayed pose straight onto
## _visual's own global_transform, which (global_transform's setter solves
## for the LOCAL transform that achieves it) silently replaced _visual's
## authored local rotation.y == PI mesh-forward correction the instant the
## first keyframe played, leaving the ghost kart rendering backwards from
## then on. advance() now moves the PARENT (self) instead, so _visual's own
## local rotation must read exactly PI no matter how many keyframes have
## played.
func test_advance_never_disturbs_the_visuals_own_pi_forward_correction() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)
	player._keyframes = [
		_frame(0.0, Vector3(0.0, 0.0, 0.0), 0.0),
		_frame(1.0, Vector3(10.0, 0.0, 0.0), 45.0),
		_frame(2.0, Vector3(20.0, 5.0, -3.0), 190.0),
	]

	player.start_replay()
	player.advance(0.5)
	player.advance(1.5)

	assert_almost_eq(player._visual.rotation.y, PI, 0.0001)


func test_advance_past_the_last_keyframe_hides_and_stops_the_replay() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)
	player._keyframes = [
		_frame(0.0, Vector3.ZERO, 0.0),
		_frame(1.0, Vector3(10.0, 0.0, 0.0), 0.0),
	]

	player.start_replay()
	player.advance(1.0)

	assert_false(player.visible, "the ghost must hide once replay reaches its end")


func test_clear_hides_and_forgets_the_loaded_ghost() -> void:
	var player := GhostPlayerType.new()
	add_child_autofree(player)
	player._keyframes = [_frame(0.0, Vector3.ZERO, 0.0)]
	player.start_replay()

	player.clear()

	assert_false(player.visible)
	assert_false(player.has_ghost())
