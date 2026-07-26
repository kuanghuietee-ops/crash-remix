class_name WarpRoom
extends Node3D

const PortalRulesType := preload(
	"res://src/gameplay/hub/portal_rules.gd"
)

signal flow_event_requested(event: Dictionary)
signal level_list_requested

var _profile: Dictionary = {}
var _catalog: GameplayTuning
var _level_metas: Dictionary = {}
var _phase_available: bool
var _available_level_ids: Array[StringName] = []
var _extra_touch_exclusions: Array = []


func _ready() -> void:
	# Mirrors LevelSession.configure()'s PROCESS_MODE_PAUSABLE: without
	# this, WarpRoom inherits GameRoot's PROCESS_MODE_ALWAYS, so the
	# Player/InputRouter/GamepadInput/TouchControls underneath the hub
	# keep running while the Level List modal has get_tree().paused set.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	$UI/LevelList.pressed.connect(
		func() -> void: level_list_requested.emit()
	)
	_connect_portals()


func configure(
	profile: Dictionary,
	catalog: GameplayTuning,
	level_metas: Dictionary = {},
	phase_available: bool = false,
	available_level_ids: Array[StringName] = [],
	extra_touch_exclusions: Array = []
) -> void:
	_profile = (
		profile.duplicate(true)
		if SaveModel.validate(profile)
		else SaveModel.fresh()
	)
	_catalog = catalog
	_level_metas = level_metas.duplicate()
	_phase_available = phase_available
	_available_level_ids = available_level_ids.duplicate()
	_extra_touch_exclusions = extra_touch_exclusions.duplicate()
	_configure_player()
	_apply_portal_states()


func refresh_profile(profile: Dictionary) -> void:
	if not SaveModel.validate(profile):
		return
	_profile = profile.duplicate(true)
	_apply_portal_states()


func _connect_portals() -> void:
	for portal: Area3D in _portals():
		var normal_callback := Callable(
			self,
			"_on_portal_body_entered"
		).bind(portal)
		if not portal.body_entered.is_connected(normal_callback):
			portal.body_entered.connect(normal_callback)
		var relic_trigger := (
			portal.get_node_or_null("RelicTrigger") as Area3D
		)
		if relic_trigger == null:
			continue
		var relic_callback := Callable(
			self,
			"_on_relic_body_entered"
		).bind(portal)
		if not relic_trigger.body_entered.is_connected(
			relic_callback
		):
			relic_trigger.body_entered.connect(relic_callback)


func _configure_player() -> void:
	if _catalog == null:
		return
	var router := $Input/InputRouter as InputRouter
	var gamepad := $Input/GamepadInput as GamepadInput
	var touch := $UI/TouchControls as TouchControls
	var player := $Player as CharacterBody3D
	router.configure(_catalog.input)
	gamepad.configure(router, _catalog.input)
	touch.configure(
		router,
		_catalog.input,
		_phase_available
	)
	touch.set_touch_exclusion_controls(
		[$UI/LevelList] + _extra_touch_exclusions
	)
	player.call(
		"configure",
		_catalog.move,
		_catalog.input,
		_catalog.depth,
		_catalog.wall_run,
		_catalog.grind,
		_catalog.swing,
		router.buffer,
		_catalog.economy,
		_phase_available,
		_catalog.hog
	)
	player.call("set_spawn_transform", player.global_transform)
	player.get_node("BlobShadow").call(
		"configure",
		player,
		_catalog.depth
	)
	player.get_node("LandingRing").call(
		"configure",
		player,
		_catalog.move,
		_catalog.depth,
		_catalog.grind,
		[]
	)


func _apply_portal_states() -> void:
	for portal: Area3D in _portals():
		var portal_id := StringName(
			portal.get_meta("level_id", &"")
		)
		var state := PortalRulesType.state_for(
			portal_id,
			_profile,
			_available_level_ids
		)
		for key: Variant in state:
			portal.set_meta(key, state[key])
		var unlocked := bool(state.get("unlocked", false))
		portal.monitoring = unlocked
		_set_visible(
			portal,
			"State/Locked",
			not unlocked
		)
		_set_visible(
			portal,
			"State/Cleared",
			bool(state.get("completed", false))
		)
		_set_visible(
			portal,
			"State/Gem",
			bool(state.get("gem", false))
		)
		_set_visible(
			portal,
			"State/Relic",
			StringName(
				state.get("relic_tier", &"none")
			) != &"none"
		)
		_set_visible(
			portal,
			"State/Flawless",
			bool(state.get("flawless", false))
		)
		_configure_relic_trigger(portal, state)
		var label := portal.get_node_or_null("Label") as Label3D
		if label != null:
			label.text = _display_name_for(portal, portal_id)


func _display_name_for(
	portal: Area3D,
	portal_id: StringName
) -> String:
	# scenes/props/portal.tscn's own base already authors
	# metadata/display_name = "" -- the key EXISTS with an empty value,
	# so get_meta's default argument (portal_id) never fires for a
	# portal instance that forgets to override it. Fail loudly (so a
	# missing authored name is caught, not silently shipped) while still
	# falling back to something visible in the 3D world instead of a
	# blank label.
	var display_name := String(
		portal.get_meta("display_name", portal_id)
	)
	if not display_name.is_empty():
		return display_name
	push_error(
		"Portal '%s' is missing an authored display_name; "
		% [portal_id]
		+ "falling back to the level id."
	)
	return String(portal_id)


func _configure_relic_trigger(
	portal: Area3D,
	state: Dictionary
) -> void:
	var trigger := (
		portal.get_node_or_null("RelicTrigger") as Area3D
	)
	if trigger == null:
		return
	var portal_id := StringName(
		portal.get_meta("level_id", &"")
	)
	var meta := _level_metas.get(portal_id) as LevelMeta
	var available := (
		bool(state.get("completed", false))
		and meta != null
		and LevelRunState.relic_pars_authored(meta)
	)
	trigger.visible = available
	trigger.monitoring = available


func _on_portal_body_entered(
	body: Node3D,
	portal: Area3D
) -> void:
	if body != $Player or not portal.get_meta("unlocked", false):
		return
	_emit_portal_event(portal, LevelRunState.MODE_NORMAL)


func _on_relic_body_entered(
	body: Node3D,
	portal: Area3D
) -> void:
	var trigger := (
		portal.get_node_or_null("RelicTrigger") as Area3D
	)
	if body != $Player or trigger == null or not trigger.monitoring:
		return
	_emit_portal_event(portal, LevelRunState.MODE_RELIC)


func _emit_portal_event(
	portal: Area3D,
	mode: StringName
) -> void:
	flow_event_requested.emit({
		"type": &"portal_enter",
		"level_id": StringName(
			portal.get_meta("level_id", &"")
		),
		"mode": mode,
	})


func _portals() -> Array[Area3D]:
	var result: Array[Area3D] = []
	for candidate: Node in $Portals.get_children():
		if candidate is Area3D and candidate.is_in_group(
			&"warp_portal"
		):
			result.append(candidate as Area3D)
	return result


func _set_visible(
	portal: Area3D,
	path: NodePath,
	is_visible: bool
) -> void:
	var visual := portal.get_node_or_null(path) as Node3D
	if visual != null:
		visual.visible = is_visible
