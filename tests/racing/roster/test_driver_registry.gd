extends GutTest

## CTR R8 Task 2 (characters/select/classes): DriverRegistry's own resolution
## + fallback contract -- see driver_registry.gd's own class doc. RaceSession
## wiring (player mount, AI fill, tint pinning, per-class health) is proven
## separately in tests/racing/test_race_session_driver_roster.gd; this file
## only proves the registry's own four public methods in isolation.

const _FALLBACK_PATH := "res://assets/models/enemies/SK_lab_assistant.glb"
const _CRASH_PATH := "res://assets/models/characters/SK_crash.glb"


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


## The spec's own fallback rule: an unfinished driver's empty character_
## scene_path silently seats the lab assistant instead -- no push_error, no
## null return, exactly one push_warning (see driver_registry.gd's own
## _fallback_scene() doc).
func test_character_scene_falls_back_to_lab_assistant_for_an_empty_path() -> void:
	for fallback_id: StringName in [&"papu", &"cortex", &"coco", &"ripper_roo"]:
		var scene := DriverRegistry.character_scene(fallback_id)
		assert_not_null(scene, "%s must still resolve to a real PackedScene" % fallback_id)
		if scene == null:
			continue
		var instance := scene.instantiate()
		add_child_autofree(instance)
		assert_eq(
			instance.scene_file_path,
			_FALLBACK_PATH,
			"%s has no character scene yet -- must silently seat the lab assistant" % fallback_id
		)
		assert_push_warning(str(fallback_id))
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
