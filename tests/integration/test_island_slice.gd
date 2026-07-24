extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const LEVEL_ID := &"wr1_n_sanity_beach"
const TEST_SAVE_DIR := "user://test_sandbox/task13_island_slice"
const CRATE_TOTAL := 40


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_island_slice_full_loop() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(root.call("state_name"), &"warp_room")
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": LEVEL_ID,
			}
		),
		OK
	)
	await wait_process_frames(2)
	var level := root.get_node_or_null(
		"Content/NSanityBeach"
	) as LevelSession
	assert_not_null(
		level,
		"the known level id must load the authored scene"
	)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	var first_crate := _crate(level, 1)
	var checkpoint := _crate(level, 14)
	var second_crate := _crate(level, 15)
	var third_crate := _crate(level, 16)
	assert_not_null(first_crate)
	assert_not_null(checkpoint)
	assert_not_null(second_crate)
	assert_not_null(third_crate)
	if (
		first_crate == null
		or checkpoint == null
		or second_crate == null
		or third_crate == null
	):
		return

	player.get_node("SpinArea").emit_signal(
		&"body_entered",
		first_crate
	)
	await wait_process_frames(1)
	assert_true(first_crate.call("is_broken"))
	assert_eq(level.run_state.broken_crate_ids, [1])
	assert_eq(
		root.get_node(
			"UI/HUD/SafeArea/Stats/Margin/Rows/Crates"
		).text,
		"CRATES  1 / %d" % CRATE_TOTAL
	)

	checkpoint.call("apply_verb", &"spin", 2.0)
	assert_eq(level.run_state.checkpoint_id, 14)
	var checkpoint_spawn: Transform3D = player.get(
		"_spawn_transform"
	)
	assert_true(
		is_equal_approx(checkpoint_spawn.origin.y, 0.05),
		"checkpoint respawn must put the player's feet above the route"
	)
	assert_gt(
		checkpoint_spawn.origin.z,
		(checkpoint as Node3D).global_position.z,
		"checkpoint respawn must sit safely behind the broken crate"
	)
	second_crate.call("apply_verb", &"spin", 3.0)
	third_crate.call("apply_verb", &"spin", 4.0)
	assert_eq(
		level.run_state.broken_crate_ids,
		[1, 14, 15, 16]
	)

	level.record_player_death()
	player.respawn()
	assert_true(
		player.global_transform.is_equal_approx(checkpoint_spawn)
	)
	for crate_id: int in [1, 14, 15, 16]:
		var broken_crate := _crate(level, crate_id)
		assert_true(broken_crate.call("is_broken"))
		assert_false(broken_crate.get_node("Mesh").visible)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	assert_true(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_eq(
		root.call("dispatch", {"type": &"resume"}),
		OK
	)
	level.complete_level()
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(payload.get("box_count"), 4)
	assert_eq(payload.get("crate_count"), CRATE_TOTAL)
	assert_false(payload.get("gem"))
	var missed_by_segment: Dictionary = payload.get(
		"missed_crate_ids_by_segment",
		{}
	)
	assert_true(missed_by_segment.has("Beach Landing"))
	assert_false(missed_by_segment.has("Unassigned"))

	var profile_path := TEST_SAVE_DIR.path_join("profile.json")
	assert_true(FileAccess.file_exists(profile_path))
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("profile.json.tmp")
		)
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(profile_path)
	)
	assert_true(parsed is Dictionary)
	if parsed is Dictionary:
		assert_true(SaveModel.validate(parsed))
		var migrated := SaveModel.migrate(parsed)
		var record := SaveModel.level_record(
			migrated,
			LEVEL_ID
		)
		assert_true(record.get("completed"))
		assert_eq(
			record.get("last_missed_crate_ids"),
			payload.get("missed_crate_ids")
		)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_bounce_launch_and_tnt_chain_are_wired_in_scene() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	root.call(
		"dispatch",
		{
			"type": &"portal_enter",
			"level_id": LEVEL_ID,
		}
	)
	await wait_process_frames(2)
	var level := root.get_node_or_null(
		"Content/NSanityBeach"
	) as LevelSession
	if level == null:
		assert_not_null(level)
		return
	var player := level.get_node("Player") as CharacterBody3D
	var bounce := _crate(level, 8)
	var tnt := _crate(level, 27)
	var blast_neighbour := _crate(level, 26)
	assert_not_null(bounce)
	assert_not_null(tnt)
	assert_not_null(blast_neighbour)
	if bounce == null or tnt == null or blast_neighbour == null:
		return

	player.velocity = Vector3.ZERO
	bounce.call("apply_bounce", 0.0, 1.0)
	assert_gt(
		player.velocity.y,
		0.0,
		"the scene session must apply a bounce crate launch"
	)
	tnt.call("apply_verb", &"spin", 2.0)
	assert_true(tnt.call("is_broken"))
	assert_true(
		blast_neighbour.call("is_broken"),
		"TNT detonation must reach nearby authored crates"
	)


func test_replay_marks_only_the_previous_runs_missed_crates() -> void:
	var seeded_profile := SaveModel.fresh()
	var record := SaveModel.level_record(
		seeded_profile,
		LEVEL_ID
	)
	record["completed"] = true
	record["last_missed_crate_ids"] = [1, 2]
	seeded_profile["levels"][String(LEVEL_ID)] = record
	assert_eq(
		SaveService.new().store_profile(
			TEST_SAVE_DIR,
			seeded_profile
		),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	root.call(
		"dispatch",
		{
			"type": &"portal_enter",
			"level_id": LEVEL_ID,
		}
	)
	await wait_process_frames(2)
	var level := root.get_node_or_null(
		"Content/NSanityBeach"
	) as LevelSession
	if level == null:
		assert_not_null(level)
		return
	var missed_one := _crate(level, 1)
	var missed_two := _crate(level, 2)
	var collected_last_run := _crate(level, 3)
	var ghost_one := missed_one.get_node_or_null(
		"GhostMarker"
	) as MeshInstance3D
	assert_not_null(ghost_one)
	assert_not_null(missed_two.get_node_or_null("GhostMarker"))
	assert_null(collected_last_run.get_node_or_null("GhostMarker"))
	if ghost_one != null:
		var material := ghost_one.material_override as ShaderMaterial
		assert_not_null(material)
		if material != null:
			assert_eq(
				material.shader.resource_path,
				"res://assets/shaders/phase_ghost.gdshader"
			)

	missed_one.call("apply_verb", &"spin", 1.0)
	assert_false(ghost_one.visible)


func test_authored_level_touch_spin_remains_live_under_the_hud() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	root.call(
		"dispatch",
		{
			"type": &"portal_enter",
			"level_id": LEVEL_ID,
		}
	)
	await wait_physics_frames(3)
	var level := root.get_node_or_null(
		"Content/NSanityBeach"
	) as LevelSession
	if level == null:
		assert_not_null(level)
		return
	var player := level.get_node("Player") as CharacterBody3D
	var touch := level.get_node("UI/TouchControls") as Control
	var spin_press := InputEventScreenTouch.new()
	spin_press.index = 13
	spin_press.position = (
		touch.call("current_layout")["spin_center"]
	)
	spin_press.pressed = true

	touch.call("handle_touch_event", spin_press)
	await wait_physics_frames(2)

	assert_true(player.call("is_spinning"))
	spin_press.pressed = false
	touch.call("handle_touch_event", spin_press)


func _instantiate_main() -> Node:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	return root


func _crate(level: Node, crate_id: int) -> Node:
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			candidate.has_method("apply_verb")
			and int(candidate.get("crate_id")) == crate_id
		):
			return candidate
	return null


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		directory.remove(file_name)
	for child_name: String in directory.get_directories():
		_remove_tree(path.path_join(child_name))
	DirAccess.remove_absolute(absolute)
