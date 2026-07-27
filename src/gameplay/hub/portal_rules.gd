class_name PortalRules
extends RefCounted

const KIND_LEVEL := &"level"
const KIND_BOSS := &"boss"
const KIND_UNKNOWN := &"unknown"
const RELIC_NONE := &"none"
const BOSS_ID := &"wr1_papu_papu"
const LEVEL_IDS: Array[StringName] = [
	&"wr1_n_sanity_beach",
	&"wr1_boulders",
	&"wr1_hog_wild",
]


static func state_for(
	portal_id: StringName,
	profile: Dictionary,
	available_level_ids: Array[StringName]
) -> Dictionary:
	if portal_id in LEVEL_IDS:
		if not SaveModel.validate(profile):
			return _closed_state(portal_id, KIND_LEVEL)
		var record := SaveModel.level_record(profile, portal_id)
		return {
			"portal_id": portal_id,
			"kind": KIND_LEVEL,
			"unlocked": portal_id in available_level_ids,
			"completed": bool(record.get("completed", false)),
			"gem": bool(record.get("gem", false)),
			"relic_tier": StringName(
				record.get("relic_tier", RELIC_NONE)
			),
			"flawless": bool(record.get("flawless", false)),
		}
	if portal_id == BOSS_ID:
		if not SaveModel.validate(profile):
			return _closed_state(portal_id, KIND_BOSS)
		var boss_value: Variant = profile.get("boss_defeated", {})
		var boss_defeated := (
			boss_value as Dictionary
			if boss_value is Dictionary
			else {}
		)
		return {
			"portal_id": portal_id,
			"kind": KIND_BOSS,
			"unlocked": boss_unlocked(profile),
			"completed": bool(
				boss_defeated.get("papu_papu", false)
			),
			"gem": false,
			"relic_tier": RELIC_NONE,
			"flawless": false,
		}
	return _closed_state(portal_id, KIND_UNKNOWN)


## Why a portal is shut, in words the player can act on, or "" when it is open.
## warp_room sets portal.monitoring = unlocked and a non-monitoring trigger
## ignores the player, so without this a locked door and a broken one are
## indistinguishable from the hub.
static func locked_reason(
	portal_id: StringName,
	profile: Dictionary
) -> String:
	if portal_id != BOSS_ID or boss_unlocked(profile):
		return ""
	var remaining := 0
	for level_id: StringName in LEVEL_IDS:
		if not bool(
			SaveModel.level_record(
				profile,
				level_id
			).get("completed", false)
		):
			remaining += 1
	if remaining == 1:
		return "CLEAR 1 MORE LEVEL"
	return "CLEAR " + str(remaining) + " MORE LEVELS"


static func boss_unlocked(profile: Dictionary) -> bool:
	if not SaveModel.validate(profile):
		return false
	for level_id: StringName in LEVEL_IDS:
		if not bool(
			SaveModel.level_record(
				profile,
				level_id
			).get("completed", false)
		):
			return false
	return true


static func portal_ids() -> Array[StringName]:
	var result := LEVEL_IDS.duplicate()
	result.append(BOSS_ID)
	return result


static func _closed_state(
	portal_id: StringName,
	kind: StringName
) -> Dictionary:
	return {
		"portal_id": portal_id,
		"kind": kind,
		"unlocked": false,
		"completed": false,
		"gem": false,
		"relic_tier": RELIC_NONE,
		"flawless": false,
	}
