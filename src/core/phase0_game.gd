class_name PhaseZeroGame
extends Node3D

const TuningServiceType := preload("res://src/tuning/tuning_service.gd")
const CameraRegionType := preload(
	"res://src/gameplay/camera/camera_region.gd"
)
const BASE_TUNING_PATH := "res://data/tuning/gameplay.tres"
const OVERRIDE_TUNING_PATH := "user://tuning/override.tres"

var tuning_service: TuningServiceType = TuningServiceType.new()
var _uses_external_tuning_service: bool = false
var _external_touch_exclusions: Array = []


static func should_enable_debug_tools(is_debug_build: bool) -> bool:
	return is_debug_build


func configure_embedded(
	service: TuningServiceType,
	touch_exclusions: Array
) -> void:
	tuning_service = service
	_uses_external_tuning_service = true
	_external_touch_exclusions = touch_exclusions.duplicate()


func _ready() -> void:
	Input.set_use_accumulated_input(false)
	if not _uses_external_tuning_service:
		var load_error := tuning_service.load_from_paths(
			BASE_TUNING_PATH,
			OVERRIDE_TUNING_PATH
		)
		if load_error != OK:
			push_error(
				"Phase 0 tuning failed to load: "
				+ error_string(load_error)
			)
			return
	elif tuning_service == null or tuning_service.catalog == null:
		push_error("Embedded toybox tuning owner is not configured.")
		return
	var catalog := tuning_service.catalog
	PhaseState.configure(catalog.phase)
	var router := get_node("Input/InputRouter")
	var gamepad := get_node("Input/GamepadInput")
	var touch := get_node("UI/TouchControls")
	var tuning_debug := get_node("UI/TuningDebug")
	var player := get_node("Player") as CharacterBody3D
	var camera_rig := get_node("CameraRig")
	router.call("configure", catalog.input)
	gamepad.call("configure", router, catalog.input)
	touch.call("configure", router, catalog.input, true)
	var debug_tools_enabled := (
		should_enable_debug_tools(OS.is_debug_build())
		and not _uses_external_tuning_service
	)
	tuning_debug.visible = debug_tools_enabled
	if debug_tools_enabled:
		tuning_debug.call("configure", tuning_service, OVERRIDE_TUNING_PATH)
		touch.call(
			"set_touch_exclusion_controls",
			[
				tuning_debug.get_node("HUD"),
				tuning_debug.get_node("Drawer"),
			]
		)
	else:
		touch.call(
			"set_touch_exclusion_controls",
			_external_touch_exclusions
		)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		true
	)
	var phase_reset_callback := Callable(
		PhaseState,
		"reset_to_authored_set"
	)
	if not player.is_connected(&"respawned", phase_reset_callback):
		player.connect(&"respawned", phase_reset_callback)
	player.call("set_spawn_transform", player.global_transform)
	_refresh_traversal_rails(catalog.camera)
	_refresh_swing_anchors(catalog.swing)
	player.get_node("BlobShadow").call("configure", player, catalog.depth)
	player.get_node("LandingRing").call(
		"configure",
		player,
		catalog.move,
		catalog.depth,
		catalog.grind,
		_traversal_rails_for_prediction()
	)
	camera_rig.call(
		"configure",
		player,
		camera_rig.get_node("Rail"),
		camera_rig.get_node("Camera3D"),
		catalog.camera,
		_camera_regions(),
		router
	)
	if debug_tools_enabled:
		tuning_debug.connect(
			"tuning_changed",
			Callable(self, "_on_tuning_changed")
		)


func _on_tuning_changed(_fingerprint: String) -> void:
	refresh_tuning()


func refresh_tuning() -> void:
	var catalog := tuning_service.catalog
	PhaseState.configure(catalog.phase)
	var router := get_node("Input/InputRouter")
	var gamepad := get_node("Input/GamepadInput")
	var touch := get_node("UI/TouchControls")
	var player := get_node("Player") as CharacterBody3D
	var camera_rig := get_node("CameraRig")
	router.call("configure", catalog.input)
	gamepad.call("configure", router, catalog.input)
	touch.call("configure", router, catalog.input, true)
	player.call(
		"configure",
		catalog.move,
		catalog.input,
		catalog.depth,
		catalog.wall_run,
		catalog.grind,
		catalog.swing,
		router.get("buffer"),
		catalog.economy,
		true
	)
	_refresh_traversal_rails(catalog.camera)
	_refresh_swing_anchors(catalog.swing)
	player.get_node("BlobShadow").call("configure", player, catalog.depth)
	player.get_node("LandingRing").call(
		"configure",
		player,
		catalog.move,
		catalog.depth,
		catalog.grind,
		_traversal_rails_for_prediction()
	)
	camera_rig.call("refresh_tuning", catalog.camera)


func _refresh_traversal_rails(camera_tuning: CameraTuning) -> void:
	for candidate: Node in get_tree().get_nodes_in_group(&"traversal_rail"):
		if is_ancestor_of(candidate) and candidate.has_method("refresh_tuning"):
			candidate.call("refresh_tuning", camera_tuning)


func _refresh_swing_anchors(swing_tuning: SwingTuning) -> void:
	for candidate: Node in get_tree().get_nodes_in_group(&"swing_anchor"):
		if is_ancestor_of(candidate) and candidate.has_method("refresh_tuning"):
			candidate.call("refresh_tuning", swing_tuning)


func _traversal_rails_for_prediction() -> Array:
	var result: Array = []
	for candidate: Node in get_tree().get_nodes_in_group(
		&"traversal_rail"
	):
		if is_ancestor_of(candidate) and candidate.has_method("samples"):
			result.append(candidate)
	return result


func _camera_regions() -> Array:
	var result: Array = []
	for candidate: Node in find_children("*", "Area3D", true, false):
		if candidate is CameraRegionType:
			result.append(candidate)
	return result
