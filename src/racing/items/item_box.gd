class_name ItemBox
extends Area3D

## Item pickup trigger (R4 Task 3, CTR item loop). Graybox Area3D + small
## floating box mesh (scenes/racing/item_box.tscn) that hides itself and
## starts its own box_respawn_s countdown the instant a kart's body enters
## it, then reappears once the countdown elapses -- entirely self-contained,
## the same "own script manages its own node state" shape checkpoint_gate.gd
## keeps for gate_index, just with actual hide/respawn behavior of its own
## instead of checkpoint_gate.gd's "passive data carrier, zero behavior".
##
## MONITORING DEFAULTS mirror checkpoint_gate.gd exactly (see its own class
## doc): monitoring forced on, monitorable forced off in _ready().
##
## BODY FILTER -- collision bit 3 (value 4), NOT checkpoint_gate.gd's own
## "just leave layer/mask at the Area3D default" shape. Discovered
## empirically while building this scene: checkpoint gates sit at y=2, well
## above the track floor/walls' own collision extents, so their default
## mask=1 (matching kart.tscn's own default collision_layer=1) never
## actually overlaps anything BUT a kart in practice. An item box sits at
## ground level with a box_pickup_radius_m-sized SphereShape3D (items.tres:
## 1.6m) that DOES reach into the floor/walls -- which also default to
## layer 1 (Godot's own CollisionObject3D default), since nothing in this
## repo's own graybox track authoring sets collision_layer explicitly (see
## track_graybox_loop.tscn's Floor/Walls StaticBody3D nodes) -- so a plain
## mask=1 filter picks up the floor itself as a "kart", permanently marking
## the box inactive before any real kart ever reaches it. kart.tscn's own
## CharacterBody3D carries collision_layer = 5 (bit 1, unchanged, for its
## ordinary floor/wall/checkpoint-gate collision -- see kart.tscn and
## checkpoint_gate.gd -- PLUS bit 3, added specifically for this filter);
## item_box.tscn's own collision_mask = 4 (bit 3 ONLY, not bit 1) so this
## Area3D can ONLY ever be entered by something actually tagged as a kart,
## never the environment. Bit 2 was deliberately left alone: it is already
## the platformer subsystem's own "hazard/enemy" detection channel (see
## scenes/player/player.tscn's hurtbox collision_mask = 2 and scenes/
## enemies/*.tscn's collision_layer = 3) -- an entirely separate scene
## domain from racing that never shares a physics world with this one, but
## reusing its bit here would still read as a false cross-reference to
## anyone auditing collision layers project-wide.
##
## EMITS NOTHING OF ITS OWN, same as checkpoint_gate.gd: RaceSession
## connects to this node's native body_entered signal itself (the "gate
## pattern" -- see race_session.gd's own gate-wiring precedent) to route a
## pickup to the entering kart's own ItemSlot.start_roll(). This script's
## OWN body_entered connection (wired here in _ready(), not by a caller) is
## a SEPARATE listener on the exact same native signal, responsible only for
## this node's own hide/respawn bookkeeping -- it never reaches into a kart
## or an ItemSlot. Both listeners fire off the same underlying signal
## delivery for a given pickup; which one runs first does not matter, since
## neither depends on the other having already run.
##
## RESPAWN TIMING. No Godot Timer node -- like every other timed system in
## src/racing/** (RaceSession.elapsed_s(), AiKartAgent's stuck-window,
## DriftStateMachine's own slide/window timers), this just accumulates
## delta_s in its own _physics_process against box_respawn_s, gated by
## process_mode = PROCESS_MODE_PAUSABLE (set in _ready(), the same "a paused
## tree must not leak wall-clock-equivalent progress" contract race_session.
## gd's own class doc documents for itself) so a paused game doesn't
## silently respawn a box in the background.
##
## While hidden, monitoring is off -- Godot's own physics server stops
## reporting overlaps for this Area3D entirely, so a kart that never leaves
## the pickup's volume during the hidden window will re-trigger body_entered
## the instant monitoring flips back on (if it is still sitting there when
## the countdown elapses). That is accepted, intended behavior (parking on
## a respawning box keeps refilling it), not a bug this script guards
## against.

var _tuning: ItemTuning
var _active: bool = true
var _respawning: bool = false
var _respawn_elapsed_s: float


func _ready() -> void:
	monitoring = true
	monitorable = false
	process_mode = Node.PROCESS_MODE_PAUSABLE
	body_entered.connect(_on_body_entered)


## Applies box_pickup_radius_m to this box's own pickup shape -- the tuning
## value is the single source of truth, same "the tuning loop must be
## provably live" contract every other tuning consumer in this repo honors.
## Assigns a BRAND NEW SphereShape3D rather than mutating collision.shape's
## radius in place: item_box.tscn's own CollisionShape3D.shape is an
## ordinary embedded sub-resource, which Godot shares across EVERY instance
## of this PackedScene (confirmed empirically -- instantiate() does not
## duplicate it unless explicitly marked resource_local_to_scene), so
## mutating it in place would silently resize every OTHER ItemBox instance
## too, including ones on a different track or in a different test's
## fixture. The scene's authored shape type is still read as a hint (a
## non-SphereShape3D, or a missing CollisionShape3D entirely -- a bare test
## fixture -- is left alone rather than guessed at), just never mutated.
func configure(item_tuning: ItemTuning) -> void:
	_tuning = item_tuning
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not (collision.shape is SphereShape3D):
		return
	var sphere := SphereShape3D.new()
	sphere.radius = item_tuning.box_pickup_radius_m
	collision.shape = sphere


## Whether this box currently has an item to give -- false while hidden and
## counting down to respawn. Exposed for HUD/effects polish and test
## observability; RaceSession's own pickup routing does not need to consult
## this (it trusts the native body_entered signal itself, which only ever
## fires while monitoring is on, i.e. exactly while this reads true).
func is_active() -> bool:
	return _active


func _physics_process(delta_s: float) -> void:
	if not _respawning:
		return
	_respawn_elapsed_s += delta_s
	if _tuning != null and _respawn_elapsed_s >= _tuning.box_respawn_s:
		_reappear()


## monitoring is set via set_deferred(), not a direct assignment: this
## handler runs synchronously from INSIDE the physics server's own signal
## dispatch for this exact Area3D (confirmed at runtime -- Godot raises
## "Function blocked during in/out signal" on a direct write here), which
## locks monitoring changes on the area currently being processed until
## that dispatch finishes. Deferring the write until the next idle frame
## (still well within the same or next physics step, long before any
## caller could observe a stale monitoring=true) avoids the lock entirely.
func _on_body_entered(_body: Node) -> void:
	if not _active:
		return
	_active = false
	visible = false
	set_deferred("monitoring", false)
	_respawning = true
	_respawn_elapsed_s = 0.0


func _reappear() -> void:
	_active = true
	visible = true
	monitoring = true
	_respawning = false
	_respawn_elapsed_s = 0.0
