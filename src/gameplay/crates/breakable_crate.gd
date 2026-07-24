class_name BreakableCrate
extends StaticBody3D

signal broken(crate_id: int, wumpa: int)
signal bounced(crate_id: int, wumpa: int, launch_speed_mps: float)
signal fuse_started(crate_id: int, deadline_s: float)
signal detonated(crate_id: int, origin: Vector3)
signal checkpoint_reached(crate_id: int)
signal mask_granted(amount: int)
signal time_awarded(seconds: float)

const CrateLogicType := preload(
	"res://src/gameplay/crates/crate_logic.gd"
)

@export var crate_id: int
@export var segment_group: StringName
@export var crate_type: StringName = CrateLogicType.TYPE_STANDARD
@export var time_crate_size: StringName = CrateLogicType.TIME_SMALL

var _economy: EconomyTuning
var _move: MoveTuning
var _input: InputTuning
var _broken: bool = false
var _bounce_count: int = 0
var _armed: bool = true
var _fuse_active: bool = false
var _fuse_started_at_s: float = 0.0


func _ready() -> void:
	if crate_type == CrateLogicType.TYPE_TIME:
		set_relic_context(false)


func configure(
	economy: EconomyTuning,
	move: MoveTuning = null,
	input: InputTuning = null,
	relic_mode: bool = false
) -> void:
	_economy = economy
	_move = move
	_input = input
	if crate_type == CrateLogicType.TYPE_TIME:
		set_relic_context(relic_mode)


func apply_verb(
	verb: StringName,
	now_s: float = 0.0
) -> Dictionary:
	if _broken or not _armed or _economy == null:
		return _inactive_result()
	var result := CrateLogicType.break_result(
		crate_type,
		verb,
		_economy
	)
	if crate_type == CrateLogicType.TYPE_TNT:
		var contact := CrateLogicType.tnt_contact_result(
			verb,
			_economy
		)
		if contact["starts_fuse"]:
			start_tnt_fuse(now_s)
		if result["detonates"]:
			_detonate()
		return result
	if result["breaks"]:
		if crate_type == CrateLogicType.TYPE_CHECKPOINT:
			checkpoint_reached.emit(crate_id)
		elif crate_type == CrateLogicType.TYPE_AKU:
			mask_granted.emit(1)
		elif crate_type == CrateLogicType.TYPE_TIME:
			time_awarded.emit(CrateLogicType.time_bonus_s(
				time_crate_size,
				_economy
			))
		_finish_break(int(result["wumpa"]))
	return result


func apply_bounce(
	jump_press_offset_s: float,
	now_s: float = 0.0
) -> Dictionary:
	if (
		_broken
		or _economy == null
		or _move == null
		or _input == null
	):
		return _inactive_bounce_result()
	if crate_type != CrateLogicType.TYPE_BOUNCE:
		var contact_result := apply_verb(
			CrateLogicType.VERB_BOUNCE,
			now_s
		)
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


func apply_blast(now_s: float) -> Dictionary:
	if _broken or not _armed or _economy == null:
		return _inactive_blast_result()
	var result := CrateLogicType.blast_result(crate_type, _economy)
	apply_verb(CrateLogicType.VERB_BLAST, now_s)
	return result


func start_tnt_fuse(now_s: float) -> bool:
	if (
		crate_type != CrateLogicType.TYPE_TNT
		or _broken
		or _economy == null
		or _fuse_active
	):
		return false
	_fuse_active = true
	_fuse_started_at_s = now_s
	fuse_started.emit(crate_id, tnt_fuse_deadline_s())
	return true


func advance_fuse(now_s: float) -> bool:
	if not _fuse_active or _economy == null:
		return false
	if not CrateLogicType.tnt_fuse_elapsed(
		_fuse_started_at_s,
		now_s,
		_economy
	):
		return false
	_detonate()
	return true


func tnt_fuse_active() -> bool:
	return _fuse_active


func tnt_fuse_deadline_s() -> float:
	if not _fuse_active or _economy == null:
		return 0.0
	return CrateLogicType.tnt_fuse_deadline(
		_fuse_started_at_s,
		_economy
	)


func set_relic_context(relic_mode: bool) -> void:
	if crate_type != CrateLogicType.TYPE_TIME:
		_armed = true
		return
	_armed = relic_mode and not _broken
	$Mesh.visible = _armed
	$CollisionShape3D.set_deferred(&"disabled", not _armed)


func is_armed() -> bool:
	return _armed


func is_broken() -> bool:
	return _broken


func _detonate() -> void:
	if _broken:
		return
	_fuse_active = false
	_finish_break(0)
	detonated.emit(crate_id, global_position)


func _finish_break(wumpa: int) -> void:
	if _broken:
		return
	_broken = true
	_fuse_active = false
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


func _inactive_blast_result() -> Dictionary:
	return {
		"breaks": false,
		"collected": false,
		"starts_fuse": false,
		"fuse_s": 0.0,
	}
