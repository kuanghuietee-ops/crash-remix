extends GutTest

# Task 1 (CTR R6, circuit polish): KartFx is a poll-model FX driver riding
# along on every kart.tscn instance (player and AI alike) -- see kart_fx.gd's
# own class doc. Mirrors test_kart_controller.gd's "spawn the real scene,
# drive it via its real public API, let real physics/timing do the rest"
# shape rather than faking DriftStateMachine/KartMotor state directly, so
# these tests prove the state actually reaches KartFx through the same
# controller getters production code (race_session.gd) reads.

const KART_SCENE_PATH := "res://scenes/racing/kart.tscn"
const KART_TUNING_PATH := "res://data/tuning/racing/kart.tres"
const FX_TUNING_PATH := "res://data/tuning/racing/fx.tres"

var _kart_tuning: KartTuning
var _fx_tuning: FxTuning


func before_all() -> void:
	_kart_tuning = load(KART_TUNING_PATH)
	assert_not_null(_kart_tuning, "kart.tres must load")
	_fx_tuning = load(FX_TUNING_PATH)
	assert_not_null(_fx_tuning, "fx.tres must load -- Task 1 registers it")


func test_kart_scene_wires_an_fx_node_with_sparks_and_flame_emitters() -> void:
	assert_true(ResourceLoader.exists(KART_SCENE_PATH))
	if not ResourceLoader.exists(KART_SCENE_PATH):
		return
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var kart := packed.instantiate() as Node3D
	add_child_autofree(kart)

	var fx := kart.get_node_or_null("Fx")
	assert_not_null(fx, "kart.tscn must instance a Fx node (kart_fx.gd)")
	if fx == null:
		return
	var sparks := fx.get_node_or_null("Sparks") as GPUParticles3D
	var flame := fx.get_node_or_null("Flame") as GPUParticles3D
	assert_not_null(sparks, "Fx must carry a Sparks GPUParticles3D child")
	assert_not_null(flame, "Fx must carry a Flame GPUParticles3D child")
	if sparks == null or flame == null:
		return

	assert_false(sparks.emitting, "sparks must start off")
	assert_false(flame.emitting, "flame must start off")
	assert_false(sparks.one_shot, "drift sparks are a continuous stream, not a burst")
	assert_false(flame.one_shot, "the boost flame is a continuous stream, not a burst")
	assert_eq(
		sparks.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"mobile posture: sparks must not cast shadows"
	)
	assert_eq(
		flame.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"mobile posture: the boost flame must not cast shadows"
	)


func test_sparks_are_off_while_not_sliding() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)

	await wait_physics_frames(2)

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	assert_false(sparks.emitting, "a kart that never slides must never emit drift sparks")


func test_sparks_emit_at_stage_0_amount_and_color_while_sliding() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)
	await wait_physics_frames(10)
	assert_true(kart.is_on_floor(), "fixture setup must be grounded before sliding")

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")
	assert_eq(int(kart.call("boost_stage")), 0, "fixture setup: no boost tap fired yet")

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	assert_true(sparks.emitting, "sliding must emit drift sparks")
	assert_eq(
		sparks.amount,
		roundi(_fx_tuning.spark_amount_stage0),
		"stage 0 amount must be the raw spark_amount_stage0"
	)
	var process_material := sparks.process_material as ParticleProcessMaterial
	assert_not_null(process_material)
	if process_material == null:
		return
	assert_eq(
		process_material.color,
		_fx_tuning.spark_color_stage1,
		"stage 0 must borrow stage 1's color (no separate stage-0 color field)"
	)


func test_sparks_stop_the_instant_the_slide_ends() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)
	await wait_physics_frames(10)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	kart.call("steer", 0.0)
	await wait_physics_frames(2)
	assert_false(kart.call("is_sliding"), "fixture setup: straightening must end the slide")

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	assert_false(sparks.emitting, "sparks must stop the instant the slide ends")


## Task 1 fix round 1 (CTR R6, circuit polish reviewer [LOW]): the original
## version of this test only drove taps through stage 2, leaving stage 3 --
## kart.tres's own authored boost_stack_max, the actual CAP -- completely
## unexercised end-to-end. Drives REAL slide-boost taps through
## DriftStateMachine (via the real controller's boost_tap(), not a stand-in)
## all the way to the cap, asserting amount/color at every stage along the
## way plus the cap itself: one further tap beyond boost_stack_max must be
## ignored, not silently escalate to a phantom stage with no tuned color.
## stage_cap is read off _kart_tuning.boost_stack_max rather than hardcoded,
## so this stays correct if that field is ever retuned; the fixture-sanity
## assert below still pins today's authored value at exactly 3, the "stage
## N -> color N" shape the Task brief calls out explicitly, through every N
## fx_tuning actually has a dedicated color for.
func test_spark_amount_and_color_escalate_with_each_real_boost_tap_through_the_cap() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)
	await wait_physics_frames(10)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	await wait_physics_frames(2)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	var process_material := sparks.process_material as ParticleProcessMaterial
	assert_not_null(process_material)
	if process_material == null:
		return

	var stage_cap := roundi(_kart_tuning.boost_stack_max)
	assert_eq(
		stage_cap,
		3,
		"fixture sanity: kart.tres's authored boost_stack_max must still be "
		+ "3 -- fx.tres only authors 3 stage colors, and a cap above that "
		+ "would leave later stages with no dedicated tuned color at all"
	)
	var stage_colors: Array[Color] = [
		_fx_tuning.spark_color_stage1,
		_fx_tuning.spark_color_stage2,
		_fx_tuning.spark_color_stage3,
	]

	# Each stacked stage's own tap window is [open_s, close_s] scaled by
	# boost_window_shrink_factor^stage (see drift_state_machine.gd's own
	# boost_tap() doc) -- SHRINKING with every successful tap. A single
	# fixed wait duration (the LOW's own bug: the first draft of this test
	# reused stage 0's un-scaled boost_window_open_s for every iteration)
	# lands inside stage 0/1's wider windows but overshoots stage 2's
	# narrower one, so this tracks exactly how many frames have elapsed
	# since the window last reset (a successful tap resets it to 0, same as
	# the real DriftStateMachine) and aims each wait at that stage's own
	# scaled window MIDPOINT -- a comfortable safety margin against the
	# +-1-frame rounding a physics-tick granularity wait already carries.
	var frames_since_window_reset := 2  # the wait_physics_frames(2) above
	var physics_fps := float(Engine.physics_ticks_per_second)

	for expected_stage in range(1, stage_cap + 1):
		var stage_index := expected_stage - 1  # _boost_stage BEFORE this tap
		var stage_factor: float = pow(
			_kart_tuning.boost_window_shrink_factor, float(stage_index)
		)
		var target_s := (
			(_kart_tuning.boost_window_open_s + _kart_tuning.boost_window_close_s)
			* 0.5
			* stage_factor
		)
		var target_frames := int(round(target_s * physics_fps))
		var frames_to_wait := target_frames - frames_since_window_reset
		assert_gt(
			frames_to_wait,
			0,
			(
				"fixture sanity: stage %d's own scaled window midpoint must "
				+ "still be ahead of the frames already elapsed"
			) % expected_stage
		)
		if frames_to_wait <= 0:
			return
		await wait_physics_frames(frames_to_wait)

		assert_eq(
			String(kart.call("boost_tap")),
			"fired",
			"fixture setup: tap #%d must land inside its own (shrunk) window" % expected_stage
		)
		frames_since_window_reset = 0
		await wait_physics_frames(1)
		frames_since_window_reset += 1

		assert_eq(int(kart.call("boost_stage")), expected_stage)
		assert_eq(
			sparks.amount,
			roundi(
				_fx_tuning.spark_amount_stage0
				+ float(expected_stage) * _fx_tuning.spark_amount_per_stage
			),
			"stage %d amount must scale by spark_amount_per_stage" % expected_stage
		)
		var color_index := clampi(expected_stage, 1, stage_colors.size()) - 1
		assert_eq(
			process_material.color,
			stage_colors[color_index],
			"stage %d must use spark_color_stage%d" % [expected_stage, color_index + 1]
		)

	# The cap itself (the LOW's own "through stage 3" ask, taken to its
	# natural conclusion): boost_tap() rejects a tap at/above the cap BEFORE
	# ever touching window arithmetic (see its own "if _boost_stage >=
	# stack_max: return &ignored" early return) -- so unlike every tap
	# above, this one needs no window timing at all, just any real call.
	assert_eq(
		String(kart.call("boost_tap")),
		"ignored",
		"a tap beyond boost_stack_max must be ignored by the real drift FSM"
	)
	await wait_physics_frames(1)
	assert_eq(
		int(kart.call("boost_stage")),
		stage_cap,
		"the stage must stay pinned at the cap after an ignored tap"
	)
	assert_eq(
		sparks.amount,
		roundi(
			_fx_tuning.spark_amount_stage0
			+ float(stage_cap) * _fx_tuning.spark_amount_per_stage
		),
		"the spark amount must stay pinned at the cap's own value too"
	)
	assert_eq(
		process_material.color,
		_fx_tuning.spark_color_stage3,
		"the spark color must stay pinned at spark_color_stage3 at the cap"
	)


## The boost flame's gate is is_boosting() specifically (KartMotor's own
## "accrued boost time remaining" query), NOT is_sliding()/boost_stage() --
## apply_boost() directly here (the same call KartController.apply_boost()
## exposes for RaceSession's turbo-item dispatch) proves the flame reaches
## it even with the kart never having slid at all.
func test_flame_emits_while_boosting_independent_of_sliding() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)
	await wait_physics_frames(2)

	var flame := fx.get_node("Flame") as GPUParticles3D
	assert_false(flame.emitting, "fixture setup: no boost applied yet")
	assert_false(bool(kart.call("is_sliding")), "fixture setup: this kart never slides")

	kart.call("apply_boost", 0.3)
	await wait_physics_frames(1)

	assert_true(
		flame.emitting,
		"the flame must emit while is_boosting() is true, with no slide involved at all"
	)

	await wait_physics_frames(
		int(ceil(0.3 * float(Engine.physics_ticks_per_second))) + 3
	)
	assert_false(
		flame.emitting,
		"the flame must stop once the accrued boost time has fully decayed"
	)


func test_both_emitters_force_off_once_the_kart_is_no_longer_run_active() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)
	await wait_physics_frames(10)

	kart.call("steer", _kart_tuning.slide_min_steer)
	kart.call("hop_pressed")
	kart.call("apply_boost", 5.0)
	await wait_physics_frames(2)
	assert_true(kart.call("is_sliding"), "fixture setup must land inside a slide")

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	var flame := fx.get_node("Flame") as GPUParticles3D
	assert_true(sparks.emitting, "fixture setup: sparks must be emitting before the freeze")
	assert_true(flame.emitting, "fixture setup: flame must be emitting before the freeze")

	kart.call("set_run_active", false)
	await wait_physics_frames(2)

	assert_false(
		sparks.emitting,
		"a finished/frozen kart must never keep throwing drift sparks"
	)
	assert_false(
		flame.emitting,
		"a finished/frozen kart must never keep throwing boost flame, even with boost time still banked"
	)


func test_refresh_tuning_reapplies_static_spark_values_to_the_real_node() -> void:
	var kart := _spawn_kart_on_floor()
	if kart == null:
		return
	var fx := kart.get_node("Fx")
	fx.call("configure", kart, _fx_tuning)

	var shrunk_tuning: FxTuning = _fx_tuning.duplicate(true)
	shrunk_tuning.spark_lifetime_s = _fx_tuning.spark_lifetime_s + 0.5
	shrunk_tuning.spark_velocity_mps = _fx_tuning.spark_velocity_mps + 4.0
	shrunk_tuning.boost_flame_lifetime_s = _fx_tuning.boost_flame_lifetime_s + 0.5
	shrunk_tuning.boost_flame_amount = _fx_tuning.boost_flame_amount + 10.0

	fx.call("refresh_tuning", shrunk_tuning)

	var sparks := fx.get_node("Sparks") as GPUParticles3D
	var flame := fx.get_node("Flame") as GPUParticles3D
	assert_almost_eq(sparks.lifetime, shrunk_tuning.spark_lifetime_s, 0.0001)
	assert_eq(flame.lifetime, shrunk_tuning.boost_flame_lifetime_s)
	assert_eq(flame.amount, roundi(shrunk_tuning.boost_flame_amount))

	var process_material := sparks.process_material as ParticleProcessMaterial
	assert_not_null(process_material)
	if process_material == null:
		return
	assert_almost_eq(
		process_material.initial_velocity_min,
		shrunk_tuning.spark_velocity_mps,
		0.0001
	)
	assert_almost_eq(
		process_material.initial_velocity_max,
		shrunk_tuning.spark_velocity_mps,
		0.0001
	)


## Regression lock (kart_fx.gd's own SHARED SUB-RESOURCE HAZARD doc, mirrors
## item_box.gd's identical CollisionShape3D precedent): the Sparks process_
## material must be resource_local_to_scene, or one kart's own per-tick color
## write would leak into every OTHER kart's sparks sharing the same
## PackedScene. Checked directly by OBJECT IDENTITY (the strongest possible
## proof) rather than indirectly through behavior -- no configure()/physics
## ticking needed, two bare instantiate()s already carry independent
## sub-resources if and only if resource_local_to_scene is actually set.
func test_sparks_process_material_is_a_distinct_instance_per_kart() -> void:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var first_kart := packed.instantiate() as Node3D
	var second_kart := packed.instantiate() as Node3D
	add_child_autofree(first_kart)
	add_child_autofree(second_kart)

	var first_material := (
		first_kart.get_node("Fx/Sparks") as GPUParticles3D
	).process_material as ParticleProcessMaterial
	var second_material := (
		second_kart.get_node("Fx/Sparks") as GPUParticles3D
	).process_material as ParticleProcessMaterial
	assert_not_null(first_material)
	assert_not_null(second_material)
	if first_material == null or second_material == null:
		return
	assert_ne(
		first_material,
		second_material,
		(
			"kart.tscn's Sparks process_material must be resource_local_to_"
			+ "scene -- otherwise every kart sharing this PackedScene would "
			+ "flash the same drift-spark color simultaneously"
		)
	)


## origin offsets the whole floor+kart fixture so multiple fixtures spawned
## in the same test don't share a global position and collide -- mirrors
## test_kart_controller.gd's own _spawn_kart_on_floor() helper exactly.
func _spawn_kart_on_floor(origin: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var packed := load(KART_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null

	var root := Node3D.new()
	root.position = origin
	add_child_autofree(root)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor)

	var kart := packed.instantiate() as CharacterBody3D
	assert_not_null(kart)
	if kart == null:
		return null
	kart.position = Vector3(0.0, 0.2, 0.0)
	root.add_child(kart)
	kart.call("configure", _kart_tuning)
	return kart
