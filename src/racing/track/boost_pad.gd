class_name BoostPad
extends Area3D

## Track-authored speed-boost trigger (Task 1, CTR R7 -- discharges spec
## debt #2). Graybox Area3D + flat glowing quad strip (scenes/racing/
## boost_pad.tscn). Mirrors item_box.gd's own class-doc shape one file over
## in src/racing/items/: a small, self-contained Area3D that RaceSession
## discovers by TYPE/SCRIPT scan under Track (_discover_boost_pads(), the
## same find_children("*", "Area3D", true, false) scan _discover_gates()/
## _discover_item_boxes() already use) and connects its own body_entered
## listener onto, gated on is_race_started -- see race_session.gd's own PAD
## WIRING doc.
##
## UNLIKE item_box.gd, this node owns NO hide/respawn state of its own (a
## boost pad has no "used up" concept -- CTR-style pads fire on every real
## pass, just not on every single physics tick of an overlap): the only
## state this script keeps is the PER-KART refire cooldown try_consume()
## below gates on. RaceSession's own connected handler is the SOLE caller
## of try_consume() and the sole place that actually calls
## KartController.apply_boost() -- this script never touches a kart
## directly, the same "own script manages its own node state, the SESSION
## applies the actual gameplay effect" split checkpoint_gate.gd/item_box.gd
## already establish (see item_box.gd's own class doc for the fullest
## statement of that split).
##
## MONITORING DEFAULTS mirror checkpoint_gate.gd/item_box.gd exactly:
## monitoring forced on, monitorable forced off in _ready().
##
## BODY FILTER -- collision bit 3 (value 4), the exact same kart-only mask
## item_box.tscn's own Area3D uses (see item_box.gd's own class doc BODY
## FILTER section for the full "why bit 3, not bit 1" rationale: a graybox
## floor/wall StaticBody3D defaults to layer 1, which a plain mask=1 filter
## would also match at ground level).
##
## COOLDOWN TIMING. No Godot Timer node, and no wall clock -- like every
## other timed system in src/racing/** (RaceSession.elapsed_s(), item_box.
## gd's own box_respawn_s countdown, AiKartAgent's stuck-window), this
## accumulates delta_s in its own _physics_process against an internal
## elapsed clock, gated by process_mode = PROCESS_MODE_PAUSABLE (set in
## _ready(), the same "a paused tree must not leak wall-clock-equivalent
## progress" contract item_box.gd's own class doc documents for itself) so
## a paused game doesn't silently let a cooldown expire in the background.
## try_consume() keys its refire-cooldown Dictionary by the entering kart's
## OWN get_instance_id() (Task 1 brief's own "instance-id keyed timestamps"
## shape) rather than by node reference directly -- an int key is a cheap,
## stable Dictionary key that survives exactly as long as the kart itself
## does, which is the whole lifetime this cooldown needs to track.
##
## VISUAL (scenes/racing/boost_pad.tscn): a flat QuadMesh strip laid on the
## road (rotated to face up), unshaded with emission enabled -- the same
## "flat, unshaded, glowing" material shape kart.tscn's own boost-flame
## particle material (kart_fx.gd's own Material_flame) already establishes
## for this repo's glow effects, rather than the flag/banner kit's own
## albedo-texture-atlas-cell shape (track_sanity_shores.tscn's own
## StandardMaterial3D_flag_* resources): those sample a FIXED, single-kit
## texture (T_beach_kit_atlas.png), which would tie this track-agnostic,
## reusable pad asset to one specific env kit that a different future track
## (e.g. Temple Twilight's own interior kit) would never share. A flat
## authored albedo_color IS this asset's own "palette cell" -- one flat,
## deliberately chosen, unmixed color per pad TYPE (see boost_pad.tscn's
## own warm-orange vs jump_pad.tscn's own cool-cyan), the same single-flat-
## region-per-part shading language build_kart.py's own vertex-painted
## "BODY" cell already uses (see item_box.gd's own class doc), just applied
## through a material color instead of vertex paint since this asset has no
## authored mesh of its own to paint.

var _tuning: RaceTuning
var _elapsed_s: float
var _last_fire_elapsed_by_kart_id: Dictionary = {}


func _ready() -> void:
	monitoring = true
	monitorable = false
	process_mode = Node.PROCESS_MODE_PAUSABLE


func configure(race_tuning: RaceTuning) -> void:
	_tuning = race_tuning


func _physics_process(delta_s: float) -> void:
	_elapsed_s += delta_s


## Returns whether THIS pad should fire for `kart` right now, and -- if so
## -- atomically claims the cooldown window (records this instant as the
## kart's own last-fire timestamp) so a caller never has to pair this with
## a separate "mark fired" call the way a check-then-set race could
## otherwise slip between. A kart id never seen before always fires (no
## sentinel sits in the Dictionary for it yet, so the cooldown comparison
## below is skipped entirely -- mirrors race_session.gd's own -1.0 "no
## data yet" sentinel shape for the identical "first time, nothing to
## compare against" case).
func try_consume(kart: Node) -> bool:
	if _tuning == null or kart == null:
		return false
	var kart_id := kart.get_instance_id()
	var last_fire_elapsed_s: float = _last_fire_elapsed_by_kart_id.get(kart_id, -1.0)
	if (
		last_fire_elapsed_s >= 0.0
		and _elapsed_s - last_fire_elapsed_s < _tuning.pad_refire_cooldown_s
	):
		return false
	_last_fire_elapsed_by_kart_id[kart_id] = _elapsed_s
	return true
