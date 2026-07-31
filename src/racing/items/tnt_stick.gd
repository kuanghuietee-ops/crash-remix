extends Node3D

## CTR R6 Task 5 (new items): CTR-style TNT stick. A thin Node that owns its
## own state directly -- see missile.gd's/beaker.gd's own class docs for why
## no separate pure-logic core and no class_name.
##
## TWO-PHASE STATE MACHINE. &"grounded" (the initial state, entered by
## configure()) -- sits exactly where the caller placed it, IDENTICAL to
## beaker.gd's own STATIC/ARM DELAY/LIFETIME shape: reuses ItemTuning.
## beaker_arm_delay_s/beaker_hit_radius_m/beaker_lifetime_s directly rather
## than a near-duplicate set of tnt_* fields (see item_tuning.gd's own TNT
## category doc for why) -- "dropped like the beaker" per the task brief.
## The FIRST candidate kart found within beaker_hit_radius_m, once armed,
## transitions this node to &"attached" (see _attach_to()) -- the same
## undefined "first found wins" tie-break missile.gd's/beaker.gd's own
## _check_hits() already uses. Un-contacted despawn at beaker_lifetime_s,
## also identical to beaker.gd.
##
## &"attached" -- FOLLOWS the victim kart's own global_position every tick
## (no offset: a graybox stand-in for a mounted visual, exact position
## match), starts a fresh fuse countdown from the attach instant (tnt_
## fuse_s), and connects to BOTH of the victim's own KartController signals
## -- hop_pressed_edge AND boost_tap_edge (see kart_controller.gd's own doc
## on each, and this file's own OBSERVING HOPS section below for why BOTH
## are required, not just one) -- to count down a SHAKE-OFF budget seeded
## from ItemTuning.tnt_shake_hops. Two ways out,
## mutually exclusive and checked in this order every tick:
##   1. _shake_hops_remaining reaches zero (the victim mashed hop enough
##      times) -- despawns HARMLESSLY, no register_hit call at all. Checked
##      first: a victim that finishes shaking it off in the SAME tick the
##      fuse would also have expired escapes clean, matching the intuitive
##      CTR reading of "shook it off in time."
##   2. _fuse_elapsed_s reaches tnt_fuse_s first -- session.register_hit(
##      victim), then despawns.
## The signal connection is torn down explicitly in both despawn paths (see
## _detach()) rather than relied on implicitly -- Godot auto-disconnects a
## signal when either endpoint is freed, but an explicit disconnect keeps
## this node's own lifecycle self-contained and testable without depending
## on that implementation detail, and guards against this node being freed
## by an EXTERNAL caller (RaceSession's own defensive hazards-root clear on
## a re-configure(), the same shape missile.gd's/beaker.gd's own instances
## are swept by) that never goes through this file's own despawn path at all.
##
## OBSERVING HOPS: real presses, not a polling hack -- fix round 1 (reviewer
## [HIGH]). hop_pressed_edge and boost_tap_edge are both genuine per-press
## Godot signals (see kart_controller.gd's own doc on each); _attach_to()
## connects to BOTH by NAME (Object.connect(), not a typed KartController
## reference), so a duck-typed test double exposing the same two signal
## names works identically to a real KartController. There is no per-tick
## comparison of a polled counter anywhere in this file.
##
## WHY BOTH SIGNALS, NOT JUST ONE. racing_input_adapter.gd's own apply_hop_
## pressed() routes a player's real hop press to EITHER KartController.
## hop_pressed() OR boost_tap(), depending on is_sliding() at the instant of
## the press -- NEVER both (see that file's own class doc). A victim who is
## already sliding when TNT attaches -- exactly the state driving INTO a
## dropped stick is likely to leave them in -- has every subsequent hop
## press routed to boost_tap(), not hop_pressed(): connecting only to hop_
## pressed_edge would make shake-off silently unreachable for a sliding
## player (the ORIGINAL version of this file did exactly that -- a real
## bug, not a hypothetical). Connecting to both signals and decrementing on
## either (see _on_victim_hop_shake_edge()) closes that gap regardless of
## which state the press lands in, and costs nothing extra for the
## non-sliding case (hop_pressed_edge alone already covered it, and still
## does).
##
## ATTACH TO THE LAUNCHER TOO. The launcher is kept in the SAME roster every
## other kart is drawn from (see configure()'s own doc, mirroring beaker.gd's
## own ARM DELAY / LAUNCHER IMMUNITY section) -- naturally immune only while
## unarmed (the shared arm-delay gate), a valid attach target once armed,
## including driving back into their own dropped stick (the task brief's
## own "attach to launcher too if they drive into it post-arm").

var _session: Object
var _launcher: CharacterBody3D
var _tuning: ItemTuning

var _all_karts: Array[CharacterBody3D] = []

var _phase: StringName = &"grounded"
var _elapsed_s: float
var _armed: bool = false
var _configured: bool = false

var _attached_kart: CharacterBody3D
var _fuse_elapsed_s: float
var _shake_hops_remaining: int


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## session/targets_getter: same duck-typed session double and Callable
## shape as missile.gd's/beaker.gd's own configure() -- see beaker.gd's own
## doc for why the launcher is deliberately kept IN this roster rather than
## excluded.
func configure(
	session: Object,
	launcher_kart: CharacterBody3D,
	item_tuning: ItemTuning,
	targets_getter: Callable
) -> void:
	_session = session
	_launcher = launcher_kart
	_tuning = item_tuning
	_phase = &"grounded"
	_elapsed_s = 0.0
	_armed = false
	_attached_kart = null

	_all_karts.clear()
	if targets_getter.is_valid():
		for entry: Variant in targets_getter.call():
			var kart: CharacterBody3D = entry.get("kart")
			if kart != null:
				_all_karts.append(kart)

	_configured = true


## Externally observable phase -- &"grounded" or &"attached" -- for tests
## and any future caller that wants to know without reaching into a private
## field.
func phase() -> StringName:
	return _phase


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return
	match _phase:
		&"grounded":
			_tick_grounded(delta_s)
		&"attached":
			_tick_attached(delta_s)


func _tick_grounded(delta_s: float) -> void:
	_elapsed_s += delta_s
	if _elapsed_s >= _tuning.beaker_lifetime_s:
		queue_free()
		return
	if not _armed and _elapsed_s >= _tuning.beaker_arm_delay_s:
		_armed = true
	if _armed:
		_check_grounded_contact()


## See the class doc's TWO-PHASE STATE MACHINE section -- the FIRST
## candidate found within beaker_hit_radius_m wins, the same undefined
## tie-break beaker.gd's/missile.gd's own hit checks already use.
func _check_grounded_contact() -> void:
	for kart: CharacterBody3D in _all_karts:
		if kart == null or not is_instance_valid(kart):
			continue
		var distance_m := (kart.global_position - global_position).length()
		if distance_m <= _tuning.beaker_hit_radius_m:
			_attach_to(kart)
			return


func _attach_to(kart: CharacterBody3D) -> void:
	_attached_kart = kart
	_phase = &"attached"
	_fuse_elapsed_s = 0.0
	_shake_hops_remaining = roundi(_tuning.tnt_shake_hops)
	# See the class doc's own WHY BOTH SIGNALS, NOT JUST ONE section --
	# either edge is a real hop-button press and must count.
	if kart.has_signal(&"hop_pressed_edge"):
		kart.connect(&"hop_pressed_edge", Callable(self, "_on_victim_hop_shake_edge"))
	if kart.has_signal(&"boost_tap_edge"):
		kart.connect(&"boost_tap_edge", Callable(self, "_on_victim_hop_shake_edge"))


func _tick_attached(delta_s: float) -> void:
	if _attached_kart == null or not is_instance_valid(_attached_kart):
		# The victim vanished out from under this stick (e.g. a test tearing
		# its own fixture down) -- nothing left to follow, fuse, or hit;
		# despawn harmlessly rather than spinning forever on a dangling ref.
		queue_free()
		return

	global_position = _attached_kart.global_position

	if _shake_hops_remaining <= 0:
		_detach()
		queue_free()
		return

	_fuse_elapsed_s += delta_s
	if _fuse_elapsed_s >= _tuning.tnt_fuse_s:
		var victim := _attached_kart
		_detach()
		if _session != null and is_instance_valid(_session):
			_session.call("register_hit", victim)
		queue_free()


## Shared by BOTH hop_pressed_edge and boost_tap_edge -- see the class doc's
## own WHY BOTH SIGNALS, NOT JUST ONE section. Either one is a real hop-
## button press regardless of which controller method it happened to route
## through, so both count identically toward the same shake budget.
func _on_victim_hop_shake_edge() -> void:
	_shake_hops_remaining -= 1


## See the class doc's own OBSERVING HOPS section on why this is an explicit
## step rather than left to Godot's own auto-disconnect-on-free. Tears down
## BOTH connections made in _attach_to() -- disconnect() is only called for
## a signal actually connected (is_connected() guards each independently),
## so this is safe even if has_signal() ever caused only one of the two to
## be wired in the first place (a duck-typed double exposing just one).
func _detach() -> void:
	if _attached_kart == null or not is_instance_valid(_attached_kart):
		_attached_kart = null
		return
	var shake_callable := Callable(self, "_on_victim_hop_shake_edge")
	if _attached_kart.is_connected(&"hop_pressed_edge", shake_callable):
		_attached_kart.disconnect(&"hop_pressed_edge", shake_callable)
	if _attached_kart.is_connected(&"boost_tap_edge", shake_callable):
		_attached_kart.disconnect(&"boost_tap_edge", shake_callable)
	_attached_kart = null


func _exit_tree() -> void:
	_detach()
