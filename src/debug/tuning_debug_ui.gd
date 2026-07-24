class_name TuningDebugUI
extends Control

signal tuning_changed(fingerprint: String)

const TuningServiceType := preload("res://src/tuning/tuning_service.gd")
const SECTION_NAMES: Array[StringName] = TuningServiceType.SECTION_NAMES
const EXCLUDED_DRAWER_PROPERTIES: Dictionary = {
	&"input": [
		&"bounce_timing_s",
		&"touch_response_target_s",
		&"touch_response_hard_fail_s",
		&"millimeters_per_inch",
		&"fallback_dpi",
		&"control_scale",
		&"layout_metrics_poll_interval_s",
	],
	&"camera": [
		&"minimum_jump_depression_degrees",
	],
}

var _service: TuningServiceType
var _override_path: String
var _summary := ""
var _last_fingerprint := ""
var _level_meta_path := ""
var _level_meta_fingerprint := ""
var _property_count: int
var _controls: Dictionary = {}

@onready var _hud: PanelContainer = $HUD
@onready var _summary_label: Label = $HUD/Margin/VBox/Summary
@onready var _override_label: Label = $HUD/Margin/VBox/Header/OverrideActive
@onready var _drawer: PanelContainer = $Drawer
@onready var _rows: VBoxContainer = $Drawer/Margin/VBox/Scroll/Rows
@onready var _status_label: Label = $Drawer/Margin/VBox/Footer/Status


func _ready() -> void:
	$HUD/Margin/VBox/Header/Open.pressed.connect(_on_open_pressed)
	$Drawer/Margin/VBox/Footer/Save.pressed.connect(_on_save_pressed)
	$Drawer/Margin/VBox/Footer/Reset.pressed.connect(_on_reset_pressed)
	$Drawer/Margin/VBox/Footer/Close.pressed.connect(_on_close_pressed)


func configure(service: TuningServiceType, override_path: String) -> void:
	_service = service
	_override_path = override_path
	_build_drawer()
	_refresh_summary(true)


func summary_text() -> String:
	return _summary


func report_level_meta(meta: LevelMeta) -> void:
	if meta == null:
		_level_meta_path = ""
		_level_meta_fingerprint = ""
	else:
		_level_meta_path = meta.resource_path
		_level_meta_fingerprint = meta.fingerprint()
	_refresh_summary(true)


func override_watermark_visible() -> bool:
	return _override_label.visible


func drawer_property_count() -> int:
	return _property_count


func drawer_row_count() -> int:
	return _rows.get_child_count()


func drawer_has_control(
	section_name: StringName,
	property_name: StringName
) -> bool:
	return _controls.has(_control_key(section_name, property_name))


func set_drawer_open(open: bool) -> void:
	_drawer.visible = open


func drawer_is_open() -> bool:
	return _drawer.visible


func hud_is_visible() -> bool:
	return _hud.visible


func set_live_value(
	section_name: StringName,
	property_name: StringName,
	value: Variant
) -> Error:
	var resource := _resource_for(section_name)
	if resource == null or not _has_exported_property(resource, property_name):
		return ERR_DOES_NOT_EXIST
	var current: Variant = resource.get(property_name)
	match typeof(current):
		TYPE_FLOAT:
			resource.set(property_name, float(value))
		TYPE_INT:
			resource.set(property_name, int(value))
		TYPE_BOOL:
			resource.set(property_name, bool(value))
		TYPE_VECTOR3:
			if typeof(value) != TYPE_VECTOR3:
				return ERR_INVALID_PARAMETER
			resource.set(property_name, value as Vector3)
		TYPE_COLOR:
			if typeof(value) != TYPE_COLOR:
				return ERR_INVALID_PARAMETER
			resource.set(property_name, value as Color)
		_:
			return ERR_INVALID_PARAMETER
	if not _service.catalog_is_usable():
		resource.set(property_name, current)
		_status_label.text = "Rejected unsafe value"
		_sync_control(section_name, property_name, current)
		return ERR_INVALID_DATA
	_sync_control(section_name, property_name, resource.get(property_name))
	_refresh_summary()
	return OK


func save_override() -> Error:
	if _service == null:
		return ERR_UNCONFIGURED
	var save_error := _service.save_override(_override_path)
	_status_label.text = "Saved" if save_error == OK else error_string(save_error)
	_refresh_summary(true)
	return save_error


func reset_to_authored() -> Error:
	if _service == null:
		return ERR_UNCONFIGURED
	var reset_error := _service.reset_to_authored()
	_status_label.text = (
		"Restored authored values"
		if reset_error == OK
		else error_string(reset_error)
	)
	if reset_error == OK:
		_build_drawer()
	_refresh_summary(true)
	return reset_error


func _build_drawer() -> void:
	_property_count = 0
	_controls.clear()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _service == null or _service.catalog == null:
		return
	for section_name: StringName in SECTION_NAMES:
		var resource := _resource_for(section_name)
		if resource == null:
			continue
		var section_label := Label.new()
		section_label.text = String(section_name).to_upper()
		section_label.add_theme_font_size_override("font_size", 24)
		_rows.add_child(section_label)
		for property_info: Dictionary in resource.get_property_list():
			var usage: int = property_info["usage"]
			if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				continue
			var property_name: StringName = property_info["name"]
			if _drawer_property_is_excluded(section_name, property_name):
				continue
			var property_type: int = property_info["type"]
			if property_type == TYPE_BOOL:
				_add_bool_control(section_name, resource, property_name)
			elif property_type == TYPE_FLOAT or property_type == TYPE_INT:
				_add_number_control(
					section_name,
					resource,
					property_name,
					property_type
				)
			elif property_type == TYPE_VECTOR3:
				_add_vector3_control(section_name, resource, property_name)
			elif property_type == TYPE_COLOR:
				_add_color_control(section_name, resource, property_name)


func _add_number_control(
	section_name: StringName,
	resource: Resource,
	property_name: StringName,
	property_type: int
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = String(property_name)
	label.custom_minimum_size.x = 285.0
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 240.0
	var spin_box := SpinBox.new()
	spin_box.custom_minimum_size.x = 150.0
	spin_box.allow_greater = true
	spin_box.allow_lesser = true
	var current := float(resource.get(property_name))
	var span := maxf(absf(current), 1.0)
	slider.min_value = minf(0.0, current - span)
	slider.max_value = maxf(0.0, current + span)
	slider.step = span / 100.0
	spin_box.min_value = -1_000_000.0
	spin_box.max_value = 1_000_000.0
	spin_box.step = 1.0 if property_type == TYPE_INT else 0.001
	slider.value = current
	spin_box.value = current
	row.add_child(label)
	row.add_child(slider)
	row.add_child(spin_box)
	_rows.add_child(row)
	slider.value_changed.connect(
		_on_number_changed.bind(section_name, property_name, property_type, spin_box)
	)
	spin_box.value_changed.connect(
		_on_spin_box_changed.bind(section_name, property_name, property_type, slider)
	)
	_controls[_control_key(section_name, property_name)] = {
		"slider": slider,
		"spin_box": spin_box,
	}
	_property_count += 1


func _add_bool_control(
	section_name: StringName,
	resource: Resource,
	property_name: StringName
) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = String(property_name)
	checkbox.button_pressed = bool(resource.get(property_name))
	checkbox.toggled.connect(
		_on_bool_changed.bind(section_name, property_name)
	)
	_rows.add_child(checkbox)
	_controls[_control_key(section_name, property_name)] = checkbox
	_property_count += 1


func _add_vector3_control(
	section_name: StringName,
	resource: Resource,
	property_name: StringName
) -> void:
	var value: Vector3 = resource.get(property_name)
	var component_names := PackedStringArray(["x", "y", "z"])
	var component_controls: Array[Dictionary] = []
	for component_index: int in range(component_names.size()):
		component_controls.append(_add_component_control(
			section_name,
			property_name,
			component_names[component_index],
			component_index,
			TYPE_VECTOR3,
			value[component_index],
			false
		))
	_controls[_control_key(section_name, property_name)] = component_controls
	_property_count += 1


func _add_color_control(
	section_name: StringName,
	resource: Resource,
	property_name: StringName
) -> void:
	var value: Color = resource.get(property_name)
	var component_names := PackedStringArray(["r", "g", "b", "a"])
	var component_controls: Array[Dictionary] = []
	for component_index: int in range(component_names.size()):
		component_controls.append(_add_component_control(
			section_name,
			property_name,
			component_names[component_index],
			component_index,
			TYPE_COLOR,
			value[component_index],
			true
		))
	_controls[_control_key(section_name, property_name)] = component_controls
	_property_count += 1


func _add_component_control(
	section_name: StringName,
	property_name: StringName,
	component_name: String,
	component_index: int,
	property_type: int,
	current: float,
	unit_interval: bool
) -> Dictionary:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = String(property_name) + "." + component_name
	label.custom_minimum_size.x = 285.0
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 240.0
	var spin_box := SpinBox.new()
	spin_box.custom_minimum_size.x = 150.0
	var span := maxf(absf(current), 1.0)
	if unit_interval:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.001
		spin_box.min_value = 0.0
		spin_box.max_value = 1.0
	else:
		slider.min_value = minf(0.0, current - span)
		slider.max_value = maxf(0.0, current + span)
		slider.step = span / 100.0
		spin_box.min_value = -1_000_000.0
		spin_box.max_value = 1_000_000.0
		spin_box.allow_greater = true
		spin_box.allow_lesser = true
	spin_box.step = 0.001
	slider.value = current
	spin_box.value = current
	row.add_child(label)
	row.add_child(slider)
	row.add_child(spin_box)
	_rows.add_child(row)
	slider.value_changed.connect(
		_on_component_slider_changed.bind(
			section_name,
			property_name,
			component_index,
			property_type,
			spin_box
		)
	)
	spin_box.value_changed.connect(
		_on_component_spin_changed.bind(
			section_name,
			property_name,
			component_index,
			property_type,
			slider
		)
	)
	return {"slider": slider, "spin_box": spin_box}


func _on_number_changed(
	value: float,
	section_name: StringName,
	property_name: StringName,
	property_type: int,
	spin_box: SpinBox
) -> void:
	spin_box.set_value_no_signal(value)
	var typed_value: Variant = int(round(value)) if property_type == TYPE_INT else value
	set_live_value(section_name, property_name, typed_value)


func _on_spin_box_changed(
	value: float,
	section_name: StringName,
	property_name: StringName,
	property_type: int,
	slider: HSlider
) -> void:
	if value < slider.min_value:
		slider.min_value = value
	if value > slider.max_value:
		slider.max_value = value
	slider.set_value_no_signal(value)
	var typed_value: Variant = int(round(value)) if property_type == TYPE_INT else value
	set_live_value(section_name, property_name, typed_value)


func _on_bool_changed(
	value: bool,
	section_name: StringName,
	property_name: StringName
) -> void:
	set_live_value(section_name, property_name, value)


func _on_component_slider_changed(
	value: float,
	section_name: StringName,
	property_name: StringName,
	component_index: int,
	property_type: int,
	spin_box: SpinBox
) -> void:
	spin_box.set_value_no_signal(value)
	_set_component_value(
		section_name,
		property_name,
		component_index,
		property_type,
		value
	)


func _on_component_spin_changed(
	value: float,
	section_name: StringName,
	property_name: StringName,
	component_index: int,
	property_type: int,
	slider: HSlider
) -> void:
	if value < slider.min_value:
		slider.min_value = value
	if value > slider.max_value:
		slider.max_value = value
	slider.set_value_no_signal(value)
	_set_component_value(
		section_name,
		property_name,
		component_index,
		property_type,
		value
	)


func _set_component_value(
	section_name: StringName,
	property_name: StringName,
	component_index: int,
	property_type: int,
	value: float
) -> void:
	var resource := _resource_for(section_name)
	if resource == null:
		return
	if property_type == TYPE_VECTOR3:
		var vector: Vector3 = resource.get(property_name)
		vector[component_index] = value
		set_live_value(section_name, property_name, vector)
	elif property_type == TYPE_COLOR:
		var color: Color = resource.get(property_name)
		color[component_index] = clampf(value, 0.0, 1.0)
		set_live_value(section_name, property_name, color)


func _sync_control(
	section_name: StringName,
	property_name: StringName,
	value: Variant
) -> void:
	var key := _control_key(section_name, property_name)
	if not _controls.has(key):
		return
	var control: Variant = _controls[key]
	if control is CheckBox:
		(control as CheckBox).set_pressed_no_signal(bool(value))
	elif control is Dictionary:
		var slider: HSlider = control["slider"]
		var spin_box: SpinBox = control["spin_box"]
		slider.set_value_no_signal(float(value))
		spin_box.set_value_no_signal(float(value))
	elif control is Array:
		for component_index: int in range(control.size()):
			var component_control: Dictionary = control[component_index]
			var component_value := float(value[component_index])
			var slider: HSlider = component_control["slider"]
			var spin_box: SpinBox = component_control["spin_box"]
			slider.set_value_no_signal(component_value)
			spin_box.set_value_no_signal(component_value)


func _refresh_summary(force_log: bool = false) -> void:
	if _service == null:
		return
	_last_fingerprint = _service.fingerprint()
	var lines := PackedStringArray([
		"TUNING FINGERPRINT",
		_last_fingerprint,
		"LOADED VALUES ONLY — VERIFY BEHAVIOR SEPARATELY",
	])
	for path: String in _service.get_loaded_resource_paths():
		lines.append(path)
	if not _level_meta_path.is_empty():
		lines.append("LEVEL META")
		lines.append(_level_meta_path)
		lines.append("FINGERPRINT " + _level_meta_fingerprint.left(12))
	_summary = "\n".join(lines)
	_summary_label.text = _summary
	_override_label.visible = (
		_service.override_active
		or _service.override_rejected
	)
	_override_label.text = (
		"OVERRIDE REJECTED"
		if _service.override_rejected
		else "OVERRIDE ACTIVE"
	)
	if force_log:
		print(_summary)
	tuning_changed.emit(_last_fingerprint)


func _resource_for(section_name: StringName) -> Resource:
	if _service == null or _service.catalog == null:
		return null
	return _service.catalog.get(section_name) as Resource


func _has_exported_property(resource: Resource, property_name: StringName) -> bool:
	for property_info: Dictionary in resource.get_property_list():
		if (
			property_info["name"] == property_name
			and int(property_info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE
		):
			return true
	return false


func _control_key(section_name: StringName, property_name: StringName) -> String:
	return String(section_name) + "/" + String(property_name)


func _drawer_property_is_excluded(
	section_name: StringName,
	property_name: StringName
) -> bool:
	if not EXCLUDED_DRAWER_PROPERTIES.has(section_name):
		return false
	var excluded: Array = EXCLUDED_DRAWER_PROPERTIES[section_name]
	return excluded.has(property_name)


func _on_open_pressed() -> void:
	set_drawer_open(true)


func _on_close_pressed() -> void:
	set_drawer_open(false)


func _on_save_pressed() -> void:
	save_override()


func _on_reset_pressed() -> void:
	reset_to_authored()
