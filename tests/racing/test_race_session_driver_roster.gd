extends GutTest

## CTR R8 Task 2 (characters/select/classes): RaceSession's own driver-
## roster wiring -- configure_selected_driver()/the player's own mount+
## compose path, _spawn_ai_karts()'s own AI-fill-excludes-the-pick path, and
## the "tints stay a slot trait, never a driver trait" pin the design spec
## and brief both call out by name. DriverRegistry's own resolution/fallback
## contract is proven in isolation in tests/racing/roster/test_driver_
## registry.gd; this file only proves RaceSession's OWN use of it. Per-class
## real-physics Temple Twilight health races live in their own dedicated
## file (test_race_session_temple_twilight_classes.gd) -- these are cheap,
## non-physics proofs, kept fast and separate on purpose.

const RACE_SCENE_PATH := "res://scenes/racing/race_time_trial.tscn"
const CATALOG_PATH := "res://data/tuning/gameplay.tres"
const CRASH_CHARACTER_SCENE_PATH := "res://assets/models/characters/SK_crash.glb"
const LAB_ASSISTANT_CHARACTER_SCENE_PATH := "res://assets/models/enemies/SK_lab_assistant.glb"
## Task 5 (characters/select/classes): papu's own DriverEntry now resolves
## for real instead of falling back to the lab assistant like every other
## still-gated driver -- see data/racing/drivers/papu.tres.
const PAPU_SEATED_CHARACTER_SCENE_PATH := "res://assets/models/bosses/SK_papu_seated.glb"

var _catalog: GameplayTuning


func before_all() -> void:
	_catalog = load(CATALOG_PATH)
	assert_not_null(_catalog, "gameplay.tres must load")


# R5 Task 1: see test_race_session.gd's identical helper for the full
# rationale -- karts spawn frozen through a real pre-race countdown, and
# every boot in this file needs the race actually configured/running.
const _COUNTDOWN_SKIP_DELTA_S := 1000.0


func _skip_pre_race_countdown(race: Node) -> void:
	race.call("_tick_countdown", _COUNTDOWN_SKIP_DELTA_S)


## selected_driver_id == &"" keeps RaceSession's own default (&"crash",
## unset) -- every existing scene/test that never calls configure_selected_
## driver() at all.
func _boot_race(selected_driver_id: StringName = &"") -> Node:
	assert_true(ResourceLoader.exists(RACE_SCENE_PATH), "race_time_trial.tscn must exist")
	if not ResourceLoader.exists(RACE_SCENE_PATH):
		return null
	var packed := load(RACE_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var race := packed.instantiate()
	add_child_autofree(race)
	# CTR R8 Task 2: configure_selected_driver() must be called BEFORE
	# configure() -- see that setter's own doc for why (configure() reads
	# _selected_driver_id once, at mount time, the same "set the field, THEN
	# configure() reads it" ordering track_id/spawn_opponents already use).
	if not selected_driver_id.is_empty():
		race.call("configure_selected_driver", selected_driver_id)
	race.call("configure", _catalog)
	_skip_pre_race_countdown(race)
	return race


func _mounted_scene_path(kart: CharacterBody3D) -> String:
	var mounted: Node3D = kart.call("mounted_character")
	if mounted == null:
		return ""
	return mounted.scene_file_path


func _material_albedo(kart: CharacterBody3D) -> Variant:
	var visual := kart.get_node_or_null("Visual")
	if visual == null:
		return null
	var mesh_instances: Array[Node] = visual.find_children("*", "MeshInstance3D", true, false)
	if mesh_instances.is_empty():
		return null
	var material := (
		(mesh_instances[0] as MeshInstance3D).material_override as StandardMaterial3D
	)
	return material.albedo_color if material != null else null


# ---------------------------------------------------------------------------
# Player mounts its pick.
# ---------------------------------------------------------------------------


func test_default_player_pick_still_mounts_crash_unchanged() -> void:
	var race := _boot_race()
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	assert_eq(
		_mounted_scene_path(kart),
		CRASH_CHARACTER_SCENE_PATH,
		"with no configure_selected_driver() call, the player must still mount Crash -- R6/R7 behavior unchanged"
	)
	var tuning: KartTuning = kart.get("_tuning")
	assert_not_null(tuning)
	if tuning != null:
		assert_eq(
			tuning.top_speed_mps,
			_catalog.kart.top_speed_mps,
			"crash's own class is Balanced (1.0 multipliers) -- composed top_speed_mps must equal the shared base exactly"
		)


func test_configure_selected_driver_mounts_the_pick_and_composes_its_class() -> void:
	var race := _boot_race(&"papu")
	if race == null:
		return
	var kart := race.get_node("Kart") as CharacterBody3D
	# Task 5 (characters/select/classes): papu's own DriverEntry now ships
	# a real character_scene_path (data/racing/drivers/papu.tres) -- his
	# pose + seat fit reused his already-operator-accepted platformer mesh,
	# not a new likeness gate, so DriverRegistry.character_scene() resolves
	# him for real instead of reaching _fallback_scene(). This proves the
	# pick reached the real mount call with the real model, not merely that
	# SOMETHING mounted.
	assert_eq(
		_mounted_scene_path(kart),
		PAPU_SEATED_CHARACTER_SCENE_PATH,
		"papu is gated for real now -- the player must seat his own seated model, never crash or the lab assistant"
	)
	var tuning: KartTuning = kart.get("_tuning")
	assert_not_null(tuning)
	if tuning != null:
		var speed_class: DriverClass = load("res://data/tuning/racing/classes/speed.tres")
		assert_eq(
			tuning.top_speed_mps,
			_catalog.kart.top_speed_mps * speed_class.top_speed_mult,
			"papu's own Speed class must be composed onto the player's own kart tuning"
		)
		assert_eq(
			tuning.steer_rate_degrees_per_s,
			_catalog.kart.steer_rate_degrees_per_s * speed_class.steer_rate_mult,
			"papu's own Speed class must be composed onto the player's own kart tuning"
		)


## CTR R8 Task 3 (save v3->v4 + ghost v2): configure() threads the player's
## own pick into _ghost_recorder (RaceSession's own GHOST WIRING section) so
## a solo run's ghost is recorded under the driver it was actually raced
## with, not always the "crash" default -- see GhostRecorder.set_driver_id()'s
## own doc and configure()'s own call-site comment for the ordering this
## relies on.
func test_configure_threads_the_selected_driver_into_the_ghost_recorder() -> void:
	var race := _boot_race(&"papu")
	if race == null:
		return
	var recorder: Object = race.get("_ghost_recorder")
	assert_not_null(recorder)
	if recorder != null:
		assert_eq(recorder.call("driver_id"), &"papu")


func test_configure_with_no_pick_still_records_the_default_crash_driver() -> void:
	var race := _boot_race()
	if race == null:
		return
	var recorder: Object = race.get("_ghost_recorder")
	assert_not_null(recorder)
	if recorder != null:
		assert_eq(recorder.call("driver_id"), &"crash")


func test_player_kart_tint_is_unaffected_by_which_driver_is_picked() -> void:
	var default_race := _boot_race()
	if default_race == null:
		return
	var papu_race := _boot_race(&"papu")
	if papu_race == null:
		return
	var default_tint: Variant = _material_albedo(default_race.get_node("Kart") as CharacterBody3D)
	var papu_tint: Variant = _material_albedo(papu_race.get_node("Kart") as CharacterBody3D)
	assert_not_null(default_tint)
	assert_eq(
		default_tint,
		papu_tint,
		"kart_tint_player is a fixed identity colour -- unaffected by which driver is mounted"
	)


# ---------------------------------------------------------------------------
# AI fill excludes the pick, deterministic, 5 distinct.
# ---------------------------------------------------------------------------


## Direct proof of _ai_fill_driver_ids() (private, called the same way this
## suite already reflects into other private RaceSession helpers -- e.g.
## test_race_session.gd's own _tick_countdown()/_on_gate_body_entered()
## calls). See that helper's own doc for why a spawned kart's external state
## (mesh/tuning) alone cannot prove this: 3 of the 6 roster ids share the
## identical Balanced class. R8 gate flip 2026-08-02: cortex/coco/
## ripper_roo's own likeness gates are now operator-accepted, same as
## papu's earlier Task 5 flip, so this bar no longer applies to the mounted
## mesh -- every roster id now ships its own distinct real scene.
func test_ai_fill_excludes_the_pick_no_duplicates_deterministic_order() -> void:
	var race := RaceSession.new()
	add_child_autofree(race)

	race.call("configure_selected_driver", &"crash")
	assert_eq(
		race.call("_ai_fill_driver_ids"),
		[&"papu", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"],
		"picking crash must fill AI with the other 5, in registry order"
	)

	race.call("configure_selected_driver", &"papu")
	assert_eq(
		race.call("_ai_fill_driver_ids"),
		[&"crash", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"],
		"picking papu must fill AI with the other 5, in registry order"
	)

	race.call("configure_selected_driver", &"lab_assistant")
	assert_eq(
		race.call("_ai_fill_driver_ids"),
		[&"crash", &"papu", &"cortex", &"coco", &"ripper_roo"],
		"picking lab_assistant must fill AI with the other 5, in registry order"
	)


func test_ai_fill_is_always_five_distinct_ids_for_every_possible_pick() -> void:
	var race := RaceSession.new()
	add_child_autofree(race)
	for pick: StringName in [&"crash", &"papu", &"cortex", &"coco", &"ripper_roo", &"lab_assistant"]:
		race.call("configure_selected_driver", pick)
		var ids: Array = race.call("_ai_fill_driver_ids")
		assert_eq(ids.size(), 5, "picking %s must still leave exactly 5 AI ids" % pick)
		assert_false(ids.has(pick), "the AI fill must never include the player's own pick (%s)" % pick)
		var seen: Array = []
		for id: Variant in ids:
			assert_false(seen.has(id), "AI fill must never duplicate an id -- got a repeat of %s" % id)
			seen.append(id)


func test_ai_karts_spawn_with_the_registry_driven_fill_real_race() -> void:
	var race := _boot_race(&"crash")
	if race == null:
		return
	var opponent_count := int(_catalog.ai.opponent_count)
	assert_eq(int(race.call("ai_kart_count")), opponent_count, "fixture sanity: the default AI roster must spawn")

	# crash (Balanced, 1.0 mults) is picked, so AI fill = papu(Speed),
	# cortex(Balanced), coco(Accel), ripper_roo(Turning), lab_assistant
	# (Balanced) -- see _ai_fill_driver_ids()'s own doc for the fixed order.
	var speed_class: DriverClass = load("res://data/tuning/racing/classes/speed.tres")
	var accel_class: DriverClass = load("res://data/tuning/racing/classes/accel.tres")
	var turning_class: DriverClass = load("res://data/tuning/racing/classes/turning.tres")
	var expected_top_speed_mults := [
		speed_class.top_speed_mult,
		1.0,
		accel_class.top_speed_mult,
		turning_class.top_speed_mult,
		1.0,
	]
	for slot_index: int in range(opponent_count):
		var ai_kart := race.call("ai_kart", slot_index) as CharacterBody3D
		assert_not_null(ai_kart, "an AI kart must exist at slot %d" % slot_index)
		if ai_kart == null:
			continue
		var tuning: KartTuning = ai_kart.get("_tuning")
		assert_not_null(tuning, "AI kart slot %d must own a configured KartTuning" % slot_index)
		if tuning == null:
			continue
		assert_almost_eq(
			tuning.top_speed_mps,
			_catalog.kart.top_speed_mps * expected_top_speed_mults[slot_index],
			0.001,
			"AI slot %d must compose the registry-assigned driver's own class" % (slot_index + 1)
		)


# ---------------------------------------------------------------------------
# Tints stay a slot trait, never a driver trait (brief pin).
# ---------------------------------------------------------------------------


func test_ai_slot_tints_are_pinned_to_the_slot_not_the_occupying_driver() -> void:
	var crash_pick_race := _boot_race(&"crash")
	if crash_pick_race == null:
		return
	var lab_assistant_pick_race := _boot_race(&"lab_assistant")
	if lab_assistant_pick_race == null:
		return

	# Slot 1 seats papu when crash is picked, but crash when lab_assistant is
	# picked (see _ai_fill_driver_ids()'s own doc) -- two DIFFERENT drivers,
	# same slot. The tint at slot 1 must be identical either way.
	var slot1_with_crash_picked: Variant = _material_albedo(
		crash_pick_race.call("ai_kart", 0) as CharacterBody3D
	)
	var slot1_with_lab_assistant_picked: Variant = _material_albedo(
		lab_assistant_pick_race.call("ai_kart", 0) as CharacterBody3D
	)
	assert_not_null(slot1_with_crash_picked)
	assert_eq(
		slot1_with_crash_picked,
		slot1_with_lab_assistant_picked,
		"slot 1's own tint must stay fixed regardless of which driver occupies it"
	)
	assert_eq(
		slot1_with_crash_picked,
		_catalog.kart.tint_for_slot(1),
		"slot 1's own tint must come from KartTuning.tint_for_slot(1), unchanged by this task"
	)
