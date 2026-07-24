class_name SessionSnapshot
extends RefCounted

const _PRIMARY_FILE := "session.json"
const _TEMP_FILE := "session.json.tmp"

var discarded_corrupt: bool = false


func store(save_dir: String, run_snapshot: Dictionary) -> Error:
	discarded_corrupt = false
	var stored: Dictionary = run_snapshot.duplicate(true)
	stored["timestamp_unix_s"] = Time.get_unix_time_from_system()
	if not validate(stored):
		return ERR_INVALID_DATA

	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_dir)
	)
	if directory_error != OK:
		return directory_error

	var temp_path := _path(save_dir, _TEMP_FILE)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(stored, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_present(temp_path)
		return write_error

	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(
			_path(save_dir, _PRIMARY_FILE)
		)
	)
	if rename_error != OK:
		_remove_if_present(temp_path)
	return rename_error


func load(save_dir: String) -> Dictionary:
	discarded_corrupt = false
	_remove_if_present(_path(save_dir, _TEMP_FILE))
	var primary_path := _path(save_dir, _PRIMARY_FILE)
	if not FileAccess.file_exists(primary_path):
		return {}

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(primary_path)) != OK:
		_discard_corrupt(primary_path)
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or not validate(parsed):
		_discard_corrupt(primary_path)
		return {}
	return (parsed as Dictionary).duplicate(true)


func delete(save_dir: String) -> Error:
	var first_error: Error = OK
	for file_name: String in [_PRIMARY_FILE, _TEMP_FILE]:
		var path := _path(save_dir, file_name)
		if not FileAccess.file_exists(path):
			continue
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
		if first_error == OK and remove_error != OK:
			first_error = remove_error
	return first_error


static func validate(data: Dictionary) -> bool:
	var level_id: Variant = data.get("level_id")
	if (
		typeof(level_id) != TYPE_STRING
		and typeof(level_id) != TYPE_STRING_NAME
	):
		return false
	if String(level_id).is_empty():
		return false

	var mode: Variant = data.get("mode")
	if (
		typeof(mode) != TYPE_STRING
		and typeof(mode) != TYPE_STRING_NAME
	):
		return false
	if StringName(mode) not in [
		LevelRunState.MODE_NORMAL,
		LevelRunState.MODE_RELIC,
	]:
		return false

	if not _is_integer(data.get("checkpoint_index")):
		return false
	for field_name: String in [
		"authored_crate_ids",
		"crates_broken",
	]:
		var ids: Variant = data.get(field_name)
		if not ids is Array:
			return false
		for value: Variant in ids:
			if not _is_integer(value):
				return false

	for field_name: String in [
		"wumpa_run",
		"masks",
		"deaths_at_checkpoint",
	]:
		if not _is_non_negative_integer(data.get(field_name)):
			return false

	for field_name: String in [
		"gem_void",
		"relic_void",
		"flawless",
	]:
		if typeof(data.get(field_name)) != TYPE_BOOL:
			return false

	var timestamp: Variant = data.get("timestamp_unix_s")
	return (
		_is_number(timestamp)
		and float(timestamp) >= 0.0
	)


func _discard_corrupt(path: String) -> void:
	discarded_corrupt = true
	_remove_if_present(path)


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _path(save_dir: String, file_name: String) -> String:
	return save_dir.path_join(file_name)


static func _is_non_negative_integer(value: Variant) -> bool:
	return _is_integer(value) and float(value) >= 0.0


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return is_finite(numeric_value) and numeric_value == floor(numeric_value)


static func _is_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))
