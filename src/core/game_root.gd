class_name GameRoot
extends Node

const TuningServiceType := preload("res://src/tuning/tuning_service.gd")
const GameFlowType := preload("res://src/core/game_flow.gd")
const SaveServiceType := preload("res://src/core/save_service.gd")
const UnlockRulesType := preload(
	"res://src/gameplay/progression/unlock_rules.gd"
)
const SessionSnapshotType := preload(
	"res://src/core/session_snapshot.gd"
)
const ResultsModelType := preload(
	"res://src/gameplay/run/results_model.gd"
)
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const RESULTS_SCREEN_SCENE := preload(
	"res://scenes/ui/results_screen.tscn"
)
const PAUSE_OVERLAY_SCENE := preload(
	"res://scenes/ui/pause_overlay.tscn"
)
const LEVEL_LIST_OVERLAY_SCENE := preload(
	"res://scenes/ui/level_list_overlay.tscn"
)
const TOYBOX_SCENE := preload("res://scenes/game.tscn")
const WARP_ROOM_SCENE := preload(
	"res://scenes/levels/warp_room_1.tscn"
)
const N_SANITY_BEACH_META := preload(
	"res://data/tuning/levels/n_sanity_beach.tres"
)
const PHASE_GHOST_SHADER := preload(
	"res://assets/shaders/phase_ghost.gdshader"
)

const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const OVERRIDE_TUNING_PATH := "user://tuning/override.tres"
const DEFAULT_SAVE_DIR := "user://save"
const DEBUG_TOYBOX_LEVEL_ID := &"debug_traversal_toybox"
const N_SANITY_BEACH_LEVEL_ID := &"wr1_n_sanity_beach"
const N_SANITY_BEACH_SCENE_PATH := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)
const _LEVEL_SCENE_PATHS: Dictionary = {
	N_SANITY_BEACH_LEVEL_ID: N_SANITY_BEACH_SCENE_PATH,
}
const _PLACEHOLDER_NAMES: Dictionary = {
	GameFlow.State.WARP_ROOM: &"WarpRoomPlaceholder",
	GameFlow.State.LEVEL: &"LevelPlaceholder",
	GameFlow.State.RESULTS: &"ResultsPlaceholder",
}

@export var save_dir: String = DEFAULT_SAVE_DIR

var tuning_service: TuningServiceType = TuningServiceType.new()
var save_service: SaveServiceType = SaveServiceType.new()
var session_snapshot: SessionSnapshotType = SessionSnapshotType.new()
var results_model: ResultsModelType = ResultsModelType.new()
var flow: GameFlowType = GameFlowType.new()
var profile: Dictionary = {}
var boot_error: Error = OK
var last_snapshot_error: Error = OK
var last_save_error: Error = OK
var last_results_payload: Dictionary = {}
var active_level_session: Node

@onready var _content: Node = $Content
@onready var _ui: CanvasLayer = $UI
@onready var _tuning_debug: TuningDebugUI = $UI/TuningDebug

var _active_level_meta: LevelMeta
var _segment_by_crate_id: Dictionary = {}
var _hud: Control
var _results_screen: Control
var _pause_overlay: Control
var _level_list_overlay: Control
var _level_list_open: bool = false
var _owns_tree_pause: bool = false
var _threaded_level_path: String = ""
var _threaded_level_id: StringName = &""
var _threaded_poll_count: int = 0


static func should_enable_debug_tools(is_debug_build: bool) -> bool:
	return is_debug_build


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_use_accumulated_input(false)
	boot_error = tuning_service.load_from_paths(
		BASE_TUNING_PATH,
		OVERRIDE_TUNING_PATH
	)
	if boot_error != OK:
		push_error("Phase 1 tuning failed to load: " + error_string(boot_error))
		return

	PhaseState.configure(tuning_service.catalog.phase)
	var debug_tools_enabled := should_enable_debug_tools(OS.is_debug_build())
	_tuning_debug.visible = debug_tools_enabled
	if debug_tools_enabled:
		_tuning_debug.configure(tuning_service, OVERRIDE_TUNING_PATH)
		_tuning_debug.tuning_changed.connect(_on_tuning_changed)
	_install_task11_ui(debug_tools_enabled)

	profile = save_service.load_profile(save_dir)
	if save_service.refused_future_version:
		boot_error = ERR_UNAVAILABLE
		push_error("Save data was written by a newer version of Crash Remix.")
		return
	if not SaveModel.validate(profile):
		boot_error = ERR_INVALID_DATA
		push_error("Phase 1 profile failed validation.")
		return

	boot_error = dispatch({"type": GameFlow.EVENT_SAVE_LOADED})
	if boot_error != OK:
		return
	var saved_session := session_snapshot.load(save_dir)
	if not saved_session.is_empty():
		boot_error = dispatch({
			"type": GameFlow.EVENT_SESSION_RESUME_AVAILABLE,
			"snapshot": saved_session,
		})


func _exit_tree() -> void:
	if _owns_tree_pause and get_tree() != null:
		get_tree().paused = false
	_owns_tree_pause = false


func _process(_delta_s: float) -> void:
	_poll_threaded_level_load()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_WM_CLOSE_REQUEST
	):
		_pause_and_snapshot_active_run()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_PAUSE})
	elif flow.state == GameFlow.State.WARP_ROOM:
		_on_warp_room_level_list_requested()
	elif flow.state == GameFlow.State.PAUSED:
		if _level_list_open:
			_on_level_list_closed()
		else:
			dispatch({"type": GameFlow.EVENT_RESUME})
	else:
		return
	get_viewport().set_input_as_handled()


func dispatch(event: Dictionary) -> Error:
	var previous_state := flow.state
	var transition_error := flow.dispatch(event)
	if transition_error != OK:
		return transition_error
	if flow.state != previous_state:
		_sync_tree_pause()
		_render_state(previous_state)
	var event_type := StringName(event.get("type", &""))
	if event_type in [
		GameFlow.EVENT_LEVEL_COMPLETE,
		GameFlow.EVENT_QUIT_LEVEL,
		GameFlow.EVENT_RESULTS_TO_HUB,
	]:
		_clear_session_snapshot()
	return OK


func state_name() -> StringName:
	return flow.state_name()


func set_active_level_session(
	session: Node,
	meta: LevelMeta = null,
	segment_by_crate_id: Dictionary = {}
) -> void:
	_disconnect_active_level_session()
	active_level_session = session
	_active_level_meta = meta
	_segment_by_crate_id = segment_by_crate_id.duplicate(true)
	if active_level_session == null:
		return
	if _active_level_meta == null:
		var run_state := (
			active_level_session.get("run_state")
			as LevelRunState
		)
		if run_state != null:
			_active_level_meta = run_state.meta
	if active_level_session.has_signal(&"run_completed"):
		active_level_session.connect(
			&"run_completed",
			_on_level_session_completed
		)
	if active_level_session.has_signal(&"run_exited"):
		active_level_session.connect(
			&"run_exited",
			_on_level_session_exited
		)
	if _hud != null:
		_hud.call(
			"configure",
			active_level_session,
			_active_level_meta
		)
	if _active_level_meta != null:
		_tuning_debug.report_level_meta(_active_level_meta)


func _on_tuning_changed(_fingerprint: String) -> void:
	PhaseState.configure(tuning_service.catalog.phase)
	_refresh_warp_room_tuning()
	_refresh_active_level_tuning()


func _pause_and_snapshot_active_run() -> void:
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_PAUSE})
	elif flow.state != GameFlow.State.PAUSED:
		return
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
	):
		return
	var run_state: Variant = active_level_session.get("run_state")
	if run_state == null or not run_state.has_method("snapshot"):
		return
	var saved: Dictionary = run_state.call("snapshot")
	if saved.is_empty():
		return
	if saved.get("mode") == LevelRunState.MODE_RELIC:
		saved["relic_void"] = true
	last_snapshot_error = session_snapshot.store(save_dir, saved)


func _clear_session_snapshot() -> void:
	last_snapshot_error = session_snapshot.delete(save_dir)
	_disconnect_active_level_session()
	active_level_session = null


func _on_level_session_completed(results: Dictionary) -> void:
	var meta := _active_level_meta
	if meta == null and active_level_session != null:
		var run_state := (
			active_level_session.get("run_state")
			as LevelRunState
		)
		if run_state != null:
			meta = run_state.meta
	if meta == null:
		last_save_error = ERR_INVALID_DATA
		push_error("Cannot build results without LevelMeta.")
		return

	var previous_record := SaveModel.level_record(
		profile,
		meta.level_id
	)
	var payload := results_model.build(
		results,
		meta,
		_segment_by_crate_id,
		previous_record
	)
	if payload.is_empty():
		last_save_error = ERR_INVALID_DATA
		push_error("Level results payload failed validation.")
		return
	last_results_payload = payload.duplicate(true)
	if _results_screen != null:
		_results_screen.call("present", last_results_payload)

	var updated_profile := results_model.persisted_profile(
		profile,
		last_results_payload
	)
	if updated_profile.is_empty():
		last_save_error = ERR_INVALID_DATA
	else:
		last_save_error = save_service.store_profile(
			save_dir,
			updated_profile
		)
		if last_save_error == OK:
			profile = updated_profile
	if last_save_error != OK:
		push_error(
			"Level results were not saved: "
			+ error_string(last_save_error)
		)

	var transition_error := dispatch({
		"type": GameFlow.EVENT_LEVEL_COMPLETE,
	})
	if transition_error != OK:
		push_error(
			"Could not show level results: "
			+ error_string(transition_error)
		)


func _on_level_session_exited() -> void:
	if flow.state == GameFlow.State.PAUSED:
		dispatch({"type": GameFlow.EVENT_RESUME})
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_QUIT_LEVEL})
	else:
		_clear_session_snapshot()


func _disconnect_active_level_session() -> void:
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
	):
		return
	var completed_callback := Callable(
		self,
		"_on_level_session_completed"
	)
	if (
		active_level_session.has_signal(&"run_completed")
		and active_level_session.is_connected(
			&"run_completed",
			completed_callback
		)
	):
		active_level_session.disconnect(
			&"run_completed",
			completed_callback
		)
	var exited_callback := Callable(self, "_on_level_session_exited")
	if (
		active_level_session.has_signal(&"run_exited")
		and active_level_session.is_connected(
			&"run_exited",
			exited_callback
		)
	):
		active_level_session.disconnect(
			&"run_exited",
			exited_callback
		)


func _install_task11_ui(debug_tools_enabled: bool) -> void:
	_hud = HUD_SCENE.instantiate() as Control
	_results_screen = RESULTS_SCREEN_SCENE.instantiate() as Control
	_pause_overlay = PAUSE_OVERLAY_SCENE.instantiate() as Control
	_level_list_overlay = (
		LEVEL_LIST_OVERLAY_SCENE.instantiate() as Control
	)
	for screen: Control in [
		_hud,
		_results_screen,
		_pause_overlay,
		_level_list_overlay,
	]:
		_ui.add_child(screen)

	_hud.connect(
		&"pause_requested",
		_on_hud_pause_requested
	)
	_results_screen.connect(
		&"retry_requested",
		_on_results_retry_requested
	)
	_results_screen.connect(
		&"relic_requested",
		_on_results_relic_requested
	)
	_results_screen.connect(
		&"hub_requested",
		_on_results_hub_requested
	)
	_pause_overlay.connect(
		&"resume_requested",
		_on_pause_resume_requested
	)
	_pause_overlay.connect(
		&"retry_requested",
		_on_pause_retry_requested
	)
	_pause_overlay.connect(
		&"level_list_requested",
		_on_pause_level_list_requested
	)
	_pause_overlay.connect(
		&"quit_requested",
		_on_pause_quit_requested
	)
	_level_list_overlay.connect(
		&"level_requested",
		_on_level_requested
	)
	_level_list_overlay.connect(
		&"toybox_requested",
		_on_toybox_requested
	)
	_level_list_overlay.connect(
		&"closed",
		_on_level_list_closed
	)
	_level_list_overlay.call(
		"configure",
		debug_tools_enabled
	)
	_sync_ui_visibility()
	_tuning_debug.move_to_front()


func _sync_tree_pause() -> void:
	if get_tree() == null:
		return
	if flow.state == GameFlow.State.PAUSED:
		get_tree().paused = true
		_owns_tree_pause = true
	elif _owns_tree_pause:
		get_tree().paused = false
		_owns_tree_pause = false


func _render_state(previous_state: int = flow.state) -> void:
	if flow.state == GameFlow.State.PAUSED:
		_level_list_open = false
		_sync_ui_visibility()
		return
	if previous_state == GameFlow.State.PAUSED:
		_level_list_open = false
		_sync_ui_visibility()
		return

	_level_list_open = false
	_sync_ui_visibility()
	_cancel_pending_level_load()
	_clear_content()

	if not _PLACEHOLDER_NAMES.has(flow.state):
		return
	if flow.state == GameFlow.State.WARP_ROOM:
		_render_warp_room()
		return
	if (
		flow.state == GameFlow.State.LEVEL
		and flow.active_level_id == DEBUG_TOYBOX_LEVEL_ID
	):
		_content.add_child(TOYBOX_SCENE.instantiate())
		return
	if (
		flow.state == GameFlow.State.LEVEL
		and _LEVEL_SCENE_PATHS.has(flow.active_level_id)
	):
		_begin_threaded_level_load(flow.active_level_id)
		return
	_show_state_placeholder()


func threaded_level_path() -> String:
	return _threaded_level_path


func threaded_level_poll_count() -> int:
	return _threaded_poll_count


func _render_warp_room() -> void:
	var room := WARP_ROOM_SCENE.instantiate()
	_content.add_child(room)
	room.call(
		"configure",
		profile,
		tuning_service.catalog,
		_hub_level_metas(),
		_phase_available(),
		_available_level_ids()
	)
	room.connect(
		&"flow_event_requested",
		_on_warp_room_flow_event
	)
	room.connect(
		&"level_list_requested",
		_on_warp_room_level_list_requested
	)


func _refresh_warp_room_tuning() -> void:
	if flow.state != GameFlow.State.WARP_ROOM:
		return
	var room := _content.get_node_or_null("WarpRoom1")
	if room == null:
		return
	room.call(
		"configure",
		profile,
		tuning_service.catalog,
		_hub_level_metas(),
		_phase_available(),
		_available_level_ids()
	)


func _hub_level_metas() -> Dictionary:
	return {
		N_SANITY_BEACH_LEVEL_ID: N_SANITY_BEACH_META,
	}


func _available_level_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for level_id: Variant in _LEVEL_SCENE_PATHS:
		result.append(StringName(level_id))
	return result


func _phase_available() -> bool:
	return UnlockRulesType.phase_unlocked(profile)


func _begin_threaded_level_load(level_id: StringName) -> void:
	var path := String(_LEVEL_SCENE_PATHS.get(level_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		_show_state_placeholder()
		return
	_threaded_level_path = path
	_threaded_level_id = level_id
	_threaded_poll_count = 0
	var request_error := ResourceLoader.load_threaded_request(
		path,
		"",
		true
	)
	if request_error != OK:
		var existing_status := (
			ResourceLoader.load_threaded_get_status(path)
		)
		if existing_status not in [
			ResourceLoader.THREAD_LOAD_IN_PROGRESS,
			ResourceLoader.THREAD_LOAD_LOADED,
		]:
			_cancel_pending_level_load()
			_show_state_placeholder()
			push_error(
				"Could not request level load: "
				+ error_string(request_error)
			)
			return
	var loading := Node3D.new()
	loading.name = &"LevelLoading"
	_content.add_child(loading)


func _poll_threaded_level_load() -> void:
	if _threaded_level_path.is_empty():
		return
	if flow.state == GameFlow.State.PAUSED:
		return
	if (
		flow.state != GameFlow.State.LEVEL
		or flow.active_level_id != _threaded_level_id
	):
		_cancel_pending_level_load()
		return
	_threaded_poll_count += 1
	var status := ResourceLoader.load_threaded_get_status(
		_threaded_level_path
	)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_cancel_pending_level_load()
		_clear_content()
		_show_state_placeholder()
		push_error("Threaded level load failed.")
		return
	var loaded_id := _threaded_level_id
	var loaded_resource := ResourceLoader.load_threaded_get(
		_threaded_level_path
	) as PackedScene
	_cancel_pending_level_load()
	_clear_content()
	if loaded_resource == null:
		_show_state_placeholder()
		push_error("Threaded level resource was not a PackedScene.")
		return
	var level := loaded_resource.instantiate()
	_content.add_child(level)
	var meta := _level_meta(loaded_id)
	if meta == null:
		_clear_content()
		_show_state_placeholder()
		push_error("Authored level has no LevelMeta.")
		return
	_configure_authored_level(level, meta)


func _cancel_pending_level_load() -> void:
	_threaded_level_path = ""
	_threaded_level_id = &""


func _level_meta(level_id: StringName) -> LevelMeta:
	if level_id == N_SANITY_BEACH_LEVEL_ID:
		return N_SANITY_BEACH_META
	return null


func _show_state_placeholder() -> void:
	var placeholder := Node3D.new()
	placeholder.name = _PLACEHOLDER_NAMES.get(
		flow.state,
		&"StatePlaceholder"
	)
	_content.add_child(placeholder)


func _configure_authored_level(
	level: Node,
	meta: LevelMeta
) -> void:
	var catalog := tuning_service.catalog
	var router := level.get_node("Input/InputRouter")
	var gamepad := level.get_node("Input/GamepadInput")
	var touch := level.get_node("UI/TouchControls")
	var player := level.get_node("Player") as CharacterBody3D
	var camera_rig := level.get_node("CameraRig")
	router.call("configure", catalog.input)
	gamepad.call("configure", router, catalog.input)
	touch.call(
		"configure",
		router,
		catalog.input,
		_phase_available()
	)
	touch.call(
		"set_touch_exclusion_controls",
		_level_touch_exclusions()
	)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		_phase_available()
	)
	var phase_reset_callback := Callable(
		PhaseState,
		"reset_to_authored_set"
	)
	if not player.is_connected(
		&"respawned",
		phase_reset_callback
	):
		player.connect(&"respawned", phase_reset_callback)
	PhaseState.reset_to_authored_set()
	player.call("set_spawn_transform", player.global_transform)
	_refresh_level_traversal(level, catalog)
	player.get_node("BlobShadow").call(
		"configure",
		player,
		catalog.depth
	)
	player.get_node("LandingRing").call(
		"configure",
		player,
		catalog.move,
		catalog.depth,
		catalog.grind,
		_level_traversal_rails(level)
	)
	camera_rig.call(
		"configure",
		player,
		camera_rig.get_node("Rail"),
		camera_rig.get_node("Camera3D"),
		catalog.camera,
		_level_camera_regions(level),
		router
	)
	var session := level as LevelSession
	session.configure(
		meta,
		flow.active_level_mode,
		catalog.economy,
		player,
		catalog.move,
		catalog.input
	)
	var segment_map := _crate_segment_map(level)
	_apply_replay_ghost_markers(
		level,
		results_model.ghost_marker_ids(
			profile,
			meta.level_id
		)
	)
	set_active_level_session(
		session,
		meta,
		segment_map
	)


func _refresh_active_level_tuning() -> void:
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
		or not active_level_session is LevelSession
	):
		return
	var level := active_level_session
	var catalog := tuning_service.catalog
	var router := level.get_node_or_null("Input/InputRouter")
	var gamepad := level.get_node_or_null("Input/GamepadInput")
	var touch := level.get_node_or_null("UI/TouchControls")
	var player := (
		level.get_node_or_null("Player") as CharacterBody3D
	)
	var camera_rig := level.get_node_or_null("CameraRig")
	if router != null:
		router.call("configure", catalog.input)
	if gamepad != null and router != null:
		gamepad.call("configure", router, catalog.input)
	if touch != null and router != null:
		touch.call(
			"configure",
			router,
			catalog.input,
			_phase_available()
		)
	if player != null and router != null:
		player.call(
			"configure",
			catalog.move,
			catalog.input,
			catalog.depth,
			catalog.wall_run,
			catalog.grind,
			catalog.swing,
			router.get("buffer"),
			catalog.economy,
			_phase_available()
		)
		_refresh_level_traversal(level, catalog)
		player.get_node("BlobShadow").call(
			"configure",
			player,
			catalog.depth
		)
		player.get_node("LandingRing").call(
			"configure",
			player,
			catalog.move,
			catalog.depth,
			catalog.grind,
			_level_traversal_rails(level)
		)
	if camera_rig != null:
		camera_rig.call("refresh_tuning", catalog.camera)
	active_level_session.call(
		"refresh_tuning",
		catalog.economy,
		catalog.move,
		catalog.input
	)
	_refresh_ghost_materials(level)


func _refresh_level_traversal(
	level: Node,
	catalog: GameplayTuning
) -> void:
	for candidate: Node in get_tree().get_nodes_in_group(
		&"traversal_rail"
	):
		if level.is_ancestor_of(candidate):
			candidate.call(
				"refresh_tuning",
				catalog.camera
			)
	for candidate: Node in get_tree().get_nodes_in_group(
		&"swing_anchor"
	):
		if level.is_ancestor_of(candidate):
			candidate.call(
				"refresh_tuning",
				catalog.swing
			)


func _level_traversal_rails(level: Node) -> Array:
	var result: Array = []
	for candidate: Node in get_tree().get_nodes_in_group(
		&"traversal_rail"
	):
		if (
			level.is_ancestor_of(candidate)
			and candidate.has_method("samples")
		):
			result.append(candidate)
	return result


func _level_camera_regions(level: Node) -> Array:
	var result: Array = []
	for candidate: Node in level.find_children(
		"*",
		"Area3D",
		true,
		false
	):
		if candidate is CameraRegion:
			result.append(candidate)
	return result


func _crate_segment_map(level: Node) -> Dictionary:
	var result: Dictionary = {}
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if not candidate.has_method("apply_verb"):
			continue
		var crate_type := StringName(
			candidate.get("crate_type")
		)
		if crate_type in [&"iron", &"time"]:
			continue
		result[int(candidate.get("crate_id"))] = (
			StringName(candidate.get("segment_group"))
		)
	return result


func _apply_replay_ghost_markers(
	level: Node,
	missed_crate_ids: Array[int]
) -> void:
	if missed_crate_ids.is_empty():
		return
	var material := ShaderMaterial.new()
	material.shader = PHASE_GHOST_SHADER
	material.set_shader_parameter(
		&"ghost_opacity",
		tuning_service.catalog.phase.ghost_opacity
	)
	material.set_shader_parameter(
		&"ghost_outline_width_m",
		tuning_service.catalog.phase.ghost_outline_width_m
	)
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			not candidate.has_method("apply_verb")
			or int(candidate.get("crate_id"))
			not in missed_crate_ids
		):
			continue
		var source := (
			candidate.get_node_or_null("Mesh")
			as MeshInstance3D
		)
		if source == null:
			continue
		var ghost := MeshInstance3D.new()
		ghost.name = &"GhostMarker"
		ghost.transform = source.transform
		ghost.mesh = source.mesh
		ghost.material_override = material
		ghost.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		candidate.add_child(ghost)
		candidate.connect(
			&"broken",
			_on_ghost_crate_broken.bind(ghost)
		)


func _on_ghost_crate_broken(
	_crate_id: int,
	_wumpa: int,
	ghost: MeshInstance3D
) -> void:
	if is_instance_valid(ghost):
		ghost.visible = false


func _refresh_ghost_materials(level: Node) -> void:
	for candidate: Node in level.find_children(
		"GhostMarker",
		"MeshInstance3D",
		true,
		false
	):
		var ghost := candidate as MeshInstance3D
		var material := ghost.material_override as ShaderMaterial
		if material == null:
			continue
		material.set_shader_parameter(
			&"ghost_opacity",
			tuning_service.catalog.phase.ghost_opacity
		)
		material.set_shader_parameter(
			&"ghost_outline_width_m",
			tuning_service.catalog.phase.ghost_outline_width_m
		)


func _level_touch_exclusions() -> Array:
	var controls: Array = [
		_hud.get_node("SafeArea/Pause"),
		_results_screen,
		_pause_overlay,
		_level_list_overlay,
	]
	if _tuning_debug.visible:
		controls.append(_tuning_debug.get_node("HUD"))
		controls.append(_tuning_debug.get_node("Drawer"))
	return controls


func _sync_ui_visibility() -> void:
	if (
		_hud == null
		or _results_screen == null
		or _pause_overlay == null
		or _level_list_overlay == null
	):
		return
	if flow.state != GameFlow.State.PAUSED:
		_hud.visible = flow.state == GameFlow.State.LEVEL
		_results_screen.visible = (
			flow.state == GameFlow.State.RESULTS
		)
	_pause_overlay.visible = (
		flow.state == GameFlow.State.PAUSED
		and not _level_list_open
	)
	_level_list_overlay.visible = (
		flow.state == GameFlow.State.PAUSED
		and _level_list_open
	)


func _clear_content() -> void:
	for child: Node in _content.get_children():
		if child.is_queued_for_deletion():
			continue
		child.name = "_RetiredContent_%d" % child.get_instance_id()
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.queue_free()


func _on_results_retry_requested() -> void:
	dispatch({"type": GameFlow.EVENT_RETRY_LEVEL})


func _on_results_relic_requested() -> void:
	if (
		_active_level_meta == null
		or not results_model.relic_entry_available(
			_active_level_meta,
			SaveModel.level_record(
				profile,
				_active_level_meta.level_id
			)
		)
	):
		return
	dispatch({
		"type": GameFlow.EVENT_RETRY_LEVEL,
		"mode": LevelRunState.MODE_RELIC,
	})


func _on_results_hub_requested() -> void:
	dispatch({"type": GameFlow.EVENT_RESULTS_TO_HUB})


func _on_hud_pause_requested() -> void:
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_PAUSE})


func _on_pause_resume_requested() -> void:
	dispatch({"type": GameFlow.EVENT_RESUME})


func _on_pause_retry_requested() -> void:
	_select_level(
		flow.active_level_id,
		flow.active_level_mode
	)


func _on_pause_level_list_requested() -> void:
	_level_list_open = true
	_sync_ui_visibility()


func _on_pause_quit_requested() -> void:
	if flow.state == GameFlow.State.PAUSED:
		dispatch({"type": GameFlow.EVENT_RESUME})
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_QUIT_LEVEL})


func _on_level_requested(level_id: StringName) -> void:
	_select_level(level_id)


func _on_toybox_requested() -> void:
	if OS.is_debug_build():
		_select_level(DEBUG_TOYBOX_LEVEL_ID)


func _on_level_list_closed() -> void:
	_level_list_open = false
	if (
		flow.state == GameFlow.State.PAUSED
		and flow.active_level_id.is_empty()
	):
		dispatch({"type": GameFlow.EVENT_RESUME})
	_sync_ui_visibility()


func _on_warp_room_flow_event(event: Dictionary) -> void:
	if flow.state != GameFlow.State.WARP_ROOM:
		return
	_select_level(
		StringName(event.get("level_id", &"")),
		StringName(
			event.get("mode", LevelRunState.MODE_NORMAL)
		)
	)


func _on_warp_room_level_list_requested() -> void:
	if flow.state != GameFlow.State.WARP_ROOM:
		return
	if dispatch({"type": GameFlow.EVENT_PAUSE}) != OK:
		return
	_level_list_open = true
	_sync_ui_visibility()


func _select_level(
	level_id: StringName,
	mode: StringName = LevelRunState.MODE_NORMAL
) -> void:
	if level_id.is_empty():
		return
	if flow.state == GameFlow.State.PAUSED:
		dispatch({"type": GameFlow.EVENT_RESUME})
	if flow.state == GameFlow.State.LEVEL:
		dispatch({"type": GameFlow.EVENT_QUIT_LEVEL})
	if flow.state != GameFlow.State.WARP_ROOM:
		return
	dispatch({
		"type": GameFlow.EVENT_PORTAL_ENTER,
		"level_id": level_id,
		"mode": mode,
	})
