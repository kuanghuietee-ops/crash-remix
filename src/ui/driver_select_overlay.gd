class_name DriverSelectOverlay
extends Control

## CTR R8 Task 4 (characters/select/classes): the CHOOSE DRIVER screen every
## RACE/TIME TRIAL/CUP menu entry now routes through before a race actually
## launches -- see game_root.gd's own _on_racing_track_requested()/_on_cup_
## requested()/_open_driver_select_overlay() docs for the full routing this
## screen is wired into. Six tiles, one per DriverRegistry.entries() row, in
## that exact fixed roster order (crash, papu, cortex, coco, ripper_roo,
## lab_assistant) -- authored directly in the .tscn (one Button per id, the
## same "fixed node count off a fixed roster" shape cup_standings_overlay.
## gd's own 6 Row labels already use) rather than instantiated at runtime,
## since DriverRegistry's own roster size is fixed by design (see that
## class's own class doc).
##
## TAP = CONFIRM. Every tile press emits driver_selected(id) -- no separate
## CONFIRM step, matching every other single-tap menu button in this
## codebase's own SafeArea/Center/Panel/Margin/Rows precedent (level_list_
## overlay.gd's own buttons, cup_standings_overlay.gd's own CONTINUE/CLOSE).
## GameRoot is the one that turns that signal into an actual save write (see
## its own _persist_selected_driver() doc for why the write lives there, not
## here -- this overlay never touches SaveModel/SaveService itself). SKIP is
## the one other way out: it changes nothing and simply tells GameRoot to
## proceed with whatever racing.selected_driver already holds on disk
## (SaveModel.selected_driver()'s own "always a real id, self-heals to
## crash" contract) -- the plan's own "skip = keep last pick, default crash"
## requirement, satisfied without this overlay needing any notion of a
## default of its own.
##
## FALLBACK HONESTY. A tile for a driver whose character_scene_path is empty
## or fails to resolve says so directly in its own text (see _tile_text()) --
## never a silent "you picked papu" that then races wearing the lab
## assistant's face with no on-screen explanation (the design spec's own
## "an unfinished face can never break a race or block the round" rule,
## extended to this screen: it can't lie about it either). Checked directly
## against DriverEntry.character_scene_path/ResourceLoader.exists() here --
## the SAME predicate DriverRegistry.character_scene() itself gates on (see
## that method's own FALLBACK doc) -- deliberately NOT calling character_
## scene() itself just to render a tile: that method's own contract fires a
## real push_warning() on every fallback resolution, and this overlay can be
## opened and closed many times a session with no race ever booting. The
## bounded fallback-warning counts test_race_flow_r6_e2e.gd/test_cup_flow_
## e2e.gd both assert on belong solely to a real race BOOT actually mounting
## a character, not to this screen merely being drawn.

signal driver_selected(id: StringName)
signal skipped

const DriverRegistryType := preload("res://src/racing/roster/driver_registry.gd")

## Node names match DriverRegistry ids exactly (PascalCase of the snake_case
## id) -- the one place this screen's own node layout is coupled to the
## roster's own id spelling; DriverRegistry.entries() itself only ever
## supplies the DISPLAY text and fallback/class facts below, never a node
## path.
@onready var _tile_buttons: Dictionary = {
	&"crash": $SafeArea/Center/Panel/Margin/Rows/Crash,
	&"papu": $SafeArea/Center/Panel/Margin/Rows/Papu,
	&"cortex": $SafeArea/Center/Panel/Margin/Rows/Cortex,
	&"coco": $SafeArea/Center/Panel/Margin/Rows/Coco,
	&"ripper_roo": $SafeArea/Center/Panel/Margin/Rows/RipperRoo,
	&"lab_assistant": $SafeArea/Center/Panel/Margin/Rows/LabAssistant,
}
@onready var _skip_button: Button = $SafeArea/Center/Panel/Margin/Rows/Skip

var _current_id: StringName = &"crash"


func _ready() -> void:
	for id: StringName in _tile_buttons.keys():
		var button: Button = _tile_buttons[id]
		button.pressed.connect(_on_tile_pressed.bind(id))
	_skip_button.pressed.connect(
		func() -> void: skipped.emit()
	)
	_render_tiles()


## GameRoot calls this once, right before showing the overlay (see game_
## root.gd's own _open_driver_select_overlay() doc) -- current_id marks
## whichever tile is the save-persisted current pick with a "> " marker, the
## same current-selection marker convention cup_standings_overlay.gd's own
## _row_text() already establishes for "> " = is_player. Purely cosmetic:
## SKIP already reads the real current pick back off SaveModel itself on the
## GameRoot side, so a caller that never calls this still behaves correctly,
## just without the highlight.
func configure(current_id: StringName) -> void:
	_current_id = current_id
	_render_tiles()


func _on_tile_pressed(id: StringName) -> void:
	driver_selected.emit(id)


## DriverRegistry.entries() is a fixed, static roster (never changes at
## runtime), so this is cheap to re-run in full on every configure() call
## rather than only patching the one tile whose marker changed.
func _render_tiles() -> void:
	for entry: DriverEntry in DriverRegistryType.entries():
		var button: Button = _tile_buttons.get(entry.id)
		if button == null:
			continue
		button.text = _tile_text(entry)


func _tile_text(entry: DriverEntry) -> String:
	var marker := "> " if entry.id == _current_id else "  "
	var chip := _class_chip(entry.driver_class_path)
	var suffix := (
		"  [FALLBACK: LAB ASSISTANT]" if _is_fallback_active(entry) else ""
	)
	return "%s%s  [%s]%s" % [marker, entry.display_name.to_upper(), chip, suffix]


## See the class doc's own FALLBACK HONESTY section for why this mirrors
## DriverRegistry.character_scene()'s own empty-path/ResourceLoader.exists()
## check instead of calling that method.
func _is_fallback_active(entry: DriverEntry) -> bool:
	var path := entry.character_scene_path
	return path.is_empty() or not ResourceLoader.exists(path)


## The brief's own "chip text from the class resource file name per entry
## mapping" -- derived straight off the authored driver_class_path's own
## file basename (e.g. ".../classes/balanced.tres" -> "BALANCED") rather
## than a hand-kept id->chip dictionary, so reassigning a driver to a
## different class .tres (a future roster edit) can never silently desync
## the chip text from it.
func _class_chip(driver_class_path: String) -> String:
	if driver_class_path.is_empty():
		return "NO CLASS"
	return driver_class_path.get_file().get_basename().to_upper()
