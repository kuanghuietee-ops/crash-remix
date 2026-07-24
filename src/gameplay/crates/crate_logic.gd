class_name CrateLogic
extends RefCounted

const JumpKinematicsType := preload(
	"res://src/gameplay/player/jump_kinematics.gd"
)

const TYPE_STANDARD := &"standard"
const TYPE_BOUNCE := &"bounce"
const TYPE_IRON := &"iron"
const TYPE_CHECKPOINT := &"checkpoint"
const TYPE_TNT := &"tnt"
const TYPE_AKU := &"aku"
const TYPE_TIME := &"time"

const VERB_SPIN := &"spin"
const VERB_JUMP_UNDER := &"jump_under"
const VERB_SLAM := &"slam"
const VERB_SLIDE := &"slide"
const VERB_BOUNCE := &"bounce"
const VERB_TOUCH := &"touch"
const VERB_BLAST := &"blast"

const TIME_SMALL := &"small"
const TIME_MEDIUM := &"medium"
const TIME_LARGE := &"large"

const _ATTACK_VERBS: Array[StringName] = [
	VERB_SPIN,
	VERB_JUMP_UNDER,
	VERB_SLAM,
	VERB_SLIDE,
]


static func break_result(
	crate_type: StringName,
	verb: StringName,
	economy: EconomyTuning
) -> Dictionary:
	var result := _empty_break_result()
	if crate_type == TYPE_TNT:
		var contact := tnt_contact_result(verb, economy)
		result["detonates"] = contact["detonates"]
		result["bounces_player"] = contact["bounces_player"]
		result["breaks"] = contact["detonates"]
		return result
	if crate_type == TYPE_IRON:
		result["bounces_player"] = verb == VERB_BOUNCE
		return result
	if crate_type == TYPE_BOUNCE:
		if verb == VERB_BOUNCE:
			result["bounces_player"] = true
		elif verb in _ATTACK_VERBS or verb == VERB_BLAST:
			result["breaks"] = true
		return result
	if (
		crate_type == TYPE_STANDARD
		and (verb in _ATTACK_VERBS or verb == VERB_BLAST)
	):
		result["breaks"] = true
		result["wumpa"] = economy.wumpa_per_standard_crate
		return result
	if (
		crate_type in [TYPE_CHECKPOINT, TYPE_AKU, TYPE_TIME]
		and (verb in _ATTACK_VERBS or verb == VERB_BLAST)
	):
		result["breaks"] = true
	return result


static func tnt_contact_result(
	verb: StringName,
	economy: EconomyTuning
) -> Dictionary:
	var starts_fuse := verb in [VERB_TOUCH, VERB_BOUNCE, VERB_BLAST]
	return {
		"starts_fuse": starts_fuse,
		"fuse_s": economy.tnt_fuse_s if starts_fuse else 0.0,
		"detonates": verb == VERB_SPIN,
		"bounces_player": verb == VERB_BOUNCE,
	}


static func tnt_fuse_deadline(
	started_at_s: float,
	economy: EconomyTuning
) -> float:
	return started_at_s + economy.tnt_fuse_s


static func tnt_fuse_elapsed(
	started_at_s: float,
	now_s: float,
	economy: EconomyTuning
) -> bool:
	return now_s >= tnt_fuse_deadline(started_at_s, economy)


static func blast_crate_ids(
	origin: Vector3,
	crate_positions: Dictionary,
	economy: EconomyTuning
) -> Array[int]:
	var affected: Array[int] = []
	var radius_squared := (
		economy.tnt_blast_radius_m * economy.tnt_blast_radius_m
	)
	for crate_id: Variant in crate_positions:
		if typeof(crate_id) != TYPE_INT:
			continue
		var position_value: Variant = crate_positions[crate_id]
		if typeof(position_value) != TYPE_VECTOR3:
			continue
		var crate_position: Vector3 = position_value
		if origin.distance_squared_to(crate_position) <= radius_squared:
			affected.append(crate_id)
	affected.sort()
	return affected


static func blast_result(
	crate_type: StringName,
	economy: EconomyTuning
) -> Dictionary:
	var break_info := break_result(crate_type, VERB_BLAST, economy)
	var tnt_contact := tnt_contact_result(VERB_BLAST, economy)
	var starts_fuse: bool = (
		crate_type == TYPE_TNT and tnt_contact["starts_fuse"]
	)
	return {
		"breaks": break_info["breaks"],
		"collected": break_info["breaks"],
		"starts_fuse": starts_fuse,
		"fuse_s": tnt_contact["fuse_s"] if starts_fuse else 0.0,
	}


static func time_bonus_s(
	size: StringName,
	economy: EconomyTuning
) -> float:
	match size:
		TIME_SMALL:
			return economy.time_crate_small_s
		TIME_MEDIUM:
			return economy.time_crate_medium_s
		TIME_LARGE:
			return economy.time_crate_large_s
	return 0.0


static func bounce_step(
	bounce_count: int,
	economy: EconomyTuning
) -> Dictionary:
	if bounce_count <= 0:
		return {
			"wumpa": 0,
			"breaks": false,
		}
	if bounce_count > economy.bounce_crate_max_bounces:
		return {
			"wumpa": 0,
			"breaks": true,
		}
	return {
		"wumpa": economy.bounce_crate_wumpa_per_bounce,
		"breaks": bounce_count >= economy.bounce_crate_max_bounces,
	}


static func bounce_launch_speed(
	jump_press_offset_s: float,
	economy: EconomyTuning,
	move: MoveTuning,
	input: InputTuning
) -> float:
	var within_timing_window := (
		absf(jump_press_offset_s) <= maxf(input.bounce_timing_s, 0.0)
	)
	var launch_height_m := (
		economy.bounce_launch_height_m
		if within_timing_window
		else move.jump_full_height_m
	)
	return JumpKinematicsType.upward_speed_for_height(
		launch_height_m,
		move
	)


static func _empty_break_result() -> Dictionary:
	return {
		"breaks": false,
		"wumpa": 0,
		"detonates": false,
		"bounces_player": false,
	}
