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
## TIMER. elapsed_s() sums delta_s from this session's own _physics_process
## each tick (M1 fix-wave revision -- it used to be a live MonotonicClock
## diff against a start timestamp, which read real wall-clock time straight
## through GameRoot pausing the whole tree via SceneTree.paused, since
## nothing about a raw clock diff cares whether anything actually ticked in
## between). configure() now sets process_mode = PROCESS_MODE_PAUSABLE
## (previously left at the INHERIT default, which silently inherited
## GameRoot's own PROCESS_MODE_ALWAYS and so never stopped ticking for a
## pause at all) so _physics_process simply doesn't run while paused,
## mirroring level_session.gd's identical process_mode = PAUSABLE +
## LevelRunState.advance_relic_timer(delta_s)-every-tick precedent for the
## platformer's own relic stopwatch. This trades the old approach's
## immunity to physics-substep jitter for pause-correctness; the resulting
## drift is bounded by Engine.physics_jitter_fix's own substep accounting
## and negligible at time-trial race lengths. Lap splits are recorded as
## the DELTA between consecutive gate-0 crossings (not a cumulative "time
## at lap N"), which is what a finish panel's "splits" list conventionally
## shows, and inherit the same pause-correctness for free since both read
## through elapsed_s().
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
##
## ITEM RNG (R4 Task 3). This session owns ONE seeded RandomNumberGenerator
## for the whole race and is the sole caller of ItemSlot.start_roll() for
## every kart in it (player and AI alike) -- see item_slot.gd's own RNG
## INJECTION doc for why the slot itself never touches randomness directly.
## item_rng_seed (exported, default 0) is the "determinism vs variety"
## knob: 0 means "no fixed seed was authored" and configure() calls
## RandomNumberGenerator.randomize() so ordinary play gets a genuinely
## different item sequence every race; any non-zero value is used as an
## explicit RandomNumberGenerator.seed, so a GUT test (or a future replay/
## regression fixture) can pin an exact, reproducible sequence of pickups
## by setting this exported field before configure() runs, the same
## "override a field on the session, don't touch RaceSession's internals"
## shape the existing spawn_opponents flag already establishes. Re-seeded
## fresh on every configure() call (including a re-configure/retry), so a
## fixed seed always reproduces the exact same sequence from race start.
##
## ITEM BOX WIRING mirrors the checkpoint-gate pattern one section up:
## boxes are discovered by type under Track (_discover_item_boxes(), the
## same find_children("*", "Area3D", true, false) scan _discover_gates()
## already uses) and this session connects to each one's native
## body_entered signal itself -- ItemBox emits nothing of its own (see
## item_box.gd's own class doc), it only manages its own hide/respawn
## bookkeeping through a SEPARATE listener on that same signal. A pickup
## routes to the ENTERING BODY's own ItemSlot (kart.item_slot(), looked up
## by calling the body directly -- no per-kart lookup table is needed the
## way gate crossings need _gate_validators, since the body IS the kart
## whose slot must roll), for player and AI karts identically -- there is
## no separate "is this the player" branch anywhere in this path. No boxes
## are authored into either real track yet (Task 5's job): on both current
## tracks _discover_item_boxes() simply returns an empty array and every
## piece of this wiring is a clean no-op, exercised only by tests that add
## a synthetic ItemBox under Track before calling configure().
##
## SOLO TIME TRIAL DOES NOT ROLL. spawn_opponents (not a new, separate
## exported flag) also gates item rolls: _items_allowed() reads it
## directly, so a solo race (spawn_opponents = false, see that field's own
## doc) never starts a roll even if a box is present and hit -- item pickups
## are a racing-against-someone mechanic, and solo time trial's own
## established contract is "race minus AI", nothing added in its place. A
## dedicated allow_items flag was considered and rejected: it would be a
## second lever controlling the exact same "is anyone actually being raced
## against" question spawn_opponents already answers, with no scene yet
## needing to set the two differently.

const RacingInputAdapterType := preload(
	"res://src/racing/input/racing_input_adapter.gd"
)
const LapValidatorType := preload("res://src/racing/track/lap_validator.gd")
const AiKartAgentType := preload("res://src/racing/ai/ai_kart_agent.gd")
const SpineFollowerType := preload("res://src/racing/track/spine_follower.gd")
const KartSceneType := preload("res://scenes/racing/kart.tscn")
# R4 Task 4: the two spawned/applied item effects that need a real scene
# instance (missile/beaker) -- turbo/shield are pure KartController calls,
# no scene needed. See dispatch_item_use()/register_hit().
const MissileSceneType := preload("res://scenes/racing/missile.tscn")
const BeakerSceneType := preload("res://scenes/racing/beaker.tscn")

signal race_finished(total_s: float, lap_times: Array)
## Fix round (H1 review): RaceHUD's RETRY button used to call
## get_tree().change_scene_to_file() directly, which frees GameRoot (the
## actual scene tree root) out from under itself -- the fresh race scene
## that replaces it never gets configure() called by anyone, since the only
## thing that ever called configure() was GameRoot, and GameRoot is now
## gone. RaceHUD now only calls request_retry(), which emits this; GameRoot
## connects to it (see game_root.gd's DEBUG_RACING_LEVEL_ID render branch)
## and re-drives the exact same _select_level() round-trip the platformer's
## own working Pause -> Retry path already uses (quit the level, re-enter
## it), which re-renders and re-configure()s a fresh race scene while
## GameRoot itself stays alive the whole time.
signal retry_requested

## Task 9 (CTR racing mode, R2): identifies which track this session's best
## times are saved under (SaveModel.racing_record()/improved_racing_record()
## are keyed by this, not by the debug level id GameRoot dispatches on --
## see game_root.gd's own DEBUG_RACING_LEVEL_ID doc for why those two ids
## are kept separate). Set per scene: race_time_trial.tscn authors
## &"graybox_loop", race_sanity_shores.tscn authors &"sanity_shores". Left
## empty ("") on any instance that never sets it (e.g. a bare test fixture),
## which GameRoot treats as "nothing to save" rather than guessing.
@export var track_id: StringName = &""

## Fix-wave MEDIUM-5: solo time trial restored (spec: "time trial ships as
## race-minus-AI"). true (the default -- every pre-existing race scene/test
## keeps its ordinary AI-populated shape unmodified) spawns AiTuning.
## opponent_count AI karts as always; false spawns NONE, regardless of what
## opponent_count itself is tuned to -- this flag, not opponent_count, owns
## "is this race solo" (opponent_count keeps validating strictly positive;
## see tuning_service.gd, unchanged by this fix). Two thin scene variants
## (race_time_trial_solo.tscn/race_sanity_shores_solo.tscn -- see game_root.
## gd's own wiring) instance the ordinary race scenes and override only
## this one exported value; the RACE scenes themselves (race_time_trial.
## tscn/race_sanity_shores.tscn) are untouched and keep spawning AI by
## default, same as every task before this one shipped them. HUD placement
## display needs no extra gating here -- placement_out_of() already reads
## _ai_karts.size() + 1 (see its own doc), which naturally collapses to 1
## when spawn_opponents leaves _ai_karts empty, and race_hud.gd's own
## "m > 1" gate already hides the panel for exactly that case (see its
## _on_race_finished doc, unchanged by this fix).
@export var spawn_opponents: bool = true

## R4 Task 3: see the class doc's ITEM RNG section. 0 (the default -- every
## pre-existing race scene/test) randomizes; a non-zero value pins an exact,
## reproducible item-roll sequence.
@export var item_rng_seed: int = 0

var _kart: CharacterBody3D
var _camera: KartCamera
var _track: Node3D
var _spine: TrackSpine
var _router: InputRouter
var _gamepad: Node
var _touch: TouchControls
var _hud: Control
var _gates: Array[CheckpointGate] = []
# R4 Task 3: see the class doc's ITEM BOX WIRING section.
var _item_boxes: Array[ItemBox] = []
var _item_rng := RandomNumberGenerator.new()

var _kart_tuning: KartTuning
var _race_tuning: RaceTuning
var _input_tuning: InputTuning
var _ai_tuning: AiTuning
var _item_tuning: ItemTuning

var _input_adapter: RacingInputAdapterType = RacingInputAdapterType.new()
var _validator: LapValidatorType = LapValidatorType.new()

# Task 5 (CTR R3 integration): opponent_count AI karts (kart.tscn + a real
# AiKartAgent each), spawned on GridSlot1..N under Track at configure() --
# see _spawn_ai_karts(). _ai_root is a plain container Node3D created lazily
# so a re-configure() (defensive; the real retry path replaces this whole
# scene via GameRoot, see retry_requested's own doc) can cleanly clear and
# rebuild it rather than leaking stale kart/agent instances.
var _ai_root: Node3D
var _ai_karts: Array[CharacterBody3D] = []
var _ai_agents: Array[AiKartAgentType] = []

# R4 Task 4: lazily-created container for spawned missile/beaker instances
# (see _ensure_hazards_root()/_spawn_missile()/_spawn_beaker()) -- mirrors
# _ai_root's own lazy-container shape one section up. Every hazard already
# self-despawns (queue_free()) on hit or its own lifetime, so this container
# needs no per-tick bookkeeping of its own; it exists only so a re-
# configure()/retry never leaves a PREVIOUS race's still-flying hazards
# parented under a fresh one (see configure()'s own defensive clear).
var _hazards_root: Node3D

# Cross-kart-progress "seam ruling" (Task 5 binding contract 2): the ONLY
# thing gate crossings do per body is advance THAT body's own LapValidator,
# looked up by identity -- never a raw index or slot assumption. Player and
# every AI kart share this one dictionary and one connected handler
# (_on_gate_body_entered), so a gate never needs to know how many karts
# exist or which one just crossed it beyond "which validator does this body
# own".
var _gate_validators: Dictionary = {}

# Task 5 binding contract 3: the player's own continuous SpineFollower total
# lives here (not on the player's Kart node, which has no such concept of
# its own) so finish placement can compare it against every AiKartAgent's
# already-exposed total_progress_m() -- both sides of every comparison are
# SpineFollower totals, never a raw seam-ambiguous spine offset. Updated
# every tick in _update_player_follower(); player_total_progress_m() is the
# getter Callable every AiKartAgent receives at configure() (band_gap_m's
# own "how far behind/ahead of the player" signal, see ai_kart_agent.gd).
var _player_follower: SpineFollowerType = SpineFollowerType.new()

# 1-based finish placement, computed once at the player's own race_complete
# instant (see _finish_race()); 0 before the race finishes.
var _placement: int = 0

var _configured: bool = false
var _finished: bool = false
var _hop_was_pressed: bool = false
var _item_was_pressed: bool = false
var _elapsed_s: float
var _final_elapsed_s: float
var _last_lap_boundary_s: float
var _lap_times: Array[float] = []
var _wrong_way_elapsed_s: float
var _wrong_way_flag: bool = false


func configure(catalog: GameplayTuning) -> void:
	# M1 fix-wave: without this, process_mode stays at the INHERIT default
	# and silently picks up GameRoot's own PROCESS_MODE_ALWAYS (see
	# game_root.gd's _ready()), so this session's _physics_process would
	# keep ticking straight through GameRoot pausing the whole tree -- see
	# elapsed_s()'s own class-doc TIMER section and level_session.gd's
	# identical precedent (set as the first line of ITS OWN configure()).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_kart_tuning = catalog.kart
	_race_tuning = catalog.race
	_input_tuning = catalog.input
	_ai_tuning = catalog.ai
	_item_tuning = catalog.items

	# R4 Task 3: see the class doc's ITEM RNG section -- re-seeded fresh on
	# every configure() (including a re-configure/retry) so a fixed non-zero
	# item_rng_seed always reproduces the exact same pickup sequence from
	# race start.
	if item_rng_seed == 0:
		_item_rng.randomize()
	else:
		_item_rng.seed = item_rng_seed

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

	_kart.call("configure", _kart_tuning, _item_tuning)
	# Task 5: this same "place the transform, then seed yaw as an
	# independent step" logic (HIGH-1 fix-wave bug doc below) is now shared
	# with every AI kart's own grid-slot placement via _seed_kart_transform()
	# -- see _spawn_ai_karts(). KartSpawn itself is left exactly as every
	# earlier task authored and read it (see the grid-slot doc on
	# _spawn_ai_karts() for why it is not renamed to GridSlot0): the player
	# still spawns from this one authored marker, unchanged.
	var spawn := _track.get_node_or_null("KartSpawn") as Marker3D
	if spawn != null:
		# HIGH-1 fix-wave bug: KartMotor's own yaw always starts at 0.0 and
		# _physics_process's first tick unconditionally overwrites this
		# body's rotation.y from it (see kart_controller.gd), silently
		# discarding whatever facing the transform copy above just set --
		# on both authored tracks that snapped the kart to face -Z instead
		# of the spawn's actual -90 degree authored yaw, straight across
		# the road into scenery, and zero checkpoint gates could ever
		# validate from a real drive. Seeding the motor's yaw AFTER placing
		# the transform (never before -- see set_yaw_degrees's own doc)
		# keeps the two in agreement from the very first tick. Derived from
		# the spawn's actual world-space forward rather than trusting its
		# local rotation_degrees.y directly, so this stays correct even if
		# a future track's spawn marker sits under a rotated parent.
		_seed_kart_transform(_kart, spawn)

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

	# R4 Task 3: see the class doc's ITEM BOX WIRING section. No per-box
	# bound handler is needed here (unlike the gate loop just above) -- the
	# routing handler below reads the ENTERING BODY's own item_slot(), never
	# which box fired, so a single unbound handler shared by every box is
	# both correct and sufficient; is_connected() against that same unbound
	# method is still what guards a re-configure() against a duplicate
	# connection.
	_item_boxes = _discover_item_boxes()
	for box: ItemBox in _item_boxes:
		box.call("configure", _item_tuning)
		if not box.body_entered.is_connected(_on_box_body_entered):
			box.body_entered.connect(_on_box_body_entered)

	# Task 5: player's own SpineFollower (binding contract 3) and the
	# body->validator routing table (binding contract 2's "gates route by
	# body identity") must both be ready before _spawn_ai_karts() below --
	# each AI kart's own AiKartAgent.configure() call reads
	# player_total_progress_m() indirectly is not required yet (its very
	# first read happens on the next physics tick), but gate routing must
	# already know about the player by the time any kart -- including one
	# spawned this same call -- could conceivably cross a gate.
	_gate_validators.clear()
	_gate_validators[_kart] = _validator
	_player_follower.configure(_spine.length_m())
	_player_follower.reset(_spine.progress_for_position(_kart.global_position))
	_placement = 0

	_spawn_ai_karts()

	# R4 Task 4: a defensive re-configure/retry clear, the same shape
	# _spawn_ai_karts() already uses for _ai_root's own children -- a
	# re-configure() on the SAME session instance must never leave a
	# PREVIOUS race's still-flying missile/beaker instances parented under
	# this fresh one. Every hazard already self-despawns on hit or its own
	# lifetime in the normal case, so this only matters for the defensive
	# reuse path, not ordinary play.
	if _hazards_root != null:
		for hazard: Node in _hazards_root.get_children():
			hazard.queue_free()

	_finished = false
	_hop_was_pressed = false
	_elapsed_s = 0.0
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


## How many ItemBox instances were discovered under Track at configure()
## time -- exposed mainly so a test can prove the box-less-track no-op case
## explicitly (0 on both current real tracks, see the class doc's ITEM BOX
## WIRING section) rather than only inferring it from the absence of a
## crash.
func item_box_count() -> int:
	return _item_boxes.size()


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
	return _elapsed_s


func lap_times() -> Array[float]:
	return _lap_times.duplicate()


func is_wrong_way() -> bool:
	return _wrong_way_flag


func is_finished() -> bool:
	return _finished


## Binding contract 3's own SpineFollower total for the PLAYER -- the exact
## Callable every AiKartAgent receives as player_progress_getter at
## configure() (see _spawn_ai_karts()), and the "player's" side of every
## finish-placement comparison in _finish_race(). 0.0 before configure(),
## matching SpineFollower's own fail-closed shape one layer down.
func player_total_progress_m() -> float:
	return _player_follower.total_progress_m() if _configured else 0.0


## 1-based finish placement (1 = won), computed once at the player's own
## race_complete instant -- see _finish_race(). 0 before the race finishes;
## HUD/callers should gate display on is_finished() the same way they
## already gate every other finish-only stat.
func placement() -> int:
	return _placement


## "m" in RaceHUD's "FINISHED n / m" -- the actual number of AI karts that
## raced plus the player, NOT a blind read of AiTuning.opponent_count: if a
## track is ever missing a GridSlot marker for a configured slot (see
## _spawn_ai_karts()'s own fail-closed skip), fewer AI karts actually spawn
## than the tuning asked for, and this must reflect the race that actually
## ran, not the one that was configured.
func placement_out_of() -> int:
	return _ai_karts.size() + 1


func ai_kart_count() -> int:
	return _ai_karts.size()


func ai_kart(index: int) -> CharacterBody3D:
	return _ai_karts[index] if index >= 0 and index < _ai_karts.size() else null


## Exposed mainly for tests that need to reach past this session into a
## specific AiKartAgent (e.g. to seed its private SpineFollower directly for
## a deterministic placement scenario) without having to rediscover it by
## scene-tree path.
func ai_agent(index: int) -> Node:
	return _ai_agents[index] if index >= 0 and index < _ai_agents.size() else null


func ai_kart_total_progress_m(index: int) -> float:
	var agent := ai_agent(index)
	return float(agent.call("total_progress_m")) if agent != null else 0.0


## Gates validated toward the AI kart's own current lap -- the AI-kart
## counterpart to progress_gates(), reading that kart's own LapValidator out
## of _gate_validators rather than the player's _validator field.
func ai_kart_progress_gates(index: int) -> int:
	var kart := ai_kart(index)
	if kart == null:
		return 0
	var validator: LapValidatorType = _gate_validators.get(kart)
	return validator.progress_gates() if validator != null else 0


## The one thing RaceHUD's RETRY button does now -- see retry_requested's
## doc above for why it no longer reloads the scene itself.
func request_retry() -> void:
	retry_requested.emit()


## Task 9 (CTR racing mode, R2): GameRoot is the only thing that ever
## touches SaveService/SaveModel (see game_root.gd's _on_racing_finished
## doc) -- this session never reads or writes the profile itself. Once
## GameRoot has compared this race's result against the saved best and
## decided whether to persist it, it calls this to hand the outcome down to
## the HUD, the same "session forwards to _hud" shape configure() already
## uses one line below its own _hud.call("configure", self).
func present_best_times(payload: Dictionary) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.call("present_best_times", payload)


## Live tuning refresh (M2 fix-wave): the racing counterpart to
## LevelSession.refresh_tuning() / phase0_game.gd's refresh_tuning() -- see
## game_root.gd's _refresh_active_level_tuning(), which now has a racing
## branch calling this. Deliberately narrow, matching the platformer's own
## split between "values every live tick already reads fresh off a stored
## tuning reference" (just reassign it here) and "state a stateful sub-
## system captured once at configure() time" (leave it alone): re-running
## LapValidator.configure() here would reset _expected_gate/_laps_completed/
## _started and silently corrupt a gate sequence already in progress mid-
## race, so the validator, gate discovery, and input routing are untouched
## -- only the kart's motor+drift tuning, the camera's tuning, and this
## session's own stored tuning references (which lap_count(), the wrong-way
## grace check, etc. already read fresh off every call/tick) refresh live.
func refresh_tuning(catalog: GameplayTuning) -> void:
	if not _configured:
		return
	_kart_tuning = catalog.kart
	_race_tuning = catalog.race
	_input_tuning = catalog.input
	_item_tuning = catalog.items
	if _kart != null and is_instance_valid(_kart):
		_kart.call("refresh_tuning", _kart_tuning, _item_tuning)
	if _camera != null and is_instance_valid(_camera):
		_camera.call("refresh_tuning", _race_tuning, _kart_tuning)


## R4 Task 4 (item 1, hit-routing foundation): the ONE place any hit source
## (missile.gd/beaker.gd's own _physics_process, and any future hazard)
## turns "this kart got hit" into the real outcome, in priority order:
## shield block, then invulnerability, then an actual spin_out. No caller
## re-implements this priority itself -- see missile.gd's/beaker.gd's own
## _check_hits(), which both just forward whichever kart they reached
## straight here via .call("register_hit", kart).
##
## &"blocked" -- the kart was shielded; the shield is consumed EARLY right
## here (KartController.consume_shield()), not left to run out its own
## remaining duration -- CTR's "blocks exactly one hit, then it's gone".
## &"invulnerable" -- the kart is still inside its post-hit invulnerable_
## after_hit_s window (see kart_motor.gd's own doc); apply_spin_out() is
## NOT called again -- a kart already reeling from one hit does not get
## re-stunned by a second projectile arriving during its own grace window.
## &"spin_out" -- neither of the above; the hit lands for real via the
## Task-1-fixed apply_spin_out() (see kart_controller.gd's own R4-BINDING
## FIX doc), which also starts the kart's own invulnerable_after_hit_s
## window as a side effect.
##
## ORDER-AWARENESS (ledger note, per this task's own brief): this is called
## from a projectile/hazard's own _physics_process, i.e. potentially the
## SAME physics tick KartController._physics_process already ran and
## unconditionally forwarded a same-frame slide-boost tap into KartMotor
## (see kart_controller.gd's own BINDING CONTRACT doc). apply_spin_out()
## below does NOT touch KartMotor's own _boost_time_remaining_s (see
## kart_motor.gd's apply_spin_out() -- it only dumps forward speed once by
## spin_out_speed_keep_ratio and starts the spin_out/invulnerable timers),
## so a boost that already landed in the motor THIS SAME TICK survives a
## hit landing the same tick. This is INTENTIONAL, a strict-CTR ruling (a
## boost that already fired is already committed -- a real CTR kart
## mid-boost that gets hit keeps its boost speed through the spin), not an
## ordering bug to "fix" by also zeroing boost here -- pinned by
## test_race_session.gd's own test_register_hit_does_not_cancel_a_same_
## frame_boost_already_forwarded_to_the_motor.
func register_hit(target_kart: CharacterBody3D) -> StringName:
	if bool(target_kart.call("is_shielded")):
		target_kart.call("consume_shield")
		return &"blocked"
	if bool(target_kart.call("is_invulnerable")):
		return &"invulnerable"
	target_kart.call("apply_spin_out")
	return &"spin_out"


## R4 Task 4 (item 5): the shared item-use dispatch surface. The player's
## ITEM press below (_route_input()) already calls KartController.use_item()
## itself via RacingInputAdapter.apply_item_pressed() (which returns the
## used item's name) and hands the result straight to dispatch_item_use();
## Task 5's AI item-use decision is documented to call kart.use_item()
## itself the SAME way and route its own result through THIS method, so
## neither caller re-implements its own missile/beaker/turbo/shield switch.
## Exposed as a convenience for any future caller that wants "call use_item
## AND dispatch" as one step (Task 5's AiKartAgent is the intended other
## caller once its own decision lands).
func use_item_for(kart: CharacterBody3D) -> StringName:
	var item_name: StringName = kart.call("use_item")
	dispatch_item_use(kart, item_name)
	return item_name


## &"none" (nothing was held, or use_item() was called on an empty/rolling
## slot -- see item_slot.gd's own use() doc) is a harmless no-op match.
func dispatch_item_use(kart: CharacterBody3D, item_name: StringName) -> void:
	match item_name:
		&"missile":
			_spawn_missile(kart)
		&"beaker":
			_spawn_beaker(kart)
		&"turbo":
			kart.call("apply_boost", _item_tuning.turbo_boost_s)
		&"shield":
			kart.call("set_shielded", _item_tuning.shield_duration_s)


func _ensure_hazards_root() -> Node3D:
	if _hazards_root == null:
		_hazards_root = Node3D.new()
		_hazards_root.name = "ItemHazards"
		add_child(_hazards_root)
	return _hazards_root


## Spawns at the launcher's own position/facing (no offset -- see missile.
## gd's own class doc: this node has no opinion on where it starts, it just
## configures the just-instantiated missile with everything it needs to
## lock its own launch-time target and run its own hit-testing from here
## on).
func _spawn_missile(launcher: CharacterBody3D) -> void:
	var missile := MissileSceneType.instantiate()
	_ensure_hazards_root().add_child(missile)
	missile.global_transform = launcher.global_transform
	missile.call(
		"configure", self, launcher, _item_tuning, Callable(self, "_item_targets")
	)


## Dropped at the launcher's own position minus its own forward vector
## times one kart length -- see beaker.gd's own class doc SPAWN POSITION
## section and _read_kart_length_m()'s own doc for the collision-extents
## derivation.
func _spawn_beaker(launcher: CharacterBody3D) -> void:
	var beaker := BeakerSceneType.instantiate()
	_ensure_hazards_root().add_child(beaker)
	var launcher_forward := -launcher.global_transform.basis.z
	var drop_point := (
		launcher.global_position - launcher_forward * _read_kart_length_m(launcher)
	)
	beaker.global_transform = Transform3D(launcher.global_transform.basis, drop_point)
	beaker.call(
		"configure", self, launcher, _item_tuning, Callable(self, "_item_targets")
	)


## The targets_getter Callable handed to every spawned missile/beaker (see
## _spawn_missile()/_spawn_beaker()) -- every kart currently in the race
## (player + AI) paired with its own current SpineFollower total_progress_m(),
## the exact seam-safe shape (see spine_follower.gd's own class doc) missile.
## gd's configure() uses to lock its launch-time target, and beaker.gd's own
## configure() reads purely for kart identities. Mirrors _other_kart_
## positions()'s own "this session already knows every kart in the race"
## rationale one section up.
func _item_targets() -> Array:
	var result: Array = []
	if _kart != null and is_instance_valid(_kart):
		result.append({"kart": _kart, "progress": player_total_progress_m()})
	for index in range(_ai_karts.size()):
		var ai_kart := _ai_karts[index]
		if ai_kart != null and is_instance_valid(ai_kart):
			result.append({"kart": ai_kart, "progress": ai_kart_total_progress_m(index)})
	return result


## Kart-length derivation mirrors ai_kart_agent.gd's own _read_kart_extents()
## (same BoxShape3D.size.z reading, see that file's own RESPAWN-ONTO-PLAYER
## AVOIDANCE doc) -- see the task brief's own "derive from kart collision
## extents like the respawn stepper did". 0.0 (a harmless zero offset -- the
## beaker drops exactly at the launcher's own position rather than crashing)
## for a kart with no readable CollisionShape3D, e.g. a bare test fixture.
func _read_kart_length_m(kart: CharacterBody3D) -> float:
	var collision := kart.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return 0.0
	var box := collision.shape as BoxShape3D
	if box == null:
		return 0.0
	return box.size.z


func _physics_process(delta_s: float) -> void:
	if not _configured or _finished:
		return
	# This tick simply never runs while the tree is paused (process_mode =
	# PAUSABLE, set in configure()), so summing delta_s here naturally
	# excludes paused time -- see elapsed_s()'s own class-doc TIMER section.
	_elapsed_s += delta_s
	_route_input()
	# Fix-wave LOW-6: _update_wrong_way() and _update_player_follower() each
	# used to call _spine.progress_for_position(_kart.global_position)
	# independently -- the same projection, computed twice a tick for no
	# reason (TrackSpine._ensure_curve() then Curve3D.get_closest_offset()
	# both re-run). Sampled once here and threaded through to both.
	var progress := _spine.progress_for_position(_kart.global_position)
	_update_wrong_way(delta_s, progress)
	_update_player_follower(progress, delta_s)


func _route_input() -> void:
	_input_adapter.apply_move(_router.buffer.movement(), _kart)
	var hop_held := _router.buffer.is_action_pressed(InputIntent.ACTION_JUMP)
	if hop_held != _hop_was_pressed:
		if hop_held:
			_input_adapter.apply_hop_pressed(_kart)
		else:
			_input_adapter.apply_hop_released(_kart)
		_hop_was_pressed = hop_held
	# R4 Task 2/4: ITEM is a fire-once action (see racing_input_adapter.gd's
	# apply_item_pressed() doc) -- only the false -> true edge routes to the
	# kart, mirroring HOP's own edge-sampling above but with no release
	# counterpart, so holding the button down never re-fires use_item()
	# every tick. apply_item_pressed() now returns whichever item name
	# KartController.use_item() handed back (Task 3's own return-name-only
	# path); Task 4 routes that name through dispatch_item_use() -- see its
	# own doc for why this is the SAME shared entry point Task 5's AI
	# item-use decision is documented to call through too.
	var item_held := _router.buffer.is_action_pressed(InputIntent.ACTION_ITEM)
	if item_held and not _item_was_pressed:
		var used_item: StringName = _input_adapter.apply_item_pressed(_kart)
		dispatch_item_use(_kart, used_item)
	_item_was_pressed = item_held


func _update_wrong_way(delta_s: float, progress: float) -> void:
	var wrong_now := _spine.is_wrong_way(_kart.velocity, progress)
	if wrong_now:
		_wrong_way_elapsed_s += delta_s
	else:
		_wrong_way_elapsed_s = 0.0
	_wrong_way_flag = _wrong_way_elapsed_s >= _race_tuning.wrong_way_grace_s


## Binding contract 3: the player's own continuous SpineFollower total,
## updated every tick exactly like every AiKartAgent already updates its own
## private one (see ai_kart_agent.gd's _physics_process). max_step_m mirrors
## AiKartAgent._max_follower_step_m()'s own derivation -- the true physical
## ceiling on how far THIS kart can travel in one tick -- minus the AI-only
## rubber_band_boost_max_ratio factor, since the player is never rubber-
## banded (that is an AI-catch-up mechanic; see ai_driver.gd's RUBBER BAND
## section). Using only tuning fields, no new literal, per this file's own
## no-bare-literal rule. Fix-wave LOW-6: raw_progress is sampled ONCE per
## tick by the caller (_physics_process) and threaded through here and into
## _update_wrong_way() rather than each calling _spine.progress_for_position()
## independently -- same projection, same result, computed once instead of
## twice a tick.
func _update_player_follower(raw_progress: float, delta_s: float) -> void:
	var max_step_m := (
		(_kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps) * delta_s
	)
	_player_follower.update(raw_progress, max_step_m)


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


## Binding contract 2 (seam ruling): gates route to a validator by BODY
## IDENTITY, looked up in _gate_validators -- never by assuming "the only
## body that can ever enter a gate is the player's Kart", which stopped
## being true the moment AI karts started sharing these same Area3D
## triggers (CheckpointGate.monitoring is forced on for exactly this: see
## checkpoint_gate.gd's own class doc). Every kart's own validator advances
## on every crossing, unconditionally; only the PLAYER's crossing goes on to
## drive lap-time bookkeeping and the finish sequence below -- an AI kart's
## own validator exists so ITS gate sequence is tracked correctly (tests can
## observe it via ai_kart_progress_gates()), not because an AI kart can ever
## "finish" the race on its own in this task.
func _on_gate_body_entered(body: Node, gate: CheckpointGate) -> void:
	if _finished:
		return
	var validator: LapValidatorType = _gate_validators.get(body)
	if validator == null:
		return
	var outcome := validator.gate_crossed(gate.gate_index)
	if body != _kart:
		return
	if outcome != &"lap_complete" and outcome != &"race_complete":
		return
	var now_elapsed := elapsed_s()
	_lap_times.append(now_elapsed - _last_lap_boundary_s)
	_last_lap_boundary_s = now_elapsed
	if outcome == &"race_complete":
		_finish_race(now_elapsed)


## See the class doc's ITEM BOX WIRING and SOLO TIME TRIAL DOES NOT ROLL
## sections. Routes straight to the entering body's OWN ItemSlot -- no
## per-kart lookup table, unlike gate crossings' _gate_validators, since the
## body passed in by the native body_entered signal already IS the kart
## whose slot must roll; player and AI karts take the exact same path here.
## A body with no item_slot() method (a stray non-kart Area3D/body, or a
## bare test fixture) is silently ignored rather than erroring.
func _on_box_body_entered(body: Node) -> void:
	if not _items_allowed():
		return
	if body == null or not is_instance_valid(body) or not body.has_method("item_slot"):
		return
	var slot: Object = body.call("item_slot")
	if slot == null:
		return
	slot.call("start_roll", _item_rng.randf())


## See the class doc's SOLO TIME TRIAL DOES NOT ROLL section.
func _items_allowed() -> bool:
	return spawn_opponents


func _discover_item_boxes() -> Array[ItemBox]:
	var result: Array[ItemBox] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is ItemBox:
			result.append(candidate as ItemBox)
	return result


## Binding contract 3: player finish placement = 1 + the number of AI karts
## whose own SpineFollower total_progress_m() exceeds the player's, sampled
## at this exact finish instant -- seam-safe by construction since both
## sides of every comparison are continuous SpineFollower totals (see the
## class doc's own "seam ruling" note on _player_follower/_gate_validators),
## never a raw, seam-ambiguous spine offset.
##
## Freezes EVERY kart (set_run_active(false), player included -- H2 review's
## original "stop it driving into the walls / force-end a mid-finish slide"
## fix, now reused for every AI kart too) BEFORE reading any AI kart's
## progress, so no kart can keep accruing distance between the placement
## read and the freeze actually taking effect. AiKartAgent's own
## is_run_active() gate (Task 5 binding contract 1) is what makes freezing
## an AI kart here safe -- a frozen AI kart's stuck-detector never fires and
## never silently reactivates it; set_physics_process(false) on top of that
## is belt-and-braces, an explicit "stop ticking at all" rather than relying
## solely on the gate reading false every tick forever.
func _finish_race(now_elapsed: float) -> void:
	_finished = true
	_final_elapsed_s = now_elapsed
	# H2 review: nothing else stops the kart driving into the walls behind
	# the finish line under its own auto-throttle, and a finish caught
	# mid-slide would otherwise leave the slide latched forever. See
	# KartController.set_run_active()'s doc for exactly what this does; the
	# camera is deliberately left alone so its own easing keeps settling the
	# finish shot.
	_kart.call("set_run_active", false)
	for ai_kart: CharacterBody3D in _ai_karts:
		ai_kart.call("set_run_active", false)

	var player_total := _player_follower.total_progress_m()
	_placement = 1
	for agent: AiKartAgentType in _ai_agents:
		if float(agent.call("total_progress_m")) > player_total:
			_placement += 1

	for agent: AiKartAgentType in _ai_agents:
		agent.set_physics_process(false)

	race_finished.emit(_final_elapsed_s, _lap_times.duplicate())


## Shared "place the transform, then seed yaw as an independent step"
## sequence -- see configure()'s own HIGH-1 fix-wave doc for the original
## player-only bug this fixed, and _spawn_ai_karts() for the AI reuse
## the Task 5 brief calls for ("the spawn-yaw seeding path must keep
## working -- reuse it per kart").
func _seed_kart_transform(kart: CharacterBody3D, marker: Marker3D) -> void:
	kart.global_transform = marker.global_transform
	var spawn_forward := -marker.global_transform.basis.z
	kart.call(
		"set_yaw_degrees",
		rad_to_deg(Vector3.FORWARD.signed_angle_to(spawn_forward, Vector3.UP))
	)


## R4 Task 4 (CARRIED MEDIUM fix -- see _spawn_ai_karts()'s own SPAWN-
## TRANSFORM ORDERING doc for the probe-confirmed hazard this closes):
## the same "place the transform, then seed yaw" sequence as
## _seed_kart_transform() above, but usable on a kart that is NOT YET
## inside the tree (no parent of its own yet) -- composing against
## parent.global_transform.affine_inverse() rather than assigning kart.
## global_transform directly (which, for an orphan node, treats the parent
## chain as identity and would silently double-apply the real parent's own
## global transform once actually added as a child, unless that parent
## chain truly is world-identity). `parent` (_ai_root) is guaranteed
## already inside the tree by the time _spawn_ai_karts() calls this, so
## its own global_transform is a valid, already-resolved reference to
## compose against.
func _seed_kart_transform_for_parent(
	kart: CharacterBody3D, marker: Marker3D, parent: Node3D
) -> void:
	kart.transform = parent.global_transform.affine_inverse() * marker.global_transform
	var spawn_forward := -marker.global_transform.basis.z
	kart.call(
		"set_yaw_degrees",
		rad_to_deg(Vector3.FORWARD.signed_angle_to(spawn_forward, Vector3.UP))
	)


func _make_lap_validator() -> LapValidatorType:
	var validator := LapValidatorType.new()
	validator.configure(_gates.size(), int(_race_tuning.lap_count))
	return validator


## Fix-wave MEDIUM-4: every OTHER kart's current global_position -- the
## Callable each AiKartAgent receives (bound to ITS OWN kart, see
## _spawn_ai_karts()) as other_kart_positions_getter, so a stuck-respawn
## teleport never drops a kart on top of the player or another AI kart. This
## session is the one place that already knows every kart in the race (the
## same reason it already owns player_total_progress_m() for binding
## contract 3), so the avoidance check is handed the same shape of Callable
## rather than reaching past this session into physics overlap queries.
func _other_kart_positions(requesting_kart: CharacterBody3D) -> Array:
	var positions: Array = []
	if _kart != null and _kart != requesting_kart:
		positions.append(_kart.global_position)
	for other_kart: CharacterBody3D in _ai_karts:
		if other_kart != requesting_kart:
			positions.append(other_kart.global_position)
	return positions


## Spawns AiTuning.opponent_count AI karts (a real kart.tscn instance + a
## real, configured AiKartAgent each) on GridSlot1..N under Track -- slot 0
## is the player's own KartSpawn, untouched (see configure()'s own doc).
##
## GRID SLOTS. Both track scenes author 5 Marker3D GridSlot1..GridSlot5
## behind the start line (see scenes/racing/track_graybox_loop.tscn and
## track_sanity_shores.tscn, and the racing-track lint's track_grid_slots
## rule) -- a fixed count matching ai.tres's own opponent_count=5.0 default,
## same "the lint has no runtime access to a tuning resource" rationale
## TRACK_ROAD_WIDTH_M already documents for the gate-width rule. Fix-wave
## LOW-8: an earlier revision also authored a GridSlot0 at the exact same
## transform as the existing KartSpawn marker -- a pure duplicate that was
## never read here (the player always spawns from KartSpawn itself, see
## configure()'s own doc on why THAT marker is not renamed) and existed only
## to visually mark "this is where slot 0 sits". Deleted from both tracks
## (and every lint fixture that authored one) as a redundant second source
## of truth for the exact same transform; KartSpawn alone remains authoritative
## for the player's own spawn, and this function still only ever reads
## GridSlot1..N. A missing GridSlotN marker for a configured slot fails
## closed (push_error + skip that one slot, never a crash) rather than
## assuming every track always has enough slots for whatever opponent_count
## happens to be tuned to.
##
## RETRY / RE-CONFIGURE SAFETY. The real retry path (RaceHUD -> request_retry
## -> GameRoot re-selecting the level, see retry_requested's own doc) frees
## this entire scene and instantiates a fresh one, so every AI kart/agent
## (ordinary scene children) dies with it automatically -- no special
## cleanup needed for that path. This function is defensively idempotent
## anyway (clears and rebuilds _ai_root's children first) so a hypothetical
## second configure() call on the SAME instance never leaks or duplicates
## karts either.
##
## SPAWN-TRANSFORM ORDERING (R4 Task 4, CARRIED MEDIUM, probe-confirmed
## hazard): each kart's full spawn transform is now built via
## _seed_kart_transform_for_parent() BEFORE add_child() ever runs, not
## after (the shape this loop used until this fix). A freshly-instantiated
## CharacterBody3D that enters the tree still at its Transform3D.IDENTITY
## default registers a REAL, one-instant physics-server broadphase
## snapshot at that position the moment add_child() runs -- before any
## later transform write in the same script tick can reach it -- exactly
## the mechanism test_item_box.gd's own _new_kart_body()/_new_box() doc
## already empirically confirmed for a dynamically-added fixture (Godot/
## Jolt can queue a body_entered delivery from that one-instant placement
## for a LATER physics frame, well after this function has already moved
## the kart to its real GridSlotN position). An origin-adjacent Area3D --
## an item box authored near a track's own origin, or any future hazard
## sharing that space -- could register a transient, permanently-sticky
## pickup/trigger against that one-frame flash. Locked with a regression
## test (test_race_session.gd's test_spawning_ai_karts_does_not_flash_a_
## kart_through_the_track_origin).
func _spawn_ai_karts() -> void:
	if _ai_root == null:
		_ai_root = Node3D.new()
		_ai_root.name = "AiKarts"
		add_child(_ai_root)
	else:
		for child in _ai_root.get_children():
			_gate_validators.erase(child)
			child.queue_free()

	_ai_karts.clear()
	_ai_agents.clear()

	# Fix-wave MEDIUM-5: spawn_opponents owns solo-ness, not opponent_count
	# itself -- see the exported field's own doc.
	var opponent_count := int(_ai_tuning.opponent_count) if spawn_opponents else 0
	for slot_index in range(1, opponent_count + 1):
		var marker := _track.get_node_or_null("GridSlot%d" % slot_index) as Marker3D
		if marker == null:
			push_error(
				(
					"RaceSession._spawn_ai_karts: no GridSlot%d marker found "
					+ "under Track -- skipping this AI slot (fail closed: "
					+ "fewer AI karts than opponent_count, never a crash)."
				) % slot_index
			)
			continue

		var ai_kart := KartSceneType.instantiate() as CharacterBody3D
		# See this function's own SPAWN-TRANSFORM ORDERING doc: configure()
		# and the transform seed both happen BEFORE add_child(), so the
		# kart's very first physics-server registration already carries its
		# real GridSlotN position -- never a one-frame flash at the origin.
		ai_kart.call("configure", _kart_tuning, _item_tuning)
		_seed_kart_transform_for_parent(ai_kart, marker, _ai_root)
		_ai_root.add_child(ai_kart)

		_gate_validators[ai_kart] = _make_lap_validator()

		var agent := AiKartAgentType.new()
		ai_kart.add_child(agent)
		agent.call(
			"configure",
			ai_kart,
			_spine,
			_ai_tuning,
			_kart_tuning,
			_race_tuning,
			slot_index,
			Callable(self, "player_total_progress_m"),
			# Fix-wave MEDIUM-4: see ai_kart_agent.gd's own RESPAWN-ONTO-PLAYER
			# AVOIDANCE doc -- bound per kart so each agent's own blocking
			# check never sees ITS OWN position in the "other karts" list.
			Callable(self, "_other_kart_positions").bind(ai_kart)
		)

		_ai_karts.append(ai_kart)
		_ai_agents.append(agent)
