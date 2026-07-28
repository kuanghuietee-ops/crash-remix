class_name LookDev
extends Node3D

## One asset, the shipping material and lighting setup, on a turntable, at real
## device resolution. Answers "does this read at phone size", which is the
## question the art ladder asks several hundred times. Debug-only: reached from
## the level list, never from a release path.

signal closed

const FULL_TURN_DEGREES := 360.0
## Degrees per second. A slow turn: fast enough to read the silhouette from every
## angle in a few seconds, slow enough to stop on a bad one.
const TURNTABLE_DEGREES_PER_SECOND := 30.0
const IMPORT_SIDECAR_SUFFIX := ".import"
const REMAP_SIDECAR_SUFFIX := ".remap"

var _assets := PackedStringArray()
var _selected_index := 0
var _turntable_degrees := 0.0

@onready var _turntable: Node3D = $Turntable
@onready var _asset_label: Label = $UI/SafeArea/Rows/AssetPath


func _ready() -> void:
	$Camera3D.look_at(Vector3.ZERO, Vector3.UP)
	$UI/SafeArea/Rows/Controls/Previous.pressed.connect(
		_on_previous_pressed
	)
	$UI/SafeArea/Rows/Controls/Next.pressed.connect(_on_next_pressed)
	$UI/SafeArea/Rows/Controls/Close.pressed.connect(close)
	_show_selected_asset()


func _process(delta: float) -> void:
	advance_turntable(delta)
	_turntable.rotation_degrees.y = turntable_degrees()


func discover_assets(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	_collect_assets(root, found)
	found.sort()
	return found


func set_assets(assets: PackedStringArray) -> void:
	_assets = assets
	_selected_index = 0
	if is_node_ready():
		_show_selected_asset()


func select(index: int) -> void:
	if _assets.is_empty():
		_selected_index = 0
	else:
		_selected_index = posmod(index, _assets.size())
	if is_node_ready():
		_show_selected_asset()


func current_asset_path() -> String:
	if _assets.is_empty():
		return ""
	return _assets[_selected_index]


func advance_turntable(delta_s: float) -> void:
	_turntable_degrees = fmod(
		_turntable_degrees + TURNTABLE_DEGREES_PER_SECOND * delta_s,
		FULL_TURN_DEGREES
	)


func turntable_degrees() -> float:
	return _turntable_degrees


func close() -> void:
	closed.emit()


func normalize_resource_path(path: String) -> String:
	for suffix: String in [IMPORT_SIDECAR_SUFFIX, REMAP_SIDECAR_SUFFIX]:
		if path.ends_with(suffix):
			return path.trim_suffix(suffix)
	return path


func _collect_assets(directory_path: String, into: PackedStringArray) -> void:
	for entry: String in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_assets(
				directory_path.path_join(entry.trim_suffix("/")),
				into
			)
			continue
		var full_path := normalize_resource_path(directory_path.path_join(entry))
		if full_path.ends_with(".glb") and not into.has(full_path):
			into.append(full_path)


func _show_selected_asset() -> void:
	for child: Node in _turntable.get_children():
		_turntable.remove_child(child)
		child.queue_free()
	var path := current_asset_path()
	if path.is_empty():
		_asset_label.text = "NO .GLB ASSETS FOUND"
		return
	_asset_label.text = path
	var asset_scene := load(path) as PackedScene
	if asset_scene == null:
		_asset_label.text = "%s  [COULD NOT LOAD]" % path
		return
	_turntable.add_child(asset_scene.instantiate())


func _on_previous_pressed() -> void:
	select(_selected_index - 1)


func _on_next_pressed() -> void:
	select(_selected_index + 1)
