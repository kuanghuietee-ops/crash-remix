class_name UnlockRules
extends RefCounted

const WARP_ROOM_FOUR_PREFIX := "wr4_"


static func phase_unlocked(profile: Dictionary) -> bool:
	if not SaveModel.validate(profile):
		return false
	var levels_value: Variant = profile.get("levels")
	if not levels_value is Dictionary:
		return false
	var levels := levels_value as Dictionary
	for level_id_value: Variant in levels:
		var level_id := String(level_id_value)
		if not level_id.begins_with(WARP_ROOM_FOUR_PREFIX):
			continue
		if bool(
			SaveModel.level_record(
				profile,
				StringName(level_id)
			).get("completed", false)
		):
			return true
	return false
