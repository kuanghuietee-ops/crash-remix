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
const MonotonicClockType := preload(
	"res://src/core/monotonic_clock.gd"
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
const BOOT_ERROR_OVERLAY_SCENE := preload(
	"res://scenes/ui/boot_error_overlay.tscn"
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
# §7.1's hub->level budget is <3s, operator-observed on device, not
# suite-assertable. This is a much larger, purely defensive backstop: a
# real load that is still THREAD_LOAD_IN_PROGRESS this long is not "slow",
# it has failed, and must not leave the player on an unbounded black
# screen with no way out.
const LEVEL_LOAD_TIMEOUT_S := 20.0

@export var save_dir: String = DEFAULT_SAVE_DIR
@export_file("*.tres") var tuning_override_path: String = ""
@export_file("*.tres") var base_tuning_path: String = BASE_TUNING_PATH

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
var _boot_error_overlay: Control
var _level_list_open: bool = false
var _owns_tree_pause: bool = false
var _threaded_level_path: String = ""
var _threaded_level_id: StringName = &""
var _threaded_poll_count: int = 0
var _threaded_load_elapsed_s: float = 0.0
var _threaded_load_status_override: Variant = null
var _loading_overlay: Label
var _warp_room_instantiate_count: int = 0
var _suppress_next_warp_room_render: bool = false


static func should_enable_debug_tools(is_debug_build: bool) -> bool:
	return is_debug_build


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_use_accumulated_input(false)
	# R5: install the boot-error overlay before anything that can refuse to
	# boot runs, so every refusal path -- including ones that fire before
	# tuning even loads -- has somewhere to show the player real text
	# instead of an invisible push_error and a black screen.
	_boot_error_overlay = (
		BOOT_ERROR_OVERLAY_SCENE.instantiate() as Control
	)
	_ui.add_child(_boot_error_overlay)

	var override_path := _resolved_tuning_override_path()
	boot_error = tuning_service.load_from_paths(
		base_tuning_path,
		override_path
	)
	if boot_error != OK:
		_boot_error_overlay.call(
			"present",
			(
				"Crash Remix could not load its core game data and "
				+ "cannot start.\nPlease reinstall the app."
			)
		)
		push_error("Phase 1 tuning failed to load: " + error_string(boot_error))
		return

	PhaseState.configure(tuning_service.catalog.phase)
	var debug_tools_enabled := should_enable_debug_tools(OS.is_debug_build())
	_tuning_debug.visible = debug_tools_enabled
	if debug_tools_enabled:
		_tuning_debug.configure(tuning_service, override_path)
		_tuning_debug.tuning_changed.connect(_on_tuning_changed)
	_install_task11_ui(debug_tools_enabled)

	profile = save_service.load_profile(save_dir)
	if save_service.recovered_from_backup:
		# Non-fatal, unlike refused_future_version below: the backup is
		# by definition the last known-good write, so boot continues
		# normally. This is a log-only consumer, deliberately not a
		# blocking player-facing overlay (the primary/backup rollback
		# already recovered real, valid progress; there is nothing for
		# the player to act on), so an operator debugging a device
		# report can see a rollback happened instead of it being
		# silently invisible.
		push_error(
			"Profile was recovered from backup after the primary "
			+ "save file failed to load."
		)
	if save_service.refused_future_version:
		boot_error = ERR_UNAVAILABLE
		_boot_error_overlay.call(
			"present",
			(
				"This save was written by a newer version of "
				+ "Crash Remix.\nYour save was not changed. "
				+ "Install the newer version to continue."
			)
		)
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
		var saved_level_id := StringName(
			saved_session.get("level_id", &"")
		)
		if (
			_LEVEL_SCENE_PATHS.has(saved_level_id)
			and _level_meta(saved_level_id) != null
		):
			boot_error = dispatch({
				"type": GameFlow.EVENT_SESSION_RESUME_AVAILABLE,
				"snapshot": saved_session,
			})
		else:
			last_snapshot_error = session_snapshot.delete(save_dir)


func _resolved_tuning_override_path() -> String:
	if not tuning_override_path.is_empty():
		return tuning_override_path
	return "user://tuning/override.tres"


func _exit_tree() -> void:
	if _owns_tree_pause and get_tree() != null:
		get_tree().paused = false
	_owns_tree_pause = false


func _process(delta_s: float) -> void:
	_poll_threaded_level_load(delta_s)


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_WM_CLOSE_REQUEST
	):
		# 01-DESIGN.md §4.4: app-pause is its own profile-write trigger,
		# independent of the session snapshot below (that covers the
		# active run's checkpoint state; this covers whatever the
		# in-memory profile already holds, in case the OS kills the app
		# before another trigger gets a chance to persist it).
		last_save_error = save_service.store_profile(save_dir, profile)
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
		_sync_active_level_timer_pause(previous_state)
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


func _sync_active_level_timer_pause(previous_state: int) -> void:
	if (
		active_level_session == null
		or not is_instance_valid(active_level_session)
		or not active_level_session.has_method(
			"set_gameplay_timers_paused"
		)
	):
		return
	var timers_paused: Variant = null
	if (
		previous_state == GameFlow.State.LEVEL
		and flow.state == GameFlow.State.PAUSED
	):
		timers_paused = true
	elif (
		previous_state == GameFlow.State.PAUSED
		and flow.state == GameFlow.State.LEVEL
	):
		timers_paused = false
	if timers_paused == null:
		return
	active_level_session.call(
		"set_gameplay_timers_paused",
		bool(timers_paused),
		MonotonicClockType.now_s()
	)


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
			_active_level_meta,
			tuning_service.catalog.economy
		)
	if _active_level_meta != null:
		_tuning_debug.report_level_meta(_active_level_meta)


func _on_tuning_changed(_fingerprint: String) -> void:
	PhaseState.configure(tuning_service.catalog.phase)
	_refresh_warp_room_tuning()
	_refresh_active_level_tuning()


func _pause_and_snapshot_active_run() -> void:
	# R3: LEVEL and WARP_ROOM are the only two states with real,
	# PROCESS_MODE_PAUSABLE-gated gameplay content underneath them
	# (LevelSession / WarpRoom respectively) that must actually stop
	# simulating when the OS backgrounds the app. Gating this on LEVEL
	# alone left the hub's own pausable content running for as long as
	# Godot keeps ticking frames in the background -- the commonest
	# real-device trigger of exactly the condition I15 was written to
	# prevent for the Level List modal.
	if (
		flow.state == GameFlow.State.LEVEL
		or flow.state == GameFlow.State.WARP_ROOM
	):
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


# 01-DESIGN.md §4.4 names four profile-write triggers: level end,
# gem/relic/flawless award, boss defeat, app-pause. This call site
# covers three of the four (app-pause has its own call site in
# _notification()):
#   - level end: LevelSession.complete_level() is the one place a run
#     can end (reached both by a normal Finish-area completion and by a
#     mercy skip that completes the level, see
#     LevelSession.accept_mercy_skip()); both emit run_completed, which
#     is the only signal this function is connected to.
#   - gem / relic / flawless award: never independently knowable before
#     the run itself ends, so results_model.build()/persisted_profile()
#     compute and persist them in the same call, for both MODE_NORMAL
#     and MODE_RELIC.
#   - boss defeat: genuinely NOT wired anywhere yet.
#     `boss_defeated.papu_papu` has no production writer repo-wide —
#     correctly so, since Phase 1 ships no boss level to defeat. Wiring
#     this belongs with whichever task first builds boss content
#     (Task 17 / Wave B), not here.
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

	var updated_profile := results_model.persisted_profile(
		profile,
		payload,
		meta
	)
	if updated_profile.is_empty():
		last_save_error = ERR_INVALID_DATA
		push_error("Level results could not update the profile.")
		return
	last_save_error = save_service.store_profile(
		save_dir,
		updated_profile
	)
	if last_save_error != OK:
		push_error(
			"Level results were not saved: "
			+ error_string(last_save_error)
		)
		return

	profile = updated_profile
	last_results_payload = payload.duplicate(true)
	if _results_screen != null:
		_results_screen.call("present", last_results_payload)

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
	# R5: _boot_error_overlay is instantiated and added to the tree earlier,
	# in _ready(), before tuning even loads -- it must not be re-instantiated
	# or re-added here (add_child on an already-parented node is an error).
	# It still needs its SafeArea configured now, once tuning is available,
	# same as every other screen below.
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
		var safe_area := screen.get_node_or_null("SafeArea")
		if safe_area != null:
			safe_area.call("configure", tuning_service.catalog.input)
	var boot_error_safe_area := _boot_error_overlay.get_node_or_null(
		"SafeArea"
	)
	if boot_error_safe_area != null:
		boot_error_safe_area.call("configure", tuning_service.catalog.input)

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
	_loading_overlay = Label.new()
	_loading_overlay.name = &"LoadingOverlay"
	_loading_overlay.text = "LOADING..."
	_loading_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.visible = false
	_ui.add_child(_loading_overlay)
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
		var toybox := TOYBOX_SCENE.instantiate()
		toybox.call(
			"configure_embedded",
			tuning_service,
			_level_touch_exclusions()
		)
		_content.add_child(toybox)
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


func warp_room_instantiate_count() -> int:
	return _warp_room_instantiate_count


func _render_warp_room() -> void:
	if _suppress_next_warp_room_render:
		_suppress_next_warp_room_render = false
		return
	_warp_room_instantiate_count += 1
	var room := WARP_ROOM_SCENE.instantiate()
	_content.add_child(room)
	room.call(
		"configure",
		profile,
		tuning_service.catalog,
		_hub_level_metas(),
		_phase_available(),
		_available_level_ids(),
		_warp_room_touch_exclusions()
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
		_available_level_ids(),
		_warp_room_touch_exclusions()
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
	_threaded_load_elapsed_s = 0.0
	_threaded_load_status_override = null
	# An earlier load of this same path can still be outstanding — e.g.
	# quit_level abandons the poll without ever draining the resource
	# loader's request (ResourceLoader has no cancel API). Re-requesting
	# the same path while that request is still IN_PROGRESS/LOADED but
	# undrained races a second load against the first inside the
	# RenderingServer's mesh storage (N2: intermittent
	# `Parameter "m" is null` / "unimplemented base type encountered in
	# renderer scene cull" / "Condition \"!F\" is true"). Re-attach to
	# the outstanding request instead of issuing a second one.
	var already_in_flight := ResourceLoader.load_threaded_get_status(
		path
	) in [
		ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		ResourceLoader.THREAD_LOAD_LOADED,
	]
	if not already_in_flight:
		# use_sub_threads=false: sub-threaded loading lets separate
		# worker threads race each other issuing RenderingServer mesh
		# calls for the level's meshes while this poll's instantiate()
		# (main thread) also touches them — the other half of the same
		# N2 race. A single background load thread still keeps the hub
		# non-blocking; it just stops recursing into extra sub-threads
		# for dependency resources.
		# CACHE_MODE_REPLACE: ResourceLoader's default CACHE_MODE_REUSE
		# hands back the SAME cached PackedScene (and its meshes) on
		# every load of this path, so a load thread's mesh construction
		# can overlap an earlier tree's teardown free() of a tree still
		# referencing that same cached mesh — the other main source of
		# the N2 race, and reachable in production via quit → re-enter,
		# not only across tests. REPLACE gives each load its own fresh
		# copy; deliberately NOT a *_DEEP variant, since forcing that
		# onto nested script dependencies (segments reference .gd
		# files) broke class resolution outright in testing.
		var request_error := ResourceLoader.load_threaded_request(
			path,
			"",
			false,
			ResourceLoader.CACHE_MODE_REPLACE
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
	if _loading_overlay != null:
		_loading_overlay.visible = true


func set_threaded_load_status_override(status: Variant) -> void:
	_threaded_load_status_override = status


func _threaded_load_status() -> int:
	if _threaded_load_status_override != null:
		return int(_threaded_load_status_override)
	return ResourceLoader.load_threaded_get_status(_threaded_level_path)


func _poll_threaded_level_load(delta_s: float) -> void:
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
	_threaded_load_elapsed_s += maxf(delta_s, 0.0)
	var status := _threaded_load_status()
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if _threaded_load_elapsed_s >= LEVEL_LOAD_TIMEOUT_S:
			_cancel_pending_level_load()
			_clear_content()
			_show_state_placeholder()
			push_error("Threaded level load timed out.")
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
	_threaded_load_elapsed_s = 0.0
	_threaded_load_status_override = null
	if _loading_overlay != null:
		_loading_overlay.visible = false


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
	if flow.has_resume_decision():
		var saved := flow.consume_resume_snapshot()
		if not session.restore_snapshot(saved):
			last_snapshot_error = session_snapshot.delete(save_dir)
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
		flow.state == GameFlow.State.LEVEL
		and flow.active_level_id == DEBUG_TOYBOX_LEVEL_ID
	):
		var toybox := _content.get_node_or_null("Game")
		if toybox != null:
			toybox.call("refresh_tuning")
		return
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
	if _hud != null:
		_hud.call("refresh_tuning", catalog.economy)
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
		_hud.get_node("SafeArea/MercyPanel"),
		_results_screen,
		_pause_overlay,
		_level_list_overlay,
	]
	controls.append_array(_debug_touch_exclusions())
	return controls


func _debug_touch_exclusions() -> Array:
	if not _tuning_debug.visible:
		return []
	return [
		_tuning_debug.get_node("HUD"),
		_tuning_debug.get_node("Drawer"),
	]


func _warp_room_touch_exclusions() -> Array:
	# The Level List overlay is a full-screen Control GameRoot draws on
	# top of the hub (I15's second half): without this, a tap aimed at
	# the overlay also lands on WarpRoom's own TouchControls underneath,
	# doubling as hub movement/jump input.
	var controls: Array = [_level_list_overlay]
	controls.append_array(_debug_touch_exclusions())
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
	_hud.call(
		"set_run_display_visible",
		flow.active_level_id != DEBUG_TOYBOX_LEVEL_ID
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
	# Retrying from pause round-trips WARP_ROOM as a same-frame FSM
	# waypoint on the way back into LEVEL (never a rendered frame), so
	# there is no need to pay for a real hub scene instantiate just to
	# discard it immediately after. The flag is always cleared right
	# after this call, regardless of the path _select_level takes, so
	# it can never leak into suppressing a later, genuine hub render.
	_suppress_next_warp_room_render = true
	_select_level(
		flow.active_level_id,
		flow.active_level_mode
	)
	_suppress_next_warp_room_render = false


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
