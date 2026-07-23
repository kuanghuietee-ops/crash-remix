extends GutTest

const PHASE_SET_SCRIPT_PATH := "res://src/gameplay/phase/phase_set.gd"
const BASE_CATALOG_PATH := "res://data/tuning/gameplay.tres"

var _phase: Resource


func before_all() -> void:
	var catalog: Resource = load(BASE_CATALOG_PATH)
	assert_not_null(catalog)
	if catalog != null:
		_phase = catalog.get("phase")


func test_exactly_one_set_is_solid_at_all_times() -> void:
	var phase_set: RefCounted = _new_phase_set()

	for index in 8:
		var blue_solid: bool = phase_set.call("is_solid", &"blue")
		var orange_solid: bool = phase_set.call("is_solid", &"orange")
		var blue_ghost: bool = phase_set.call("is_ghost", &"blue")
		var orange_ghost: bool = phase_set.call("is_ghost", &"orange")
		assert_ne(
			blue_solid,
			orange_solid,
			"both solid or both ghost at step %d" % index
		)
		assert_ne(blue_ghost, orange_ghost)
		assert_ne(blue_solid, blue_ghost)
		assert_ne(orange_solid, orange_ghost)
		phase_set.call("try_toggle", float(index), _phase)


func test_retoggle_cooldown_is_honored() -> void:
	var phase_set: RefCounted = _new_phase_set()
	var cooldown_s: float = _phase.get("retoggle_cooldown_s")

	assert_true(phase_set.call("try_toggle", 1.0, _phase))
	var set_after_toggle: StringName = phase_set.get("active_set")
	assert_false(
		phase_set.call("try_toggle", 1.1, _phase),
		"flipped inside the cooldown"
	)
	assert_eq(
		phase_set.get("active_set"),
		set_after_toggle,
		"rejected toggle must not mutate the active set"
	)
	assert_true(
		phase_set.call("try_toggle", 1.0 + cooldown_s, _phase),
		"exact cooldown boundary must be inclusive"
	)
	assert_ne(phase_set.get("active_set"), set_after_toggle)


func test_first_toggle_is_always_allowed() -> void:
	var phase_set: RefCounted = _new_phase_set()

	assert_true(phase_set.call("can_toggle", 0.0, _phase))


func _new_phase_set() -> RefCounted:
	var script: GDScript = load(PHASE_SET_SCRIPT_PATH)
	assert_not_null(script)
	return script.new() if script != null else null
