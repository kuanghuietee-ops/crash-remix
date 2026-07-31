extends Node3D

## CTR R6 Task 5 (new items): CTR-style lobbed bomb. A thin Node that owns
## its own state directly -- see missile.gd's/beaker.gd's own class docs for
## why no separate pure-logic core and no class_name (nothing needs to `is
## Bomb`-check this node; race_session.gd only ever preloads its scene's
## PackedScene and wires it via duck-typed .call()).
##
## SPAWN POSITION/FACING is entirely the caller's decision (RaceSession.
## _spawn_bomb(), not this file): the launcher's own global_transform, no
## offset -- the same "no offset" choice missile.gd's own SPAWN section
## makes, since a lob's own initial upward arc clears the launcher's own
## position within a fraction of a second regardless.
##
## LAUNCH GEOMETRY. configure() reads the launcher's own forward vector
## (-global_transform.basis.z, already seeded onto this node by the caller
## BEFORE configure() runs, the same ordering missile.gd/beaker.gd already
## rely on) and blends it evenly with Vector3.UP: `(forward + Vector3.UP).
## normalized() * bomb_speed_mps`. Two EQUAL-MAGNITUDE unit components
## (forward and up, both weight 1) is an analytic 45-degree launch angle by
## construction -- no bare angle literal (src/racing/**'s own numeric-
## literal lint bans everything outside 0/1/-1, see CLAUDE.md) and no new
## angle tuning field either; Vector3.UP is a Godot built-in constant, not a
## literal. Vertical motion afterward integrates real gravity
## (kart_tuning.gravity_mps2, read fresh every tick the same
## `v -= g * delta_s` identity kart_motor.gd's own airborne integration
## uses) -- a real ballistic parabola, not a scripted arc.
##
## ARM DELAY / LAUNCHER IMMUNITY. Before bomb_arm_delay_s elapses, no
## contact/explosion check of any kind runs -- the same "arm delay is a
## total hit-test gate, not merely a launcher exemption" shape missile.gd/
## beaker.gd already use. In practice this never matters for ground contact
## (the bomb is still rising for its first fraction of a second under a
## 45-degree launch, so it can never dip back to spawn height before
## bomb_arm_delay_s elapses at any tuned bomb_speed_mps), but it DOES matter
## for kart contact: a kart tailgating right at the launch point is not
## insta-detonated the instant this bomb spawns. Once armed, EVERY kart in
## the race is a valid blast target, INCLUDING the launcher -- the classic
## CTR self-bomb (the task brief's own "launcher included post-arm").
##
## GROUND CONTACT is a flat-track graybox simplification: "touched the
## ground" is read as `global_position.y <= spawn_y` (the height it launched
## from), not a real raycast/collision query -- consistent with beaker.gd's
## own "no ground-snapping of any kind" choice and missile.gd's own flat
## flight, neither of which follows terrain either.
##
## BLAST. Once armed, EVERY physics tick checks every candidate kart's real
## spatial (Euclidean) distance against bomb_blast_radius_m -- unlike
## missile.gd's/beaker.gd's own "first candidate found wins, then despawn"
## shape, a bomb's explosion registers a hit against EVERY kart within
## radius in the SAME explosion (the task brief's own "register_hit EVERY
## kart within bomb_blast_radius_m"), then despawns once, regardless of how
## many karts it just hit (zero, one, or several). The same radius doubles
## as both the "did I touch a kart" contact trigger and the blast damage
## radius -- a single field, not two, since a contact-worthy proximity and a
## blast-worthy proximity are the same distance for a lobbed explosive.
##
## LIFETIME. Reuses beaker_lifetime_s (see item_tuning.gd's own Bomb
## category doc for why there is no separate bomb_lifetime_s field) as a
## safety-net despawn for the pathological case of a bomb that never
## touches ground or a kart (queue_free with no register_hit calls at all).

var _session: Object
var _launcher: CharacterBody3D
var _tuning: ItemTuning
var _kart_tuning: KartTuning

var _all_karts: Array[CharacterBody3D] = []

var _velocity: Vector3
var _spawn_y: float
var _elapsed_s: float
var _armed: bool = false
var _configured: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## session/targets_getter: same duck-typed session double and Callable
## shape as missile.gd's/beaker.gd's own configure() -- see their own docs.
## kart_tuning is the one new parameter neither of those needs: this file's
## own LAUNCH GEOMETRY section reads gravity_mps2 off it every tick.
func configure(
	session: Object,
	launcher_kart: CharacterBody3D,
	item_tuning: ItemTuning,
	kart_tuning: KartTuning,
	targets_getter: Callable
) -> void:
	_session = session
	_launcher = launcher_kart
	_tuning = item_tuning
	_kart_tuning = kart_tuning
	_elapsed_s = 0.0
	_armed = false
	_spawn_y = global_position.y

	var forward := -global_transform.basis.z
	_velocity = (forward + Vector3.UP).normalized() * _tuning.bomb_speed_mps

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
	if not _armed and _elapsed_s >= _tuning.bomb_arm_delay_s:
		_armed = true

	_velocity.y -= _kart_tuning.gravity_mps2 * delta_s
	global_position += _velocity * delta_s

	if _armed and (global_position.y <= _spawn_y or _touching_any_kart()):
		_explode()


## See the class doc's GROUND CONTACT/BLAST sections -- shares bomb_blast_
## radius_m with _explode() below, but only needs to know THAT a contact
## happened, not who; the real per-kart hit list is (re)computed in
## _explode() itself the instant this returns true.
func _touching_any_kart() -> bool:
	for kart: CharacterBody3D in _all_karts:
		if kart == null or not is_instance_valid(kart):
			continue
		if (kart.global_position - global_position).length() <= _tuning.bomb_blast_radius_m:
			return true
	return false


## See the class doc's BLAST section: every candidate within bomb_blast_
## radius_m gets register_hit, not just the first found.
func _explode() -> void:
	for kart: CharacterBody3D in _all_karts:
		if kart == null or not is_instance_valid(kart):
			continue
		if (kart.global_position - global_position).length() <= _tuning.bomb_blast_radius_m:
			if _session != null and is_instance_valid(_session):
				_session.call("register_hit", kart)
	queue_free()
