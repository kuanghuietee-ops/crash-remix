class_name SaveService
extends RefCounted

const _PRIMARY_FILE := "profile.json"
const _BACKUP_FILE := "profile.json.bak"
const _TEMP_FILE := "profile.json.tmp"
const _CORRUPT_FILE := "profile.json.corrupt"

const _MISSING := 0
const _VALID := 1
const _INVALID := 2
const _FUTURE := 3

var recovered_from_backup: bool = false
var refused_future_version: bool = false


func load_profile(save_dir: String) -> Dictionary:
	recovered_from_backup = false
	refused_future_version = false
	_remove_if_present(_path(save_dir, _TEMP_FILE))

	var primary_path := _path(save_dir, _PRIMARY_FILE)
	var primary := _read_candidate(primary_path)
	match int(primary["status"]):
		_VALID:
			return primary["data"]
		_FUTURE:
			refused_future_version = true
			return {}

	var backup_path := _path(save_dir, _BACKUP_FILE)
	var backup := _read_candidate(backup_path)
	match int(backup["status"]):
		_VALID:
			recovered_from_backup = true
			return backup["data"]
		_FUTURE:
			refused_future_version = true
			return {}

	if int(primary["status"]) == _INVALID:
		_preserve_corrupt(primary_path, _path(save_dir, _CORRUPT_FILE))
	elif int(backup["status"]) == _INVALID:
		_preserve_corrupt(backup_path, _path(save_dir, _CORRUPT_FILE))
	return SaveModel.fresh()


func store_profile(save_dir: String, data: Dictionary) -> Error:
	recovered_from_backup = false
	refused_future_version = false
	if not SaveModel.validate(data):
		return ERR_INVALID_DATA

	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_dir)
	)
	if directory_error != OK:
		return directory_error

	var primary_path := _path(save_dir, _PRIMARY_FILE)
	var primary := _read_candidate(primary_path)
	if int(primary["status"]) == _FUTURE:
		refused_future_version = true
		return ERR_UNAVAILABLE

	var temp_path := _path(save_dir, _TEMP_FILE)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	_flush_file(file)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_present(temp_path)
		return write_error

	if int(primary["status"]) == _VALID:
		var backup_path := _path(save_dir, _BACKUP_FILE)
		var backup_error := _copy_absolute(
			ProjectSettings.globalize_path(primary_path),
			ProjectSettings.globalize_path(backup_path)
		)
		if backup_error != OK:
			_remove_if_present(temp_path)
			return backup_error
	elif int(primary["status"]) == _INVALID:
		_preserve_corrupt(
			primary_path,
			_path(save_dir, _CORRUPT_FILE)
		)

	var rename_error := _rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(primary_path)
	)
	if rename_error != OK:
		_remove_if_present(temp_path)
	return rename_error


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"status": _MISSING,
			"data": {},
		}

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {
			"status": _INVALID,
			"data": {},
		}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {
			"status": _INVALID,
			"data": {},
		}

	var parsed_data: Dictionary = parsed
	if SaveModel.is_future_version(parsed_data):
		return {
			"status": _FUTURE,
			"data": {},
		}

	var migrated := SaveModel.migrate(parsed_data)
	if migrated.is_empty():
		return {
			"status": _INVALID,
			"data": {},
		}
	return {
		"status": _VALID,
		"data": migrated,
	}


func _preserve_corrupt(source_path: String, corrupt_path: String) -> void:
	if not FileAccess.file_exists(source_path):
		return
	var evidence_path := _available_evidence_path(
		source_path,
		corrupt_path
	)
	if evidence_path.is_empty():
		return
	_copy_absolute(
		ProjectSettings.globalize_path(source_path),
		ProjectSettings.globalize_path(evidence_path)
	)


func _available_evidence_path(
	source_path: String,
	base_corrupt_path: String
) -> String:
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var candidate := base_corrupt_path
	var suffix := 0
	while FileAccess.file_exists(candidate):
		if FileAccess.get_file_as_bytes(candidate) == source_bytes:
			return ""
		suffix += 1
		candidate = "%s.%d" % [base_corrupt_path, suffix]
	return candidate


func _flush_file(file: FileAccess) -> void:
	file.flush()


func _copy_absolute(
	source_absolute: String,
	target_absolute: String
) -> Error:
	return DirAccess.copy_absolute(source_absolute, target_absolute)


func _rename_absolute(
	source_absolute: String,
	target_absolute: String
) -> Error:
	return DirAccess.rename_absolute(source_absolute, target_absolute)


func _remove_if_present(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)


func _path(save_dir: String, file_name: String) -> String:
	return save_dir.path_join(file_name)
