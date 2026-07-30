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
## - lateral_target_m: this slot's centered offset from the pursuit line,
##   computed once in configure() (see _compute_lateral_target_m()) since
##   slot_index/ai_tuning never change per tick.
## - lateral_error_m = lateral_target_m - actual_lateral_m, where
##   actual_lateral_m is the perpendicular projection of (kart_pos -
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
## STUCK DETECTION reads the KART'S OWN REAL, physics-resolved horizontal
## velocity (CharacterBody3D.velocity, flattened to XZ) against
## ai_tuning.respawn_stuck_speed_mps -- deliberately NOT
## KartController.speed_mps() (KartMotor's purely kinematic "commanded"
## speed, used above for state.speed_mps). KartMotor's forward_speed_mps
## has no feedback from collision resolution at all: a kart wedged against a
## wall keeps accelerating its own internal target regardless, so
## speed_mps() would never notice a real jam. The real CharacterBody3D
## velocity DOES reflect move_and_slide()'s actual collision response, which
## is the only physically meaningful signal for "is this kart actually
## stuck". Vertical velocity is excluded (a kart mid-hop-arc with near-zero
## horizontal speed is legitimately airborne, not stuck).
##
## STUCK RESPAWN, once _stuck_elapsed_s reaches respawn_stuck_after_s:
## teleport to spine.point_at_progress(follower.total_progress_m() -
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
## its own class doc ("e.g. Task 4's stuck-kart respawn path"). Deliberately
## narrow, matching only what the brief names: this does NOT force-cancel an
## in-progress slide (DriftStateMachine.cancel_slide() has no public
## KartController proxy, and a kart stuck long enough to trigger this is in
## practice not mid-drift -- sliding implies cornering at speed). If a kart
## somehow gets wedged mid-slide, the next tick's fresh (near-zero-curvature
## in practice) state lets the real FSM's own straighten-out end path finish
## naturally.

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

var _driver: RefCounted
var _follower: RefCounted
var _lateral_target_m: float

var _stuck_elapsed_s: float
var _hop_release_pending: bool
var _configured: bool


func configure(
	kart: CharacterBody3D,
	spine: TrackSpine,
	ai_tuning: AiTuning,
	kart_tuning: KartTuning,
	race_tuning: RaceTuning,
	slot_index: int,
	player_progress_getter: Callable
) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_kart = kart
	_spine = spine
	_ai_tuning = ai_tuning
	_kart_tuning = kart_tuning
	_race_tuning = race_tuning
	_slot_index = slot_index
	_player_progress_getter = player_progress_getter

	_driver = AiDriverType.new()
	_driver.configure(ai_tuning, kart_tuning)

	_follower = SpineFollowerType.new()
	_follower.configure(spine.length_m())
	_follower.reset(spine.progress_for_position(kart.global_position))

	_lateral_target_m = _compute_lateral_target_m()
	_stuck_elapsed_s = 0.0
	_hop_release_pending = false
	_configured = true


## This kart's own continuous, never-wrapping progress -- exposed so a
## caller (Task 5's standings/placement, or this suite's own tests) never
## has to reach past this agent into its private SpineFollower. 0.0 before a
## successful configure(), matching SpineFollower's own fail-closed shape.
func total_progress_m() -> float:
	return _follower.total_progress_m() if _configured else 0.0


func _physics_process(delta_s: float) -> void:
	if not _configured:
		return

	if _hop_release_pending:
		_kart.call("hop_released")
		_hop_release_pending = false

	var kart_pos: Vector3 = _kart.global_position
	var raw_progress := _spine.progress_for_position(kart_pos)
	_follower.update(raw_progress, _max_follower_step_m(delta_s))
	var progress: float = _follower.lap_progress_m()

	var horizontal_velocity := Vector3(_kart.velocity.x, 0.0, _kart.velocity.z)
	_track_stuck(horizontal_velocity.length(), delta_s)
	if _stuck_elapsed_s >= _ai_tuning.respawn_stuck_after_s:
		_respawn()
		return

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
		"lateral_target_m": _lateral_target_m,
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


func _track_stuck(horizontal_speed_mps: float, delta_s: float) -> void:
	if horizontal_speed_mps < _ai_tuning.respawn_stuck_speed_mps:
		_stuck_elapsed_s += delta_s
	else:
		_stuck_elapsed_s = 0.0


## See the class doc's LATERAL SLOT CENTERING section.
func _compute_lateral_target_m() -> float:
	var total_karts := _ai_tuning.opponent_count + 1.0
	var centered_slot := float(_slot_index) - (total_karts - 1.0) * ScalarMathType.HALF
	return centered_slot * _ai_tuning.lateral_slot_spacing_m


## See the class doc's STUCK RESPAWN section.
func _respawn() -> void:
	var target_total: float = _follower.total_progress_m() - _ai_tuning.respawn_drop_gap_m
	var length := _spine.length_m()
	var wrapped_target := fposmod(target_total, length) if length > 0.0 else 0.0

	var point := _spine.point_at_progress(wrapped_target)
	var tangent := _spine.tangent_at_progress(wrapped_target)

	_kart.global_position = point + Vector3.UP * _race_tuning.respawn_drop_height_m
	if not tangent.is_zero_approx():
		var facing_degrees := rad_to_deg(Vector3.FORWARD.signed_angle_to(tangent, Vector3.UP))
		_kart.call("set_yaw_degrees", facing_degrees)
	_kart.call("reset_speed")

	_follower.reset(target_total)
	_driver.reset()
	_stuck_elapsed_s = 0.0
	_hop_release_pending = false
