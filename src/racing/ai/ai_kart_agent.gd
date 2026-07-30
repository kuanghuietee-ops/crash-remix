class_name AiKartAgent
extends Node

## Node glue that drives one AI kart every physics tick (Task 4, CTR R3: AI
## opponents). Owns a real SpineFollower + AiDriver and feeds a real,
## already-configured KartController through the EXACT SAME public API a
## human racer drives through (steer()/set_brake()/hop_pressed()/
## hop_released()/boost_tap()/set_speed_scale()) -- see kart_controller.gd's
## own class doc: "Input is a poll surface... the racing input mode is
## expected to call steer()/set_brake() every frame and hop_pressed()/
## hop_released() on edges". This class is that "racing input mode", just
## driven by AiDriver.decide() instead of a human thumb. It never reaches
## past the controller into KartMotor/DriftStateMachine directly, and it
## never touches the kart's CharacterBody3D physics except during the
## stuck-respawn teleport below.
##
## PROCESS MODE. Set to PROCESS_MODE_PAUSABLE in configure(), the same
## "physics-driven per-tick accumulation must actually stop while the tree
## is paused" contract race_session.gd's own configure() establishes for
## itself (see its class doc's TIMER section) -- an AI kart has no business
## still driving itself while the game is paused.
##
## KART TYPE. The plan text describes configure()'s first parameter loosely
## as "kart: Node", but this class reads kart.global_position,
## kart.global_transform, and kart.velocity every tick (Node3D/
## CharacterBody3D built-in properties, not something a bare Node has) and
## writes kart.global_position directly during a stuck-respawn teleport --
## so, like race_session.gd's own _kart field, it is typed CharacterBody3D.
## Every KartController-specific method (steer(), configure(), etc.) still
## goes through .call() rather than a static KartController type, the same
## duck-typed shape racing_input_adapter.gd's own controller parameter uses.
##
## STATE ASSEMBLY, per ai_driver.gd's documented INPUT STATE contract:
## - position/forward: the kart's own current world-space position/facing.
## - speed_mps: KartController.speed_mps() (the MOTOR's own commanded
##   speed) -- deliberately NOT the same signal stuck-detection uses below
##   (see STUCK DETECTION). This is the right signal for lookahead-distance
##   scaling and AiDriver's own corner-speed/brake formula: both want to
##   know how fast the kart is COMMANDED to be going, independent of a
##   momentary collision.
## - lookahead_m = ai_tuning.lookahead_min_m + speed_mps *
##   ai_tuning.lookahead_speed_gain_s (the brief's own formula, no new
##   literal).
## - lookahead_point = spine.point_at_progress(progress + lookahead_m) --
##   wraps past the seam internally (see track_spine.gd's point_at_progress()
##   doc).
## - curvature_ahead = spine.curvature_at_progress(progress, lookahead_m).
##   RESOLVED AMBIGUITY (the brief flagged "decide cleanly, document"):
##   ai_driver.gd's own SIGNED CURVATURE CONTRACT defines tangent_now as
##   "the spine tangent at the KART'S CURRENT PROGRESS" and tangent_ahead as
##   "the spine tangent at the LOOKAHEAD SAMPLE POINT" -- i.e. progress_m =
##   the kart's own current progress (not the lookahead point itself), and
##   sample_span_m = lookahead_m (the along-spine distance from the kart to
##   that lookahead point). That is EXACTLY curvature_at_progress(progress,
##   lookahead_m)'s own signature, so this is not a free choice -- it is
##   what the already-shipped, binding AiDriver contract requires. The
##   plan's alternate phrasing ("sample tangents at +/-lookahead") would
##   center the sample AROUND the lookahead point instead, which does not
##   match tangent_now's own definition ("the kart's current progress") and
##   was not used.
## - lateral_error_m = _lateral_target_m - actual_lateral_m, where
##   _lateral_target_m is this slot's own centered offset from the pursuit
##   line, computed once in configure() (see _compute_lateral_target_m())
##   since slot_index/ai_tuning never change per tick -- fix-wave LOW-9: this
##   private field is NOT itself included as a separate "lateral_target_m"
##   key in the assembled state Dictionary below. It used to be, but ai_
##   driver.gd's own INPUT STATE doc already says that key is "not read
##   here, lateral_error_m already carries what this driver needs" -- a
##   dead key with no consumer, removed rather than kept as unused
##   bookkeeping (see ai_driver.gd's own doc, updated to match). actual_
##   lateral_m is the perpendicular projection of (kart_pos -
##   centerline_point) onto the CURRENT tangent's own "right" vector
##   (tangent.cross(Vector3.UP) -- the same right-hand identity
##   kart_motor.gd's own velocity() uses: for the default facing (0,0,-1),
##   forward.cross(UP) = (1,0,0) = world +X = Godot's own basis.x for an
##   identity transform, i.e. "right" by the same convention steer's own
##   +right sign already uses). Positive lateral_error_m therefore means
##   the target slot sits to the kart's world-space right, satisfying
##   ai_driver.gd's own documented sign requirement for this value.
## - band_gap_m = player_progress_getter.call() - follower.total_progress_m()
##   (positive = this kart is behind the player) -- SEAM-SAFE by
##   construction since both sides of the subtraction are continuous
##   SpineFollower totals, never a raw seam-ambiguous spine offset (see the
##   plan's own "Seam ruling").
##
## LATERAL SLOT CENTERING. lateral_slot_spacing_m's own doc says "slot_i *
## spacing, centered across the field" -- centered across ALL
## ai_tuning.opponent_count + 1 karts (every AI opponent PLUS the player,
## who conventionally takes slot 0 -- see the plan's Task 5), not just the
## opponents: centered_slot = slot_index - HALF of (opponent_count + 1 - 1),
## lateral_target_m = centered_slot * lateral_slot_spacing_m (HALF via
## src/core/scalar_math.gd, per this file's own no-bare-literal rule -- see
## spine_follower.gd's identical use of ScalarMathType.HALF for its own
## half-length wrap). This spreads every kart (player included) to a
## distinct lateral offset around the pursuit line rather than only
## centering the AI pack and leaving the player's own slot 0 off to one
## side.
##
## OUTPUT ROUTING:
## - steer, set_brake: called every tick unconditionally, mirroring
##   racing_input_adapter.gd's apply_move() (a level, not an edge).
## - hop: AiDriver's own hop output is ALREADY an edge (true only once per
##   armed intent, see ai_driver.gd's class doc), but KartController wants a
##   PRESS-then-RELEASE pair, not a press held forever -- holding it forever
##   would leave DriftStateMachine's own _hop_held latch armed indefinitely,
##   which is harmless to slide-START (that already only fires once) but is
##   needless stale state with no benefit. So: hop=true this tick calls
##   hop_pressed() THIS tick and arms _hop_release_pending; the NEXT tick
##   (before assembling any new state) calls hop_released() and clears it --
##   a clean one-tick "tap" simulation, decided once here rather than
##   re-litigated per corner.
## - boost_tap: AiDriver's own output is already a one-shot edge; routed
##   straight through with no press/release pairing needed (boost_tap() is
##   itself a single discrete call on the controller, same as
##   racing_input_adapter.gd's own hop-while-sliding branch).
## - speed_scale: set_speed_scale() every tick, unconditionally (KartMotor's
##   own default of 1.0 covers "no scaling" for the ticks before the first
##   decide() call ever runs, so there is no missing-call gap to guard).
##
## STUCK DETECTION (fix-wave HIGH-1 -- REPLACES the fix-round-1 net-
## DISPLACEMENT design below with NET SPINE PROGRESS). Still a TUMBLING
## window, not a continuously-reset instantaneous-speed check:
## _stuck_window_anchor_total_progress_m/_stuck_window_elapsed_s anchor the
## kart's own follower.total_progress_m() once and accumulate real elapsed
## time; once _stuck_window_elapsed_s reaches respawn_stuck_after_s, this
## compares (follower.total_progress_m() - anchor) against
## respawn_stuck_speed_mps * respawn_stuck_after_s (the same natural product
## of the two existing tuning fields the fix-round-1 design already used --
## no new literal). Below that: stuck, respawn. At or above it: NOT stuck --
## re-anchor to the current total and start a fresh window, so a genuinely
## progressing kart always gets a fair, un-poisoned window rather than one
## contaminated by an earlier slow patch. total_progress_m() can decrease
## (SpineFollower.update()'s own "reverse driving decreases" semantics), so
## a kart making real net BACKWARD progress reads as stuck too, correctly --
## a comparison against 0.0 alone would not, but this compares against the
## tuned crawl-speed threshold instead, which a negative delta always fails.
##
## WHY NOT NET DISPLACEMENT (the fix-round-1 design this replaces): a kart
## can rack up real straight-line displacement every tick -- oscillating
## across the road width, spinning against a wall, ricocheting between two
## obstacles -- without ever advancing a single meter along the actual
## racing line. Net displacement compares the window's start/end WORLD
## positions, so it reads that oscillation as "moved N meters, not stuck"
## purely because the two sampled instants happened to land on different
## sides of it, even though the kart's own progress around the lap never
## went anywhere (measured: a kart oscillating at 8.7 m/s stayed confined to
## a 14m spine span for a full 30 real seconds with zero respawns -- moving
## without progressing). Net spine progress does not have this blind spot:
## it compares the SAME continuous, seam-safe SpineFollower total every
## other cross-kart comparison in this codebase already trusts (see the
## class doc's own STATE ASSEMBLY section), so a kart that is genuinely
## moving but never actually advancing reads as exactly what it is.
## Decided to REPLACE rather than keep both checks: an AND of the two would
## suppress the fix (a moving-without-progressing kart usually still clears
## the old displacement threshold, which is the whole bug), and an OR would
## make the displacement check purely redundant -- fix-round-1's own
## motivating case (a kart bouncing in place against a wall, sharp velocity
## spikes and all) already reads as flat net progress too, since none of
## that bouncing is net forward motion along the spine either. Vertical
## motion has no bearing on spine progress at all (a 2D projection onto the
## track's own polyline), so the fix-round-1 design's separate "flatten to
## XZ" step has no equivalent need here -- a kart mid-hop-arc making real
## forward progress advances its own total_progress_m() exactly as it
## should, hop or no hop.
##
## STUCK RESPAWN, once a window closes below the stuck threshold: teleport
## to spine.point_at_progress(follower.total_progress_m() -
## respawn_drop_gap_m), Y raised by RaceTuning.respawn_drop_height_m (the
## first real consumer of this previously-unread field -- see the spec's
## Recorded-debts #3), facing spine.tangent_at_progress() there via
## KartController.set_yaw_degrees() (the SAME seeding path race_session.gd's
## own spawn placement uses: place the transform, then seed yaw as an
## independent step). reset_speed() clears the motor's stale forward/
## vertical speed; follower.reset() and driver.reset() are called with the
## SAME target total (preserving lap count -- see SpineFollower.reset()'s
## own "resume mid-race" semantics) so cross-kart standings never see a
## fabricated near-full-lap regression, and clear AiDriver's edge memory per
## its own class doc ("e.g. Task 4's stuck-kart respawn path").
##
## FORCE-CLEARING AN ACTIVE SLIDE (fix round 1, reviewer follow-up on the
## same finding): the East-turn repro that motivated the displacement fix
## above gets stuck WHILE mid-slide (is_sliding() stays true for many
## seconds straight, bouncing against the inner wall) -- the original
## respawn path only reset motor speed/yaw and left the real
## DriftStateMachine's _sliding/_hop_held state completely untouched, so a
## freshly-teleported kart would still report is_sliding() true and keep
## adding slide_yaw_bonus_degrees_per_s of extra yaw every tick, right after
## being dropped onto a clean line. KartController has no direct public
## "cancel the slide" proxy, but set_run_active(false) already calls
## DriftStateMachine.cancel_slide() as one of its side effects (see
## kart_controller.gd's own doc) -- bouncing false then immediately back to
## true (both calls synchronous, no tick runs in between, so nothing ever
## observes the kart in "race finished" mode) reuses that existing public
## surface to force-clear the slide/hop-held latch without adding a new
## method whose only caller would be this one teleport path.
## respawn_count() (a plain running counter, incremented here) is exposed so
## a caller -- notably this suite's own East-turn regression-lock test --
## can observe "did the safety net actually fire" precisely, instead of
## inferring it from noisy progress deltas.
##
## RESPAWN-ONTO-PLAYER AVOIDANCE (fix-wave MEDIUM-4). Before committing to
## the centerline drop point above, _clear_of_other_karts() checks it
## against every OTHER kart's CURRENT position (horizontal-only, same
## flatten-to-XZ shape the stuck detector's own fix-round-1 displacement
## check used) -- a stuck-respawn must never teleport this kart on top of
## the player or another AI kart that happens to be sitting right there.
## ACCESS: this agent has no reach into RaceSession's own kart roster, so
## the session hands it a Callable at configure() (other_kart_positions_
## getter, optional, defaults to an invalid Callable -- every existing
## caller that never passes one keeps the exact pre-fix behavior, no
## avoidance step at all) returning every OTHER kart's global_position; see
## race_session.gd's own _spawn_ai_karts() for how it is built and bound per
## kart. This mirrors player_progress_getter's own established shape
## (binding contract 3) rather than reaching past the agent into physics
## overlap queries or a new controller-level proxy -- the session already
## owns the one place that knows about every kart, the same reason it
## already owns player_progress_getter.
## BLOCKING RADIUS / STEP SIZE: "within about one kart-length" (the brief's
## own phrasing) reads as this kart's own collision box's Z extent (see
## _read_kart_extents(), kart.tscn's BoxShape3D size = (width, height,
## length)); the lateral nudge steps in increments of that SAME box's X
## extent (kart-WIDTH steps) -- both read from the real scene once at
## configure() time rather than a literal, per this file's own no-bare-
## literal rule. A kart with no readable CollisionShape3D (bare test
## fixtures that construct a plain CharacterBody3D.new()) reads both as
## 0.0, which safely disables this whole step rather than guessing.
## SEARCH: tries the centerline point first (the common case: nothing is
## there), then steps outward in kart-width increments alternating right/
## left, capped at the widest lateral offset any already-authored AI slot
## legitimately sits at (opponent_count/2 slots * lateral_slot_spacing_m --
## see MEDIUM-3's grid-slot fix, which proved that whole range fits both
## real tracks' own road width) so this can never push a kart somewhere
## MEDIUM-3 didn't already verify is on the road. If every step in that
## bounded range is still blocked (pathological -- would need the full AI
## grid plus the player all crowded onto the exact same short stretch), it
## falls back to the plain centerline point rather than searching forever
## or picking something outside the proven-safe range.

const AiDriverType := preload("res://src/racing/ai/ai_driver.gd")
const SpineFollowerType := preload("res://src/racing/track/spine_follower.gd")
const ScalarMathType := preload("res://src/core/scalar_math.gd")

var _kart: CharacterBody3D
var _spine: TrackSpine
var _ai_tuning: AiTuning
var _kart_tuning: KartTuning
var _race_tuning: RaceTuning
var _slot_index: int
var _player_progress_getter: Callable
# Fix-wave MEDIUM-4: optional -- see configure()'s own doc and the class
# doc's RESPAWN-ONTO-PLAYER AVOIDANCE section below.
var _other_kart_positions_getter: Callable

var _driver: RefCounted
var _follower: RefCounted
var _lateral_target_m: float
# Fix-wave MEDIUM-4: this kart's own collision extents, read once at
# configure() (see _read_kart_extents()) -- 0.0 when unreadable (a test
# fixture with no CollisionShape3D child), which safely disables the
# respawn-onto-player avoidance below rather than guessing a literal.
var _kart_length_m: float
var _kart_width_m: float

var _stuck_window_anchor_total_progress_m: float
var _stuck_window_elapsed_s: float
var _respawn_count: int
var _hop_release_pending: bool
var _configured: bool
# See the class doc's RUN-ACTIVE GATE section. Starts true so a kart that is
# active from its very first tick (the normal case) never misreads tick 1 as
# a "reactivation".
var _was_run_active: bool = true


## RUN-ACTIVE GATE (Task 5, CTR R3 integration, BINDING CONTRACT 1). Every
## _physics_process tick first checks kart.is_run_active() -- when false
## (RaceSession freezes every kart at the finish line via set_run_active(
## false), see race_session.gd's own finish handling) this entire method is a
## no-op: no steer/hop/speed_scale calls, and critically, NO stuck-window
## accumulation either. Without the second half of that, a frozen kart whose
## position legitimately stops changing (it is deliberately parked) would
## read EXACTLY like a wedged one once _stuck_window_elapsed_s crosses
## respawn_stuck_after_s, and _respawn()'s own set_run_active(false) ->
## set_run_active(true) bounce (see FORCE-CLEARING AN ACTIVE SLIDE below)
## would silently reactivate it seconds after the race was supposed to have
## frozen it solid -- a real, reviewer-probe-confirmed resurrection bug.
##
## _was_run_active tracks the PREVIOUS tick's active state so a
## false -> true transition (reactivation) can be caught as an edge: the
## stuck window is re-anchored fresh right then (anchor = current follower.
## total_progress_m(), elapsed = 0.0) rather than either (a) carrying
## forward however much time accumulated while frozen (which would
## immediately misread the frozen gap itself as "hasn't moved in ages" and
## fire a false-positive respawn on the very next qualifying tick) or (b)
## comparing against a stale pre-freeze anchor total. This mirrors _check_
## stuck_and_respawn's own "genuinely progressing kart always gets a fair,
## un-poisoned window" rationale one
## level up: a kart coming OFF a freeze deserves the same fresh start a kart
## that just cleared its own stuck threshold gets.
##
## Fix round 1 (reviewer [MEDIUM]): configure() now verifies the SpineFollower
## it just built is actually usable (spine.length_m() > 0, mirrored by
## SpineFollower.is_valid() -- see spine_follower.gd's own configure() doc)
## before committing to _configured = true. A TrackSpine with no markers (or
## any other zero/negative-length degenerate) previously left this agent
## "configured" but silently driving off of a follower that fails closed to
## 0.0 forever -- steer/lookahead/curvature would all be computed from a
## permanently-wrong progress=0.0 instead of anything real. Failing closed
## here instead (push_error, _configured stays false, every _physics_process
## tick after is a no-op) matches AiDriver's/SpineFollower's own fail-closed
## shape one layer up, and is loud about it immediately at configure() time
## rather than silently misbehaving forever.
func configure(
	kart: CharacterBody3D,
	spine: TrackSpine,
	ai_tuning: AiTuning,
	kart_tuning: KartTuning,
	race_tuning: RaceTuning,
	slot_index: int,
	player_progress_getter: Callable,
	other_kart_positions_getter: Callable = Callable()
) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_kart = kart
	_spine = spine
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning
	_race_tuning = race_tuning
	_slot_index = slot_index
	_player_progress_getter = player_progress_getter
	_other_kart_positions_getter = other_kart_positions_getter

	var extents := _read_kart_extents()
	_kart_width_m = extents.x
	_kart_length_m = extents.z

	_driver = AiDriverType.new()
	_driver.configure(ai_tuning, kart_tuning)

	_follower = SpineFollowerType.new()
	_follower.configure(spine.length_m())
	if not _follower.is_valid():
		push_error(
			(
				"AiKartAgent.configure: TrackSpine.length_m() was not "
				+ "positive (got %s) -- failing closed: this agent will not "
				+ "process until reconfigured with a valid spine."
			) % spine.length_m()
		)
		_configured = false
		return
	_follower.reset(spine.progress_for_position(kart.global_position))

	_lateral_target_m = _compute_lateral_target_m()
	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	_respawn_count = 0
	_hop_release_pending = false
	_was_run_active = true
	_configured = true


## This kart's own continuous, never-wrapping progress -- exposed so a
## caller (Task 5's standings/placement, or this suite's own tests) never
## has to reach past this agent into its private SpineFollower. 0.0 before a
## successful configure(), matching SpineFollower's own fail-closed shape.
func total_progress_m() -> float:
	return _follower.total_progress_m() if _configured else 0.0


## How many times the stuck-detector has force-teleported this kart --
## exposed for the same "observe the safety net precisely, don't infer it
## from noisy progress deltas" reason total_progress_m() is. 0 before a
## successful configure() (nothing has run yet) and 0 after one that never
## needed to respawn -- both indistinguishable from "never got stuck",
## which is the correct reading either way.
func respawn_count() -> int:
	return _respawn_count


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return

	# See the class doc's RUN-ACTIVE GATE section (Task 5 binding contract).
	if not bool(_kart.call("is_run_active")):
		_was_run_active = false
		return
	if not _was_run_active:
		_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
		_stuck_window_elapsed_s = 0.0
		_was_run_active = true

	if _hop_release_pending:
		_kart.call("hop_released")
		_hop_release_pending = false

	if _check_stuck_and_respawn(delta_s):
		return

	var kart_pos: Vector3 = _kart.global_position
	var raw_progress := _spine.progress_for_position(kart_pos)
	_follower.update(raw_progress, _max_follower_step_m(delta_s))
	var progress: float = _follower.lap_progress_m()

	var decision: Dictionary = _driver.decide(_assemble_state(kart_pos, progress))
	_route_decision(decision)


func _assemble_state(kart_pos: Vector3, progress: float) -> Dictionary:
	var speed_mps: float = _kart.call("speed_mps")
	var lookahead_m := _ai_tuning.lookahead_min_m + speed_mps * _ai_tuning.lookahead_speed_gain_s

	var forward: Vector3 = -_kart.global_transform.basis.z
	var lookahead_point := _spine.point_at_progress(progress + lookahead_m)
	var curvature_ahead := _spine.curvature_at_progress(progress, lookahead_m)

	var tangent_now := _spine.tangent_at_progress(progress)
	var right := tangent_now.cross(Vector3.UP)
	var centerline_point := _spine.point_at_progress(progress)
	var actual_lateral_m := (kart_pos - centerline_point).dot(right)
	var lateral_error_m := _lateral_target_m - actual_lateral_m

	var player_progress := 0.0
	if _player_progress_getter.is_valid():
		player_progress = float(_player_progress_getter.call())
	var band_gap_m: float = player_progress - _follower.total_progress_m()

	return {
		"position": kart_pos,
		"forward": forward,
		"speed_mps": speed_mps,
		"is_sliding": bool(_kart.call("is_sliding")),
		"boost_window_open": bool(_kart.call("boost_window_open")),
		"lookahead_point": lookahead_point,
		"curvature_ahead": curvature_ahead,
		"lateral_error_m": lateral_error_m,
		"band_gap_m": band_gap_m,
	}


func _route_decision(decision: Dictionary) -> void:
	_kart.call("steer", float(decision.get("steer", 0.0)))
	_kart.call("set_brake", bool(decision.get("brake", false)))
	if bool(decision.get("hop", false)):
		_kart.call("hop_pressed")
		_hop_release_pending = true
	if bool(decision.get("boost_tap", false)):
		_kart.call("boost_tap")
	_kart.call("set_speed_scale", float(decision.get("speed_scale", 1.0)))


## Per-tick clamp for this kart's own SpineFollower.update() -- the true
## physical ceiling on how far a kart can travel in one tick, derived
## entirely from tuning (no literal): (top_speed_mps + boost_speed_bonus_mps)
## is KartMotor's own maximum possible forward-speed TARGET (see
## kart_motor.gd's tick()), and (1.0 + rubber_band_boost_max_ratio) is the
## most that target can then be scaled up by (see kart_motor.gd's own
## set_speed_scale() doc and ai_driver.gd's RUBBER BAND section for the cap).
## Multiplying both in is the actual worst-case top speed this specific kart
## can ever be commanded to -- using only top_speed_mps (as the brief's own
## looser phrasing, "kart top speed x delta x a safety factor", might
## suggest) would UNDERESTIMATE it during a boosted, rubber-banding tick and
## risk clamping away real forward movement into a false seam-ambiguity
## read.
func _max_follower_step_m(delta_s: float) -> float:
	var max_target_speed_mps := (
		(_kart_tuning.top_speed_mps + _kart_tuning.boost_speed_bonus_mps)
		* (1.0 + _ai_tuning.rubber_band_boost_max_ratio)
	)
	return max_target_speed_mps * delta_s


## See the class doc's STUCK DETECTION section for why this is a tumbling
## NET SPINE PROGRESS window rather than a net-displacement or instantaneous-
## velocity check. Reads follower.total_progress_m() as it stood at the END
## of the PREVIOUS tick's update (this tick's own follower.update() has not
## run yet -- see _physics_process's own ordering) -- a one-tick staleness
## that is immaterial against a multi-second window. Returns true (and has
## already respawned) exactly on the tick a closing window reads as stuck;
## the caller must skip the rest of that tick's normal drive logic, since
## _respawn() has just invalidated the kart's position/the follower's own
## total out from under it.
func _check_stuck_and_respawn(delta_s: float) -> bool:
	_stuck_window_elapsed_s += delta_s
	if _stuck_window_elapsed_s < _ai_tuning.respawn_stuck_after_s:
		return false

	var net_progress_m: float = (
		float(_follower.total_progress_m()) - _stuck_window_anchor_total_progress_m
	)
	var stuck_threshold_m := (
		_ai_tuning.respawn_stuck_speed_mps * _ai_tuning.respawn_stuck_after_s
	)
	if net_progress_m < stuck_threshold_m:
		_respawn()
		return true

	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	return false


## See the class doc's LATERAL SLOT CENTERING section.
func _compute_lateral_target_m() -> float:
	var total_karts := _ai_tuning.opponent_count + 1.0
	var centered_slot := float(_slot_index) - (total_karts - 1.0) * ScalarMathType.HALF
	return centered_slot * _ai_tuning.lateral_slot_spacing_m


## See the class doc's STUCK RESPAWN and FORCE-CLEARING AN ACTIVE SLIDE
## sections.
func _respawn() -> void:
	_respawn_count += 1

	var target_total: float = _follower.total_progress_m() - _ai_tuning.respawn_drop_gap_m
	var length := _spine.length_m()
	var wrapped_target := fposmod(target_total, length) if length > 0.0 else 0.0

	var point := _spine.point_at_progress(wrapped_target)
	var tangent := _spine.tangent_at_progress(wrapped_target)
	# See the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section.
	point = _clear_of_other_karts(point, tangent)

	_kart.global_position = point + Vector3.UP * _race_tuning.respawn_drop_height_m
	if not tangent.is_zero_approx():
		var facing_degrees := rad_to_deg(Vector3.FORWARD.signed_angle_to(tangent, Vector3.UP))
		_kart.call("set_yaw_degrees", facing_degrees)
	_kart.call("reset_speed")
	# Fix round 1 (reviewer follow-up): force-clears DriftStateMachine's own
	# _sliding/_hop_held state through the only public surface that reaches
	# it (see the class doc's FORCE-CLEARING AN ACTIVE SLIDE section) -- a
	# kart teleported off a wedge it was still actively sliding against must
	# not keep adding slide yaw on its fresh, clean line.
	_kart.call("set_run_active", false)
	_kart.call("set_run_active", true)

	_follower.reset(target_total)
	_driver.reset()
	_stuck_window_anchor_total_progress_m = _follower.total_progress_m()
	_stuck_window_elapsed_s = 0.0
	_hop_release_pending = false


## See the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section. Returns the
## centerline point unchanged when there is nothing to check against (no
## getter wired -- the default for every caller that never passes one, see
## configure()'s own doc -- or no readable kart extents, or a degenerate
## zero tangent with no sensible lateral direction to offset along).
func _clear_of_other_karts(point: Vector3, tangent: Vector3) -> Vector3:
	if not _other_kart_positions_getter.is_valid():
		return point
	if tangent.is_zero_approx() or _kart_length_m <= 0.0 or _kart_width_m <= 0.0:
		return point
	var other_positions: Array = _other_kart_positions_getter.call()
	if _point_is_clear_of(point, other_positions):
		return point

	var right := tangent.cross(Vector3.UP)
	# The widest lateral offset any legitimately-placed AI kart already sits
	# at (slot_index = opponent_count, the far end of _compute_lateral_
	# target_m()'s own centered range) -- a tuning-derived bound on how far
	# this nudge may push the drop point, so it can only ever land somewhere
	# already proven to fit the road (see MEDIUM-3's grid-slot fix), never
	# off it. No new literal: HALF via ScalarMathType, same as _compute_
	# lateral_target_m()'s own derivation one function up.
	var max_offset_m := _ai_tuning.opponent_count * ScalarMathType.HALF * _ai_tuning.lateral_slot_spacing_m
	var step_index := 1
	while float(step_index) * _kart_width_m <= max_offset_m:
		var offset_m := float(step_index) * _kart_width_m
		var candidate_right := point + right * offset_m
		if _point_is_clear_of(candidate_right, other_positions):
			return candidate_right
		var candidate_left := point - right * offset_m
		if _point_is_clear_of(candidate_left, other_positions):
			return candidate_left
		step_index += 1
	# No clear step found within the tuning-derived bound -- best effort:
	# drop at the original centerline point rather than searching forever or
	# picking something outside the proven-safe range.
	return point


## Horizontal-only (flattened to XZ, same rationale as the stuck-detector's
## own fix-round-1 displacement check) proximity test against every OTHER
## kart's current position -- "within about one kart-length" per this fix's
## own brief, using the real collision extents read at configure() rather
## than a literal.
func _point_is_clear_of(point: Vector3, other_positions: Array) -> bool:
	for other_position: Variant in other_positions:
		var other: Vector3 = other_position
		var horizontal := Vector3(
			point.x - other.x,
			0.0,
			point.z - other.z
		).length()
		if horizontal < _kart_length_m:
			return false
	return true


## Reads this kart's own collision extents once at configure() time -- see
## the class doc's RESPAWN-ONTO-PLAYER AVOIDANCE section. Vector3.ZERO (x/z
## both 0.0) when the kart has no BoxShape3D CollisionShape3D child to read
## (a bare test fixture, e.g. a plain CharacterBody3D.new()) -- the caller
## treats a non-positive extent as "cannot compute a meaningful kart-length/
## kart-width, skip the avoidance step entirely" rather than guessing.
func _read_kart_extents() -> Vector3:
	var collision := _kart.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return Vector3.ZERO
	var box := collision.shape as BoxShape3D
	if box == null:
		return Vector3.ZERO
	return box.size
