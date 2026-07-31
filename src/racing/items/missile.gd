extends Node3D

## R4 Task 4 (CTR item loop): CTR-style homing missile projectile. A thin
## Node that owns its own state directly -- like item_box.gd/checkpoint_
## gate.gd, a single-purpose hazard's own tick/hit/despawn bookkeeping does
## not need to be split into a separate, reusable pure-logic core the way
## KartMotor/DriftStateMachine's shared, cross-consumer math does. No
## class_name (see race_session.gd's own preload of this scene's
## PackedScene + duck-typed .call() wiring -- CheckpointGate/ItemBox need a
## real class_name because race_session.gd type-scans FOR them under Track;
## nothing ever needs to `is Missile`-check this node, so there is no
## reason to pay Task 3's own documented ".godot/global_script_class_cache.
## cfg needs a rebuild" tax for one that would go unused).
##
## LAUNCH-TIME TARGET LOCK. configure() calls targets_getter EXACTLY ONCE
## (never again for the rest of this missile's life) to snapshot every kart
## currently in the race plus each one's own SpineFollower total_progress_m()
## -- the same seam-safe shape (see spine_follower.gd's own class doc)
## RaceSession already assembles for finish placement (race_session.gd's
## _item_targets()). The locked target is whichever OTHER kart has the
## smallest strictly-positive (its own progress - the launcher's own
## progress) margin -- the nearest kart truly AHEAD of the launcher at the
## instant of firing. Real CTR missiles do not retarget mid-flight even if
## a different kart later pulls closer or overtakes; if nothing is ahead
## (the launcher is already in the lead), there is no target at all and
## this missile flies straight for its whole lifetime, still armed and
## lethal to anything it happens to reach.
##
## PURSUIT STEERING, every tick while a target is still locked and still a
## valid instance: turns (horizontal-only, the same ground-vehicle
## convention kart_motor.gd's own yaw uses) toward the target's LIVE
## global_position, capped at missile_turn_rate_degrees_per_s * delta_s per
## tick via Vector3.signed_angle_to() + rotate_y() -- a bounded turn, not an
## instant snap, so a target far enough off this missile's own launch axis
## can out-turn it and force a miss followed by a lifetime expiry.
##
## HIT DETECTION uses real spatial (Euclidean) distance against every OTHER
## candidate kart's live global_position -- deliberately NOT the
## SpineFollower totals the launch-time targeting snapshot uses ("how far
## along the track" is the wrong notion of "close enough to explode"; see
## the task brief's own "radius check vs SpineFollower is wrong here, use
## spatial distance" note) -- and only once ARMED (missile_arm_delay_s
## after launch): before that, no hit test runs against ANY kart at all, so
## a kart already sitting within missile_hit_radius_m of the launch point
## (e.g. tailgating right behind the launcher) is not insta-detonated the
## instant this missile spawns. The LAUNCHER itself is additionally
## excluded from the hit-candidate roster PERMANENTLY, arming or not (built
## once at configure() time, see _candidate_karts) -- a stronger, structural
## guarantee on top of the arm-delay gate, matching the brief's own "no
## self-hit before arming; never hits the launcher".
##
## LIFETIME. Despawns (queue_free) once missile_lifetime_s has elapsed with
## no hit, or immediately on any hit -- session.register_hit()'s own
## returned outcome (&"blocked"/&"invulnerable"/&"spin_out") is read but
## never changes whether THIS missile itself despawns; a missile is spent
## the instant it reaches anyone, blocked or not.

var _session: Object
var _launcher: CharacterBody3D
var _tuning: ItemTuning

var _locked_target: CharacterBody3D
var _candidate_karts: Array[CharacterBody3D] = []

var _elapsed_s: float
var _armed: bool = false
var _configured: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## session: duck-typed (only ever needs register_hit(target) -> StringName,
## called via .call() below) rather than typed against RaceSession
## directly, so this is testable against a small fake double with no scene
## tree involved -- the same shape racing_input_adapter.gd's own controller
## parameter uses.
##
## targets_getter: Callable -> Array[Dictionary], each entry shaped
## {"kart": CharacterBody3D, "progress": float} -- the exact shape
## race_session.gd's own _item_targets() builds. Called exactly once, right
## here, to lock the launch-time target and snapshot the full non-launcher
## candidate roster used for the rest of this missile's hit-testing -- see
## the class doc's own LAUNCH-TIME TARGET LOCK section for why this Callable
## is never invoked again after this call.
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

	var snapshot: Array = targets_getter.call() if targets_getter.is_valid() else []

	_candidate_karts.clear()
	var launcher_progress := 0.0
	var have_launcher_progress := false
	for entry: Variant in snapshot:
		var kart: CharacterBody3D = entry.get("kart")
		if kart == _launcher:
			launcher_progress = float(entry.get("progress", 0.0))
			have_launcher_progress = true
			continue
		if kart != null:
			_candidate_karts.append(kart)

	_locked_target = null
	if have_launcher_progress:
		var best_margin := INF
		for entry: Variant in snapshot:
			var kart: CharacterBody3D = entry.get("kart")
			if kart == null or kart == _launcher:
				continue
			var margin: float = float(entry.get("progress", 0.0)) - launcher_progress
			if margin > 0.0 and margin < best_margin:
				best_margin = margin
				_locked_target = kart

	_configured = true


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return
	_elapsed_s += delta_s
	if _elapsed_s >= _tuning.missile_lifetime_s:
		queue_free()
		return
	if not _armed and _elapsed_s >= _tuning.missile_arm_delay_s:
		_armed = true

	_steer_toward_target(delta_s)
	global_position += (-global_transform.basis.z) * _tuning.missile_speed_mps * delta_s

	if _armed:
		_check_hits()


## See the class doc's PURSUIT STEERING section. A no-op while there is no
## locked target (the leaderless "flies straight" case) or the locked
## target instance has since been freed.
func _steer_toward_target(delta_s: float) -> void:
	if _locked_target == null or not is_instance_valid(_locked_target):
		return
	var forward := -global_transform.basis.z
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.is_zero_approx():
		return
	var to_target := _locked_target.global_position - global_position
	var flat_to_target := Vector3(to_target.x, 0.0, to_target.z)
	if flat_to_target.is_zero_approx():
		return

	var max_turn_radians := deg_to_rad(_tuning.missile_turn_rate_degrees_per_s * delta_s)
	var angle_radians := flat_forward.normalized().signed_angle_to(
		flat_to_target.normalized(), Vector3.UP
	)
	rotate_y(clampf(angle_radians, -max_turn_radians, max_turn_radians))


## See the class doc's HIT DETECTION section. Only ever called while
## _armed; the FIRST candidate kart found within missile_hit_radius_m wins
## (undefined which, if several are simultaneously in range -- a graybox-
## era edge case, not a gameplay-critical ordering).
func _check_hits() -> void:
	for kart: CharacterBody3D in _candidate_karts:
		if kart == null or not is_instance_valid(kart):
			continue
		var distance_m := (kart.global_position - global_position).length()
		if distance_m <= _tuning.missile_hit_radius_m:
			if _session != null and is_instance_valid(_session):
				_session.call("register_hit", kart)
			queue_free()
			return
