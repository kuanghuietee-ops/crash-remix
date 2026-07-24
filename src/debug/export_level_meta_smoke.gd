extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const LEVEL_ID := &"wr1_n_sanity_beach"
const LEVEL_NODE_PATH := "Content/NSanityBeach"
const MAX_LOAD_FRAMES: int = 300

var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Export smoke could not load the main scene.")
		quit(1)
		return
	_game = packed.instantiate()
	_game.set("save_dir", "user://export_level_meta_smoke")
	root.add_child(_game)
	await process_frame
	var dispatch_error := int(_game.call(
		"dispatch",
		{
			"type": &"portal_enter",
			"level_id": LEVEL_ID,
		}
	))
	if dispatch_error != OK:
		push_error("Export smoke could not enter the authored level.")
		quit(dispatch_error)
		return
	for _poll_index: int in range(MAX_LOAD_FRAMES):
		if _game.has_node(LEVEL_NODE_PATH):
			print("EXPORTED LEVEL META SMOKE READY")
			quit(OK)
			return
		await process_frame
	push_error("Export smoke timed out loading the authored level.")
	quit(ERR_TIMEOUT)
