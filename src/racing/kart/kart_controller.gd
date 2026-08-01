class_name KartController
extends CharacterBody3D

## CharacterBody3D glue for the CTR kart (Task 3). Thin by design: all the
## actual velocity/yaw/boost/spin-out math lives in KartMotor and all the
## drift/slide-boost timing lives in DriftStateMachine (Task 2); this class
## just owns move_and_slide, ground detection, and wiring the two pure-logic
## systems together each physics tick.
##
## BINDING CONTRACT (orchestrator ruling): every physics tick this
## controller polls DriftStateMachine.consume_boost() and hands whatever
## comes back straight to KartMotor.add_boost(), unconditionally -- most
## ticks that is 0.0 seconds (a cheap no-op in add_boost), but the tick a
## slide-boost tap fires, the accrued seconds are applied the same frame,
## not deferred. Do not gate this call behind "only when sliding" or
## similar -- a valid slide end still leaves boost consumable afterward
## (see drift_state_machine.gd), and it must land on the very next tick
## regardless of whether the slide is still active.
##
## Input is a poll surface, not a live read of Input singleton state: the
## racing input mode (Task 4) is expected to call steer()/set_brake() every
## frame and hop_pressed()/hop_released() on edges, the same way callers
## push into DriftStateMachine directly. hop_pressed() only produces an
## actual vertical impulse when the kart is grounded AND not already
## sliding (mirrors CTR -- mashing hop mid-air does not stack extra hops,
## and a hop press mid-drift is a boost tap, not a jump); outside of a
## spin-out stun (see the R4-BINDING FIX paragraph below) it still always
## forwards to the drift FSM so an airborne hop-then-land can arm a slide on
## landing. Fix round 1: RacingInputAdapter now routes every hop press that
## arrives while already sliding to boost_tap() instead of calling
## hop_pressed() at all (see racing_input_adapter.gd and drift_state_
## machine.gd's class docs for why), so this guard is defense in depth
## against any other caller reaching hop_pressed() mid-slide, not something
## the adapter's own call pattern currently exercises.
##
## R4-BINDING FIX (Task 1, striking the design spec's Recorded debts #1): a
## hit landing mid-slide used to zero the motor's yaw authority (KartMotor.
## apply_spin_out()) while leaving DriftStateMachine completely unaware --
## is_sliding() kept reporting true, KartCamera's drift bias kept reading a
## now-stale slide_direction(), and boost_tap() could still fire, "rewarding"
## a hit with a boost stacked the instant before or during it. apply_spin_
## out() now also calls DriftStateMachine.cancel_slide() -- a real force-end
## (same shape set_run_active(false) already uses below): zeroes boost_
## stage/accrued boost/window_elapsed_s and clears is_sliding() the same
## tick, so a camera reading it stops applying any drift bias immediately --
## plus hop_released() alongside it, because cancel_slide() only clears the
## "hop held" latch when a slide was actually active; a hop pressed-but-
## not-yet-sliding right before the hit would otherwise survive untouched
## and arm a slide off that stale latch the instant steer crosses the
## threshold mid-stun (the same latch-leak reason set_run_active(false)
## also calls hop_released() explicitly rather than trusting cancel_slide()
## alone). boost_tap() and hop_pressed() are ALSO now gated on KartMotor.
## is_spinning_out(): a controller-level no-op/&"ignored" for the whole
## spin_out_duration_s stun, so a hit can never be "rewarded" with a boost
## tap or a fresh hop/slide-arm landing during or immediately after it,
## regardless of what the drift FSM's own state would otherwise allow.
## Recovery needs no controller-side bookkeeping of its own: KartMotor's own
## spin-out timer expiring is what un-gates both calls again (is_spinning_
## out() reads straight through), the same "the timer just runs out" shape
## invulnerable_after_hit_s already uses as its own independent window.

## CTR R6 Task 5, fix round 1 (reviewer [HIGH] -- the ORIGINAL version of
## this doc comment claimed hop_pressed_edge alone gives tnt_stick.gd's own
## SHAKE-OFF mechanism parity between the player and every AI kart "with no
## separate wiring either one has to opt into"; that claim was FALSE and is
## corrected here, not silently fixed). hop_pressed_edge fires on EVERY real
## hop_pressed() call below, unconditionally -- including the spin_out-
## stunned early-return case, since a real physical button press happened
## regardless of whether the motor/drift FSM acted on it.
##
## THIS ALONE IS NOT ENOUGH FOR THE PLAYER. racing_input_adapter.gd's own
## apply_hop_pressed() routes a press to EITHER hop_pressed() OR boost_tap()
## depending on is_sliding() (see that file's own class doc) -- NEVER both.
## A player mashing hop WHILE SLIDING (the exact state a just-attached TNT
## stick's own victim is very likely to be in, having just driven into it)
## routes every one of those presses to boost_tap() instead, so hop_pressed_
## edge alone never fires for them. boost_tap_edge below exists for exactly
## this reason -- see its own doc. A caller that needs "count every real hop
## button press regardless of which state routed it where" (tnt_stick.gd's
## own SHAKE-OFF mechanism is the one real consumer) must connect to BOTH
## signals, which is exactly what it does.
##
## The AI path needs no such split: AiKartAgent._route_decision() only ever
## calls hop_pressed() directly for AiDriver's own "hop" output (already
## gated `not is_sliding` at the driver level -- see ai_driver.gd's own SLIDE
## (hop) COUPLING doc, so this call never lands mid-slide either), and
## boost_tap() directly for AiDriver's own separate "boost_tap" output (the
## AI's own analogous slide-release action) -- both already reachable
## through this controller's real API with no adapter indirection, so both
## signals already fire correctly for an AI kart with no extra wiring.
signal hop_pressed_edge

## CTR R6 Task 5, fix round 1 (reviewer [HIGH]): fires on EVERY real
## boost_tap() call below, unconditionally -- same "before any gating, a
## real press/decision happened either way" rationale as hop_pressed_edge
## above. Exists specifically so a mid-slide hop press (racing_input_
## adapter.gd's own apply_hop_pressed() routes it here instead of hop_
## pressed(), see that signal's own doc) still counts as a real button press
## for any listener that needs one -- tnt_stick.gd connects to this ALONGSIDE
## hop_pressed_edge for exactly that reason. Also fires for an AI kart's own
## direct boost_tap() calls (ai_kart_agent.gd's own OUTPUT ROUTING), which is
## a real slide-release action either way -- a harmless, arguably correct
## bonus, not something any caller has to guard against.
signal boost_tap_edge

const KartMotorType := preload("res://src/racing/kart/kart_motor.gd")
const DriftStateMachineType := preload(
	"res://src/racing/kart/drift_state_machine.gd"
)
const ItemSlotType := preload("res://src/racing/items/item_slot.gd")

## CTR R6 Task 3: the seated-riding clip Crash's own model already carries
## (see src/visual/player/crash_animation_driver.gd's HOG_RIDE constant --
## same StringName, reused verbatim, not re-authored). The lab assistant
## model has no such clip (its only animation is A_lab_assistant_walk, an
## on-foot patrol cycle with no seated pose) -- _play_seat_pose() below
## checks has_animation() before playing and reports back whether it
## actually found and played one; mount_character() falls back to
## _apply_static_seat_pose() when it did not (R6 fix wave, operator device
## test: "the opponent character should sit down just like Crash, not
## standing on the car" -- see that method's own doc for the fallback).
const SEAT_ANIMATION_CLIP := &"A_crash_hog_ride"

## R6 fix wave: static seated-pose data for a mounted character with no
## seated clip of its own -- see SeatPoseTuning's own class doc (data/
## tuning/racing/seat_pose.tres) for where the values come from and why
## this lives outside GameplayTuning/TuningService's live-fingerprint
## catalog. A plain preload(), the same shape as KartMotorType/
## DriftStateMachineType above -- this is visual rig data, not a per-race
## config a caller ever needs to swap.
const SeatPoseTuningType := preload("res://data/tuning/racing/seat_pose.tres")

## Skeleton3D bone names (both character rigs share this exact DEF-* naming
## -- see _apply_static_seat_pose()'s own doc) that _apply_static_seat_pose()
## overrides. String constants, never numeric literals, so this table lives
## safely in src/racing/** without tripping scripts/lint_gameplay_numbers.py.
const SEAT_POSE_BONE_THIGH_L := "DEF-thigh.L"
const SEAT_POSE_BONE_THIGH_R := "DEF-thigh.R"
const SEAT_POSE_BONE_SHIN_L := "DEF-shin.L"
const SEAT_POSE_BONE_SHIN_R := "DEF-shin.R"
const SEAT_POSE_BONE_UPPER_ARM_L := "DEF-upper_arm.L"
const SEAT_POSE_BONE_UPPER_ARM_R := "DEF-upper_arm.R"
const SEAT_POSE_BONE_FOREARM_L := "DEF-forearm.L"
const SEAT_POSE_BONE_FOREARM_R := "DEF-forearm.R"

var _tuning: KartTuning
var _motor: KartMotorType = KartMotorType.new()
var _drift: DriftStateMachineType = DriftStateMachineType.new()
var _item_slot: ItemSlotType = ItemSlotType.new()

var _steer_input: float
var _brake_input: bool
var _run_active: bool = true
var _item_use_count: int = 0

## CTR R6 Task 3: character-mount + body-tint node refs. NODE LOOKUP, NOT
## @onready -- mirrors kart_fx.gd's own class-doc precedent exactly (see that
## file's "NODE LOOKUP, NOT @onready" section): RaceSession._spawn_ai_karts()
## calls mount_character()/apply_body_tint() on a freshly-instantiate()d kart
## BEFORE add_child() (the same ordering that already forces kart_fx.gd's own
## Fx.configure() to avoid @onready), so an @onready var here would still
## read null when either method needs it. _ensure_visual_refs() looks both
## up lazily and caches them, the identical shape kart_fx.gd's own _ensure_
## particle_refs() already uses.
var _visual: Node3D
var _seat_mount: Node3D
var _mounted_character: Node3D


## item_tuning (R4 Task 3) is OPTIONAL and defaults to null so every
## pre-existing caller that only ever passed kart_tuning (test fixtures,
## chiefly) keeps compiling and behaving exactly as before -- a kart
## configured with no item_tuning simply never reconfigures its ItemSlot,
## which stays in its default &"empty" state and fails closed to &"none"
## from held_item()/use() (see item_slot.gd's own class doc). RaceSession
## (race_session.gd) is the one real caller that passes it, for both the
## player's kart and every AI kart, mirroring how kart_tuning itself is
## threaded through.
func configure(kart_tuning: KartTuning, item_tuning: ItemTuning = null) -> void:
	_tuning = kart_tuning
	_motor.configure(kart_tuning)
	_drift.configure(kart_tuning)
	if item_tuning != null:
		_item_slot.configure(item_tuning)
	set_run_active(true)


## Live tuning refresh (M2 fix-wave): re-applies a new KartTuning to the
## motor and drift FSM this controller already owns, the same "the tuning
## loop must be provably live" contract every other live tuning consumer in
## this repo honors (see camera_rail_controller.gd's own refresh_tuning()).
## Unlike configure(), this deliberately does NOT call set_run_active(true)
## -- a mid-race tuning edit must never reactivate a kart a race has
## already frozen at the finish line (see set_run_active()'s own doc); it
## also never touches any live motor/drift STATE (speed, yaw, boost, slide
## progress), only which tuning values that state is computed against next
## tick, exactly like KartMotor.configure()/DriftStateMachine.configure()
## already do on their own.
## item_tuning is likewise OPTIONAL (defaults to null, see configure()'s own
## doc) -- when supplied it reapplies live to the same ItemSlot instance
## this controller has owned since construction, WITHOUT resetting its
## current state/elapsed roll progress, mirroring exactly how this method
## already refreshes _motor/_drift in place rather than replacing them.
func refresh_tuning(kart_tuning: KartTuning, item_tuning: ItemTuning = null) -> void:
	_tuning = kart_tuning
	_motor.configure(kart_tuning)
	_drift.configure(kart_tuning)
	if item_tuning != null:
		_item_slot.configure(item_tuning)


func steer(value: float) -> void:
	_steer_input = value
	_drift.steer(value)


func set_brake(braking: bool) -> void:
	_brake_input = braking


## Seeds the motor's yaw so a kart placed on an authored spawn transform
## (see race_session.gd's configure(), which calls this AFTER copying the
## spawn's global_transform onto this body) actually keeps facing the way
## it was authored, instead of _physics_process's own unconditional
## rotation.y write below snapping it back to KartMotor's default 0.0
## heading on the very first tick -- the HIGH-1 fix-wave bug: a kart placed
## on a spawn authored facing anything other than -Z (yaw 0) would wedge
## into scenery before a single real gate could validate. Also writes
## rotation.y immediately so the body's own facing basis is correct even
## before the next physics tick runs (matches the invariant
## _physics_process already maintains every tick thereafter).
func set_yaw_degrees(degrees: float) -> void:
	_motor.set_yaw_degrees(degrees)
	rotation.y = deg_to_rad(degrees)


## Gated on the motor's spin-out state (R4 Task 1, see the class doc's
## R4-BINDING FIX paragraph): a hop press during a stun is a full no-op --
## it never reaches the drift FSM at all, so it can neither add a vertical
## impulse nor latch _hop_held to arm a slide the instant the stun ends.
func hop_pressed() -> void:
	hop_pressed_edge.emit()
	if _motor.is_spinning_out():
		return
	_drift.hop_pressed()
	if is_on_floor() and not _drift.is_sliding():
		_motor.hop()


func hop_released() -> void:
	_drift.hop_released()


## Gated on the motor's spin-out state (R4 Task 1, see the class doc's
## R4-BINDING FIX paragraph): a boost tap during a stun returns &"ignored"
## without ever reaching DriftStateMachine.boost_tap() -- a hit can't be
## "rewarded" with a boost stacked the instant before or during it.
func boost_tap() -> StringName:
	boost_tap_edge.emit()
	if _motor.is_spinning_out():
		return &"ignored"
	return _drift.boost_tap()


func apply_boost(seconds: float) -> void:
	_motor.add_boost(seconds)


## JumpPad's own entry point (Task 1, CTR R7 pads) -- mirrors apply_boost()
## immediately above exactly: a thin, unconditional pass-through onto the
## motor, no grounded/spin-out gate of its own (see KartMotor.launch()'s own
## doc for why -- this is an environmental effect, not player input).
func launch(scale: float) -> void:
	_motor.launch(scale)


## R4 Task 3: replaces the Task-2 no-op stub (which always returned
## &"none") with the real hand-off onto this controller's own ItemSlot --
## delegates straight to ItemSlot.use() (returns-and-clears: &"none" unless
## an item is actually &"held"). Spawning/applying whatever comes back
## (missile projectile, shield, turbo, beaker) is Task 4's job; this task's
## whole contract is that the correct item name comes back out.
## item_use_count() mirrors AiKartAgent's own respawn_count() -- a plain
## call counter exposed for test observability, incremented on every
## use_item() call regardless of what it returns (mirrors the Task-2 stub's
## own counting behavior, unchanged here).
func use_item() -> StringName:
	_item_use_count += 1
	return _item_slot.use()


func item_use_count() -> int:
	return _item_use_count


## Exposes the real, already-configured-and-ticked ItemSlot this controller
## owns -- for the HUD (roulette flicker/held-item display) and Task 4's
## AiKartAgent (deciding whether/when to use an item), neither of which
## should have to reach past this controller into a private field the way
## a handful of this suite's own white-box tests already do for _motor/
## _drift.
func item_slot() -> ItemSlotType:
	return _item_slot


## R4 Task 1 (striking the design spec's Recorded debts #1 -- see the class
## doc's R4-BINDING FIX paragraph): also force-ends the drift FSM's own
## slide state, the same cancel_slide() + hop_released() pair set_run_
## active(false) already uses below for the identical "stop drifting right
## now, don't leave the hop latch armed" reason.
func apply_spin_out() -> void:
	_motor.apply_spin_out()
	_drift.hop_released()
	_drift.cancel_slide()


func speed_mps() -> float:
	return _motor.speed_mps()


func is_sliding() -> bool:
	return _drift.is_sliding()


## Fix round 1 (KartCamera review): -1/1, locked for the life of a slide --
## see drift_state_machine.gd. Exposed alongside is_sliding()/speed_mps() so
## a camera rig can bias its look yaw into the slide without reaching past
## this controller into the private drift FSM it owns.
func slide_direction() -> int:
	return _drift.slide_direction()


## Task 1 (CTR R6, circuit polish): proxies straight onto the real
## DriftStateMachine's own boost_stage() -- see drift_state_machine.gd's own
## doc (0-based, capped at roundi(kart.boost_stack_max), reset to 0 by a
## fresh slide/a punish/a cancel). Exposed alongside is_sliding() so
## kart_fx.gd's drift-spark driver can pick this slide's current color/
## amount without reaching past this controller into the private drift FSM
## it owns, the same "proxy straight through" shape every other drift/motor
## query on this controller already uses.
func boost_stage() -> int:
	return _drift.boost_stage()


## Task 1 (CTR R6, circuit polish): proxies straight onto the real
## KartMotor's own is_boosting() (accrued boost time remaining > 0, see
## kart_motor.gd's own doc) -- KartController never exposed this before,
## even though the motor itself always has. kart_fx.gd's boost-flame driver
## is the first caller: the flame's own binary emitting gate is is_boosting()
## specifically, NOT is_sliding()/boost_stage() -- a kart can still be
## mid-boost well after its slide has ended (add_boost() decays by delta_s
## every tick regardless of slide state).
func is_boosting() -> bool:
	return _motor.is_boosting()


func is_invulnerable() -> bool:
	return _motor.is_invulnerable()


## Proxies straight onto the real KartMotor's own timed shield flag -- see
## kart_motor.gd's set_shielded() doc. RaceSession applies this the instant
## a &"shield" item is used (see race_session.gd's own item-use dispatch
## doc), unconditionally replacing any remaining shield window rather than
## stacking.
func set_shielded(duration_s: float) -> void:
	_motor.set_shielded(duration_s)


func is_shielded() -> bool:
	return _motor.is_shielded()


## Proxies straight onto the real KartMotor's own consume_shield() -- see
## its own doc. RaceSession.register_hit() is the one caller, ending a
## shield the instant it blocks a hit rather than leaving the remainder of
## its own timer to run out on its own.
func consume_shield() -> void:
	_motor.consume_shield()


## Proxies straight onto the real KartMotor's own query -- see kart_motor.
## gd's is_spinning_out() doc. Exposed alongside is_invulnerable() so a
## caller (HUD, AI, or a test) can distinguish "still stunned" (zero yaw
## authority, boost_tap()/hop_pressed() gated -- see the class doc's
## R4-BINDING FIX paragraph) from "still can't be hit again" without
## reaching past this controller into the private motor it owns.
func is_spinning_out() -> bool:
	return _motor.is_spinning_out()


## Proxies straight onto the real KartMotor's own lever -- see kart_motor.gd's
## set_speed_scale() doc. Task 4's AiKartAgent is the only caller; a
## human-driven kart never calls this and stays at the motor's default 1.0.
func set_speed_scale(ratio: float) -> void:
	_motor.set_speed_scale(ratio)


## Proxies straight onto the real DriftStateMachine's own read-only query --
## see drift_state_machine.gd's boost_window_open() doc. Exposed alongside
## is_sliding()/boost_tap() so Task 4's AiKartAgent can assemble AiDriver's
## state dict without reaching past this controller into the private drift
## FSM it owns.
func boost_window_open() -> bool:
	return _drift.boost_window_open()


## Zeros the underlying motor's forward/vertical speed and this body's own
## CharacterBody3D.velocity -- Task 4's AI stuck-kart respawn path (see
## ai_kart_agent.gd's class doc) calls this right after teleporting a kart
## onto a fresh centerline position, so it doesn't carry stale motion
## (residual forward speed, a mid-air fall, or leftover move_and_slide()
## velocity from wherever it got stuck) into its new spot. Yaw is
## deliberately untouched -- callers seed that separately via
## set_yaw_degrees(), the same split race_session.gd's own spawn placement
## already keeps (place the transform, THEN seed yaw, as two independent
## steps).
func reset_speed() -> void:
	_motor.reset_speed()
	velocity = Vector3.ZERO


## Fix round (H2 review): a race that just finished must stop the kart
## driving into walls behind the finish line under its own auto-throttle,
## and must not leave a mid-finish slide latched forever accumulating yaw.
## false zeroes the routed steer, releases the held hop latch, and
## force-ends any active slide (DriftStateMachine.cancel_slide()) as a
## one-time transition -- _physics_process then branches every following
## tick to KartMotor.decelerate_to_stop() instead of the normal drift+motor
## tick, so the kart visually rolls to a stop (brake_mps2) and stays there
## rather than snapping to zero or creeping back up to speed once it
## arrives. true is the default and is re-applied by configure(), so a
## fresh kart (the normal case: race retry reinstantiates the whole scene)
## always starts active; it also lets a caller that reuses a KartController
## instance across races reactivate it explicitly.
func set_run_active(active: bool) -> void:
	if active == _run_active:
		return
	_run_active = active
	if not active:
		_steer_input = 0.0
		_brake_input = false
		_drift.steer(0.0)
		_drift.hop_released()
		_drift.cancel_slide()


func is_run_active() -> bool:
	return _run_active


func _physics_process(delta_s: float) -> void:
	if _tuning == null:
		return
	var grounded := is_on_floor()
	if _run_active:
		_drift.tick(delta_s, grounded)
		_motor.add_boost(_drift.consume_boost())
		_motor.tick(
			delta_s,
			_steer_input,
			_brake_input,
			grounded,
			_drift.is_sliding(),
			_drift.slide_direction()
		)
		# R4 Task 3: the item roulette only advances while this kart is
		# actually racing -- gated on _run_active the same way the drift/
		# motor tick above already is, so a kart frozen at the finish line
		# (set_run_active(false)) can never have a roll silently land while
		# nobody can act on it.
		_item_slot.tick(delta_s)
	else:
		_motor.decelerate_to_stop(delta_s, grounded)
	velocity = _motor.velocity()
	velocity.y = _motor.vertical_speed_mps()
	# Fix round 1 (KartCamera review): the body's own basis never turned --
	# KartMotor already computes velocity FROM its internal yaw (see
	# kart_motor.gd's velocity()), but nothing wrote that yaw back onto this
	# CharacterBody3D's transform, so -global_transform.basis.z (the
	# "facing" a chase camera or any other Node3D-level reader needs) stayed
	# stuck at whatever it spawned with regardless of steering. Writing
	# rotation.y from the same yaw_degrees() the motor already used for
	# velocity() this tick keeps the two consistent by construction.
	rotation.y = deg_to_rad(_motor.yaw_degrees())
	move_and_slide()


# ---------------------------------------------------------------------------
# CTR R6 Task 3: character-mount + body-tint API. kart.tscn ships with NO
# character by default -- RaceSession decides who rides (Crash on the
# player, a lab assistant on every AI kart) and calls these once per kart at
# spawn time, mirroring the Fx wiring one section up (kart.get_node("Fx").
# call("configure", ...)) exactly: same "session owns the decision, the
# scene stays generic" split, same pre-add_child() call timing, same NODE
# LOOKUP NOT @onready reason (see this class's own var declarations above).
# ---------------------------------------------------------------------------


## Instances character_scene under this kart's own SeatMount marker (a
## Marker3D sibling of Visual, authored in kart.tscn at the seat's own
## estimated position -- see that scene's own SeatMount node), plays its
## seated-riding pose if the model has one (see SEAT_ANIMATION_CLIP's own
## doc), and returns the instantiated node. A previously mounted character,
## if any, is freed first -- mount_character() is safe to call again (a
## defensive re-configure/retry path, the same "safe to call twice" shape
## every other configure()-adjacent method on this controller already
## keeps).
##
## NO PHYSICS FROM THE CHARACTER: character_scene's own root (SK_crash.glb/
## SK_lab_assistant.glb) is a plain Node3D/Skeleton3D subtree, never a
## CharacterBody3D or any other physics body -- parenting it under SeatMount
## (itself a plain Marker3D, not a PhysicsBody3D) gives it no collision
## shape and no physics processing of its own; it is purely visual, exactly
## like the kart's own Visual mesh instance one node up.
##
## YAW: NO explicit facing sync of any kind is needed, and this is
## deliberate, not an oversight -- contrast with hog_mount.gd's own
## _face_travel_direction(), which exists ONLY because that rig reparents
## the HOG VISUAL onto the PLAYER's own CharacterBody3D, a SEPARATE body
## that does not itself rotate to face travel direction. Here the
## relationship is the other way around and simpler: the character is a
## plain descendant of THIS kart's own CharacterBody3D, which already
## writes its own rotation.y from the motor's yaw every physics tick (see
## _physics_process() above) -- Godot's scene graph carries that rotation
## down through SeatMount to the mounted character for free. The character
## cannot "fight" the kart's yaw because it has no yaw authority of its own
## to fight it with.
##
## rotation.y = PI (via the PI built-in, never a bare numeric literal --
## src/racing/**'s own numeric-literal lint bans everything outside 0/1/-1,
## see CLAUDE.md) corrects the same "-Y-forward-in-Blender exports as
## +Z-front-in-Godot" convention every character/rideable asset in this repo
## shares (docs/art/import-export-contract.md's own Orientation section) --
## the identical fix scenes/player/player.tscn's own CrashModel node already
## carries (rotation = Vector3(0, 3.1415927, 0)), just applied at mount time
## here instead of authored once in a scene, since the mounted character is
## never scene-authored (kart.tscn ships with none, per this section's own
## class doc).
func mount_character(character_scene: PackedScene) -> Node3D:
	_ensure_visual_refs()
	unmount_character()
	if character_scene == null or _seat_mount == null:
		return null
	var character := character_scene.instantiate() as Node3D
	if character == null:
		return null
	_seat_mount.add_child(character)
	character.rotation.y = PI
	_mounted_character = character
	if not _play_seat_pose(character):
		_apply_static_seat_pose(character)
	return character


## Frees the currently mounted character, if any. A harmless no-op when
## nothing is mounted (mirrors this controller's other defensive-clear
## shapes, e.g. _spawn_ai_karts()'s own _ai_root child clear in race_
## session.gd).
func unmount_character() -> void:
	if _mounted_character != null and is_instance_valid(_mounted_character):
		_mounted_character.queue_free()
	_mounted_character = null


## The character subtree mounted by the most recent mount_character() call,
## or null if none was ever mounted (kart.tscn's own shipped default).
func mounted_character() -> Node3D:
	return _mounted_character


## Recolors the kart's own visible shell, per RaceSession's own per-kart
## assignment (KartTuning.kart_tint_player for the player, KartTuning.
## tint_for_slot(slot_index) for each AI kart -- see race_session.gd's own
## configure()/_spawn_ai_karts()). A single StandardMaterial3D override,
## applied to EVERY MeshInstance3D found under Visual (root included --
## _mesh_instances_in() checks both, since the imported kart glb's own root
## node type is not guaranteed, see that helper's own doc): vertex_color_
## use_as_albedo = true multiplies the mesh's own vertex-painted colour by
## albedo_color = tint. scripts/blender/build_kart.py's own three palette
## cells are deliberately unequal brightness for exactly this: BODY is
## light/near-neutral so the tint reads clearly, WHEELS and SEAT are near-
## black so the SAME uniform multiply barely shifts them -- see that
## script's own module doc. This is why one material_override can recolor
## "the kart" the way the design brief asks for without needing separate
## per-surface materials or extra draw calls.
func apply_body_tint(tint: Color) -> void:
	_ensure_visual_refs()
	if _visual == null:
		return
	var tint_material := StandardMaterial3D.new()
	tint_material.vertex_color_use_as_albedo = true
	tint_material.albedo_color = tint
	for mesh_instance: MeshInstance3D in _mesh_instances_in(_visual):
		mesh_instance.material_override = tint_material


## Returns true when a real seated-riding clip was found and started (Crash's
## own path); false when the model has no such clip, telling mount_character()
## to fall back to _apply_static_seat_pose() instead. Never both -- see that
## method's own doc for why the fallback must never touch Crash.
func _play_seat_pose(character: Node3D) -> bool:
	var animation_players := character.find_children(
		"*",
		"AnimationPlayer",
		true,
		false
	)
	if animation_players.size() != 1:
		return false
	var animation_player := animation_players[0] as AnimationPlayer
	if not animation_player.has_animation(SEAT_ANIMATION_CLIP):
		return false
	animation_player.play(SEAT_ANIMATION_CLIP)
	return true


## R6 fix wave (operator device test: "the opponent character should sit
## down just like Crash, not standing on the car"). Called only when _play_
## seat_pose() found no real seated clip to play (the lab assistant's own
## case today -- its only animation is a walk cycle, see SEAT_ANIMATION_
## CLIP's own doc) -- Crash always takes the animation path above and never
## reaches here.
##
## Bends the hip/knee/arm bones into a fixed seated silhouette via
## Skeleton3D.set_bone_pose_rotation() -- a STATIC pose override, no
## AnimationPlayer involved, applied once at mount time and left alone
## (nothing re-applies it per tick, so it costs nothing beyond this one
## call). set_bone_pose_rotation() writes an ABSOLUTE rotation in the
## bone's own parent-relative space, the same space animation rotation
## tracks target, which is exactly what SeatPoseTuningType's own fields
## carry -- see that Resource's class doc for where the numbers come from
## and why a lab-assistant-only fallback can safely reuse them.
##
## Only bone ROTATIONS are overridden here -- never bone positions -- so
## the character's own skeleton-local bone anchors (hip/knee/shoulder pivot
## points) stay exactly where the rig was authored; the fold into a seated
## silhouette comes entirely from rotating around those fixed pivots, the
## same forward-kinematics shape a real seated animation uses.
##
## pelvis_drop_m then lowers the WHOLE mounted character's own local Y
## position (SeatMount-relative) by a fixed amount: bending the hip/knee
## alone does not move the character's own root down to seat height (the
## rig's hip-height anchor bones do not move when only rotated around their
## own pivot), so without this the model would still float at its full
## standing hip height above the seat, arguably still reading as
## "hovering" rather than "sitting". This is a coarse, whole-character
## offset, not a second bone override -- see SeatPoseTuningType's own
## pelvis_drop_m doc for the value's derivation.
func _apply_static_seat_pose(character: Node3D) -> void:
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		return
	var skeleton := skeletons[0] as Skeleton3D
	_set_bone_pose(skeleton, SEAT_POSE_BONE_THIGH_L, SeatPoseTuningType.thigh_l_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_THIGH_R, SeatPoseTuningType.thigh_r_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_SHIN_L, SeatPoseTuningType.shin_l_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_SHIN_R, SeatPoseTuningType.shin_r_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_UPPER_ARM_L, SeatPoseTuningType.upper_arm_l_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_UPPER_ARM_R, SeatPoseTuningType.upper_arm_r_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_FOREARM_L, SeatPoseTuningType.forearm_l_pose)
	_set_bone_pose(skeleton, SEAT_POSE_BONE_FOREARM_R, SeatPoseTuningType.forearm_r_pose)
	character.position.y -= SeatPoseTuningType.pelvis_drop_m


## Fail-closed like every other GridSlotN/marker lookup in this codebase
## (e.g. race_session.gd's own _spawn_ai_karts() doc): a rig that is ever
## reauthored without one of these DEF-* bone names simply skips that one
## override instead of crashing the mount.
func _set_bone_pose(skeleton: Skeleton3D, bone_name: String, pose: Quaternion) -> void:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index == -1:
		return
	skeleton.set_bone_pose_rotation(bone_index, pose)


## Root-or-descendant MeshInstance3D collection -- mirrors scripts/godot/
## enable_vertex_color_albedo.gd's own recursive walk (checks `node is
## MeshInstance3D` before recursing into children), the same resilience this
## repo's post-import script already needs because a glTF-imported
## PackedScene's root node type depends on the source mesh's own shape and
## is not something callers should have to hardcode a path assumption
## about. Confirmed empirically for the real kart glb: its root is a plain
## Node3D wrapping one MeshInstance3D child, not a MeshInstance3D itself --
## this helper handles that shape and the reverse one identically.
func _mesh_instances_in(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root as MeshInstance3D)
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		found.append(child as MeshInstance3D)
	return found


func _ensure_visual_refs() -> void:
	if _visual == null:
		_visual = get_node_or_null("Visual") as Node3D
	if _seat_mount == null:
		_seat_mount = get_node_or_null("SeatMount") as Node3D
