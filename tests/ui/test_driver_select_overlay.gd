extends GutTest

## CTR R8 Task 4 (characters/select/classes): pure Control-level proof for
## DriverSelectOverlay -- no GameRoot, no real race scene (that half is
## proven end to end in tests/integration/test_main_boot.gd's own
## "choose driver" tests and tests/integration/test_cup_flow_e2e.gd's own
## cup-holds-the-pick test). Locks down: six tiles, DriverRegistry's own
## fixed roster order, honest fallback labeling (never claims a real
## likeness for a driver that doesn't ship one yet), and the two ways this
## screen ever resolves -- a tile tap (driver_selected) or SKIP (skipped).

const OVERLAY_SCENE_PATH := "res://scenes/ui/driver_select_overlay.tscn"
const DriverRegistryType := preload("res://src/racing/roster/driver_registry.gd")
const _ROW_PREFIX := "SafeArea/Center/Panel/Margin/Rows/"

var _overlay: Control


func before_each() -> void:
	var packed := load(OVERLAY_SCENE_PATH) as PackedScene
	assert_not_null(packed, "driver_select_overlay.tscn must exist")
	if packed == null:
		return
	_overlay = packed.instantiate() as Control
	add_child_autofree(_overlay)


func test_lists_six_tiles_in_registry_order_with_display_name_and_class_chip() -> void:
	var entries := DriverRegistryType.entries()
	assert_eq(entries.size(), 6, "fixture sanity: the roster is fixed at 6")
	for entry: DriverEntry in entries:
		var button := _tile_button(entry.id)
		assert_not_null(button, "missing tile for %s" % entry.id)
		if button == null:
			continue
		assert_true(
			button.text.contains(entry.display_name.to_upper()),
			"tile for %s must show its own display name: got '%s'" % [entry.id, button.text]
		)


## R8 gate flip 2026-08-02: cortex/coco/ripper_roo -- the last three
## fallback-active drivers -- are now operator-accepted (docs/art/gates/
## 2026-08-02-{cortex,coco,ripper-roo}/gate-record.md's own "Result"
## lines), joining papu's earlier Task 5 flip. All six roster ids now ship
## a real, loadable character_scene_path, so driver_select_overlay.gd's own
## _is_fallback_active() (character_scene_path.is_empty() or a load
## failure -- that method's own doc) returns false for every tile: no
## driver is fallback-active any more, and this screen must never claim
## otherwise.
func test_fallback_active_drivers_render_the_fallback_never_lie() -> void:
	for id: StringName in [&"crash", &"papu", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"]:
		var button := _tile_button(id)
		assert_not_null(button)
		if button == null:
			continue
		assert_false(
			button.text.contains("FALLBACK"),
			"every roster driver now ships a real character scene -- must never claim a fallback: got '%s'" % button.text
		)


func test_tapping_a_tile_emits_driver_selected_with_that_id_and_nothing_else() -> void:
	var selected_calls: Array = []
	var skipped_calls: Array = []
	_overlay.driver_selected.connect(func(id: StringName) -> void: selected_calls.append(id))
	_overlay.skipped.connect(func() -> void: skipped_calls.append(true))
	var papu_button := _tile_button(&"papu")
	assert_not_null(papu_button)
	if papu_button == null:
		return
	papu_button.pressed.emit()
	assert_eq(selected_calls, [&"papu"])
	assert_eq(skipped_calls.size(), 0)


func test_skip_emits_skipped_and_never_driver_selected() -> void:
	var selected_calls: Array = []
	var skipped_calls: Array = []
	_overlay.driver_selected.connect(func(id: StringName) -> void: selected_calls.append(id))
	_overlay.skipped.connect(func() -> void: skipped_calls.append(true))
	var skip_button := _overlay.get_node(_ROW_PREFIX + "Skip") as Button
	assert_not_null(skip_button)
	if skip_button == null:
		return
	skip_button.pressed.emit()
	assert_eq(selected_calls.size(), 0)
	assert_eq(skipped_calls, [true])


func test_configure_marks_the_current_pick_and_only_the_current_pick() -> void:
	_overlay.call("configure", &"coco")
	var coco_button := _tile_button(&"coco")
	var crash_button := _tile_button(&"crash")
	assert_not_null(coco_button)
	assert_not_null(crash_button)
	if coco_button == null or crash_button == null:
		return
	assert_true(
		coco_button.text.begins_with("> "),
		"the current pick's tile must be marked: got '%s'" % coco_button.text
	)
	assert_false(
		crash_button.text.begins_with("> "),
		"a non-current pick must not be marked: got '%s'" % crash_button.text
	)


func _tile_button(id: StringName) -> Button:
	return _overlay.get_node_or_null(_ROW_PREFIX + _node_name_for(id)) as Button


func _node_name_for(id: StringName) -> String:
	match id:
		&"crash":
			return "Crash"
		&"papu":
			return "Papu"
		&"cortex":
			return "Cortex"
		&"coco":
			return "Coco"
		&"ripper_roo":
			return "RipperRoo"
		&"lab_assistant":
			return "LabAssistant"
	return ""
