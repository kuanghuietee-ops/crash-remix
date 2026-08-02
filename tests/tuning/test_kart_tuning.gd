extends GutTest

## CTR R8 Task 1 (characters/select/classes): pure-logic coverage for
## KartTuning.composed_with(DriverClass) -- see that method's own doc.
## RaceSession's own integration coverage (each kart actually receiving a
## composed duplicate, and the live-refresh path recomposing it) lives in
## tests/racing/test_race_session.gd, matching the existing split between
## this file's would-be KartTuning-only concerns and that file's own
## scene-level proofs.

const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"

## The exact three fields composed_with() is documented to touch -- see
## driver_class.gd's own doc and KartTuning.composed_with()'s own doc for
## why these three and no others.
const COMPOSED_FIELD_NAMES: Array[StringName] = [
	&"top_speed_mps",
	&"accel_mps2",
	&"steer_rate_degrees_per_s",
]


func _base_kart_tuning() -> KartTuning:
	# duplicate() immediately after load(): KART_TUNING_PATH resolves
	# through Godot's own resource cache, so mutating a bare load() result
	# in-place would leak across every other test/file that also loads
	# kart.tres this same run -- the identical reason test_race_session.gd's
	# own refresh_tuning test duplicates _catalog before touching it.
	var loaded := load(KART_TUNING_PATH) as KartTuning
	return loaded.duplicate() as KartTuning


func _driver_class(
	top_speed_mult: float,
	accel_mult: float,
	steer_rate_mult: float
) -> DriverClass:
	var driver_class := DriverClass.new()
	driver_class.top_speed_mult = top_speed_mult
	driver_class.accel_mult = accel_mult
	driver_class.steer_rate_mult = steer_rate_mult
	return driver_class


## Mirrors TuningService._exported_property_names()/LevelMeta.fingerprint()'s
## own identical filter -- every field composed_with() must leave alone is
## enumerated this way rather than hand-listed, so a future KartTuning field
## can never silently escape this test's own "no others" coverage.
func _exported_property_names(resource: Resource) -> PackedStringArray:
	var names := PackedStringArray()
	for property_info: Dictionary in resource.get_property_list():
		var usage: int = property_info["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property_info["name"])
	return names


func test_composed_with_multiplies_exactly_the_three_named_fields() -> void:
	var base := _base_kart_tuning()
	var driver_class := _driver_class(1.06, 0.97, 0.90)

	var composed := base.composed_with(driver_class)

	assert_almost_eq(
		composed.top_speed_mps,
		base.top_speed_mps * 1.06,
		0.0001,
		"top_speed_mps must scale by the class's own top_speed_mult"
	)
	assert_almost_eq(
		composed.accel_mps2,
		base.accel_mps2 * 0.97,
		0.0001,
		"accel_mps2 must scale by the class's own accel_mult"
	)
	assert_almost_eq(
		composed.steer_rate_degrees_per_s,
		base.steer_rate_degrees_per_s * 0.90,
		0.0001,
		"steer_rate_degrees_per_s must scale by the class's own steer_rate_mult"
	)


func test_composed_with_leaves_every_other_field_unchanged() -> void:
	var base := _base_kart_tuning()
	# A uniform, obviously-not-1.0 multiplier on every field: if composed_
	# with() ever touched a field outside COMPOSED_FIELD_NAMES, this would
	# make that leak impossible to miss (an untouched field can only ever
	# equal the base's own value, never 1.5x it).
	var driver_class := _driver_class(1.5, 1.5, 1.5)

	var composed := base.composed_with(driver_class)

	for property_name: StringName in _exported_property_names(base):
		if COMPOSED_FIELD_NAMES.has(property_name):
			continue
		assert_eq(
			composed.get(property_name),
			base.get(property_name),
			"composed_with() must leave %s untouched" % property_name
		)


func test_composed_with_does_not_mutate_the_shared_base_resource() -> void:
	var base := _base_kart_tuning()
	var original_top_speed := base.top_speed_mps
	var original_accel := base.accel_mps2
	var original_steer_rate := base.steer_rate_degrees_per_s
	var driver_class := _driver_class(2.0, 2.0, 2.0)

	var composed := base.composed_with(driver_class)

	assert_eq(
		base.top_speed_mps,
		original_top_speed,
		"the shared base resource's top_speed_mps must never be mutated by compose"
	)
	assert_eq(
		base.accel_mps2,
		original_accel,
		"the shared base resource's accel_mps2 must never be mutated by compose"
	)
	assert_eq(
		base.steer_rate_degrees_per_s,
		original_steer_rate,
		"the shared base resource's steer_rate_degrees_per_s must never be mutated by compose"
	)
	assert_ne(
		composed.get_instance_id(),
		base.get_instance_id(),
		"composed_with() must return an independent instance, never the shared resource itself"
	)


func test_composed_with_null_class_returns_identical_values_as_a_distinct_instance() -> void:
	var base := _base_kart_tuning()

	var composed := base.composed_with(null)

	assert_ne(
		composed.get_instance_id(),
		base.get_instance_id(),
		"even a null class must still hand back the kart's own instance, never the shared resource"
	)
	for property_name: StringName in _exported_property_names(base):
		assert_eq(
			composed.get(property_name),
			base.get(property_name),
			"a null driver_class must leave every field identical to the shared base, including %s" % property_name
		)


## The "hash moves" proof (CLAUDE.md rule 2) applied at composed_with()'s own
## boundary: a live edit to the SAME DriverClass instance (the on-device-
## drawer/live-refresh shape, not a fresh object) must be reflected the very
## next time it is composed, never a value snapshotted from an earlier call.
func test_composed_with_reflects_a_live_edit_to_the_driver_class() -> void:
	var base := _base_kart_tuning()
	var driver_class := _driver_class(1.0, 1.0, 1.0)

	var before := base.composed_with(driver_class)
	driver_class.top_speed_mult = 1.06
	var after := base.composed_with(driver_class)

	assert_ne(
		before.top_speed_mps,
		after.top_speed_mps,
		(
			"composed_with() must read the driver class's CURRENT field "
			+ "values, not a stale snapshot -- an on-device tuning edit "
			+ "must change the composed result on the very next call"
		)
	)
	assert_almost_eq(after.top_speed_mps, base.top_speed_mps * 1.06, 0.0001)
