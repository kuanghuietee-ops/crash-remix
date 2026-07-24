class_name BreakableCrate
extends StaticBody3D

signal broken(crate_id: int, wumpa: int)
signal bounced(crate_id: int, wumpa: int, launch_speed_mps: float)

const CrateLogicType := preload(
	"res://src/gameplay/crates/crate_logic.gd"
)

@export var crate_id: int
@export var segment_group: StringName
@export var crate_type: StringName = CrateLogicType.TYPE_STANDARD

var _economy: EconomyTuning
var _move: MoveTuning
var _input: InputTuning
var _broken: bool = false
var _bounce_count: int = 0


func configure(
	economy: EconomyTuning,
	move: MoveTuning = null,
	input: InputTuning = null
) -> void:
	_economy = economy
	_move = move
	_input = input


func apply_verb(verb: StringName) -> Dictionary:
	if _broken or _economy == null:
		return _inactive_result()
	var result := CrateLogicType.break_result(
		crate_type,
		verb,
		_economy
	)
	if result["breaks"]:
		_finish_break(int(result["wumpa"]))
	return result


func apply_bounce(jump_press_offset_s: float) -> Dictionary:
	if (
		_broken
		or _economy == null
		or _move == null
		or _input == null
	):
		return _inactive_bounce_result()
	if crate_type != CrateLogicType.TYPE_BOUNCE:
		var contact_result := apply_verb(CrateLogicType.VERB_BOUNCE)
		if not contact_result["bounces_player"]:
			return _inactive_bounce_result()
		var iron_launch_speed := CrateLogicType.bounce_launch_speed(
			jump_press_offset_s,
			_economy,
			_move,
			_input
		)
		bounced.emit(crate_id, 0, iron_launch_speed)
		return {
			"wumpa": 0,
			"breaks": false,
			"launch_speed_mps": iron_launch_speed,
		}

	_bounce_count += 1
	var step := CrateLogicType.bounce_step(_bounce_count, _economy)
	var launch_speed := CrateLogicType.bounce_launch_speed(
		jump_press_offset_s,
		_economy,
		_move,
		_input
	)
	bounced.emit(crate_id, int(step["wumpa"]), launch_speed)
	if step["breaks"]:
		_finish_break(0)
	return {
		"wumpa": step["wumpa"],
		"breaks": step["breaks"],
		"launch_speed_mps": launch_speed,
	}


func is_broken() -> bool:
	return _broken


func _finish_break(wumpa: int) -> void:
	if _broken:
		return
	_broken = true
	$Mesh.visible = false
	$CollisionShape3D.set_deferred(&"disabled", true)
	broken.emit(crate_id, wumpa)


func _inactive_result() -> Dictionary:
	return {
		"breaks": false,
		"wumpa": 0,
		"detonates": false,
		"bounces_player": false,
	}


func _inactive_bounce_result() -> Dictionary:
	return {
		"wumpa": 0,
		"breaks": false,
		"launch_speed_mps": 0.0,
	}
