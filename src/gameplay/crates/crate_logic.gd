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
	if crate_type == TYPE_IRON:
		result["bounces_player"] = verb == VERB_BOUNCE
		return result
	if crate_type == TYPE_BOUNCE:
		if verb == VERB_BOUNCE:
			result["bounces_player"] = true
		elif verb in _ATTACK_VERBS:
			result["breaks"] = true
		return result
	if crate_type == TYPE_STANDARD and verb in _ATTACK_VERBS:
		result["breaks"] = true
		result["wumpa"] = economy.wumpa_per_standard_crate
	return result


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
