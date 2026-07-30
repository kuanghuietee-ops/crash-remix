extends GutTest

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const DEFAULT_SAVE_DIR := "user://save"
const TEST_SAVE_DIR := "user://test_sandbox/task5_main_boot"
const TEST_OVERRIDE_PATH := (
	TEST_SAVE_DIR + "/injected_tuning_override.tres"
)
const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const PLACEHOLDER_LEVEL_ID := &"test_level"
const FUTURE_SAVE_FIXTURE := (
	"res://tests/fixtures/saves/profile_future_version.json"
)
const N_SANITY_META_PATH := (
	"res://data/tuning/levels/n_sanity_beach.tres"
)
const DynamicResolutionType := preload(
	"res://src/core/dynamic_resolution.gd"
)
# Against the 60 fps budget: 16 ms is nearly out of it, 8 ms is far inside.
const SLOW_FRAME_S := 0.016
const FAST_FRAME_S := 0.008

var _input_use_accumulated_before_test: bool


class FailingSaveService:
	extends SaveService

	func store_profile(_save_dir: String, _data: Dictionary) -> Error:
		return ERR_CANT_CREATE


func before_each() -> void:
	_input_use_accumulated_before_test = (
		Input.is_using_accumulated_input()
	)
	_remove_tree(TEST_SAVE_DIR)


func after_each() -> void:
	_remove_tree(TEST_SAVE_DIR)
	var phase_state := get_node_or_null("/root/PhaseState")
	if phase_state != null:
		phase_state.call("reset_to_authored_set")
	Input.set_use_accumulated_input(
		_input_use_accumulated_before_test
	)


func test_main_cleanup_restores_input_accumulation_global() -> void:
	var entering_state := Input.is_using_accumulated_input()
	Input.set_use_accumulated_input(true)
	before_each()
	var root := _instantiate_main()
	if root == null:
		Input.set_use_accumulated_input(entering_state)
		before_each()
		return
	await wait_process_frames(1)
	assert_false(
		Input.is_using_accumulated_input(),
		"the real main root must exercise its global input mutation"
	)

	after_each()

	assert_true(
		Input.is_using_accumulated_input(),
		"test cleanup must restore the entering Input singleton state"
	)
	Input.set_use_accumulated_input(entering_state)
	before_each()


func test_main_boots_fresh_profile_to_warp_room_through_scratch_path() -> void:
	var live_primary := DEFAULT_SAVE_DIR.path_join("profile.json")
	var live_existed := FileAccess.file_exists(live_primary)
	var live_bytes := (
		FileAccess.get_file_as_bytes(live_primary)
		if live_existed
		else PackedByteArray()
	)
	assert_true(
		ResourceLoader.exists(MAIN_SCENE_PATH),
		"Phase 1 main scene must exist"
	)
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
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
	assert_true(SaveModel.validate(root.get("profile")))
	assert_eq(root.get("save_dir"), TEST_SAVE_DIR)
	assert_true(root.has_node("Content/WarpRoom1"))
	var hub_player := root.get_node("Content/WarpRoom1/Player")
	assert_true(
		_has_property(hub_player, &"_phase_enabled"),
		"the hub player must receive the progression consumption gate"
	)
	if _has_property(hub_player, &"_phase_enabled"):
		assert_false(hub_player.get("_phase_enabled"))
	assert_false(
		DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(TEST_SAVE_DIR)
		),
		"loading a fresh profile must not create a save directory"
	)
	assert_eq(FileAccess.file_exists(live_primary), live_existed)
	if live_existed:
		assert_eq(FileAccess.get_file_as_bytes(live_primary), live_bytes)


func test_future_profile_refuses_real_boot_without_overwrite() -> void:
	var primary_path := TEST_SAVE_DIR.path_join("profile.json")
	_write_text(
		primary_path,
		FileAccess.get_file_as_string(FUTURE_SAVE_FIXTURE)
	)
	var before := FileAccess.get_file_as_bytes(primary_path)
	var root := _instantiate_main()
	if root == null:
		return

	await wait_process_frames(1)

	assert_push_error("Save data was written by a newer version")
	assert_eq(root.get("boot_error"), ERR_UNAVAILABLE)
	assert_eq(root.call("state_name"), &"boot")
	assert_false(root.has_node("Content/WarpRoom1"))
	var boot_error_overlay := root.get_node_or_null(
		"UI/BootError"
	) as Control
	assert_not_null(
		boot_error_overlay,
		"Q9 must show a player-visible boot error"
	)
	if boot_error_overlay != null:
		assert_true(boot_error_overlay.visible)
		var message := boot_error_overlay.call(
			"message_text"
		) as String
		assert_string_contains(message.to_lower(), "newer version")
		assert_string_contains(message.to_lower(), "not changed")
	assert_eq(
		FileAccess.get_file_as_bytes(primary_path),
		before,
		"Q9 must leave the future save byte-identical"
	)


func test_wrong_typed_base_tuning_catalog_shows_a_player_facing_boot_error() -> void:
	# R5: the base-tuning-load failure returns before Task 11's _install_task11_ui()
	# ever ran, so _boot_error_overlay did not exist yet -- a total black screen
	# with no text, worse than the Q9 case this same overlay already covers.
	# Points base_tuning_path at a real, cleanly-loadable resource of the WRONG
	# type (a LevelMeta, not a GameplayTuning) rather than a nonexistent path:
	# `load_from_paths` rejects it the identical way (`not authored is
	# GameplayTuning`), without a genuinely missing file provoking spurious
	# engine-level load errors unrelated to what this test is proving.
	var root := _instantiate_main_with_base_tuning_path(
		N_SANITY_META_PATH
	)
	if root == null:
		return
	await wait_process_frames(1)

	assert_push_error("Phase 1 tuning failed to load")
	assert_ne(root.get("boot_error"), OK)
	assert_eq(root.call("state_name"), &"boot")
	assert_false(root.has_node("Content/WarpRoom1"))
	var boot_error_overlay := root.get_node_or_null(
		"UI/BootError"
	) as Control
	assert_not_null(
		boot_error_overlay,
		"a missing base tuning catalog must still show a player-visible boot error"
	)
	if boot_error_overlay == null:
		return
	assert_true(boot_error_overlay.visible)
	var message := boot_error_overlay.call("message_text") as String
	assert_false(
		message.is_empty(),
		"the overlay must render real text, not stay blank"
	)


func test_unusable_authored_base_catalog_shows_a_player_facing_boot_error() -> void:
	# R7 added a second cause of the same early return: catalog_is_usable()
	# rejecting the authored base itself (not just a missing/corrupt file).
	# Both causes share the one early return in _ready() and both must reach
	# the player, not just push_error into an invisible engine log.
	var broken_base_path := TEST_SAVE_DIR.path_join(
		"broken_base_catalog.tres"
	)
	assert_eq(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(TEST_SAVE_DIR)
		),
		OK
	)
	var authored: GameplayTuning = (
		load(BASE_TUNING_PATH).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	)
	authored.move.run_speed_mps = 0.0
	assert_eq(ResourceSaver.save(authored, broken_base_path), OK)

	var root := _instantiate_main_with_base_tuning_path(broken_base_path)
	if root == null:
		return
	await wait_process_frames(1)

	assert_push_error("Phase 1 tuning failed to load")
	assert_ne(root.get("boot_error"), OK)
	assert_eq(root.call("state_name"), &"boot")
	var boot_error_overlay := root.get_node_or_null(
		"UI/BootError"
	) as Control
	assert_not_null(
		boot_error_overlay,
		"an unusable authored base catalog must still show a player-visible boot error"
	)
	if boot_error_overlay == null:
		return
	assert_true(boot_error_overlay.visible)
	var message := boot_error_overlay.call("message_text") as String
	assert_false(
		message.is_empty(),
		"the overlay must render real text, not stay blank"
	)


func test_future_backup_without_primary_is_preserved_and_does_not_brick_boot() -> void:
	var backup_path := TEST_SAVE_DIR.path_join(
		"profile.json.bak"
	)
	var preserved_path := TEST_SAVE_DIR.path_join(
		"profile.json.bak.future"
	)
	_write_text(
		backup_path,
		FileAccess.get_file_as_string(FUTURE_SAVE_FIXTURE)
	)
	var before := FileAccess.get_file_as_bytes(backup_path)
	var root := _instantiate_main()
	if root == null:
		return

	await wait_process_frames(1)

	assert_eq(root.get("boot_error"), OK)
	assert_eq(root.call("state_name"), &"warp_room")
	assert_true(root.has_node("Content/WarpRoom1"))
	assert_true(SaveModel.validate(root.get("profile")))
	assert_eq(
		FileAccess.get_file_as_bytes(backup_path),
		before,
		"boot must not overwrite the newer backup"
	)
	assert_eq(
		FileAccess.get_file_as_bytes(preserved_path),
		before,
		"the downgrade-safe copy must retain the newer bytes"
	)


func test_recovered_from_backup_is_logged_and_does_not_block_boot() -> void:
	var primary_path := TEST_SAVE_DIR.path_join("profile.json")
	var backup_path := TEST_SAVE_DIR.path_join("profile.json.bak")
	var seeded_service := SaveService.new()
	var first_profile := SaveModel.fresh()
	first_profile["lifetime_wumpa"] = 17
	var second_profile := SaveModel.fresh()
	second_profile["lifetime_wumpa"] = 31
	assert_eq(
		seeded_service.store_profile(TEST_SAVE_DIR, first_profile),
		OK
	)
	assert_eq(
		seeded_service.store_profile(TEST_SAVE_DIR, second_profile),
		OK
	)
	assert_true(FileAccess.file_exists(backup_path))
	_write_text(primary_path, "{broken primary")

	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	assert_push_error("recovered from backup")
	assert_eq(
		root.get("boot_error"),
		OK,
		"a backup recovery must not block boot, unlike a future-version refusal"
	)
	assert_eq(root.call("state_name"), &"warp_room")
	assert_eq(
		root.get("profile"),
		first_profile,
		"the older, still-valid backup must be what boot actually loads"
	)


func test_wr4_completion_routes_phase_unlock_to_hub_ui_and_player() -> void:
	var profile := SaveModel.fresh()
	var future_level_id := &"wr4_future_fixture"
	var record := SaveModel.level_record(profile, future_level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(future_level_id)] = record
	var service := SaveService.new()
	assert_eq(
		service.store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var player := root.get_node("Content/WarpRoom1/Player")
	assert_true(
		_has_property(player, &"_phase_enabled"),
		"the hub player must expose the progression gate"
	)
	if not _has_property(player, &"_phase_enabled"):
		return

	assert_true(player.get("_phase_enabled"))
	var touch := root.get_node(
		"Content/WarpRoom1/UI/TouchControls"
	)
	assert_true(
		(touch.call("current_layout") as Dictionary).has(
			"phase_center"
		)
	)


func test_fresh_profile_keeps_phase_locked_in_authored_level() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	assert_not_null(level, "the known level id must load the authored scene")
	if level == null:
		return
	var player := level.get_node("Player")
	assert_false(player.get("_phase_enabled"))
	var touch := level.get_node("UI/TouchControls")
	assert_false(
		(touch.call("current_layout") as Dictionary).has(
			"phase_center"
		)
	)


func test_wr4_unlock_reaches_real_level_portal_player_and_touch() -> void:
	var profile := SaveModel.fresh()
	var future_level_id := &"wr4_future_fixture"
	var record := SaveModel.level_record(profile, future_level_id)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(future_level_id)] = record
	assert_eq(
		SaveService.new().store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var portal := _portal_for_level(
		room,
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return

	portal.emit_signal(&"body_entered", room.get_node("Player"))
	var level := await _wait_for_authored_level(root)
	assert_not_null(level, "the real hub portal must load the authored scene")
	if level == null:
		return
	var touch := level.get_node("UI/TouchControls")
	var layout := touch.call("current_layout") as Dictionary
	assert_true(
		layout.has("phase_center"),
		"the unlocked level must render a real PHASE touch target"
	)
	if not layout.has("phase_center"):
		return
	var phase_state := get_node("/root/PhaseState")
	var before: StringName = phase_state.call("active_set")
	var press := InputEventScreenTouch.new()
	press.index = 29
	press.position = layout["phase_center"]
	press.pressed = true
	touch.call("handle_touch_event", press)

	await wait_physics_frames(1)

	var release := InputEventScreenTouch.new()
	release.index = press.index
	release.position = press.position
	release.pressed = false
	touch.call("handle_touch_event", release)
	assert_ne(
		phase_state.call("active_set"),
		before,
		"the real level player must consume the routed PHASE intent"
	)


func test_main_scene_owns_live_tuning_fingerprint_contract() -> void:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		assert_true(false, "Phase 1 main scene must exist")
		return
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	var service: Variant = root.get("tuning_service")
	var debug_ui := root.get_node("UI/TuningDebug")
	var summary: String = debug_ui.call("summary_text")
	assert_not_null(service)
	assert_not_null(service.get("catalog"))
	assert_string_contains(summary, service.call("fingerprint"))
	assert_string_contains(summary, "res://data/tuning/gameplay.tres")


func test_main_boot_reads_only_the_injected_tuning_override() -> void:
	var authoring_service := TuningService.new()
	assert_eq(
		authoring_service.load_from_paths(
			BASE_TUNING_PATH,
			TEST_OVERRIDE_PATH
		),
		OK
	)
	assert_false(authoring_service.catalog.input.left_handed_layout)
	authoring_service.catalog.input.left_handed_layout = true
	assert_eq(
		authoring_service.save_override(TEST_OVERRIDE_PATH),
		OK
	)

	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	var path_is_injectable := _has_property(
		root,
		&"tuning_override_path"
	)
	if path_is_injectable:
		root.set("tuning_override_path", TEST_OVERRIDE_PATH)
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	assert_true(
		path_is_injectable,
		"the real main scene must expose its tuning override input"
	)
	var boot_service := root.get("tuning_service") as TuningService
	assert_true(boot_service.override_active)
	assert_true(boot_service.catalog.input.left_handed_layout)
	assert_has(
		boot_service.get_loaded_resource_paths(),
		TEST_OVERRIDE_PATH
	)


func test_real_level_entry_reports_level_meta_to_live_tuning_hud() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var portal := _portal_for_level(
		room,
		&"wr1_n_sanity_beach"
	)
	assert_not_null(portal)
	if portal == null:
		return

	portal.emit_signal(&"body_entered", room.get_node("Player"))
	var level := await _wait_for_authored_level(root)
	assert_not_null(level, "the real hub portal must load the authored scene")
	if level == null:
		return
	var meta := load(N_SANITY_META_PATH) as LevelMeta
	var summary: String = root.get_node(
		"UI/TuningDebug"
	).call("summary_text")

	assert_string_contains(summary, N_SANITY_META_PATH)
	assert_string_contains(
		summary,
		String(meta.fingerprint()).left(12)
	)


func test_real_level_list_opens_toybox_with_one_tuning_owner() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)
	var overlay := root.get_node("UI/LevelListOverlay")
	assert_true(
		overlay.visible,
		"the shipped warp-room button must open the real level list"
	)
	var toybox_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Toybox"
	) as Button
	assert_true(
		toybox_button.visible,
		"debug builds must expose the toybox through the real list"
	)

	toybox_button.pressed.emit()
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"level")
	var toybox := root.get_node_or_null("Content/Game")
	assert_not_null(
		toybox,
		"the real toybox request must instantiate its shipped scene"
	)
	if toybox == null:
		return
	var root_debug := root.get_node("UI/TuningDebug") as TuningDebugUI
	var toybox_debug := toybox.get_node(
		"UI/TuningDebug"
	) as TuningDebugUI
	var visible_tuning_drawers := 0
	for candidate: Node in root.find_children(
		"*",
		"TuningDebugUI",
		true,
		false
	):
		if (candidate as Control).visible:
			visible_tuning_drawers += 1
	assert_eq(
		visible_tuning_drawers,
		1,
		"the nested toybox must not create a second live drawer"
	)
	assert_true(root_debug.visible)
	assert_false(toybox_debug.visible)
	assert_same(
		toybox.get("tuning_service"),
		root.get("tuning_service"),
		"the root drawer and toybox must share one tuning owner"
	)
	var camera := toybox.get_node("CameraRig/Camera3D") as Camera3D
	assert_eq(
		root_debug.call(
			"set_live_value",
			&"camera",
			&"field_of_view_degrees",
			71.0
		),
		OK
	)
	await wait_process_frames(1)
	assert_eq(
		camera.fov,
		71.0,
		"the sole root drawer must refresh the embedded toybox"
	)
	var hud := root.get_node("UI/HUD")
	assert_true(hud.visible)
	assert_false(
		hud.get_node("SafeArea/Stats").visible,
		"toybox entry must not show false CRATES 0 / 0 run stats"
	)
	assert_true(
		hud.get_node("SafeArea/Pause").visible,
		"the toybox must retain its touch-reachable escape route"
	)


func test_real_level_list_opens_racing_time_trial_prototype() -> void:
	# Task 7 (CTR racing mode, R1): the "Racing (prototype)" entry mirrors
	# the toybox/look-dev debug-entry pattern above end to end -- same
	# real-button click, same real GameRoot dispatch, same escape-route
	# expectation via the retained platformer Pause button (see the toybox
	# test's own "must retain its touch-reachable escape route" assertion).
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)
	var overlay := root.get_node("UI/LevelListOverlay")
	var racing_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingTimeTrial"
	) as Button
	assert_true(
		racing_button.visible,
		"debug builds must expose the racing prototype through the real list"
	)

	racing_button.pressed.emit()
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"level")
	var race := root.get_node_or_null("Content/RaceTimeTrial")
	assert_not_null(
		race,
		"the real racing request must instantiate the real race scene"
	)
	if race == null:
		return
	assert_false(bool(race.call("is_finished")))
	assert_eq(int(race.call("gate_count")), 6)

	var hud := root.get_node("UI/HUD")
	assert_true(hud.visible)
	assert_false(
		hud.get_node("SafeArea/Stats").visible,
		"racing entry must not show false platformer CRATES/WUMPA run stats"
	)
	assert_true(
		hud.get_node("SafeArea/Pause").visible,
		"the racing prototype must retain its touch-reachable escape route"
	)


func test_racing_retry_reinstantiates_and_reconfigures_a_fresh_race_scene() -> void:
	# H1 fix round (Task 7 review): RaceHUD's RETRY button used to call
	# get_tree().change_scene_to_file() directly, which freed GameRoot (this
	# very root node) out from under itself -- the fresh race scene that
	# replaced it never got configure() called by anyone. RaceSession now
	# only emits retry_requested; GameRoot is the one that reloads it, via
	# the same _select_level() round-trip its working Pause -> Retry path
	# already uses. Drives that real GameRoot handler end to end (not just
	# the session's own signal in isolation -- see test_race_session.gd's
	# test_request_retry_emits_the_retry_requested_signal for that half) and
	# proves the NEW instance actually got configured: non-null kart tuning,
	# same shape test_real_level_list_opens_toybox_with_one_tuning_owner
	# above uses to prove its own embedded scene got wired up for real.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)
	var overlay := root.get_node("UI/LevelListOverlay")
	var racing_button := overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/RacingTimeTrial"
	) as Button
	racing_button.pressed.emit()
	await wait_process_frames(1)

	var race_before := root.get_node_or_null("Content/RaceTimeTrial")
	assert_not_null(race_before, "sanity: the racing entry must already be open")
	if race_before == null:
		return
	var kart_before := race_before.get_node_or_null("Kart")
	assert_not_null(kart_before)
	if kart_before == null:
		return
	assert_not_null(
		kart_before.get("_tuning"),
		"sanity: the first race instance must already be configured"
	)
	var race_before_id := race_before.get_instance_id()

	race_before.call("request_retry")
	await wait_process_frames(1)

	assert_eq(
		root.call("state_name"),
		&"level",
		"retry must land back in the racing state, not drop to the hub"
	)
	var race_after := root.get_node_or_null("Content/RaceTimeTrial")
	assert_not_null(
		race_after,
		"retry must re-render a real race scene, not leave Content empty"
	)
	if race_after == null:
		return
	assert_ne(
		race_after.get_instance_id(),
		race_before_id,
		"retry must reinstantiate the race scene, not reuse the old one"
	)
	var kart_after := race_after.get_node_or_null("Kart")
	assert_not_null(kart_after)
	if kart_after == null:
		return
	assert_not_null(
		kart_after.get("_tuning"),
		"the new session instance must have been configure()d for real"
	)
	assert_true(
		bool(kart_after.call("is_run_active")),
		"a fresh/retried kart must start active, not frozen"
	)
	assert_false(bool(race_after.call("is_finished")))


func test_hub_level_list_actually_pauses_warp_room_gameplay() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var player := room.get_node("Player")
	var router := room.get_node("Input/InputRouter")
	var gamepad := room.get_node("Input/GamepadInput")
	var touch := room.get_node("UI/TouchControls")
	assert_true(
		player.can_process(),
		"sanity: the hub Player must process before the modal opens"
	)
	assert_true(
		touch.can_process(),
		"sanity: hub touch controls must process before the modal opens"
	)

	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)

	assert_true(
		get_tree().paused,
		"opening the hub level list must actually pause the tree"
	)
	assert_false(
		player.can_process(),
		"the hub Player must stop processing under the level list modal"
	)
	assert_false(
		router.can_process(),
		"the hub InputRouter must stop processing under the modal"
	)
	assert_false(
		gamepad.can_process(),
		"the hub GamepadInput must stop processing under the modal"
	)
	assert_false(
		touch.can_process(),
		"the hub TouchControls must stop processing under the modal"
	)


func test_application_pause_while_idling_in_the_hub_pauses_gameplay() -> void:
	# R3: _pause_and_snapshot_active_run() only ever dispatched EVENT_PAUSE
	# when flow.state == LEVEL. Backgrounding the app while simply standing
	# in the hub (no Level List modal open, flow.state == WARP_ROOM) hit the
	# `WARP_ROOM != PAUSED` branch and returned without ever pausing the
	# tree -- defeating I15's WarpRoom.process_mode = PROCESS_MODE_PAUSABLE
	# guard for the single most common real-device trigger.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call("state_name"),
		&"warp_room",
		"sanity: must be idling in the hub before this test's premise holds"
	)
	var room := root.get_node("Content/WarpRoom1")
	var player := room.get_node("Player")
	var router := room.get_node("Input/InputRouter")
	var gamepad := room.get_node("Input/GamepadInput")
	var touch := room.get_node("UI/TouchControls")
	assert_true(
		player.can_process(),
		"sanity: the hub Player must process before the app is backgrounded"
	)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)

	assert_eq(
		root.call("state_name"),
		&"paused",
		"backgrounding the app while idling in the hub must pause the FSM"
	)
	assert_true(
		get_tree().paused,
		"backgrounding the app while idling in the hub must pause the tree"
	)
	assert_false(
		player.can_process(),
		"the hub Player must stop processing when the app is backgrounded"
	)
	assert_false(
		router.can_process(),
		"the hub InputRouter must stop processing when the app is backgrounded"
	)
	assert_false(
		gamepad.can_process(),
		"the hub GamepadInput must stop processing when the app is backgrounded"
	)
	assert_false(
		touch.can_process(),
		"the hub TouchControls must stop processing when the app is backgrounded"
	)


func test_hub_touch_exclusions_include_the_level_list_overlay() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var room := root.get_node("Content/WarpRoom1")
	var level_list_button := room.get_node("UI/LevelList") as Button
	level_list_button.pressed.emit()
	await wait_process_frames(1)

	var overlay := root.get_node("UI/LevelListOverlay") as Control
	assert_true(
		overlay.visible,
		"sanity: the real level list overlay must be open"
	)

	var touch := room.get_node("UI/TouchControls")
	var layout: Dictionary = touch.call("current_layout")
	var stick_region: Rect2 = layout["stick_region"]
	var press := InputEventScreenTouch.new()
	press.index = 41
	press.position = stick_region.get_center()
	press.pressed = true
	touch.call("handle_touch_event", press)

	assert_eq(
		touch.call("stick_touch_index"),
		-1,
		(
			"a tap aimed at the full-screen level list overlay must not "
			+ "also register as hub movement input underneath it"
		)
	)


func test_project_boots_the_new_main_scene() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"),
		MAIN_SCENE_PATH
	)


func test_boot_consumes_valid_session_into_the_authored_level() -> void:
	var snapshot := _normal_snapshot()
	snapshot["timestamp_unix_s"] = Time.get_unix_time_from_system()
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(snapshot)
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	var flow: Variant = root.get("flow")
	assert_eq(root.call("state_name"), &"level")
	var level := await _wait_for_authored_level(root)
	if level == null:
		return
	assert_eq(level.run_state.broken_crate_ids, [1])
	assert_eq(level.run_state.wumpa_run, 1)
	assert_eq(
		level.run_state.authored_crate_ids.size(),
		level.run_state.meta.crate_count,
		"the live scene catalog must override stale snapshot crate ids"
	)
	assert_true(flow.get("resume_snapshot").is_empty())


func test_corrupt_session_is_discarded_while_profile_still_loads() -> void:
	var profile := SaveModel.fresh()
	profile["lifetime_wumpa"] = 17
	var profile_service := SaveService.new()
	assert_eq(
		profile_service.store_profile(TEST_SAVE_DIR, profile),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		"{broken session"
	)
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"warp_room")
	assert_eq(root.get("profile").get("lifetime_wumpa"), 17)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_application_pause_auto_pauses_and_snapshots_active_run() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call("set_active_level_session", session)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)

	assert_eq(root.call("state_name"), &"paused")
	var stored: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_true(stored is Dictionary)
	if stored is Dictionary:
		assert_eq(stored.get("crates_broken"), [1.0])


func test_wm_close_request_auto_pauses_and_snapshots_active_run() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call("set_active_level_session", session)

	# Android/desktop window managers deliver a close request (task-kill,
	# window X button) as NOTIFICATION_WM_CLOSE_REQUEST, not
	# NOTIFICATION_APPLICATION_PAUSED — the run must be saved either way.
	root.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	assert_eq(root.call("state_name"), &"paused")
	var stored: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)
	assert_true(stored is Dictionary)
	if stored is Dictionary:
		assert_eq(stored.get("crates_broken"), [1.0])


func test_app_pause_persists_the_in_memory_profile() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	# Simulate progress that only lives in the in-memory profile so far
	# (01-DESIGN.md §4.4 names app-pause as its own independent
	# profile-write trigger, not contingent on a level having just ended).
	var modified_profile: Dictionary = (
		root.get("profile").duplicate(true)
	)
	modified_profile["lifetime_wumpa"] = 4242
	root.set("profile", modified_profile)

	root.notification(NOTIFICATION_APPLICATION_PAUSED)

	var stored: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			TEST_SAVE_DIR.path_join("profile.json")
		)
	)
	assert_true(
		stored is Dictionary,
		"app-pause must write profile.json even if no level has ended yet"
	)
	if stored is Dictionary:
		assert_eq(
			int(stored.get("lifetime_wumpa", -1)),
			4242,
			"app-pause must persist the current in-memory profile, not a stale one"
		)


func test_level_completion_deletes_session_snapshot() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(_normal_snapshot())
	)

	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_quit_to_hub_deletes_session_snapshot() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	_write_text(
		TEST_SAVE_DIR.path_join("session.json"),
		JSON.stringify(_normal_snapshot())
	)

	assert_eq(
		root.call("dispatch", {"type": &"quit_level"}),
		OK
	)
	assert_false(
		FileAccess.file_exists(
			TEST_SAVE_DIR.path_join("session.json")
		)
	)


func test_task11_ui_is_owned_by_main_and_starts_out_of_the_way() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	assert_true(root.has_node("UI/HUD"))
	assert_true(root.has_node("UI/ResultsScreen"))
	assert_true(root.has_node("UI/PauseOverlay"))
	assert_true(root.has_node("UI/LevelListOverlay"))
	if not root.has_node("UI/HUD"):
		return
	for screen_name: String in [
		"HUD",
		"ResultsScreen",
		"PauseOverlay",
		"LevelListOverlay",
	]:
		assert_true(
			root.has_node("UI/%s/SafeArea" % screen_name),
			"%s must map required UI into the device safe area"
			% screen_name
		)
	assert_false(root.get_node("UI/HUD").visible)
	assert_false(root.get_node("UI/ResultsScreen").visible)
	assert_false(root.get_node("UI/PauseOverlay").visible)
	assert_false(root.get_node("UI/LevelListOverlay").visible)


func test_level_completion_builds_persists_and_presents_results() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.get_node("Content/LevelPlaceholder").add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 2
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call(
		"set_active_level_session",
		session,
		meta,
		{
			1: &"Beach Start",
			2: &"Finish",
		}
	)

	session.complete_level()

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(payload.get("box_count"), 1)
	assert_eq(payload.get("crate_count"), 2)
	assert_eq(payload.get("missed_crate_ids"), [2])
	assert_eq(
		payload.get("missed_crate_ids_by_segment"),
		{"Finish": [2]}
	)
	assert_eq(root.get("last_save_error"), OK)
	var saved_record := SaveModel.level_record(
		root.get("profile"),
		meta.level_id
	)
	assert_true(saved_record.get("completed"))
	assert_eq(saved_record.get("last_missed_crate_ids"), [2])
	assert_true(root.get_node("UI/ResultsScreen").visible)
	assert_true(root.has_node("Content/ResultsPlaceholder"))


func test_results_screen_renders_the_real_completion_payload() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.get_node("Content/LevelPlaceholder").add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	# Author real relic pars from real economy values so relic-entry
	# unlock is exercised by something other than its own false default.
	meta.relic_platinum_s = catalog.economy.time_crate_small_s
	meta.relic_gold_s = (
		meta.relic_platinum_s
		+ catalog.economy.time_crate_medium_s
	)
	meta.relic_sapphire_s = (
		meta.relic_gold_s
		+ catalog.economy.time_crate_large_s
	)
	session.configure(meta, &"normal", catalog.economy)
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call(
		"set_active_level_session",
		session,
		meta,
		{1: &"Beach Start"}
	)

	session.complete_level()

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	# The only authored crate was broken: a real clean sweep.
	assert_eq(payload.get("box_count"), 1)
	assert_eq(payload.get("crate_count"), 1)
	assert_true(
		payload.get("gem"),
		"breaking every authored crate must award the real gem"
	)
	assert_true(payload.get("flawless"))
	assert_eq(
		payload.get("wumpa_banked"),
		catalog.economy.wumpa_per_standard_crate
	)
	assert_true(payload.get("relic_entry_available"))

	var results := root.get_node("UI/ResultsScreen")
	assert_true(results.visible)
	var summary := results.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Summary"
	) as Label
	var misses := results.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Misses"
	) as Label
	var relic_trial := results.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Actions/RelicTrial"
	) as Button
	assert_eq(
		summary.text,
		(
			"CRATES  %d / %d\nGEM  %s\nFLAWLESS  %s\nWUMPA BANKED  %d"
			% [
				int(payload.get("box_count")),
				int(payload.get("crate_count")),
				"YES" if bool(payload.get("gem")) else "NO",
				"YES" if bool(payload.get("flawless")) else "NO",
				int(payload.get("wumpa_banked")),
			]
		),
		(
			"the rendered summary must reflect the real completion "
			+ "payload, not a synthetic one supplied by the test"
		)
	)
	assert_eq(
		misses.text,
		"MISSED CRATES  NONE",
		"a real clean sweep must render no missed crates"
	)
	assert_eq(
		relic_trial.visible,
		bool(payload.get("relic_entry_available")),
		"the relic-trial button must mirror the real payload's unlock state"
	)


func test_results_screen_renders_missed_crates_without_array_syntax() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var session := LevelSession.new()
	root.get_node("Content/LevelPlaceholder").add_child(session)
	var finish := Area3D.new()
	finish.name = "Finish"
	session.add_child(finish)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 3
	var catalog := load(
		"res://data/tuning/gameplay.tres"
	).duplicate_deep(
		Resource.DEEP_DUPLICATE_ALL
	) as GameplayTuning
	session.configure(meta, &"normal", catalog.economy)
	# Break only crate 1; crates 2 and 3 are left missing, so this is a
	# real, non-perfect completion -- I10's own test only ever exercised
	# the empty "MISSED CRATES  NONE" case.
	session.run_state.record_crate_broken(
		1,
		catalog.economy.wumpa_per_standard_crate
	)
	root.call(
		"set_active_level_session",
		session,
		meta,
		{2: &"Beach Landing", 3: &"Beach Landing"}
	)

	session.complete_level()

	assert_eq(root.call("state_name"), &"results")
	var payload: Dictionary = root.get("last_results_payload")
	assert_eq(
		payload.get("missed_crate_ids_by_segment"),
		{"Beach Landing": [2, 3]},
		"sanity: the real run must leave exactly crates 2 and 3 missing"
	)

	var misses := root.get_node(
		"UI/ResultsScreen/SafeArea/Center/Panel/Margin/Rows/Misses"
	) as Label
	assert_eq(
		misses.text,
		"MISSED CRATES\nBeach Landing: 2, 3",
		(
			"a real non-perfect completion must render readable crate "
			+ "ids, not raw GDScript array syntax like '[2, 3]'"
		)
	)


func test_failed_completion_save_keeps_snapshot_and_withholds_award() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	root.notification(NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(root.call("state_name"), &"paused")
	var snapshot_path := TEST_SAVE_DIR.path_join("session.json")
	assert_true(FileAccess.file_exists(snapshot_path))
	assert_eq(
		root.call("dispatch", {"type": &"resume"}),
		OK
	)
	var profile_before: Dictionary = root.get("profile").duplicate(true)
	root.set("save_service", FailingSaveService.new())
	var results := root.get_node("UI/ResultsScreen") as Control
	assert_false(results.visible)

	var finish := level.get_node("Finish") as Area3D
	var finish_shape := (
		finish.get_node("CollisionShape3D").shape as BoxShape3D
	)
	# H10 (turns-camera-difficulty Task 8): the real Finish gate now sits
	# past a 90° corner with a +90° yaw of its own (see
	# scenes/levels/wr1_n_sanity_beach.tscn) -- "outside, on the approach
	# side" is whatever the gate's own local +Z axis points at in world
	# space now, and "forward progress" is measured along the level's
	# real camera rail (which is built from the same markers the runtime
	# camera uses, so it already bends through the corner) instead of a
	# single frozen world axis.
	var approach_axis := Vector3(
		finish.global_transform.basis.z.x,
		0.0,
		finish.global_transform.basis.z.z
	).normalized()
	var approach_target := (
		finish.global_position
		+ approach_axis * (finish_shape.size.z * 0.5 + 1.0)
	)
	player.global_position = Vector3(
		approach_target.x,
		player.global_position.y,
		approach_target.z
	)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await wait_physics_frames(1)
	assert_false(
		finish.overlaps_body(player),
		"the failed-save scenario must begin outside the real exit"
	)
	var rail := level.get_node("CameraRig/Rail") as Path3D
	var start_offset := rail.curve.get_closest_offset(
		rail.to_local(player.global_position)
	)
	var router := level.get_node(
		"Input/InputRouter"
	) as InputRouter
	router.push_intent(
		InputIntent.move(
			Vector2(0.0, -1.0),
			0.0,
			InputIntent.SOURCE_KEYBOARD
		)
	)
	var walked_forward := false
	for _physics_index: int in range(120):
		if root.get("last_save_error") != OK:
			break
		if is_instance_valid(player):
			var current_offset := rail.curve.get_closest_offset(
				rail.to_local(player.global_position)
			)
			walked_forward = (
				walked_forward
				or current_offset > start_offset
			)
		await wait_physics_frames(1)

	assert_push_error("Level results were not saved")
	assert_true(
		walked_forward,
		"the real controller must walk into the real Finish area"
	)
	assert_eq(root.get("last_save_error"), ERR_CANT_CREATE)
	assert_eq(root.call("state_name"), &"level")
	assert_true(FileAccess.file_exists(snapshot_path))
	assert_eq(root.get("profile"), profile_before)
	assert_true(root.get("last_results_payload").is_empty())
	assert_false(
		results.visible,
		"an uncommitted award must not be presented as saved"
	)
	assert_same(root.get("active_level_session"), level)
	root.queue_free()
	await wait_process_frames(2)


func test_results_relic_entry_stays_locked_then_retries_in_relic_mode() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	root.set("_active_level_meta", meta)
	var profile: Dictionary = root.get("profile")
	var record := SaveModel.level_record(
		profile,
		meta.level_id
	)
	record["completed"] = true
	var levels: Dictionary = profile["levels"]
	levels[String(meta.level_id)] = record
	root.set("profile", profile)
	var results := root.get_node("UI/ResultsScreen")

	results.emit_signal(&"relic_requested")

	assert_eq(root.call("state_name"), &"results")
	assert_eq(
		root.get("flow").get("active_level_mode"),
		LevelRunState.MODE_NORMAL
	)

	var economy := (
		load("res://data/tuning/gameplay.tres")
		as GameplayTuning
	).economy
	meta.relic_platinum_s = economy.time_crate_small_s
	meta.relic_gold_s = (
		meta.relic_platinum_s
		+ economy.time_crate_medium_s
	)
	meta.relic_sapphire_s = (
		meta.relic_gold_s
		+ economy.time_crate_large_s
	)
	results.emit_signal(&"relic_requested")

	assert_eq(root.call("state_name"), &"level")
	assert_eq(
		root.get("flow").get("active_level_mode"),
		LevelRunState.MODE_RELIC
	)


func test_pause_overlay_preserves_level_content_and_retry_is_direct() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var level_content := root.get_node("Content/LevelPlaceholder")

	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	assert_same(
		root.get_node("Content/LevelPlaceholder"),
		level_content
	)
	assert_true(root.get_node("UI/PauseOverlay").visible)
	assert_eq(
		root.call("dispatch", {"type": &"resume"}),
		OK
	)
	assert_same(
		root.get_node("Content/LevelPlaceholder"),
		level_content
	)

	assert_eq(
		root.call("dispatch", {"type": &"level_complete"}),
		OK
	)
	root.get_node("UI/ResultsScreen").emit_signal(
		"retry_requested"
	)
	assert_eq(root.call("state_name"), &"level")
	assert_eq(
		root.get("flow").get("active_level_id"),
		PLACEHOLDER_LEVEL_ID
	)


func test_hud_pause_button_reaches_the_real_pause_overlay() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	var pause_button := root.get_node_or_null(
		"UI/HUD/SafeArea/Pause"
	) as Button
	assert_not_null(
		pause_button,
		"the live HUD must expose a touch-reachable pause button"
	)
	if pause_button == null:
		return
	assert_true(pause_button.visible)
	assert_false(root.get_node("UI/PauseOverlay").visible)
	await wait_process_frames(1)
	var touch_position := pause_button.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 21
	press.position = touch_position
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.index = press.index
	release.position = touch_position
	release.pressed = false

	var hud := root.get_node("UI/HUD")
	hud.call("_input", press)
	hud.call("_input", release)
	await wait_process_frames(1)

	assert_eq(root.call("state_name"), &"paused")
	assert_true(root.get_node("UI/PauseOverlay").visible)
	assert_true(get_tree().paused)


func test_pause_overlay_resume_button_returns_to_the_same_level() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")
	watch_signals(overlay)

	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Resume"
	).emit_signal(&"pressed")

	assert_signal_emitted(overlay, &"resume_requested")
	assert_eq(root.call("state_name"), &"level")
	assert_false(get_tree().paused)
	assert_same(
		root.get_node_or_null("Content/NSanityBeach"),
		level,
		"resume must return to the same in-progress level, not reload it"
	)


func test_pause_overlay_retry_button_restarts_the_active_level_fresh() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var first_crate := _crate(level, 1)
	assert_not_null(first_crate, "the real level must author crate 1")
	if first_crate == null:
		return
	var player := level.get_node("Player") as CharacterBody3D
	player.get_node("SpinArea").emit_signal(
		&"body_entered",
		first_crate
	)
	await wait_process_frames(1)
	assert_true(
		level.run_state.broken_crate_ids.size() > 0,
		"the retry proof needs a real crate broken before retrying"
	)

	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")
	watch_signals(overlay)

	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Retry"
	).emit_signal(&"pressed")

	assert_signal_emitted(overlay, &"retry_requested")
	var fresh_level := await _wait_for_authored_level(root)
	assert_eq(root.call("state_name"), &"level")
	assert_not_null(fresh_level)
	if fresh_level == null:
		return
	assert_not_same(
		fresh_level,
		level,
		"retry must throw away the in-progress level, not resume it"
	)
	assert_eq(
		fresh_level.run_state.broken_crate_ids,
		[],
		"a real retry must not carry over the previous run's broken crates"
	)


func test_pause_overlay_retry_does_not_strand_the_player_at_the_hub() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")

	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Retry"
	).emit_signal(&"pressed")
	await _wait_for_authored_level(root)

	assert_eq(
		root.call("state_name"),
		&"level",
		(
			"retry must land back in a playable level, "
			+ "not strand the player at the hub"
		)
	)
	assert_false(
		root.has_node("Content/WarpRoom1"),
		"the hub must not be the terminal content after a retry"
	)
	assert_true(
		root.get_node("UI/HUD").visible,
		"the level HUD, not the hub, must be what the player sees after retry"
	)
	assert_false(root.get_node("UI/LevelListOverlay").visible)
	assert_false(root.get_node("UI/PauseOverlay").visible)


func test_pause_overlay_retry_does_not_round_trip_a_hub_instantiate() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	var count_after_boot := int(
		root.call("warp_room_instantiate_count")
	)
	assert_eq(
		count_after_boot,
		1,
		"boot's own first hub visit is the only expected instantiate so far"
	)

	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")
	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Retry"
	).emit_signal(&"pressed")
	await _wait_for_authored_level(root)

	assert_eq(
		int(root.call("warp_room_instantiate_count")),
		count_after_boot,
		(
			"retry-from-pause must not instantiate a full hub scene just "
			+ "to immediately discard it"
		)
	)


func test_pause_overlay_level_list_button_opens_the_level_list() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": PLACEHOLDER_LEVEL_ID,
			}
		),
		OK
	)
	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")
	watch_signals(overlay)

	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/LevelList"
	).emit_signal(&"pressed")

	assert_signal_emitted(overlay, &"level_list_requested")
	assert_eq(root.call("state_name"), &"paused")
	assert_true(root.get_node("UI/LevelListOverlay").visible)
	assert_false(
		overlay.visible,
		"opening the level list from pause must hide the pause overlay"
	)


func test_pause_overlay_quit_button_returns_to_the_hub() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var level := await _enter_authored_level(root)
	if level == null:
		return
	assert_eq(
		root.call("dispatch", {"type": &"pause"}),
		OK
	)
	var overlay := root.get_node("UI/PauseOverlay")
	watch_signals(overlay)

	overlay.get_node(
		"SafeArea/Center/Panel/Margin/Rows/Quit"
	).emit_signal(&"pressed")

	assert_signal_emitted(overlay, &"quit_requested")
	assert_eq(root.call("state_name"), &"warp_room")
	assert_false(get_tree().paused)


func test_level_touch_exclusions_include_the_mercy_panel() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var mercy_panel := root.get_node_or_null(
		"UI/HUD/SafeArea/MercyPanel"
	)
	assert_not_null(
		mercy_panel,
		"the live HUD must expose the mercy panel"
	)
	if mercy_panel == null:
		return
	var exclusions: Array = root.call("_level_touch_exclusions")
	assert_true(
		exclusions.has(mercy_panel),
		(
			"a visible mercy panel drawn over the touch controls "
			+ "must be excluded from gameplay touch, the same way "
			+ "the pause button already is (§5.2 occlusion rule)"
		)
	)


func test_main_scene_gates_the_perf_readout_on_debug_tools() -> void:
	# Authored hidden, switched on by should_enable_debug_tools(). A release
	# build never flips it, so a hardcoded visible=true fails the first
	# assertion and a missing GameRoot wire fails the second.
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var root := packed.instantiate()
	var authored := root.get_node_or_null("UI/PerfReadoutArea/PerfReadout") as Control
	assert_not_null(
		authored,
		"main.tscn must carry the perf readout in its debug branch"
	)
	if authored == null:
		root.free()
		return
	assert_false(
		authored.visible,
		"the readout must be authored hidden so release builds never show it"
	)

	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	await wait_process_frames(1)

	assert_eq(
		authored.visible,
		root.call("should_enable_debug_tools", OS.is_debug_build()),
		"GameRoot must gate the readout on the same debug switch"
	)
	assert_false(
		root.call("should_enable_debug_tools", false),
		"and that switch must be off for a release build"
	)


func test_game_root_actually_drives_the_viewport_render_scale() -> void:
	# E1-01: the readout reported SCALE, but nothing in production ever moved
	# it, so it read 1.00 forever and the render-scale half of Gate F
	# criterion 2 could not fail. This is the anti-dead-wire test for the
	# driver: feed the real production method a sustained slow frame and the
	# real viewport must actually change.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var viewport := root.get_viewport()
	assert_not_null(viewport)
	if viewport == null:
		return
	var entry_scale := viewport.scaling_3d_scale
	viewport.scaling_3d_scale = 1.0

	var elapsed_s := 0.0
	while elapsed_s < DynamicResolutionType.ADJUST_INTERVAL_S:
		# Drive _process itself, not the helper: a driver that exists but is
		# never called from the frame callback is exactly what E1-01 was.
		root.call("_process", SLOW_FRAME_S)
		elapsed_s += SLOW_FRAME_S

	var loaded_scale := viewport.scaling_3d_scale
	assert_lt(
		loaded_scale,
		1.0,
		"sustained load must actually lower the viewport render scale"
	)

	# And it must climb back, or a single hitch would cost image quality for
	# the rest of the session.
	elapsed_s = 0.0
	while elapsed_s < DynamicResolutionType.ADJUST_INTERVAL_S:
		root.call("_process", FAST_FRAME_S)
		elapsed_s += FAST_FRAME_S

	assert_gt(
		viewport.scaling_3d_scale,
		loaded_scale,
		"headroom must give the resolution back"
	)

	viewport.scaling_3d_scale = entry_scale


func test_the_perf_readout_stays_inside_the_display_safe_area() -> void:
	# E1-03: authored as a direct UI child, the readout was anchored to the
	# full 1920-wide canvas. On a landscape phone with a right-side cutout or
	# rounded inset, that hides exactly the numbers the device gate needs.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var area := root.get_node_or_null("UI/PerfReadoutArea") as Control
	assert_not_null(
		area,
		"the readout needs the PhaseOneSafeArea inset every other overlay has"
	)
	if area == null:
		return
	var readout := root.get_node_or_null(
		"UI/PerfReadoutArea/PerfReadout"
	) as Control
	assert_not_null(readout)
	if readout == null:
		return

	var cutout_safe_rect := Rect2(100.0, 40.0, 1720.0, 1000.0)
	area.call("set_layout_override", cutout_safe_rect)
	area.call("_apply_safe_area")
	await wait_process_frames(1)

	assert_true(
		cutout_safe_rect.encloses(readout.get_global_rect()),
		(
			"the readout must sit inside the safe rect; got "
			+ str(readout.get_global_rect())
			+ " against "
			+ str(cutout_safe_rect)
		)
	)


func test_level_touch_exclusions_include_the_perf_readout() -> void:
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var readout := root.get_node_or_null("UI/PerfReadoutArea/PerfReadout") as Control
	assert_not_null(readout)
	if readout == null:
		return
	assert_true(
		readout.visible,
		"debug tools must be enabled in this test environment"
	)
	var exclusions: Array = root.call("_level_touch_exclusions")
	assert_true(
		exclusions.has(readout),
		(
			"a perf readout drawn over the touch controls must be "
			+ "excluded from gameplay touch, or it steals thumb input "
			+ "during the 20-minute soak it exists to support "
			+ "(§5.2 occlusion rule)"
		)
	)


func _instantiate_main() -> Node:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	add_child_autofree(root)
	return root


func _instantiate_main_with_base_tuning_path(path: String) -> Node:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	root.set("save_dir", TEST_SAVE_DIR)
	root.set("base_tuning_path", path)
	add_child_autofree(root)
	return root


func _enter_authored_level(root: Node) -> LevelSession:
	assert_eq(
		root.call(
			"dispatch",
			{
				"type": &"portal_enter",
				"level_id": &"wr1_n_sanity_beach",
			}
		),
		OK
	)
	return await _wait_for_authored_level(root)


func _portal_for_level(
	room: Node,
	level_id: StringName
) -> Area3D:
	for candidate: Node in room.find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if (
			candidate.is_in_group(&"warp_portal")
			and StringName(
				candidate.get_meta("level_id", &"")
			) == level_id
		):
			return candidate as Area3D
	return null


func _wait_for_authored_level(root: Node) -> LevelSession:
	for _poll_index: int in range(120):
		var level := root.get_node_or_null(
			"Content/NSanityBeach"
		) as LevelSession
		if level != null:
			return level
		await wait_process_frames(1)
	assert_true(false, "the authored level must finish threaded loading")
	return null


func _crate(level: Node, crate_id: int) -> Node:
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			candidate.has_method("apply_verb")
			and candidate.has_signal(&"broken")
			and int(candidate.get("crate_id")) == crate_id
		):
			return candidate
	return null


func _normal_snapshot() -> Dictionary:
	var meta := load(
		"res://data/tuning/levels/n_sanity_beach.tres"
	).duplicate(true) as LevelMeta
	meta.crate_count = 1
	var state := LevelRunState.new()
	state.start(meta, &"normal")
	state.record_crate_broken(1, 1)
	return state.snapshot()


func _write_text(path: String, text: String) -> void:
	assert_eq(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(path.get_base_dir())
		),
		OK
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


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


func test_completing_the_boss_level_records_the_defeat() -> void:
	# game_root.gd's own note said boss_defeated.papu_papu had no production
	# writer repo-wide, correctly so while Phase 1 shipped no boss. It ships
	# one now, so beating him must survive the save.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)
	var meta := load(
		"res://data/tuning/levels/papu_papu.tres"
	) as LevelMeta
	assert_not_null(meta)
	if meta == null:
		return
	root.set("_active_level_meta", meta)
	var profile: Dictionary = root.get("profile")
	assert_false(
		bool(
			(profile.get("boss_defeated", {}) as Dictionary).get(
				"papu_papu", false
			)
		),
		"precondition: the boss starts undefeated"
	)

	root.call("_on_level_session_completed", {
		"completed": true,
		"crates_broken": 0,
		"wumpa": 0,
		"deaths": 0,
		"flawless": true,
		"elapsed_s": 1.0,
	})

	# This drives the completion handler directly from the hub state, so the
	# FSM correctly refuses the level->results transition. That refusal is this
	# test's own setup artifact, not the behaviour under test, which is the
	# profile write above it.
	assert_push_error("Could not show level results")
	var saved: Dictionary = root.get("profile")
	assert_true(
		bool(
			(saved.get("boss_defeated", {}) as Dictionary).get(
				"papu_papu", false
			)
		),
		"defeating Papu must be written to the profile"
	)


func test_boot_installs_a_configured_audio_service() -> void:
	# Not another unwired component: the service reports its silence once at
	# boot, which only happens if GameRoot actually built and configured it.
	var root := _instantiate_main()
	if root == null:
		return
	await wait_process_frames(1)

	var audio := root.get_node_or_null("Audio") as AudioService

	assert_not_null(audio, "boot must install the audio service")
	if audio == null:
		return
	assert_false(
		audio.boot_report().is_empty(),
		"a configured service reports its slot state once at boot"
	)
	assert_false(
		audio.has_clip(AudioService.SLOT_CRATE_POP),
		"H10 has not happened: every slot is still legitimately silent"
	)
