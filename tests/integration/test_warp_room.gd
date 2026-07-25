extends GutTest

const WARP_ROOM_SCENE_PATH := "res://scenes/levels/warp_room_1.tscn"
const PORTAL_SCENE_PATH := "res://scenes/props/portal.tscn"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const N_SANITY_SCENE_PATH := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)
const TEST_SAVE_DIR := "user://test_sandbox/task15_warp_room"
const LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
	&"wr1_boulders",
	&"wr1_hog_wild",
]
const AVAILABLE_LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
]
const BOSS_ID := &"wr1_papu_papu"


func before_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)


func test_warp_room_authors_all_portals_but_locks_unbuilt_levels() -> void:
	var room := _instantiate_room()
	if room == null:
		return
	await wait_process_frames(1)
	_configure_room(room, SaveModel.fresh())

	assert_true(room.has_node("Player"))
	assert_true(room.has_node("UI/LevelList"))
	var portals := _portals(room)
	assert_eq(portals.size(), LEVEL_IDS.size() + 1)
	for level_id: StringName in LEVEL_IDS:
		var portal := _portal_for(portals, level_id)
		assert_not_null(portal, "%s portal must be authored" % level_id)
		if portal != null:
			var expected_open := level_id == &"wr1_n_sanity_beach"
			assert_eq(
				portal.get_meta("unlocked", false),
				expected_open
			)
			assert_eq(portal.monitoring, expected_open)
	var boss := _portal_for(portals, BOSS_ID)
	assert_not_null(boss)
	if boss != null:
		assert_false(boss.get_meta("unlocked", true))
		assert_false(boss.monitoring)


func test_entering_a_portal_emits_the_exact_flow_event_payload() -> void:
	var room := _instantiate_room()
	if room == null:
		return
	await wait_process_frames(1)
	_configure_room(room, SaveModel.fresh())
	var received: Array[Dictionary] = []
	room.connect(
		&"flow_event_requested",
		func(event: Dictionary) -> void:
			received.append(event.duplicate(true))
	)
	var portal := _portal_for(
		_portals(room),
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return

	portal.emit_signal(&"body_entered", room.get_node("Player"))

	assert_eq(received.size(), 1)
	if received.is_empty():
		return
	assert_eq(received[0].get("type"), &"portal_enter")
	assert_eq(
		received[0].get("level_id"),
		&"wr1_n_sanity_beach"
	)
	assert_eq(received[0].get("mode"), &"normal")


func test_unbuilt_portal_stays_in_warp_room_when_player_enters_its_volume() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)
	var room := root.get_node_or_null("Content/WarpRoom1")
	assert_not_null(room)
	if room == null:
		return
	var portal := _portal_for(
		_portals(room),
		&"wr1_boulders"
	)
	assert_not_null(portal)
	if portal == null:
		return
	assert_false(
		portal.monitoring,
		"an unbuilt level portal must not monitor player bodies"
	)
	var player := room.get_node("Player") as CharacterBody3D
	player.global_position = portal.global_position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(3)

	assert_eq(
		root.call("state_name"),
		&"warp_room",
		"entering an unbuilt portal volume must not leave the hub"
	)
	assert_true(root.has_node("Content/WarpRoom1"))
	assert_false(root.has_node("Content/LevelPlaceholder"))


func test_completed_level_exposes_relic_portal_only_with_authored_pars() -> void:
	var room := _instantiate_room()
	if room == null:
		return
	await wait_process_frames(1)
	var profile := SaveModel.fresh()
	var record := SaveModel.level_record(
		profile,
		&"wr1_n_sanity_beach"
	)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels["wr1_n_sanity_beach"] = record
	var catalog := (
		load("res://data/tuning/gameplay.tres")
		as GameplayTuning
	)
	var meta := (
		load(
			"res://data/tuning/levels/n_sanity_beach.tres"
		).duplicate(true) as LevelMeta
	)
	meta.relic_platinum_s = catalog.economy.time_crate_small_s
	meta.relic_gold_s = (
		meta.relic_platinum_s
		+ catalog.economy.time_crate_medium_s
	)
	meta.relic_sapphire_s = (
		meta.relic_gold_s
		+ catalog.economy.time_crate_large_s
	)
	room.call(
		"configure",
		profile,
		catalog,
		{&"wr1_n_sanity_beach": meta},
		false,
		AVAILABLE_LEVEL_IDS
	)
	var portal := _portal_for(
		_portals(room),
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return
	var relic_trigger := portal.get_node(
		"RelicTrigger"
	) as Area3D
	assert_true(relic_trigger.visible)
	assert_true(relic_trigger.monitoring)
	var received: Array[Dictionary] = []
	room.connect(
		&"flow_event_requested",
		func(event: Dictionary) -> void:
			received.append(event.duplicate(true))
	)

	relic_trigger.emit_signal(
		&"body_entered",
		room.get_node("Player")
	)

	assert_eq(received.size(), 1)
	if not received.is_empty():
		assert_eq(received[0].get("mode"), &"relic")


func test_real_boss_portal_requires_each_level_clear_individually() -> void:
	var room := _instantiate_room()
	if room == null:
		return
	await wait_process_frames(1)
	var boss := _portal_for(_portals(room), BOSS_ID)
	assert_not_null(boss)
	if boss == null:
		return

	for missing_level_id: StringName in LEVEL_IDS:
		var profile := SaveModel.fresh()
		for level_id: StringName in LEVEL_IDS:
			if level_id != missing_level_id:
				_set_completed(profile, level_id)
		_configure_room(room, profile)
		assert_false(
			boss.get_meta("unlocked", true),
			"%s must keep the real boss portal locked"
			% missing_level_id
		)
		assert_false(boss.monitoring)


func test_boot_hub_level_list_reaches_level_through_threaded_load() -> void:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		assert_true(false, "main scene must exist")
		return
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"warp_room")
	assert_true(root.has_node("Content/WarpRoom1"))
	if not root.has_node("Content/WarpRoom1"):
		return
	var room := root.get_node("Content/WarpRoom1")
	room.get_node("UI/LevelList").emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"paused")
	var list := root.get_node("UI/LevelListOverlay")
	assert_true(list.visible)

	list.get_node(
		"SafeArea/Center/Panel/Margin/Rows/NSanityBeach"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"level")
	assert_eq(
		root.call("threaded_level_path"),
		N_SANITY_SCENE_PATH
	)

	# Hold the consumer while the test observes the loader's terminal state.
	# Otherwise GameRoot may validly consume a fast cached request first.
	root.set_process(false)
	var status := ResourceLoader.load_threaded_get_status(
		N_SANITY_SCENE_PATH
	)
	var poll_count := 0
	while (
		status == ResourceLoader.THREAD_LOAD_IN_PROGRESS
		and poll_count < 120
	):
		await wait_process_frames(1)
		poll_count += 1
		status = ResourceLoader.load_threaded_get_status(
			N_SANITY_SCENE_PATH
		)
	assert_eq(status, ResourceLoader.THREAD_LOAD_LOADED)
	root.set_process(true)
	await wait_process_frames(2)
	assert_true(root.has_node("Content/NSanityBeach"))
	assert_gt(
		int(root.call("threaded_level_poll_count")),
		0,
		"GameRoot itself must poll the threaded request"
	)
	root.queue_free()
	await wait_process_frames(2)


func test_app_pause_during_real_level_load_resumes_into_authored_scene() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)
	var room := root.get_node_or_null("Content/WarpRoom1")
	assert_not_null(room)
	if room == null:
		return

	room.get_node("UI/LevelList").emit_signal(&"pressed")
	var list := root.get_node("UI/LevelListOverlay")
	list.get_node(
		"SafeArea/Center/Panel/Margin/Rows/NSanityBeach"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"level")
	assert_true(root.has_node("Content/LevelLoading"))

	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	await wait_process_frames(1)
	root.get_node(
		"UI/PauseOverlay/SafeArea/Center/Panel/Margin/Rows/Resume"
	).emit_signal(&"pressed")
	assert_eq(root.call("state_name"), &"level")

	var frames := 0
	while (
		not root.has_node("Content/NSanityBeach")
		and frames < 120
	):
		await wait_process_frames(1)
		frames += 1
	assert_true(
		root.has_node("Content/NSanityBeach"),
		"resuming the real pause UI must finish the interrupted level load"
	)


func test_quit_during_threaded_load_can_reenter_without_stalling() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)
	var portal_event := {
		"type": &"portal_enter",
		"level_id": &"wr1_n_sanity_beach",
	}

	assert_eq(root.call("dispatch", portal_event), OK)
	assert_eq(
		root.call("dispatch", {"type": &"quit_level"}),
		OK
	)
	assert_eq(root.call("state_name"), &"warp_room")
	assert_eq(root.call("dispatch", portal_event), OK)

	var frames := 0
	while (
		not root.has_node("Content/NSanityBeach")
		and frames < 120
	):
		await wait_process_frames(1)
		frames += 1
	assert_true(root.has_node("Content/NSanityBeach"))
	root.queue_free()
	await wait_process_frames(2)


func test_hub_touch_exclusions_include_the_debug_drawer() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"warp_room")
	assert_true(root.has_node("Content/WarpRoom1"))
	if not root.has_node("Content/WarpRoom1"):
		return
	var debug_ui := root.get_node("UI/TuningDebug")
	assert_true(
		debug_ui.visible,
		"debug tools must be enabled in this test environment"
	)
	var touch := root.get_node("Content/WarpRoom1/UI/TouchControls")
	var exclusions: Array = touch.get("_touch_exclusion_controls")
	assert_true(
		exclusions.has(debug_ui.get_node("HUD")),
		(
			"the hub's touch controls must exclude the debug HUD strip, "
			+ "the same way the level's do (§5.2 occlusion rule)"
		)
	)
	assert_true(
		exclusions.has(debug_ui.get_node("Drawer")),
		(
			"the hub's touch controls must exclude the debug drawer, "
			+ "the same way the level's do (§5.2 occlusion rule)"
		)
	)


func _instantiate_room() -> Node:
	assert_true(
		ResourceLoader.exists(PORTAL_SCENE_PATH),
		"Task 15 must provide the reusable portal prop"
	)
	assert_true(
		ResourceLoader.exists(WARP_ROOM_SCENE_PATH),
		"Task 15 must provide Warp Room 1"
	)
	if (
		not ResourceLoader.exists(PORTAL_SCENE_PATH)
		or not ResourceLoader.exists(WARP_ROOM_SCENE_PATH)
	):
		return null
	var packed := load(WARP_ROOM_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var room := packed.instantiate()
	add_child_autofree(room)
	return room


func _configure_room(room: Node, profile: Dictionary) -> void:
	var catalog := (
		load("res://data/tuning/gameplay.tres")
		as GameplayTuning
	)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	) as LevelMeta
	room.call(
		"configure",
		profile,
		catalog,
		{&"wr1_n_sanity_beach": meta},
		false,
		AVAILABLE_LEVEL_IDS
	)


func _portals(room: Node) -> Array[Area3D]:
	var result: Array[Area3D] = []
	for candidate: Node in room.find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if candidate.is_in_group(&"warp_portal"):
			result.append(candidate as Area3D)
	return result


func _portal_for(
	portals: Array[Area3D],
	level_id: StringName
) -> Area3D:
	for portal: Area3D in portals:
		if StringName(portal.get_meta("level_id", &"")) == level_id:
			return portal
	return null


func _set_completed(profile: Dictionary, level_id: StringName) -> void:
	var record := SaveModel.level_record(profile, level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(level_id)] = record


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
