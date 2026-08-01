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
const DynamicResolutionType := preload(
	"res://src/core/dynamic_resolution.gd"
)
const AudioServiceType := preload("res://src/core/audio_service.gd")
const AUDIO_DIR := "res://assets/audio"
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
const LOOK_DEV_SCENE := preload("res://scenes/debug/look_dev.tscn")
# Task 4 (CTR R7): every racing track's scene/level-id/display-name wiring
# now lives in ONE registry table, shared with level_list_overlay.gd --
# see RacingTrackRegistry's own class doc for the full "why" (this used to
# be 2 preload consts + 2 debug-level-id consts per track, hand-copied on
# both sides for every new circuit). Fix-wave MEDIUM-5's own history (solo
# time trial = spawn_opponents=false wrapper scenes, AI by default on the
# RACE entries even though the level list labels them "RACE" not "TIME
# TRIAL") is preserved verbatim inside the registry rows themselves, not
# restated here.
const RacingTrackRegistryType := preload(
	"res://src/racing/track/track_registry.gd"
)
# Task 5 (CTR R7, the Cup): see cup_session.gd's own OWNERSHIP class doc for
# why GameRoot is the one node that holds this across a race-scene swap, and
# cup_standings_overlay.gd's own class doc for the one screen this task uses
# for both the between-race interstitial and the final podium.
const CupSessionType := preload("res://src/racing/flow/cup_session.gd")
const CUP_STANDINGS_OVERLAY_SCENE := preload(
	"res://scenes/racing/cup_standings_overlay.tscn"
)
const WARP_ROOM_SCENE := preload(
	"res://scenes/levels/warp_room_1.tscn"
)
const N_SANITY_BEACH_META := preload(
	"res://data/tuning/levels/n_sanity_beach.tres"
)
const BOULDERS_META := preload(
	"res://data/tuning/levels/boulders.tres"
)
const HOG_WILD_META := preload(
	"res://data/tuning/levels/hog_wild.tres"
)
const PAPU_PAPU_META := preload(
	"res://data/tuning/levels/papu_papu.tres"
)
const MISSED_CRATE_OUTLINE_SHADER := preload(
	"res://assets/shaders/missed_crate_outline.gdshader"
)

const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const DEFAULT_SAVE_DIR := "user://save"
const DEBUG_TOYBOX_LEVEL_ID := &"debug_traversal_toybox"
const DEBUG_LOOK_DEV_LEVEL_ID := &"debug_look_dev"
const N_SANITY_BEACH_LEVEL_ID := &"wr1_n_sanity_beach"
const N_SANITY_BEACH_SCENE_PATH := (
	"res://scenes/levels/wr1_n_sanity_beach.tscn"
)
const BOULDERS_LEVEL_ID := &"wr1_boulders"
const BOULDERS_SCENE_PATH := (
	"res://scenes/levels/wr1_boulders.tscn"
)
const HOG_WILD_LEVEL_ID := &"wr1_hog_wild"
const HOG_WILD_SCENE_PATH := (
	"res://scenes/levels/wr1_hog_wild.tscn"
)
const PAPU_PAPU_LEVEL_ID := &"wr1_papu_papu"
const PAPU_PAPU_SCENE_PATH := (
	"res://scenes/levels/wr1_papu_papu.tscn"
)
const _LEVEL_SCENE_PATHS: Dictionary = {
	N_SANITY_BEACH_LEVEL_ID: N_SANITY_BEACH_SCENE_PATH,
	BOULDERS_LEVEL_ID: BOULDERS_SCENE_PATH,
	HOG_WILD_LEVEL_ID: HOG_WILD_SCENE_PATH,
	PAPU_PAPU_LEVEL_ID: PAPU_PAPU_SCENE_PATH,
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
var audio_service: AudioServiceType

@onready var _content: Node = $Content
@onready var _ui: CanvasLayer = $UI
@onready var _tuning_debug: TuningDebugUI = $UI/TuningDebug
@onready var _perf_readout_area: Control = $UI/PerfReadoutArea
@onready var _perf_readout: PerfReadout = $UI/PerfReadoutArea/PerfReadout

var _active_level_meta: LevelMeta
var _segment_by_crate_id: Dictionary = {}
var _hud: Control
var _results_screen: Control
var _pause_overlay: Control
var _level_list_overlay: Control
var _boot_error_overlay: Control
# Task 5 (CTR R7, the Cup): non-null only while a cup is actually in
# progress -- see cup_session.gd's own OWNERSHIP doc. Cleared whenever the
# player navigates to anything OTHER than the cup's own next race (see
# _abandon_active_cup()), so a stray finish on an ordinarily-launched race
# can never be mistaken for cup progress.
var _cup_session: CupSessionType
var _cup_standings_overlay: Control
# Task 5 (CTR R7, the Cup): which of _cup_session's own race indices the
# CURRENTLY LOADED race scene corresponds to, or -1 when no cup race is in
# flight -- set only by _advance_cup(), the one place a cup race is ever
# launched. Deliberately NOT re-derived from CupSession.next_race_index()
# anywhere a race's own finish is scored: next_race_index() answers "which
# race has CupSession never recorded a result for", which is the WRONG
# question for a RETRY of a race that already has one -- next_race_index()
# would already point PAST it. This field is the one place that tracks "what
# is actually in flight right now", independent of what CupSession has or
# hasn't recorded yet.
var _cup_active_race_index: int = -1
var _level_list_open: bool = false
var _owns_tree_pause: bool = false
var _threaded_level_path: String = ""
var _threaded_level_id: StringName = &""
var _threaded_poll_count: int = 0
var _threaded_load_elapsed_s: float = 0.0
var _threaded_load_status_override: Variant = null
var _loading_overlay: Label
var _dynamic_resolution: DynamicResolutionType = DynamicResolutionType.new()
var _warp_room_instantiate_count: int = 0
var _suppress_next_warp_room_render: bool = false
# Task 8 (CTR racing mode, R2): the level list's racing entries all take
# the exact same debug-only render branch (see _render_state() below),
# keyed by which debug level id was selected. Task 4 (CTR R7): the
# dictionary itself is now BUILT in _ready() (see
# _build_race_scenes_by_level_id()) from RacingTrackRegistryType.TRACKS
# rather than hand-written per track -- GDScript const initializers can't
# call functions, so this can't stay a `const` once it's derived; every
# reader below only ever does .has()/[] lookups, so an instance var built
# once at boot is behaviorally identical to the old const for the rest of
# this file.
var _race_scenes_by_level_id: Dictionary = {}


static func should_enable_debug_tools(is_debug_build: bool) -> bool:
	return is_debug_build


## Task 4 (CTR R7): builds the flat level_id->PackedScene lookup every
## racing call site below reads (_render_state()'s launch branch,
## _refresh_active_level_tuning()'s live-tuning-refresh branch, _sync_ui_
## visibility()'s run-display gate) from RacingTrackRegistryType.TRACKS --
## one RACE + one TIME TRIAL entry per row, same shape the old hand-
## written _RACE_SCENES_BY_LEVEL_ID const had. Pure (no side effects
## beyond returning the dict) so it can be called from _ready() without
## depending on anything else _ready() has or hasn't set up yet.
static func _build_race_scenes_by_level_id() -> Dictionary:
	var scenes_by_level_id := {}
	for track in RacingTrackRegistryType.TRACKS:
		scenes_by_level_id[track.level_id] = track.race_scene
		scenes_by_level_id[track.solo_level_id] = track.solo_scene
	return scenes_by_level_id


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_use_accumulated_input(false)
	_race_scenes_by_level_id = _build_race_scenes_by_level_id()
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

	# Installed at boot so its one-line silence report happens once, and so the
	# SFX call sites have something real to talk to. H10 owns the clips; every
	# slot is empty by design until then.
	audio_service = AudioServiceType.new()
	audio_service.name = "Audio"
	add_child(audio_service)
	audio_service.configure(AUDIO_DIR)

	PhaseState.configure(tuning_service.catalog.phase)
	var debug_tools_enabled := should_enable_debug_tools(OS.is_debug_build())
	_tuning_debug.visible = debug_tools_enabled
	# Authored hidden in main.tscn; a release build leaves it that way, and
	# PerfReadout stops sampling entirely while hidden.
	_perf_readout.visible = debug_tools_enabled
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
	_apply_dynamic_resolution(delta_s)


## E1-01: §9.4's 1.0->0.7 fallback had no production driver, so the perf
## readout's SCALE field could only ever report 1.00 and the second half of
## Gate F criterion 2 was untestable. This runs in every build, not just debug
## ones -- the point is to hold 60 fps on the phone, not to show a number.
func _apply_dynamic_resolution(delta_s: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var current_scale := viewport.scaling_3d_scale
	var next_scale := _dynamic_resolution.tick(delta_s, current_scale)
	if is_equal_approx(next_scale, current_scale):
		return
	viewport.scaling_3d_scale = next_scale


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
	if active_level_session.has_method("set_audio_service"):
		active_level_session.call("set_audio_service", audio_service)
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
	# Installed at boot so its one-line silence report happens once, and so the
	# SFX call sites have something real to talk to. H10 owns the clips; every
	# slot is empty by design until then.
	audio_service = AudioServiceType.new()
	audio_service.name = "Audio"
	add_child(audio_service)
	audio_service.configure(AUDIO_DIR)

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
#   - boss defeat: wired below, by Task 22. Completing the boss level
#     stamps `boss_defeated.papu_papu` into the same profile write as
#     its results, so a defeat cannot be recorded without the run that
#     earned it also being persisted.
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
	# 01-DESIGN §4.4's fourth profile-write trigger. It had no production
	# writer while Phase 1 shipped no boss; Task 22 ships one, so a cleared
	# boss level stamps the defeat in the same write as its results rather
	# than in a second save.
	if meta.level_id == PAPU_PAPU_LEVEL_ID:
		var boss_value: Variant = updated_profile.get("boss_defeated", {})
		var boss_defeated: Dictionary = (
			boss_value as Dictionary if boss_value is Dictionary else {}
		)
		boss_defeated["papu_papu"] = true
		updated_profile["boss_defeated"] = boss_defeated
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
	# Task 5 (CTR R7, the Cup): a GameRoot-owned overlay, installed once here
	# alongside every other persistent screen -- see cup_standings_overlay.
	# gd's own OWNERSHIP doc for why it must NOT be a child of any race
	# scene.
	_cup_standings_overlay = (
		CUP_STANDINGS_OVERLAY_SCENE.instantiate() as Control
	)
	for screen: Control in [
		_hud,
		_results_screen,
		_pause_overlay,
		_level_list_overlay,
		_cup_standings_overlay,
	]:
		_ui.add_child(screen)
		var safe_area := screen.get_node_or_null("SafeArea")
		if safe_area != null:
			safe_area.call("configure", tuning_service.catalog.input)
	# E1-03: the perf readout gets the same safe-area inset and the same
	# display-metrics poll as every other overlay, so a device cutout cannot
	# hide the numbers the weekly device check reads.
	_perf_readout_area.call("configure", tuning_service.catalog.input)
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
		&"look_dev_requested",
		_on_look_dev_requested
	)
	# Task 4 (CTR R7): one generic signal replaces the old one-signal-per-
	# track/mode set (racing_time_trial_requested, racing_sanity_shores_
	# requested, and the two Fix-wave MEDIUM-5 solo counterparts) --
	# level_list_overlay.gd's own _RACING_BUTTONS table now supplies
	# (track_id, is_solo) for every racing button, existing and new.
	_level_list_overlay.connect(
		&"racing_track_requested",
		_on_racing_track_requested
	)
	# Task 5 (CTR R7, the Cup): see level_list_overlay.gd's own cup_requested
	# doc for why this is its own dedicated signal rather than another
	# racing_track_requested row.
	_level_list_overlay.connect(
		&"cup_requested",
		_on_cup_requested
	)
	_level_list_overlay.connect(
		&"closed",
		_on_level_list_closed
	)
	_level_list_overlay.call(
		"configure",
		debug_tools_enabled
	)
	_cup_standings_overlay.connect(
		&"continue_requested",
		_on_cup_continue_requested
	)
	_cup_standings_overlay.connect(
		&"closed",
		_on_cup_standings_closed
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
		# Task 5 (CTR R7, the Cup): pausing out of a race must not leave the
		# cup interstitial/podium visibly stuck on top of the Pause overlay --
		# see _hide_cup_standings_overlay()'s own doc.
		_hide_cup_standings_overlay()
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
	# Task 5 (CTR R7, the Cup): EVERY path that rebuilds Content -- a fresh
	# level, a retry (LEVEL -> WARP_ROOM -> LEVEL, same flow.state so the
	# PAUSED branch above never runs), the cup's own CONTINUE advance -- must
	# not leave a PREVIOUS race's cup screen visibly stuck on top of whatever
	# renders next. Retrying the race the interstitial/podium is currently
	# showing for is exactly the case this catches that _on_cup_continue_
	# requested()/_on_cup_standings_closed()'s own explicit hides do not:
	# those only run when the PLAYER dismisses the screen through it, not
	# when they retry out from under it instead (see cup_session.gd's own
	# RETRY SEMANTICS doc -- the active CupSession itself is untouched here,
	# only this transient screen hides).
	_hide_cup_standings_overlay()

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
		and flow.active_level_id == DEBUG_LOOK_DEV_LEVEL_ID
	):
		var look_dev: LookDev = LOOK_DEV_SCENE.instantiate()
		look_dev.set_assets(
			look_dev.discover_assets("res://assets/models")
		)
		look_dev.closed.connect(_on_level_session_exited)
		_content.add_child(look_dev)
		return
	if (
		flow.state == GameFlow.State.LEVEL
		and _race_scenes_by_level_id.has(flow.active_level_id)
	):
		var race_scene: PackedScene = _race_scenes_by_level_id[
			flow.active_level_id
		]
		var race := race_scene.instantiate()
		_content.add_child(race)
		race.call("configure", tuning_service.catalog)
		if race.has_signal(&"retry_requested"):
			race.connect(&"retry_requested", _on_racing_retry_requested)
		# Task 9 (CTR racing mode, R2): see _on_racing_finished's own doc for
		# why GameRoot (not RaceSession) owns the save comparison/write, the
		# same division of responsibility _on_level_session_completed already
		# has with LevelSession.
		if race.has_signal(&"race_finished"):
			race.connect(
				&"race_finished",
				_on_racing_finished.bind(race)
			)
		return
	if (
		flow.state == GameFlow.State.LEVEL
		and _LEVEL_SCENE_PATHS.has(flow.active_level_id)
	):
		_begin_threaded_level_load(flow.active_level_id)
		return
	_show_state_placeholder()


## Task 5 (CTR R7, the Cup): the one place that hides _cup_standings_overlay
## defensively (null/freed-safe, see every call site above) -- the CupSession
## it was showing data FOR is never touched here (see each call site's own
## doc for why); this only ever hides the transient screen, never abandons
## the cup itself.
func _hide_cup_standings_overlay() -> void:
	if (
		_cup_standings_overlay != null
		and is_instance_valid(_cup_standings_overlay)
	):
		_cup_standings_overlay.visible = false


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
		BOULDERS_LEVEL_ID: BOULDERS_META,
		HOG_WILD_LEVEL_ID: HOG_WILD_META,
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
	if level_id == BOULDERS_LEVEL_ID:
		return BOULDERS_META
	if level_id == HOG_WILD_LEVEL_ID:
		return HOG_WILD_META
	if level_id == PAPU_PAPU_LEVEL_ID:
		return PAPU_PAPU_META
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
		_phase_available(),
		catalog.hog
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
		catalog.input,
		catalog
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
		flow.state == GameFlow.State.LEVEL
		and _race_scenes_by_level_id.has(flow.active_level_id)
	):
		# M2 (final fix wave): a race is never stored on active_level_session
		# (see set_active_level_session()'s own doc -- only LevelSession
		# instances go through that path), so unlike the toybox branch above
		# there is no single fixed child name to look up either: the two
		# race scenes' own root nodes are named differently
		# (RaceTimeTrial/RaceSanityShores). _content holds exactly one
		# child while a race is the active content (see _render_state()'s
		# own racing branch, which _clear_content()s before adding it), so
		# the first (only) child IS the live race session.
		var race := (
			_content.get_child(0) if _content.get_child_count() > 0 else null
		)
		if race != null and race.has_method("refresh_tuning"):
			race.call("refresh_tuning", tuning_service.catalog)
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
			_phase_available(),
			catalog.hog
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
		catalog.input,
		catalog
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
		if (
			not candidate.has_method("apply_verb")
			or not candidate.has_signal(&"broken")
		):
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
	material.shader = MISSED_CRATE_OUTLINE_SHADER
	_apply_missed_crate_outline_parameters(material)
	for candidate: Node in level.find_children(
		"*",
		"StaticBody3D",
		true,
		false
	):
		if (
			not candidate.has_method("apply_verb")
			or not candidate.has_signal(&"broken")
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
		_apply_missed_crate_outline_parameters(material)


func _apply_missed_crate_outline_parameters(
	material: ShaderMaterial
) -> void:
	var phase := tuning_service.catalog.phase
	material.set_shader_parameter(
		&"missed_crate_outline_color",
		phase.missed_crate_outline_color
	)
	material.set_shader_parameter(
		&"missed_crate_outline_opacity",
		phase.missed_crate_outline_opacity
	)
	material.set_shader_parameter(
		&"missed_crate_outline_edge_width_uv",
		phase.missed_crate_outline_edge_width_uv
	)
	material.set_shader_parameter(
		&"missed_crate_outline_padding_m",
		phase.missed_crate_outline_padding_m
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
	var controls: Array = []
	if _perf_readout.visible:
		# Top-right corner: outside §5.2's bottom-right JUMP wedge, but still
		# over the play area, and a thumb landing on it during the 20-minute
		# soak must not double as gameplay input.
		controls.append(_perf_readout)
	if not _tuning_debug.visible:
		return controls
	controls.append(_tuning_debug.get_node("HUD"))
	controls.append(_tuning_debug.get_node("Drawer"))
	return controls


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
		(
			flow.active_level_id not in [
				DEBUG_TOYBOX_LEVEL_ID,
				DEBUG_LOOK_DEV_LEVEL_ID,
			]
			# Fix-wave MEDIUM-5: reads the same dictionary _render_state()'s
			# own racing branch already keys off of, rather than a second,
			# separately hand-kept id list -- the two new solo-race ids added
			# alongside it are automatically covered with no edit needed here.
			and not _race_scenes_by_level_id.has(flow.active_level_id)
		)
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
	_retry_current_level()


## Fix round (H1 review, Task 7): RaceHUD's RETRY button used to call
## get_tree().change_scene_to_file() directly, which frees GameRoot (the
## real scene tree root) out from under itself -- the fresh race scene that
## replaces it never gets configure() called by anyone, since GameRoot was
## the only thing that ever called it. RaceSession now emits
## retry_requested instead (see its own doc), connected to this handler
## from _render_state()'s racing render branch below (Task 4, CTR R7: keyed
## off _race_scenes_by_level_id, built from RacingTrackRegistryType.TRACKS),
## one connection per fresh race instance. This reuses the exact same
## _retry_current_level() round-trip the platformer's own working Pause ->
## Retry path already proved out -- quit the level, re-enter it -- which
## lands back in _render_state()'s racing branch and instantiates +
## configure()s a brand new race scene while GameRoot itself stays alive
## throughout.
func _on_racing_retry_requested() -> void:
	_retry_current_level()


## Task 9 (CTR racing mode, R2): racing's counterpart to
## _on_level_session_completed above -- the only place a race's result is
## compared against the saved best and (if better) written to disk.
## RaceSession never touches SaveModel/SaveService itself (see its own
## track_id/present_best_times docs); this is the one place that does,
## mirroring how LevelSession never writes its own save either. Bound with
## the race node itself (see the race_finished.connect() call above) so this
## can read its exported track_id and hand the outcome back down to its HUD
## without GameRoot needing to know RaceHUD's own node path.
##
## R5 Task 3 (spec debt #9 RULING, ZERO schema change): best total/lap times
## are the TIME-TRIAL record -- written, and even COMPARED for improvement,
## ONLY when this session is solo (`spawn_opponents == false` already owns
## "is this session solo", see race_session.gd's own doc on that exported
## field; read here via race.get() the same duck-typed way track_id already
## is). Debt #9 named the two remaining options once R4 items and R5's start
## systems diverged what a RACE lap-time and a TIME-TRIAL lap-time each
## measure: split the save key by mode, or stop writing best times from AI
## races entirely and keep the record TIME-TRIAL-only. This is the second --
## simpler, no new save-key shape, no migration. A race deliberately never
## even CALLS SaveModel.improved_racing_record(): doing so and then simply
## skipping the write would still compute new_best_total/new_best_lap true
## for a race that ran faster than the saved best, and this exact payload
## also drives RaceHUD's own NEW BEST marker (present_best_times()) -- so a
## race would flash "NEW BEST" for a result that was never persisted and
## vanishes the instant the scene closes. Reading the EXISTING record
## unmodified and handing it to the HUD as a labeled "TT BEST" reference
## (see race_hud.gd's own TT BEST class-doc section) is what debt #9's own
## ruling calls "races still DISPLAY the time-trial best as reference".
func _on_racing_finished(
	total_s: float,
	lap_times: Array,
	race: Node
) -> void:
	var track_id := StringName(race.get("track_id"))
	if track_id.is_empty():
		return
	var previous_record := SaveModel.racing_record(profile, track_id)
	var is_solo := not bool(race.get("spawn_opponents"))
	var updated_record := previous_record
	var new_best_total := false
	var new_best_lap := false
	if is_solo:
		var candidate_record := SaveModel.improved_racing_record(
			previous_record,
			total_s,
			lap_times
		)
		if not candidate_record.is_empty():
			updated_record = candidate_record
			new_best_total = (
				int(updated_record.get("best_total_time_ms", 0))
				!= int(previous_record.get("best_total_time_ms", 0))
			)
			new_best_lap = (
				int(updated_record.get("best_lap_time_ms", 0))
				!= int(previous_record.get("best_lap_time_ms", 0))
			)
			# "persist if better" (task brief): an unimproved run is shown
			# against the existing best (below) but must not touch the save
			# file at all.
			if new_best_total or new_best_lap:
				var updated_profile := profile.duplicate(true)
				var racing_value: Variant = updated_profile.get("racing")
				var racing: Dictionary = (
					(racing_value as Dictionary).duplicate(true)
					if racing_value is Dictionary
					else {}
				)
				racing[String(track_id)] = updated_record
				updated_profile["racing"] = racing
				if not SaveModel.validate(updated_profile):
					push_error("Racing profile update failed validation.")
					return
				var save_error := save_service.store_profile(
					save_dir,
					updated_profile
				)
				if save_error != OK:
					last_save_error = save_error
					push_error(
						"Racing best time was not saved: "
						+ error_string(save_error)
					)
					return
				last_save_error = OK
				profile = updated_profile
				# Task 6 (CTR R7, stretch: time-trial ghost). GHOST
				# PERSISTENCE: hooks this exact "the profile write just
				# succeeded" point -- the SAME solo/new-best-gated branch
				# that decided racing.<track_id> was worth writing at all --
				# rather than duplicating any of is_solo/new_best_total's
				# own logic here. Gated specifically on new_best_total, NOT
				# new_best_lap: a ghost replays a whole race top to bottom
				# against TOTAL time, so a run that only improved a single
				# lap split (new_best_lap true, new_best_total false) has
				# nothing more worth racing against than the ghost already
				# on disk. RaceSession.save_ghost() (race_session.gd's own
				# WRITE HOOK doc) owns the real user://ghosts/<track_id>.
				# ghost path and every corruption/failure concern from here
				# down; has_method() guards the same way present_best_
				# times() below already does, for any older/synthetic race
				# fixture that predates this task.
				if new_best_total and race.has_method("save_ghost"):
					race.call("save_ghost")
	if race.has_method("present_best_times"):
		race.call("present_best_times", {
			"best_total_ms": int(
				updated_record.get("best_total_time_ms", 0)
			),
			"best_lap_ms": int(
				updated_record.get("best_lap_time_ms", 0)
			),
			"new_best_total": new_best_total,
			"new_best_lap": new_best_lap,
		})

	# Task 5 (CTR R7, the Cup): see cup_session.gd's own OWNERSHIP class doc
	# for the whole design this reads from. This race scored into the active
	# cup ONLY if a cup is active AND this is genuinely the track _cup_active_
	# race_index says is currently in flight -- an ordinarily-launched
	# "RACE — SANITY SHORES" finish must never be mistaken for cup progress
	# just because the track ids happen to match (see _abandon_active_cup(),
	# called from every non-cup racing/level entry point, for the other half
	# of that guarantee). Matched against _cup_active_race_index -- NOT
	# CupSession.next_race_index() -- so a RETRY of an already-recorded race
	# is still recognized as scoring THAT race again (see _cup_active_race_
	# index's own field doc for why next_race_index() is the wrong question
	# here).
	if (
		_cup_session != null
		and _cup_active_race_index >= 0
		and (
			_cup_session.track_id_for_race(_cup_active_race_index)
			== track_id
		)
	):
		_cup_session.record_race_result(
			_cup_active_race_index,
			race.call("standings")
		)
		_handle_cup_race_recorded()


## Task 5 (CTR R7, the Cup): the interstitial (between race 1 and race 2) or
## the final podium (after race 2), whichever record_race_result() just
## produced -- CupSession.is_complete() is the one thing that tells the two
## apart (see cup_standings_overlay.gd's own present() doc for what each
## rendering looks like). The just-finished race's own display name (for the
## interstitial's title) is read straight off RacingTrackRegistry, keyed by
## _cup_active_race_index -- the race that ACTUALLY just finished, not
## whatever CupSession.next_race_index() reads now that it has already been
## recorded (see that field's own doc).
func _handle_cup_race_recorded() -> void:
	if _cup_session == null:
		return
	var is_final := _cup_session.is_complete()
	if is_final:
		_persist_cup_result_if_improved()
	_cup_standings_overlay.call(
		"present",
		_cup_session.standings(),
		is_final,
		_track_display_name(
			_cup_session.track_id_for_race(_cup_active_race_index)
		)
	)


## Task 5 (CTR R7, the Cup): save v3 -- writes racing.cups.island_cup.
## best_placement ONLY on genuine improvement (SaveModel.improved_cup_
## record()'s own "write only improvements, first result always writes"
## contract), the exact same "compare, then write only if it actually
## changed" shape _on_racing_finished's own best-time block above already
## uses for racing.<track_id>. The player's own final cup placement is read
## off CupSession.standings() -- the one row with is_player true.
func _persist_cup_result_if_improved() -> void:
	var player_placement := 0
	for row: Variant in _cup_session.standings():
		if bool((row as Dictionary).get("is_player", false)):
			player_placement = int((row as Dictionary).get("position", 0))
			break
	if player_placement <= 0:
		return

	var previous_record := SaveModel.cup_record(
		profile,
		CupSessionType.CUP_ID
	)
	var updated_record := SaveModel.improved_cup_record(
		previous_record,
		player_placement
	)
	if (
		updated_record.is_empty()
		or int(updated_record.get("best_placement", 0))
		== int(previous_record.get("best_placement", 0))
	):
		return

	var updated_profile := profile.duplicate(true)
	var racing_value: Variant = updated_profile.get("racing")
	var racing: Dictionary = (
		(racing_value as Dictionary).duplicate(true)
		if racing_value is Dictionary
		else {}
	)
	var cups_value: Variant = racing.get("cups")
	var cups: Dictionary = (
		(cups_value as Dictionary).duplicate(true)
		if cups_value is Dictionary
		else {}
	)
	cups[String(CupSessionType.CUP_ID)] = updated_record
	racing["cups"] = cups
	updated_profile["racing"] = racing
	if not SaveModel.validate(updated_profile):
		push_error("Cup profile update failed validation.")
		return
	var save_error := save_service.store_profile(save_dir, updated_profile)
	if save_error != OK:
		last_save_error = save_error
		push_error(
			"Cup best placement was not saved: " + error_string(save_error)
		)
		return
	last_save_error = OK
	profile = updated_profile


func _track_display_name(track_id: StringName) -> String:
	for track in RacingTrackRegistryType.TRACKS:
		if track.track_id == track_id:
			return String(track.display_name)
	return String(track_id)


## Task 5 (CTR R7, the Cup): the CUP menu entry (level_list_overlay.gd's own
## cup_requested signal) -- creates a fresh CupSession and starts race 1,
## the same real _select_level() round-trip every ordinary racing menu pick
## already uses (see _advance_cup() below).
func _on_cup_requested() -> void:
	if not OS.is_debug_build():
		return
	_cup_session = CupSessionType.new()
	_cup_session.configure(tuning_service.catalog.race)
	_advance_cup()


## The cup interstitial's own CONTINUE button.
func _on_cup_continue_requested() -> void:
	_hide_cup_standings_overlay()
	_advance_cup()


## The final podium's own CLOSE button -- the cup is over either way (this
## is only ever shown once CupSession.is_complete() is true, see _handle_
## cup_race_recorded()'s own doc), so this simply dismisses the overlay and
## releases the finished CupSession; whatever race 2's own ordinary finish
## panel is still showing underneath (ordinary Retry included) stays exactly
## as it was.
func _on_cup_standings_closed() -> void:
	_hide_cup_standings_overlay()
	_cup_session = null
	_cup_active_race_index = -1


## Loads the active CupSession's own next unplayed race through the SAME
## registered race scene an ordinary "RACE — <track>" menu pick already
## launches (RacingTrackRegistryType.TRACKS, matched by track_id -- never a
## cup-specific scene of its own, see cup_session.gd's own class doc for why
## the Cup reuses these rows verbatim). A no-op if the cup is already
## complete or absent -- defensive only, since both real call sites
## (_on_cup_requested/_on_cup_continue_requested) only ever call this when
## there IS a next race. THE one place _cup_active_race_index is ever set
## (see that field's own doc) -- a subsequent retry of this same race
## re-selects the level through a completely different path (_retry_current_
## level(), never this function) and so leaves it untouched, which is
## exactly the point.
func _advance_cup() -> void:
	if _cup_session == null:
		return
	var race_index := _cup_session.next_race_index()
	if race_index < 0:
		return
	var track_id := _cup_session.track_id_for_race(race_index)
	for track in RacingTrackRegistryType.TRACKS:
		if track.track_id == track_id:
			_cup_active_race_index = race_index
			_select_level(track.level_id)
			return


## Task 5 (CTR R7, the Cup): called from every menu/level entry point that
## is NOT "continue the active cup" -- picking any ordinary racing/platformer
## level, or opening the toybox/look-dev debug entries, abandons whatever cup
## is in progress. Without this, finishing an ORDINARILY-launched "RACE —
## SANITY SHORES" after a still-active, never-finished cup happened to be
## waiting on that exact same track would be silently scored as cup progress
## (see _on_racing_finished()'s own track_id-match guard, which alone cannot
## tell "the player picked the ordinary menu entry" apart from "the player
## continued the cup"). Retrying the CURRENT race (either retry path,
## _retry_current_level()) deliberately does NOT call this -- see cup_
## session.gd's own RETRY SEMANTICS doc for why a mid-cup retry must leave
## the active cup completely untouched.
func _abandon_active_cup() -> void:
	if _cup_session == null:
		return
	_cup_session = null
	_cup_active_race_index = -1
	_hide_cup_standings_overlay()


## Shared by both retry paths above -- see each caller's doc for why they
## can share this unchanged. Retrying round-trips WARP_ROOM as a same-frame
## FSM waypoint on the way back into LEVEL (never a rendered frame), so
## there is no need to pay for a real hub scene instantiate just to discard
## it immediately after. The suppress flag is always cleared right after
## this call, regardless of the path _select_level takes, so it can never
## leak into suppressing a later, genuine hub render.
func _retry_current_level() -> void:
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
	_abandon_active_cup()
	_select_level(level_id)


func _on_toybox_requested() -> void:
	if OS.is_debug_build():
		_abandon_active_cup()
		_select_level(DEBUG_TOYBOX_LEVEL_ID)


func _on_look_dev_requested() -> void:
	if OS.is_debug_build():
		_abandon_active_cup()
		_select_level(DEBUG_LOOK_DEV_LEVEL_ID)


## Task 4 (CTR R7): replaces the four near-identical _on_racing_*_requested
## handlers (one RACE + one TIME TRIAL/solo per track, Fix-wave MEDIUM-5's
## own copy-paste) with one lookup into RacingTrackRegistryType.TRACKS by
## track_id, same debug-build gate and _select_level() call every one of
## the old handlers made.
##
## Task 5 (CTR R7, the Cup): abandons any active cup first -- see _abandon_
## active_cup()'s own doc for why an ordinary racing-menu pick must never be
## mistaken for continuing a cup, even when it happens to land on the exact
## track the cup was still waiting on.
func _on_racing_track_requested(
	track_id: StringName,
	is_solo: bool
) -> void:
	if not OS.is_debug_build():
		return
	_abandon_active_cup()
	for track in RacingTrackRegistryType.TRACKS:
		if track.track_id != track_id:
			continue
		_select_level(track.solo_level_id if is_solo else track.level_id)
		return


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
	_abandon_active_cup()
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
