extends GutTest

## CTR R8 Task 1 (characters/select/classes): the four shipped driver
## classes (data/tuning/racing/classes/*.tres) load with their exact
## authored multipliers -- see the plan's own "these defaults are feel-gate
## fodder, not sacred, but they ARE the shipped values until the operator
## says otherwise". Pinned so a future edit is a deliberate, visible diff to
## this test, not a silent drift. fingerprint() coverage mirrors test_level_
## meta.gd's own test_level_meta_fingerprint_moves_when_a_par_changes shape
## exactly -- see driver_class.gd's own doc for why DriverClass carries the
## identical per-resource fingerprint() pattern LevelMeta already does.

const BALANCED_PATH := "res://data/tuning/racing/classes/balanced.tres"
const SPEED_PATH := "res://data/tuning/racing/classes/speed.tres"
const ACCEL_PATH := "res://data/tuning/racing/classes/accel.tres"
const TURNING_PATH := "res://data/tuning/racing/classes/turning.tres"


func _assert_multipliers(
	path: String,
	top_speed_mult: float,
	accel_mult: float,
	steer_rate_mult: float
) -> void:
	var driver_class := load(path) as Resource
	assert_not_null(driver_class, "%s must load" % path)
	if driver_class == null:
		return
	assert_eq(driver_class.get("top_speed_mult"), top_speed_mult)
	assert_eq(driver_class.get("accel_mult"), accel_mult)
	assert_eq(driver_class.get("steer_rate_mult"), steer_rate_mult)


func test_balanced_class_loads_with_neutral_multipliers() -> void:
	_assert_multipliers(BALANCED_PATH, 1.0, 1.0, 1.0)


func test_speed_class_loads_with_its_authored_multipliers() -> void:
	_assert_multipliers(SPEED_PATH, 1.06, 0.97, 0.90)


func test_accel_class_loads_with_its_authored_multipliers() -> void:
	_assert_multipliers(ACCEL_PATH, 0.98, 1.12, 1.02)


func test_turning_class_loads_with_its_authored_multipliers() -> void:
	_assert_multipliers(TURNING_PATH, 0.96, 1.0, 1.12)


func test_driver_class_fingerprint_moves_when_a_multiplier_changes() -> void:
	var loaded := load(BALANCED_PATH) as Resource
	assert_not_null(loaded)
	if loaded == null:
		return
	var driver_class := loaded.duplicate() as Resource
	var before: String = driver_class.call("fingerprint")

	driver_class.set("top_speed_mult", 1.06)

	assert_ne(
		before,
		driver_class.call("fingerprint"),
		"a driver class's own multipliers never reach its fingerprint"
	)
	assert_eq(before.length(), 64)
