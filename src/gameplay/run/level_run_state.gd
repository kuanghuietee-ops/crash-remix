class_name LevelRunState
extends RefCounted

const MODE_NORMAL := &"normal"
const MODE_RELIC := &"relic"
const START_CHECKPOINT: int = -1

var meta: LevelMeta
var mode: StringName = MODE_NORMAL
var authored_crate_ids: Array[int] = []
var broken_crate_ids: Array[int] = []
var wumpa_run: int = 0
var masks: int = 0
var checkpoint_id: int = START_CHECKPOINT
var deaths_at_checkpoint: int = 0
var flawless: bool = true
var gem_void: bool = false
var relic_void: bool = false
var run_active: bool = false


func start(level_meta: LevelMeta, run_mode: StringName) -> void:
	meta = level_meta
	mode = run_mode
	authored_crate_ids.clear()
	var crate_id := 1
	while meta != null and crate_id <= meta.crate_count:
		authored_crate_ids.append(crate_id)
		crate_id += 1
	_reset_run_values()
	run_active = (
		meta != null
		and mode in [MODE_NORMAL, MODE_RELIC]
	)


func register_authored_crate_ids(crate_ids: Array[int]) -> void:
	authored_crate_ids.clear()
	for crate_id: int in crate_ids:
		if crate_id >= 0 and crate_id not in authored_crate_ids:
			authored_crate_ids.append(crate_id)
	authored_crate_ids.sort()


func record_crate_broken(crate_id: int, wumpa: int) -> void:
	if (
		not run_active
		or crate_id not in authored_crate_ids
		or crate_id in broken_crate_ids
	):
		return
	broken_crate_ids.append(crate_id)
	broken_crate_ids.sort()
	record_wumpa_collected(wumpa)


func record_wumpa_collected(amount: int) -> void:
	if run_active and amount > 0:
		wumpa_run += amount


func record_mask_granted(amount: int) -> void:
	if run_active and amount > 0:
		masks += amount


func record_checkpoint(crate_id: int) -> void:
	if (
		not run_active
		or mode == MODE_RELIC
		or crate_id == checkpoint_id
	):
		return
	checkpoint_id = crate_id
	deaths_at_checkpoint = 0


func record_death(economy: EconomyTuning) -> Dictionary:
	var outcome := {
		"respawn_checkpoint": checkpoint_id,
		"grant_mercy_mask": false,
		"offer_skip": false,
		"relic_void_reset": false,
	}
	if not run_active:
		return outcome

	masks = 0
	if mode == MODE_RELIC:
		_reset_attempt()
		relic_void = true
		outcome["respawn_checkpoint"] = START_CHECKPOINT
		outcome["relic_void_reset"] = true
		return outcome

	flawless = false
	deaths_at_checkpoint += 1
	outcome["grant_mercy_mask"] = (
		deaths_at_checkpoint == economy.mercy_mask_death_threshold
	)
	outcome["offer_skip"] = (
		deaths_at_checkpoint >= economy.mercy_skip_death_threshold
	)
	return outcome


func accept_mercy_skip(next_checkpoint_id: int) -> bool:
	if not run_active or mode != MODE_NORMAL:
		return false
	checkpoint_id = next_checkpoint_id
	deaths_at_checkpoint = 0
	gem_void = true
	relic_void = true
	return true


func record_level_complete(_economy: EconomyTuning) -> Dictionary:
	if not run_active or meta == null:
		return {}
	var missing_ids := _missing_crate_ids()
	var collected_all := (
		broken_crate_ids.size() == meta.crate_count
		and missing_ids.is_empty()
	)
	var result := {
		"level_id": meta.level_id,
		"mode": mode,
		"box_count": broken_crate_ids.size(),
		"crate_count": meta.crate_count,
		"missing_crate_ids": missing_ids,
		"gem": (
			mode == MODE_NORMAL
			and collected_all
			and not gem_void
		),
		"flawless": mode == MODE_NORMAL and flawless,
		"wumpa_banked": wumpa_run,
		"gem_void": gem_void,
		"relic_void": relic_void,
	}
	_discard_run()
	return result


func record_exit() -> void:
	_discard_run()


func snapshot() -> Dictionary:
	if not run_active or meta == null:
		return {}
	return {
		"level_id": meta.level_id,
		"mode": mode,
		"checkpoint_index": checkpoint_id,
		"authored_crate_ids": authored_crate_ids.duplicate(),
		"crates_broken": broken_crate_ids.duplicate(),
		"wumpa_run": wumpa_run,
		"masks": masks,
		"deaths_at_checkpoint": deaths_at_checkpoint,
		"gem_void": gem_void,
		"relic_void": relic_void,
		"flawless": flawless,
	}


static func restore(
	saved: Dictionary,
	level_meta: LevelMeta
) -> LevelRunState:
	var restored := LevelRunState.new()
	var mode_value: Variant = saved.get("mode")
	var restored_mode := (
		StringName(mode_value)
		if (
			typeof(mode_value) == TYPE_STRING
			or typeof(mode_value) == TYPE_STRING_NAME
		)
		else MODE_NORMAL
	)
	restored.start(level_meta, restored_mode)
	if not restored.run_active:
		return restored

	var level_id_value: Variant = saved.get("level_id")
	if (
		level_meta == null
		or (
			typeof(level_id_value) != TYPE_STRING
			and typeof(level_id_value) != TYPE_STRING_NAME
		)
		or StringName(level_id_value) != level_meta.level_id
	):
		restored.record_exit()
		return restored

	var authored_value: Variant = saved.get("authored_crate_ids")
	if authored_value is Array:
		restored.register_authored_crate_ids(
			_int_array(authored_value)
		)

	if restored_mode == MODE_RELIC:
		restored.relic_void = true
		return restored

	var broken_value: Variant = saved.get("crates_broken")
	if broken_value is Array:
		for crate_id: int in _int_array(broken_value):
			if crate_id in restored.authored_crate_ids:
				restored.broken_crate_ids.append(crate_id)
		restored.broken_crate_ids.sort()
	restored.wumpa_run = _non_negative_int(
		saved.get("wumpa_run")
	)
	restored.masks = _non_negative_int(saved.get("masks"))
	restored.deaths_at_checkpoint = _non_negative_int(
		saved.get("deaths_at_checkpoint")
	)
	var checkpoint_value: Variant = saved.get(
		"checkpoint_index",
		START_CHECKPOINT
	)
	if _is_integer(checkpoint_value):
		restored.checkpoint_id = int(checkpoint_value)
	restored.gem_void = bool(saved.get("gem_void", false))
	restored.relic_void = bool(saved.get("relic_void", false))
	restored.flawless = bool(saved.get("flawless", true))
	return restored


func _missing_crate_ids() -> Array[int]:
	var result: Array[int] = []
	for crate_id: int in authored_crate_ids:
		if crate_id not in broken_crate_ids:
			result.append(crate_id)
	return result


func _reset_attempt() -> void:
	broken_crate_ids.clear()
	wumpa_run = 0
	masks = 0
	checkpoint_id = START_CHECKPOINT
	deaths_at_checkpoint = 0


func _reset_run_values() -> void:
	_reset_attempt()
	flawless = true
	gem_void = false
	relic_void = false
	run_active = false


func _discard_run() -> void:
	_reset_run_values()
	run_active = false


static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		if _is_integer(value):
			var integer_value := int(value)
			if integer_value not in result:
				result.append(integer_value)
	result.sort()
	return result


static func _non_negative_int(value: Variant) -> int:
	return maxi(int(value), 0) if _is_integer(value) else 0


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return is_finite(numeric_value) and numeric_value == floor(numeric_value)
