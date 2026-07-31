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

const KartMotorType := preload("res://src/racing/kart/kart_motor.gd")
const DriftStateMachineType := preload(
	"res://src/racing/kart/drift_state_machine.gd"
)
const ItemSlotType := preload("res://src/racing/items/item_slot.gd")

var _tuning: KartTuning
var _motor: KartMotorType = KartMotorType.new()
var _drift: DriftStateMachineType = DriftStateMachineType.new()
var _item_slot: ItemSlotType = ItemSlotType.new()

var _steer_input: float
var _brake_input: bool
var _run_active: bool = true
var _item_use_count: int = 0


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
	if _motor.is_spinning_out():
		return &"ignored"
	return _drift.boost_tap()


func apply_boost(seconds: float) -> void:
	_motor.add_boost(seconds)


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
