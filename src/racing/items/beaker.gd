extends Node3D

## R4 Task 4 (CTR item loop): CTR-style dropped hazard (the classic "Nitro
## Beaker" left behind a kart). A thin Node that owns its own state
## directly -- see missile.gd's own class doc for why no separate pure-logic
## core and no class_name (nothing needs to `is Beaker`-check this node;
## race_session.gd only ever preloads its scene's PackedScene and wires it
## via duck-typed .call()).
##
## SPAWN POSITION is entirely the CALLER's decision (RaceSession.
## _spawn_beaker(), not this file): the launcher's own position minus its
## own forward vector times one kart length, read from the launcher's real
## BoxShape3D collision extents -- the exact derivation ai_kart_agent.gd's
## own _read_kart_extents() already uses for its respawn-avoidance
## stepping (see the task brief's own "derive from kart collision extents
## like the respawn stepper did"). This node has no opinion on where it
## starts, only what happens once it's there.
##
## ARM DELAY / LAUNCHER IMMUNITY. Before beaker_arm_delay_s elapses, no hit
## test runs against ANY kart at all -- the same "arm delay is a total
## hit-test gate, not merely a launcher exemption" shape missile.gd uses.
## Because of that shared gate, the launcher is naturally immune ONLY while
## unarmed: once armed, EVERY kart in the race becomes a valid target,
## INCLUDING the launcher itself -- the classic CTR self-beaker, and the
## one real behavioral difference from missile.gd's own PERMANENT launcher
## exclusion (a missile can never hit its own launcher, arming or not; a
## beaker can, once armed).
##
## STATIC. No movement and no steering of any kind -- global_position is
## set once by the caller before configure() and never touched again by
## this script.
##
## LIFETIME. Despawns (queue_free) once beaker_lifetime_s has elapsed with
## no hit, or immediately on any hit, mirroring missile.gd's own shape.

var _session: Object
var _launcher: CharacterBody3D
var _tuning: ItemTuning

var _all_karts: Array[CharacterBody3D] = []

var _elapsed_s: float
var _armed: bool = false
var _configured: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## session/targets_getter: same duck-typed session double and Callable
## shape as missile.gd's own configure() -- see its doc. Beaker only ever
## needs the KART identities out of the snapshot (never the "progress"
## field -- see the class doc's own "spatial distance, not SpineFollower
## totals" rule, matching missile.gd's identical choice), captured ONCE
## here since a race's own kart roster never changes mid-race. UNLIKE
## missile.gd's own _candidate_karts, the launcher is deliberately kept IN
## this roster -- see the class doc's ARM DELAY / LAUNCHER IMMUNITY
## section for why exclusion is unnecessary (the shared arm-delay gate
## already protects it pre-arm, and post-arm it must be a valid target).
func configure(
	session: Object,
	launcher_kart: CharacterBody3D,
	item_tuning: ItemTuning,
	targets_getter: Callable
) -> void:
	_session = session
	_launcher = launcher_kart
	_tuning = item_tuning
	_elapsed_s = 0.0
	_armed = false

	_all_karts.clear()
	if targets_getter.is_valid():
		for entry: Variant in targets_getter.call():
			var kart: CharacterBody3D = entry.get("kart")
			if kart != null:
				_all_karts.append(kart)

	_configured = true


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return
	_elapsed_s += delta_s
	if _elapsed_s >= _tuning.beaker_lifetime_s:
		queue_free()
		return
	if not _armed and _elapsed_s >= _tuning.beaker_arm_delay_s:
		_armed = true
	if _armed:
		_check_hits()


## See the class doc's ARM DELAY / LAUNCHER IMMUNITY section -- only ever
## called once _armed, at which point every kart (launcher included) is a
## valid target. The FIRST candidate found within beaker_hit_radius_m wins,
## same undefined-tie-break shape as missile.gd's own _check_hits().
func _check_hits() -> void:
	for kart: CharacterBody3D in _all_karts:
		if kart == null or not is_instance_valid(kart):
			continue
		var distance_m := (kart.global_position - global_position).length()
		if distance_m <= _tuning.beaker_hit_radius_m:
			if _session != null and is_instance_valid(_session):
				_session.call("register_hit", kart)
			queue_free()
			return
