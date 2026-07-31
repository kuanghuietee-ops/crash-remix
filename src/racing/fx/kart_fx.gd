class_name KartFx
extends Node3D

## Task 1 (CTR R6, circuit polish): drift-spark + boost-flame FX driver, one
## instance per kart.tscn (both the player's and every AI kart share the
## same packed scene, so this rides along on every one of them -- see
## race_session.gd's own configure()/_spawn_ai_karts() for the per-kart
## configure() call this class expects).
##
## POLL MODEL, no signals -- mirrors drift_state_machine.gd/kart_motor.gd's
## own "configure once, tick every physics frame, read state back through
## getters" idiom, just in the other direction: this class READS the
## controller's own already-exposed getters every physics tick instead of
## computing state of its own. kart is duck-typed to the same "Node3D-with-
## KartController-API" surface kart_camera.gd already assumes (is_sliding(),
## boost_stage(), is_boosting(), is_run_active() -- the first two are thin
## proxies KartController now exposes onto its private DriftStateMachine/
## KartMotor, added by this same task; see kart_controller.gd's own class
## doc), so a plain Node type hint plus .call() works for both a real
## KartController and any future test double exposing that surface.
##
## NODE LOOKUP, NOT @onready (race_session.gd ordering hazard). Every AI
## kart's own configure() call happens on the freshly-instantiate()d subtree
## BEFORE add_child() (see race_session.gd's own _spawn_ai_karts(), which
## calls ai_kart.call("configure", ...) first so the kart's very first
## physics-server registration already carries its real GridSlotN position)
## -- at that point _ready() has not fired for anything under this node yet,
## so an @onready var would still read null. blob_shadow.gd's own configure()
## hits this exact hazard and fixes it the same way: get_node_or_null()
## looked up lazily and cached, never trusted to already be populated by the
## time configure()/refresh_tuning() runs.
##
## DRIFT SPARKS (rear, "Sparks" child GPUParticles3D). Emitting is gated
## purely on is_sliding() -- CTR sparks fly for the WHOLE slide, not just
## while a boost stage is stacked. Amount and color both key off the
## CURRENT boost_stage() every physics tick: amount = spark_amount_stage0 +
## stage * spark_amount_per_stage (rounded via roundi() -- see fx_tuning.gd's
## own "float field, COUNT semantics" doc, the same shape kart.boost_
## stack_max/race.lap_count already use); color = spark_color_stage1/2/3
## indexed by clampi(stage, 1, 3) -- stage 0 borrows stage 1's color at the
## lower stage-0 amount (there is no separate "stage 0" color field; only
## the amount differs, see fx_tuning.gd). Lifetime and initial velocity are
## NOT stage-dependent -- applied once per configure()/refresh_tuning() call
## in _apply_static_tuning(), the same "static tuning applied once, dynamic
## state applied every tick" split KartMotor/DriftStateMachine's own
## configure()-vs-tick() methods already keep.
##
## SHARED SUB-RESOURCE HAZARD (item_box.gd's own BODY FILTER precedent,
## different field): kart.tscn's Sparks process_material is an embedded
## ParticleProcessMaterial sub-resource, which Godot shares across EVERY
## instance of this PackedScene unless marked resource_local_to_scene = true
## (confirmed by item_box.gd's own class doc for its CollisionShape3D.shape,
## the identical hazard) -- kart.tscn marks it explicitly for exactly this
## reason, because this script mutates its .color per kart per tick, and an
## unmarked shared material would make every kart's sparks flash the same
## color simultaneously. The Flame process_material is never mutated after
## authoring, so it is deliberately left shared (unmarked), matching crate_
## break_effect.tscn's own "only mark what actually gets mutated" precedent.
##
## BOOST FLAME (exhaust, "Flame" child GPUParticles3D). A pure binary gate on
## is_boosting() (KartMotor's own "boost time remaining > 0" query, proxied
## straight through KartController) -- NOT boost_stage()/is_sliding(). A
## kart can be mid-boost well after a slide has ended (add_boost() decays by
## delta_s every tick regardless of slide state, see kart_motor.gd), and the
## flame is the "currently under boost power" tell, independent of drift.
##
## RUN-ACTIVE GATING. Both emitters force off the instant is_run_active()
## reads false (a race that just finished, see KartController.set_run_
## active()) -- mirrors the drift/motor/item-slot tick gating KartController.
## _physics_process itself already applies, so a kart frozen at the finish
## line never keeps throwing sparks/flame off whatever state it happened to
## freeze in.
##
## PROCESS_MODE_PAUSABLE (set in _ready(), same "a paused tree must not leak
## wall-clock-equivalent progress" contract every other timed racing system
## in this file already documents for itself -- see item_box.gd's own class
## doc) -- a paused game must not keep emitting particles in the background.

var _kart: Node
var _tuning: FxTuning

var _sparks: GPUParticles3D
var _flame: GPUParticles3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_particle_refs()


func configure(kart: Node, fx_tuning: FxTuning) -> void:
	_kart = kart
	_tuning = fx_tuning
	_ensure_particle_refs()
	_apply_static_tuning()


## Live tuning refresh (M2 fix-wave shape, see kart_controller.gd's own
## refresh_tuning() doc for the precedent this mirrors): re-applies fresh
## static FX values immediately -- the very next _physics_process tick
## already reads _tuning fresh for the stage-dependent values, exactly like
## every other live tuning consumer in this repo.
func refresh_tuning(fx_tuning: FxTuning) -> void:
	_tuning = fx_tuning
	_ensure_particle_refs()
	_apply_static_tuning()


func _physics_process(_delta_s: float) -> void:
	_ensure_particle_refs()
	if _sparks == null or _flame == null:
		return
	if _kart == null or _tuning == null or not bool(_kart.call("is_run_active")):
		_sparks.emitting = false
		_flame.emitting = false
		return

	var sliding := bool(_kart.call("is_sliding"))
	_sparks.emitting = sliding
	if sliding:
		var stage := int(_kart.call("boost_stage"))
		_sparks.amount = roundi(
			_tuning.spark_amount_stage0
			+ float(stage) * _tuning.spark_amount_per_stage
		)
		var sparks_process := _sparks.process_material as ParticleProcessMaterial
		if sparks_process != null:
			sparks_process.color = _spark_color_for_stage(stage)

	_flame.emitting = bool(_kart.call("is_boosting"))


## Indexes the three stage colors by clampi(stage, 1, count) -- avoids the
## bare numeric literals 2/3 a match-on-int-stage would need (src/racing/**'s
## own numeric-literal lint bans everything outside 0/1/-1, see CLAUDE.md),
## reading the color count off the array itself instead.
func _spark_color_for_stage(stage: int) -> Color:
	var stage_colors: Array[Color] = [
		_tuning.spark_color_stage1,
		_tuning.spark_color_stage2,
		_tuning.spark_color_stage3,
	]
	var color_index := clampi(stage, 1, stage_colors.size()) - 1
	return stage_colors[color_index]


func _apply_static_tuning() -> void:
	if _tuning == null or _sparks == null or _flame == null:
		return
	_sparks.lifetime = _tuning.spark_lifetime_s
	var sparks_process := _sparks.process_material as ParticleProcessMaterial
	if sparks_process != null:
		sparks_process.initial_velocity_min = _tuning.spark_velocity_mps
		sparks_process.initial_velocity_max = _tuning.spark_velocity_mps

	_flame.lifetime = _tuning.boost_flame_lifetime_s
	_flame.amount = roundi(_tuning.boost_flame_amount)


func _ensure_particle_refs() -> void:
	if _sparks == null:
		_sparks = get_node_or_null("Sparks") as GPUParticles3D
	if _flame == null:
		_flame = get_node_or_null("Flame") as GPUParticles3D
