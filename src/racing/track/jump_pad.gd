class_name JumpPad
extends Area3D

## Track-authored vertical-launch trigger (Task 1, CTR R7 -- discharges spec
## debt #2). Graybox Area3D + flat glowing quad strip (scenes/racing/
## jump_pad.tscn). Mirrors boost_pad.gd's own class-doc shape exactly --
## see that script's own doc for the full rationale (RaceSession discovery/
## wiring shape, the "own script manages ONLY the cooldown, the session
## applies the actual gameplay effect" split, monitoring defaults, body
## filter, and the no-wall-clock cooldown timing). The only difference
## between the two pad scripts is WHICH kart method the session's own
## connected handler calls once try_consume() claims the window --
## KartController.apply_boost(pad_boost_s) there, KartController.launch(
## jump_pad_velocity_scale) here -- and this file's own configure() reads
## RaceTuning the identical way, so nothing below duplicates that doc.

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


## See boost_pad.gd's own try_consume() doc -- identical shape, kept as an
## independent copy rather than a shared base class the same way item_box.
## gd and checkpoint_gate.gd stay independent Area3D scripts rather than
## sharing one (this repo's own established "small, self-contained Area3D
## triggers, no inheritance hierarchy between them" convention).
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
