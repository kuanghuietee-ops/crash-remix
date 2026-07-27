class_name PapuPapuArena
extends Node3D

## Scene glue for the Papu Papu gauntlet. All fight rules live in the pure
## BossFightFlow (01-DESIGN §4.14, spec §8.2); this node only turns real
## Area3D overlaps into strikes and reports the result back.

const BossFightFlowType := preload(
	"res://src/gameplay/boss/boss_fight_flow.gd"
)

## Emitted when the last phase is cleared. LevelSession turns this into the
## level's completion, so victory follows the same path as any other finish.
signal boss_defeated

@export var strike_trigger_paths: Array[NodePath] = []

var _flow: BossFightFlowType = BossFightFlowType.new()
var _player: Node3D
var _triggers_connected := false


func _ready() -> void:
	add_to_group(&"papu_arena")


func configure(player: Node3D, tuning: BossTuning) -> void:
	_player = player
	_flow.configure(tuning)
	_connect_strike_triggers()


func current_phase() -> int:
	return _flow.current_phase()


func checkpoint_phase() -> int:
	return _flow.checkpoint_phase()


func strikes_this_phase() -> int:
	return _flow.strikes_this_phase()


func is_defeated() -> bool:
	return _flow.is_defeated()


func on_player_death() -> void:
	_flow.on_player_death()


func _connect_strike_triggers() -> void:
	if _triggers_connected:
		return
	for trigger_path: NodePath in strike_trigger_paths:
		var trigger := get_node_or_null(trigger_path) as Area3D
		if trigger == null:
			continue
		if not trigger.body_entered.is_connected(
			_on_strike_trigger_body_entered
		):
			trigger.body_entered.connect(
				_on_strike_trigger_body_entered
			)
	_triggers_connected = true


func _on_strike_trigger_body_entered(body: Node3D) -> void:
	# A non-player body must change nothing, and a won fight must not keep
	# accumulating strikes.
	if body != _player or _flow.is_defeated():
		return
	_flow.register_strike()
	if _flow.is_defeated():
		boss_defeated.emit()
