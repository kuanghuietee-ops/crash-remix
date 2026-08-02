extends GutTest

## CTR R8 Task 2 (characters/select/classes): DriverRegistry's own resolution
## + fallback contract -- see driver_registry.gd's own class doc. RaceSession
## wiring (player mount, AI fill, tint pinning, per-class health) is proven
## separately in tests/racing/test_race_session_driver_roster.gd; this file
## only proves the registry's own four public methods in isolation.

const _FALLBACK_PATH := "res://assets/models/enemies/SK_lab_assistant.glb"
const _CRASH_PATH := "res://assets/models/characters/SK_crash.glb"
const _PAPU_SEATED_PATH := "res://assets/models/bosses/SK_papu_seated.glb"
## R8 gate flip: cortex/coco/ripper_roo all operator-accepted 2026-08-02
## (see docs/art/gates/2026-08-02-{cortex,coco,ripper-roo}/gate-record.md's
## own "Result" lines) -- same shape as _PAPU_SEATED_PATH above.
const _CORTEX_PATH := "res://assets/models/characters/SK_cortex.glb"
const _COCO_PATH := "res://assets/models/characters/SK_coco.glb"
const _RIPPER_ROO_PATH := "res://assets/models/characters/SK_ripper_roo.glb"


func test_entries_returns_the_six_roster_ids_in_fixed_order() -> void:
	var ids: Array[StringName] = []
	for entry: DriverEntry in DriverRegistry.entries():
		ids.append(entry.id)
	assert_eq(
		ids,
		[&"crash", &"papu", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"],
		"the roster order is fixed and load-bearing -- see the class doc's own ROSTER ORDER section"
	)


func test_entry_resolves_each_known_id() -> void:
	for expected_id: StringName in [
		&"crash", &"papu", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"
	]:
		var found := DriverRegistry.entry(expected_id)
		assert_not_null(found, "entry(%s) must resolve" % expected_id)
		if found != null:
			assert_eq(found.id, expected_id)


func test_entry_returns_null_for_an_unknown_id() -> void:
	assert_null(DriverRegistry.entry(&"not_a_real_driver"))


func test_character_scene_resolves_crash_to_the_real_gated_model() -> void:
	var scene := DriverRegistry.character_scene(&"crash")
	assert_not_null(scene, "crash must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _CRASH_PATH)


func test_character_scene_resolves_lab_assistant_to_the_real_model() -> void:
	var scene := DriverRegistry.character_scene(&"lab_assistant")
	assert_not_null(scene, "lab_assistant must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _FALLBACK_PATH)


## Task 5 (characters/select/classes): papu's own DriverEntry now ships a
## real character_scene_path (data/racing/drivers/papu.tres) -- his pose +
## seat fit reused his already-operator-accepted platformer mesh, not a
## new likeness gate (see create_papu_seated.py's own module doc), so this
## flip does not need an operator gate the way cortex/coco/ripper_roo will.
func test_character_scene_resolves_papu_to_the_real_seated_model() -> void:
	var scene := DriverRegistry.character_scene(&"papu")
	assert_not_null(scene, "papu must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _PAPU_SEATED_PATH)
	assert_push_warning_count(0, "a gated driver must never push a fallback warning")


## R8 gate flip 2026-08-02: mirrors test_character_scene_resolves_papu_to_
## the_real_seated_model() above -- cortex's own likeness gate is operator-
## accepted (docs/art/gates/2026-08-02-cortex/gate-record.md's own "Result"
## line), so character_scene_path is no longer empty and this must resolve
## for real, with zero fallback warnings.
func test_character_scene_resolves_cortex_to_the_real_model() -> void:
	var scene := DriverRegistry.character_scene(&"cortex")
	assert_not_null(scene, "cortex must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _CORTEX_PATH)
	assert_push_warning_count(0, "a gated driver must never push a fallback warning")


## R8 gate flip 2026-08-02: mirrors test_character_scene_resolves_papu_to_
## the_real_seated_model() above -- coco's own likeness gate is operator-
## accepted (docs/art/gates/2026-08-02-coco/gate-record.md's own "Result"
## line), so character_scene_path is no longer empty and this must resolve
## for real, with zero fallback warnings.
func test_character_scene_resolves_coco_to_the_real_model() -> void:
	var scene := DriverRegistry.character_scene(&"coco")
	assert_not_null(scene, "coco must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _COCO_PATH)
	assert_push_warning_count(0, "a gated driver must never push a fallback warning")


## R8 gate flip 2026-08-02: mirrors test_character_scene_resolves_papu_to_
## the_real_seated_model() above -- ripper_roo's own likeness gate is
## operator-accepted (docs/art/gates/2026-08-02-ripper-roo/gate-record.md's
## own "Result" line), so character_scene_path is no longer empty and this
## must resolve for real, with zero fallback warnings.
func test_character_scene_resolves_ripper_roo_to_the_real_model() -> void:
	var scene := DriverRegistry.character_scene(&"ripper_roo")
	assert_not_null(scene, "ripper_roo must resolve to a real PackedScene")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _RIPPER_ROO_PATH)
	assert_push_warning_count(0, "a gated driver must never push a fallback warning")


## R8 gate flip 2026-08-02: cortex/coco/ripper_roo were the last roster ids
## with an empty character_scene_path -- now that all three are operator-
## accepted (see the three tests directly above), no live roster row can
## exercise character_scene()'s own "found != null but path.is_empty()"
## branch any more (every DriverEntry in ENTRIES now ships a real path).
## Rather than drop coverage of that branch entirely, this constructs a
## synthetic DriverEntry with an empty path -- the same shape a future
## not-yet-gated driver would ship -- and drives _fallback_scene() (the
## function character_scene() itself calls on that branch) directly with
## its id/path, so the fallback CODE path stays proven even though the real
## roster can no longer trigger it. test_character_scene_falls_back_to_lab_
## assistant_for_an_unknown_id() below separately covers the OTHER way in
## (found == null, an id absent from the roster entirely).
func test_fallback_scene_seats_the_lab_assistant_for_a_synthetic_empty_path_entry() -> void:
	var synthetic := DriverEntry.new()
	synthetic.id = &"synthetic_ungated_driver"
	synthetic.character_scene_path = ""
	var scene := DriverRegistry._fallback_scene(synthetic.id, synthetic.character_scene_path)
	assert_not_null(scene, "a synthetic empty-path entry must still resolve to the lab assistant")
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _FALLBACK_PATH)
	assert_push_warning(str(synthetic.id))
	assert_push_error_count(0, "a fallback-active driver must never push_error")


func test_character_scene_falls_back_to_lab_assistant_for_an_unknown_id() -> void:
	var scene := DriverRegistry.character_scene(&"not_a_real_driver")
	assert_not_null(scene)
	if scene == null:
		return
	var instance := scene.instantiate()
	add_child_autofree(instance)
	assert_eq(instance.scene_file_path, _FALLBACK_PATH)
	assert_push_warning("not_a_real_driver")
	assert_push_error_count(0)


func test_driver_class_maps_every_driver_to_its_authored_class() -> void:
	var expected := {
		&"crash": "res://data/tuning/racing/classes/balanced.tres",
		&"papu": "res://data/tuning/racing/classes/speed.tres",
		&"cortex": "res://data/tuning/racing/classes/balanced.tres",
		&"coco": "res://data/tuning/racing/classes/accel.tres",
		&"ripper_roo": "res://data/tuning/racing/classes/turning.tres",
		&"lab_assistant": "res://data/tuning/racing/classes/balanced.tres",
	}
	for id: StringName in expected:
		var driver_class := DriverRegistry.driver_class(id)
		assert_not_null(driver_class, "%s must resolve a real DriverClass" % id)
		var want: DriverClass = load(expected[id])
		if driver_class != null:
			assert_eq(driver_class.top_speed_mult, want.top_speed_mult, "%s top_speed_mult" % id)
			assert_eq(driver_class.accel_mult, want.accel_mult, "%s accel_mult" % id)
			assert_eq(driver_class.steer_rate_mult, want.steer_rate_mult, "%s steer_rate_mult" % id)


func test_driver_class_is_null_safe_for_an_unknown_id() -> void:
	assert_null(DriverRegistry.driver_class(&"not_a_real_driver"))
