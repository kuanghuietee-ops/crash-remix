class_name RaceSession
extends Node3D

## Time-trial race conductor (Task 7). Mirrors level_session.gd's role --
## the one place that wires the racing pieces built by Tasks 1-6 together
## and drives the parts of a race that don't already self-tick -- but much
## smaller, since it owns none of the platformer's crate/enemy/checkpoint
## machinery. This IS the root script of scenes/racing/race_time_trial.tscn,
## the same relationship LevelSession has to a level scene (e.g.
## NSanityBeach): its children are found by fixed authored paths, not
## rediscovered by type scan, except for the CheckpointGate instances
## (found by type under Track, the same "find the small authored instances"
## shape LevelSession uses for crates/enemies).
##
## SELF-TICKING CHILDREN. KartController (kart_controller.gd) and
## KartCamera (kart_camera.gd) both already drive themselves every physics
## tick via their own _physics_process() once configure()d and in the tree
## -- see their class docs. This session must NOT also call a tick/update
## method on either; doing so would double-tick them. This session's own
## _physics_process() is responsible only for what nothing else already
## drives: routing input into the kart, the wrong-way grace timer, and
## noticing when the race is over.
##
## TIMER. elapsed_s() is a live diff against MonotonicClock, the same "now"
## primitive level_session.gd stamps onto its own events (see
## MonotonicClockType.now_s() call sites there) -- not a per-tick delta_s
## accumulator, so it can't drift with physics substep jitter. Lap splits
## are recorded as the DELTA between consecutive gate-0 crossings (not a
## cumulative "time at lap N"), which is what a finish panel's "splits"
## list conventionally shows.
##
## INPUT ROUTING. RacingInputAdapter (racing_input_adapter.gd) maps
## InputRouter's buffered move vector and the shared HOP action onto the
## kart's poll surface. hop_pressed()/hop_released() must fire once per
## real edge, not once per tick the button happens to read true -- this
## session tracks the previous tick's held state itself rather than using
## InputIntentBuffer's windowed consume_pressed()/consume_released() (that
## windowed buffering exists for the platformer's jump-buffer forgiveness
## window, tuned by a platformer-only InputTuning field with no racing
## equivalent; a hop press has no such forgiveness need since
## DriftStateMachine already owns its own slide-arming timing).

const RacingInputAdapterType := preload(
	"res://src/racing/input/racing_input_adapter.gd"
)
const LapValidatorType := preload("res://src/racing/track/lap_validator.gd")
const MonotonicClockType := preload("res://src/core/monotonic_clock.gd")

signal race_finished(total_s: float, lap_times: Array)

var _kart: CharacterBody3D
var _camera: KartCamera
var _track: Node3D
var _spine: TrackSpine
var _router: InputRouter
var _gamepad: Node
var _touch: TouchControls
var _hud: Control
var _gates: Array[CheckpointGate] = []

var _kart_tuning: KartTuning
var _race_tuning: RaceTuning
var _input_tuning: InputTuning

var _input_adapter: RacingInputAdapterType = RacingInputAdapterType.new()
var _validator: LapValidatorType = LapValidatorType.new()

var _configured: bool = false
var _finished: bool = false
var _hop_was_pressed: bool = false
var _start_s: float
var _final_elapsed_s: float
var _last_lap_boundary_s: float
var _lap_times: Array[float] = []
var _wrong_way_elapsed_s: float
var _wrong_way_flag: bool = false


func configure(catalog: GameplayTuning) -> void:
	_kart_tuning = catalog.kart
	_race_tuning = catalog.race
	_input_tuning = catalog.input

	_kart = get_node("Kart") as CharacterBody3D
	_camera = get_node("CameraRig") as KartCamera
	_track = get_node("Track") as Node3D
	_spine = _track.get_node("Spine") as TrackSpine
	_router = get_node("Input/InputRouter") as InputRouter
	_gamepad = get_node("Input/GamepadInput")
	_touch = get_node("UI/TouchControls") as TouchControls
	_hud = get_node("UI/RaceHUD")
	_hud.get_node("SafeArea").call("configure", _input_tuning)

	_router.call("configure", _input_tuning)
	_router.call("set_racing_mode", true)
	_gamepad.call("configure", _router, _input_tuning)
	_touch.call("configure", _router, _input_tuning, true)
	_touch.call("set_racing_layout", true)
	_touch.call(
		"set_touch_exclusion_controls",
		[_hud.get_node("SafeArea/FinishPanel/Margin/Rows/Retry")]
	)

	_kart.call("configure", _kart_tuning)
	var spawn := _track.get_node_or_null("KartSpawn") as Marker3D
	if spawn != null:
		_kart.global_transform = spawn.global_transform

	_camera.call(
		"configure",
		_kart,
		_camera.get_node("Camera3D"),
		_race_tuning,
		_kart_tuning
	)
	_spine.call("configure", catalog.camera)

	_gates = _discover_gates()
	for gate: CheckpointGate in _gates:
		# Callable equality (Godot 4) compares object+method+bound-args, so
		# a per-gate bound handler reused for both the check and the
		# connect() call correctly guards a re-configure() against a
		# duplicate connection -- comparing against the UNBOUND method here
		# would never match what actually gets connected below and could
		# never catch a repeat.
		var handler := _on_gate_body_entered.bind(gate)
		if not gate.body_entered.is_connected(handler):
			gate.body_entered.connect(handler)

	_validator.configure(_gates.size(), int(_race_tuning.lap_count))
	_input_adapter.configure(_input_tuning)

	_finished = false
	_hop_was_pressed = false
	_start_s = MonotonicClockType.now_s()
	_final_elapsed_s = 0.0
	_last_lap_boundary_s = 0.0
	_lap_times.clear()
	_wrong_way_elapsed_s = 0.0
	_wrong_way_flag = false
	_configured = true

	_hud.call("configure", self)


func current_lap() -> int:
	return _validator.current_lap() if _configured else 1


func lap_count() -> int:
	return int(_race_tuning.lap_count) if _race_tuning != null else 1


func gate_count() -> int:
	return _gates.size()


## Gates validated toward the lap currently in progress -- a thin
## pass-through onto LapValidator.progress_gates(), exposed mainly so an
## out-of-order crossing's rejection is externally observable (it leaves
## this unchanged) without reaching past this session into the private
## validator it owns.
func progress_gates() -> int:
	return _validator.progress_gates() if _configured else 0


func elapsed_s() -> float:
	if _finished:
		return _final_elapsed_s
	if not _configured:
		return 0.0
	return maxf(MonotonicClockType.now_s() - _start_s, 0.0)


func lap_times() -> Array[float]:
	return _lap_times.duplicate()


func is_wrong_way() -> bool:
	return _wrong_way_flag


func is_finished() -> bool:
	return _finished


func _physics_process(delta_s: float) -> void:
	if not _configured or _finished:
		return
	_route_input()
	_update_wrong_way(delta_s)


func _route_input() -> void:
	_input_adapter.apply_move(_router.buffer.movement(), _kart)
	var hop_held := _router.buffer.is_action_pressed(InputIntent.ACTION_JUMP)
	if hop_held != _hop_was_pressed:
		if hop_held:
			_input_adapter.apply_hop_pressed(_kart)
		else:
			_input_adapter.apply_hop_released(_kart)
		_hop_was_pressed = hop_held


func _update_wrong_way(delta_s: float) -> void:
	var progress := _spine.progress_for_position(_kart.global_position)
	var wrong_now := _spine.is_wrong_way(_kart.velocity, progress)
	if wrong_now:
		_wrong_way_elapsed_s += delta_s
	else:
		_wrong_way_elapsed_s = 0.0
	_wrong_way_flag = _wrong_way_elapsed_s >= _race_tuning.wrong_way_grace_s


func _discover_gates() -> Array[CheckpointGate]:
	var result: Array[CheckpointGate] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is CheckpointGate:
			result.append(candidate as CheckpointGate)
	result.sort_custom(
		func(a: CheckpointGate, b: CheckpointGate) -> bool:
			return a.gate_index < b.gate_index
	)
	return result


func _on_gate_body_entered(body: Node, gate: CheckpointGate) -> void:
	if _finished or body != _kart:
		return
	var outcome := _validator.gate_crossed(gate.gate_index)
	if outcome != &"lap_complete" and outcome != &"race_complete":
		return
	var now_elapsed := elapsed_s()
	_lap_times.append(now_elapsed - _last_lap_boundary_s)
	_last_lap_boundary_s = now_elapsed
	if outcome == &"race_complete":
		_finished = true
		_final_elapsed_s = now_elapsed
		race_finished.emit(_final_elapsed_s, _lap_times.duplicate())
