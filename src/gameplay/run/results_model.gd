class_name ResultsModel
extends RefCounted

const _UNASSIGNED_SEGMENT := "Unassigned"


func build(
	run_result: Dictionary,
	meta: LevelMeta,
	segment_by_crate_id: Dictionary,
	previous_level_record: Dictionary
) -> Dictionary:
	if meta == null:
		return {}
	var missed_ids := _int_array(
		run_result.get("missing_crate_ids", [])
	)
	var mode := StringName(
		run_result.get("mode", LevelRunState.MODE_NORMAL)
	)
	var completed_before := bool(
		previous_level_record.get("completed", false)
	)
	var relic_void := bool(
		run_result.get("relic_void", false)
	)
	return {
		"level_id": meta.level_id,
		"display_name": meta.display_name,
		"mode": mode,
		"box_count": maxi(
			int(run_result.get("box_count", 0)),
			0
		),
		"crate_count": meta.crate_count,
		"gem": bool(run_result.get("gem", false)),
		"missed_crate_ids": missed_ids,
		"missed_crate_ids_by_segment": (
			_group_misses(missed_ids, segment_by_crate_id)
		),
		"flawless": bool(
			run_result.get("flawless", false)
		),
		"wumpa_banked": maxi(
			int(run_result.get("wumpa_banked", 0)),
			0
		),
		"ghost_marker_ids": (
			_ghost_ids_from_record(previous_level_record)
		),
		"relic_time_s": (
			run_result.get("relic_time_s")
			if mode == LevelRunState.MODE_RELIC
			else null
		),
		"relic_tier": (
			run_result.get("relic_tier")
			if mode == LevelRunState.MODE_RELIC
			else null
		),
		"relic_void": relic_void,
		"relic_entry_available": (
			LevelRunState.relic_pars_authored(meta)
			and not relic_void
			and (
				completed_before
				or mode == LevelRunState.MODE_NORMAL
			)
		),
	}


func relic_entry_available(
	meta: LevelMeta,
	level_record: Dictionary
) -> bool:
	return (
		bool(level_record.get("completed", false))
		and LevelRunState.relic_pars_authored(meta)
	)


func persisted_profile(
	profile: Dictionary,
	payload: Dictionary,
	level_meta: LevelMeta
) -> Dictionary:
	if not SaveModel.validate(profile):
		return {}
	var level_id_value: Variant = payload.get("level_id")
	if (
		typeof(level_id_value) != TYPE_STRING
		and typeof(level_id_value) != TYPE_STRING_NAME
	):
		return {}
	var level_id := StringName(level_id_value)
	if level_id.is_empty():
		return {}
	var mode_value: Variant = payload.get(
		"mode",
		LevelRunState.MODE_NORMAL
	)
	if (
		typeof(mode_value) != TYPE_STRING
		and typeof(mode_value) != TYPE_STRING_NAME
	):
		return {}
	var mode := StringName(mode_value)
	if mode not in [
		LevelRunState.MODE_NORMAL,
		LevelRunState.MODE_RELIC,
	]:
		return {}

	var updated := profile.duplicate(true)
	var record := SaveModel.level_record(updated, level_id)
	if (
		mode == LevelRunState.MODE_RELIC
		and not bool(record.get("completed", false))
	):
		return {}

	if mode == LevelRunState.MODE_NORMAL:
		record["completed"] = true
		record["gem"] = (
			bool(record.get("gem", false))
			or bool(payload.get("gem", false))
		)
		record["flawless"] = (
			bool(record.get("flawless", false))
			or bool(payload.get("flawless", false))
		)
		record["last_missed_crate_ids"] = _int_array(
			payload.get("missed_crate_ids", [])
		)
	else:
		if not bool(payload.get("relic_void", false)):
			var relic_time_value: Variant = payload.get(
				"relic_time_s"
			)
			if (
				typeof(relic_time_value) != TYPE_FLOAT
				and typeof(relic_time_value) != TYPE_INT
			):
				return {}
			if (
				level_meta == null
				or level_meta.level_id != level_id
			):
				return {}
			record = SaveModel.improved_relic_record(
				record,
				float(relic_time_value),
				level_meta
			)
			if record.is_empty():
				return {}
	var levels: Dictionary = updated["levels"]
	levels[String(level_id)] = record
	if mode == LevelRunState.MODE_NORMAL:
		updated["lifetime_wumpa"] = (
			int(updated.get("lifetime_wumpa", 0))
			+ maxi(
				int(payload.get("wumpa_banked", 0)),
				0
			)
		)
	return updated if SaveModel.validate(updated) else {}


func ghost_marker_ids(
	profile: Dictionary,
	level_id: StringName
) -> Array[int]:
	if not SaveModel.validate(profile):
		return []
	return _ghost_ids_from_record(
		SaveModel.level_record(profile, level_id)
	)


func _group_misses(
	missed_ids: Array[int],
	segment_by_crate_id: Dictionary
) -> Dictionary:
	var grouped: Dictionary = {}
	for crate_id: int in missed_ids:
		var segment_value: Variant = segment_by_crate_id.get(
			crate_id,
			segment_by_crate_id.get(
				str(crate_id),
				_UNASSIGNED_SEGMENT
			)
		)
		var segment_name := String(segment_value)
		if segment_name.is_empty():
			segment_name = _UNASSIGNED_SEGMENT
		if not grouped.has(segment_name):
			grouped[segment_name] = []
		var ids: Array = grouped[segment_name]
		ids.append(crate_id)
	for segment_name: Variant in grouped:
		var ids: Array = grouped[segment_name]
		ids.sort()
	return grouped


func _ghost_ids_from_record(
	level_record: Dictionary
) -> Array[int]:
	if bool(level_record.get("gem", false)):
		return []
	return _int_array(
		level_record.get("last_missed_crate_ids", [])
	)


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for candidate: Variant in value:
		if not _is_integer(candidate):
			continue
		var integer_value := int(candidate)
		if integer_value >= 0 and integer_value not in result:
			result.append(integer_value)
	result.sort()
	return result


func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return (
		is_finite(numeric_value)
		and numeric_value == floor(numeric_value)
	)
