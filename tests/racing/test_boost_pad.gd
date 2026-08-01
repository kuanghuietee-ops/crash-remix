extends GutTest

# Task 1 (CTR R7, discharges spec debt #2): BoostPad is a self-contained
# Area3D whose only owned state is the per-kart refire cooldown -- see
# boost_pad.gd's own class doc. Mirrors test_item_box.gd's "load the raw
# script, prove the node-level contract" shape for the monitoring-defaults
# test, and test_kart_controller.gd's "spawn a real body, let real physics
# advance frames" shape for the cooldown-over-time tests.

const PAD_SCRIPT_PATH := "res://src/racing/track/boost_pad.gd"
const PAD_SCENE_PATH := "res://scenes/racing/boost_pad.tscn"
const RACE_TUNING_PATH := "res://data/tuning/racing/race.tres"

var _tuning: RaceTuning


func before_all() -> void:
	_tuning = load(RACE_TUNING_PATH)
	assert_not_null(_tuning, "race.tres must load -- CTR R7 Task 1 registers pad_boost_s/pad_refire_cooldown_s")


# ---------------------------------------------------------------------------
# Monitoring defaults (mirrors test_checkpoint_gate.gd/test_item_box.gd).
# ---------------------------------------------------------------------------


func test_pad_forces_monitoring_on_and_monitorable_off() -> void:
	var pad: Area3D = load(PAD_SCRIPT_PATH).new()
	pad.monitoring = false
	pad.monitorable = true
	add_child_autofree(pad)

	assert_true(pad.monitoring, "_ready() must force monitoring on")
	assert_false(pad.monitorable, "_ready() must force monitorable off")


# ---------------------------------------------------------------------------
# Scene wiring.
# ---------------------------------------------------------------------------


func test_pad_scene_loads_and_instantiates_with_collision_and_mesh() -> void:
	assert_true(ResourceLoader.exists(PAD_SCENE_PATH), "the boost pad graybox scene must exist")
	if not ResourceLoader.exists(PAD_SCENE_PATH):
		return
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	assert_not_null(pad.get_node_or_null("CollisionShape3D"))
	assert_not_null(pad.get_node_or_null("Mesh"))


## See item_box.gd's own class doc BODY FILTER section for the full
## rationale -- collision_mask = 4 (kart-only bit 3) so a graybox floor/
## wall StaticBody3D (plain Godot layer-1 default) never trips a pad.
func test_pad_scene_uses_the_kart_only_body_filter() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	assert_eq(pad.collision_mask, 4, "must only detect the kart-only bit, same as item_box.tscn")


# ---------------------------------------------------------------------------
# try_consume(): per-kart refire cooldown, no wall clock.
# ---------------------------------------------------------------------------


func test_try_consume_returns_false_before_configure() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))

	assert_false(
		bool(pad.call("try_consume", kart)),
		"an unconfigured pad (no tuning yet) must never claim a fire"
	)


func test_try_consume_fires_on_first_pass() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	pad.call("configure", _tuning)
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))

	assert_true(
		bool(pad.call("try_consume", kart)),
		"a kart's first-ever pass through this pad must always fire"
	)


func test_try_consume_blocks_an_immediate_second_pass_within_the_cooldown() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	pad.call("configure", _tuning)
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))
	assert_true(bool(pad.call("try_consume", kart)), "fixture setup: the first pass must fire")

	assert_false(
		bool(pad.call("try_consume", kart)),
		"an immediate re-entry (parked overlap, or a lap loop-back) must not refire within pad_refire_cooldown_s"
	)


func test_try_consume_allows_a_refire_once_pad_refire_cooldown_s_elapses() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	pad.call("configure", _tuning)
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))
	assert_true(bool(pad.call("try_consume", kart)), "fixture setup: the first pass must fire")

	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 5
	var frames_needed := int(ceil(_tuning.pad_refire_cooldown_s * physics_fps)) + margin_frames
	await wait_physics_frames(frames_needed)

	assert_true(
		bool(pad.call("try_consume", kart)),
		"a pass after pad_refire_cooldown_s has fully elapsed must fire again"
	)


func test_try_consume_stays_blocked_shortly_before_pad_refire_cooldown_s_elapses() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	pad.call("configure", _tuning)
	var kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))
	assert_true(bool(pad.call("try_consume", kart)), "fixture setup: the first pass must fire")

	var physics_fps := float(Engine.physics_ticks_per_second)
	var margin_frames := 5
	var frames_short_of_cooldown := int(floor(_tuning.pad_refire_cooldown_s * physics_fps)) - margin_frames
	assert_gt(frames_short_of_cooldown, 0, "fixture sanity: pad_refire_cooldown_s must be several frames long")
	if frames_short_of_cooldown <= 0:
		return
	await wait_physics_frames(frames_short_of_cooldown)

	assert_false(
		bool(pad.call("try_consume", kart)),
		"must stay blocked right up until pad_refire_cooldown_s has actually elapsed"
	)


## Per-KART, not global -- a second kart's own first pass must fire
## regardless of whatever cooldown state the first kart already claimed.
func test_try_consume_cooldown_is_independent_per_kart() -> void:
	var pad := _new_pad(Vector3.ZERO)
	if pad == null:
		return
	pad.call("configure", _tuning)
	var first_kart := _new_kart_body(Vector3(500.0, 0.0, 0.0))
	var second_kart := _new_kart_body(Vector3(600.0, 0.0, 0.0))
	assert_true(bool(pad.call("try_consume", first_kart)), "fixture setup: kart 1's first pass must fire")
	assert_false(
		bool(pad.call("try_consume", first_kart)),
		"fixture setup: kart 1's immediate second pass must be blocked"
	)

	assert_true(
		bool(pad.call("try_consume", second_kart)),
		"kart 2's own first pass must fire -- the cooldown is per-kart, not shared across the whole pad"
	)


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------


func _new_pad(origin: Vector3) -> Area3D:
	var packed := load(PAD_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var pad := packed.instantiate() as Area3D
	assert_not_null(pad)
	if pad == null:
		return null
	pad.position = origin
	add_child_autofree(pad)
	return pad


## A minimal stand-in for kart.tscn's own CharacterBody3D -- see item_box.gd's
## own test suite (_new_kart_body's own doc) for the full BODY FILTER and
## position-before-add_child_autofree rationale this mirrors exactly.
## try_consume() itself never inspects collision at all (it is called
## directly, not driven through a real Area3D overlap), so a minimal body
## with no collision shape at all would work too -- this mirrors the real
## kart shape anyway for consistency with the rest of this suite family and
## so a future overlap-driven test can reuse it unchanged.
func _new_kart_body(origin: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 5
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 0.6, 2.0)
	collision.shape = shape
	body.add_child(collision)
	body.position = origin
	add_child_autofree(body)
	return body
