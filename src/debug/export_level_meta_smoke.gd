extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MAX_LOAD_FRAMES: int = 300
const LEVEL_CASES: Array[Dictionary] = [
	{
		&"level_id": &"wr1_n_sanity_beach",
		&"node_path": "Content/NSanityBeach",
		&"ready_marker": "EXPORTED LEVEL META SMOKE READY",
	},
	{
		&"level_id": &"wr1_boulders",
		&"node_path": "Content/Boulders",
		&"ready_marker": "EXPORTED BOULDERS SMOKE READY",
	},
]

var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Export smoke could not load the main scene.")
		quit(1)
		return
	for level_case: Dictionary in LEVEL_CASES:
		var result := await _load_level_case(
			packed,
			level_case
		)
		if result != OK:
			quit(result)
			return
	quit(OK)


func _load_level_case(
	packed: PackedScene,
	level_case: Dictionary
) -> int:
	_game = packed.instantiate()
	var level_id := StringName(
		level_case.get(&"level_id", &"")
	)
	_game.set(
		"save_dir",
		"user://export_level_meta_smoke_%s" % level_id
	)
	root.add_child(_game)
	await process_frame
	var dispatch_error := int(_game.call(
		"dispatch",
		{
			"type": &"portal_enter",
			"level_id": level_id,
		}
	))
	if dispatch_error != OK:
		push_error(
			"Export smoke could not enter %s." % level_id
		)
		_game.queue_free()
		await process_frame
		return dispatch_error
	var node_path := NodePath(
		String(level_case.get(&"node_path", ""))
	)
	for _poll_index: int in range(MAX_LOAD_FRAMES):
		if _game.has_node(node_path):
			print(String(level_case.get(
				&"ready_marker",
				"EXPORTED LEVEL READY"
			)))
			_game.queue_free()
			await process_frame
			return OK
		await process_frame
	push_error(
		"Export smoke timed out loading %s." % level_id
	)
	_game.queue_free()
	await process_frame
	return ERR_TIMEOUT
