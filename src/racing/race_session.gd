class_name RaceSession
extends Node3D

## Time-trial race conductor (Task 7). Mirrors level_session.gd's role --
## the one place that wires the racing pieces built by Tasks 1-6 together
## and drives the parts of a race that don't already self-tick -- but much
## smaller, since it owns none of the platformer's crate/enemy/checkpoint
## machinery. This IS the root script of scenes/racing/race_time_trial.tscn,
## the same relationship LevelSession has to a level scene (e.g.
## NSanityBeach): its children are found by fixed authored paths, not
## rediscovered by type scan, except for the CheckpointGate instances
## (found by type under Track, the same "find the small authored instances"
## shape LevelSession uses for crates/enemies).
##
## SELF-TICKING CHILDREN. KartController (kart_controller.gd) and
## KartCamera (kart_camera.gd) both already drive themselves every physics
## tick via their own _physics_process() once configure()d and in the tree
## -- see their class docs. This session must NOT also call a tick/update
## method on either; doing so would double-tick them. This session's own
## _physics_process() is responsible only for what nothing else already
## drives: routing input into the kart, the wrong-way grace timer, and
## noticing when the race is over.
##
## TIMER. elapsed_s() sums delta_s from this session's own _physics_process
## each tick (M1 fix-wave revision -- it used to be a live MonotonicClock
## diff against a start timestamp, which read real wall-clock time straight
## through GameRoot pausing the whole tree via SceneTree.paused, since
## nothing about a raw clock diff cares whether anything actually ticked in
## between). configure() now sets process_mode = PROCESS_MODE_PAUSABLE
## (previously left at the INHERIT default, which silently inherited
## GameRoot's own PROCESS_MODE_ALWAYS and so never stopped ticking for a
## pause at all) so _physics_process simply doesn't run while paused,
## mirroring level_session.gd's identical process_mode = PAUSABLE +
## LevelRunState.advance_relic_timer(delta_s)-every-tick precedent for the
## platformer's own relic stopwatch. This trades the old approach's
## immunity to physics-substep jitter for pause-correctness; the resulting
## drift is bounded by Engine.physics_jitter_fix's own substep accounting
## and negligible at time-trial race lengths. Lap splits are recorded as
## the DELTA between consecutive gate-0 crossings (not a cumulative "time
## at lap N"), which is what a finish panel's "splits" list conventionally
## shows, and inherit the same pause-correctness for free since both read
## through elapsed_s().
##
## INPUT ROUTING. RacingInputAdapter (racing_input_adapter.gd) maps
## InputRouter's buffered move vector and the shared HOP action onto the
## kart's poll surface. hop_pressed()/hop_released() must fire once per
## real edge, not once per tick the button happens to read true -- this
## session tracks the previous tick's held state itself rather than using
## InputIntentBuffer's windowed consume_pressed()/consume_released() (that
## windowed buffering exists for the platformer's jump-buffer forgiveness
## window, tuned by a platformer-only InputTuning field with no racing
## equivalent; a hop press has no such forgiveness need since
## DriftStateMachine already owns its own slide-arming timing).
##
## ITEM RNG (R4 Task 3). This session owns ONE seeded RandomNumberGenerator
## for the whole race and is the sole caller of ItemSlot.start_roll() for
## every kart in it (player and AI alike) -- see item_slot.gd's own RNG
## INJECTION doc for why the slot itself never touches randomness directly.
## item_rng_seed (exported, default 0) is the "determinism vs variety"
## knob: 0 means "no fixed seed was authored" and configure() calls
## RandomNumberGenerator.randomize() so ordinary play gets a genuinely
## different item sequence every race; any non-zero value is used as an
## explicit RandomNumberGenerator.seed, so a GUT test (or a future replay/
## regression fixture) can pin an exact, reproducible sequence of pickups
## by setting this exported field before configure() runs, the same
## "override a field on the session, don't touch RaceSession's internals"
## shape the existing spawn_opponents flag already establishes. Re-seeded
## fresh on every configure() call (including a re-configure/retry), so a
## fixed seed always reproduces the exact same sequence from race start.
##
## ITEM BOX WIRING mirrors the checkpoint-gate pattern one section up:
## boxes are discovered by type under Track (_discover_item_boxes(), the
## same find_children("*", "Area3D", true, false) scan _discover_gates()
## already uses) and this session connects to each one's native
## body_entered signal itself -- ItemBox emits nothing of its own (see
## item_box.gd's own class doc), it only manages its own hide/respawn
## bookkeeping through a SEPARATE listener on that same signal. A pickup
## routes to the ENTERING BODY's own ItemSlot (kart.item_slot(), looked up
## by calling the body directly -- no per-kart lookup table is needed the
## way gate crossings need _gate_validators, since the body IS the kart
## whose slot must roll), for player and AI karts identically -- there is
## no separate "is this the player" branch anywhere in this path. R4 Task 5
## authored 6 ItemBox instances on each of the two real tracks (ItemBoxes/
## ItemBoxNorth1-3 + ItemBoxSouth1-3 under track_graybox_loop.tscn,
## ItemBoxEast1-3 + ItemBoxBack1-3 under track_sanity_shores.tscn), each kept
## a real 10m clearance from the track's own local origin -- enforced by the
## TRACK_ITEM_BOX_RULE authoring lint (scripts/lint_level_authoring.py's own
## TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M, spec Recorded-debt #10; see
## tests/lint/test_level_authoring_lint.py::
## test_item_box_near_origin_fires_the_item_box_rule) rather than by anything
## this session itself checks. _discover_item_boxes() picks all 6 up on both
## tracks via the same find_children() scan this section's own opening line
## describes, so this wiring is live and exercised on every real race, not
## merely by the synthetic-ItemBox tests that first proved the plumbing
## before any track authored one.
##
## PAD WIRING (Task 1, CTR R7 -- discharges spec debt #2) mirrors the ITEM
## BOX WIRING shape immediately above almost exactly: BoostPad/JumpPad
## instances are discovered by TYPE under Track (_discover_boost_pads()/
## _discover_jump_pads(), the same find_children("*", "Area3D", true,
## false) scan _discover_gates()/_discover_item_boxes() already use) and
## this session connects to each one's native body_entered signal itself.
## Two real differences from item boxes: (1) a PER-PAD bound handler is
## used (pad.body_entered.connect(_on_boost_pad_body_entered.bind(pad)),
## the same Callable-equality-guards-against-a-duplicate-connection shape
## the gate loop above already uses) rather than one shared unbound
## handler, because -- unlike item-box routing, which only ever needs the
## ENTERING BODY -- firing a pad also needs to know WHICH pad fired, to
## call that pad's own try_consume() cooldown gate; and (2) each handler
## reads _race_tuning.pad_boost_s/jump_pad_velocity_scale itself and calls
## the entering body's own apply_boost()/launch() directly -- there is no
## per-kart routing table to look up (mirrors _on_box_body_entered's own
## "the body passed in by body_entered already IS the kart" shape, not
## _gate_validators' identity-lookup shape).
##
## Gated on _race_started (see _on_gate_body_entered's/_on_box_body_
## entered's own "Fix round 1, reviewer [LOW-2]" doc: a frozen kart can
## never physically reach a pad before GO either) -- both pad handlers
## early-return pre-GO, proven directly the same synthetic-call way
## test_race_start_flow.gd's own test_gate_crossing_is_a_no_op_pre_go/
## test_box_pickup_is_a_no_op_pre_go already prove it for gates/boxes.
##
## pad.try_consume(body) is called BEFORE the kart method, and its own
## return value gates whether this session calls apply_boost()/launch() at
## all -- see boost_pad.gd's own try_consume() doc for why this is a
## single atomic "check AND claim" call rather than a separate check-then-
## mark pair. Neither track currently authors any pads (Task 3/4 do) --
## _discover_boost_pads()/_discover_jump_pads() simply return empty arrays
## on a pad-less Track, the identical "no boxes authored yet" degrade
## _discover_item_boxes() already handled the same way before R4 Task 5
## authored any.
##
## SOLO TIME TRIAL DOES NOT ROLL. spawn_opponents (not a new, separate
## exported flag) also gates item rolls: _items_allowed() reads it
## directly, so a solo race (spawn_opponents = false, see that field's own
## doc) never starts a roll even if a box is present and hit -- item pickups
## are a racing-against-someone mechanic, and solo time trial's own
## established contract is "race minus AI", nothing added in its place. A
## dedicated allow_items flag was considered and rejected: it would be a
## second lever controlling the exact same "is anyone actually being raced
## against" question spawn_opponents already answers, with no scene yet
## needing to set the two differently.
##
## COUNTDOWN + START BOOST (R5 Task 1). Every kart -- player included --
## now spawns FROZEN (set_run_active(false), called right after each kart's
## own configure() re-activates it -- see configure()'s and _spawn_ai_
## karts()'s own per-kart doc) and stays frozen through a real 3-2-1
## countdown before the race actually begins. _physics_process branches on
## _race_started: while false, the ONLY thing that happens is _tick_
## countdown() (drives the pure CountdownTimer and, for the player only,
## samples HOP-held into the pure StartBoostJudge) -- nothing else in this
## session's usual per-tick body runs, which is what makes "frozen pre-GO"
## true by construction rather than by convention: _route_input() never
## fires (no move/hop/item ever reaches a kart pre-GO), _update_wrong_way()
## never fires (the wrong-way flag simply cannot raise pre-GO), and _elapsed_
## s never accumulates (the race timer starts AT GO, not at spawn -- see
## elapsed_s()'s own class-doc TIMER section one level up, unchanged: it
## still just sums delta_s from ticks that actually ran this body's own
## logic). AI karts need no equivalent gating here at all -- they are frozen
## the exact same way the finish line already freezes them, and AiKartAgent's
## own is_run_active() gate (Task 5 binding contract 1, see ai_kart_agent.
## gd's own RUN-ACTIVE GATE section) is what makes THAT freeze safe for the
## stuck detector "by construction", proven once there and reused here
## unmodified -- this task's own coverage drives real physics through a real
## countdown to prove that reuse actually holds, rather than assuming it.
##
## GO: _tick_countdown() calls _start_race() on the exact tick CountdownTimer.
## tick() returns &"go" (a one-shot edge -- see countdown_timer.gd's own
## class doc). _start_race() reads StartBoostJudge.verdict() ONCE and
## applies it:
## &"boost" -- the player's own kart unfreezes immediately and gets
## apply_boost(kart_tuning.boost_duration_s) the SAME tick. There is no
## dedicated "launch boost seconds" tuning field of its own to spend here --
## inventing one would duplicate KartTuning.boost_duration_s (the item-turbo
## boost's own duration) for a value with no reason to differ, so the launch
## boost deliberately REUSES that same field rather than adding a new one.
## &"bog" -- the player's own kart is NOT unfrozen this tick. Instead
## _bog_kart/_bog_remaining_s record which kart and for how much longer
## (RaceTuning.start_bog_penalty_s), and the post-GO _physics_process branch
## below counts that down every real tick (pause-correct for free, the same
## "only ticks that actually ran contribute" TIMER contract elapsed_s()
## already relies on) until it reaches zero, at which point THAT kart's own
## set_run_active(true) finally fires, once. A dedicated "hold this kart's
## throttle at zero" mechanism was considered and rejected in favor of
## reusing set_run_active(false)/(true) exactly as authored (the finish-line
## freeze already proves this call pair is a real, safe "stop, then resume"
## primitive) -- simplest correct choice, not a new one.
## &"none" -- the player's own kart unfreezes plainly, same as every AI kart.
## AI karts ALWAYS unfreeze plainly at GO regardless of verdict -- the start-
## boost minigame is a player-skill mechanic in R5 (documented, not an
## oversight: AiDriver has no HOP-hold heuristic to samples this judge
## against, and giving AI a free/random verdict would need its own tuned
## behavior this task's brief does not ask for).
##
## _route_input() now early-returns when the PLAYER's own kart reports
## is_run_active() false -- before this task the only way _route_input()
## ever ran while the kart was inactive was never (a finished race short-
## circuits the whole _physics_process before _route_input() is reached, see
## the branch at the top of that function). The bog delay is new ground: the
## race has genuinely started (_race_started true) while the bogged kart
## specifically is still mid-freeze, so _physics_process DOES reach _route_
## input() during that window. Without this guard, a HOP press during the
## bog penalty would still reach KartController.hop_pressed() -- which does
## NOT itself check is_run_active() (see kart_controller.gd's own doc: only
## is_spinning_out() gates it) -- and could apply a real vertical hop impulse
## to a kart RaceSession believes is frozen solid, the exact class of bug
## the countdown's own "zero displacement while frozen" contract exists to
## prevent. Steer/brake/item routing are harmless no-ops on a decelerating
## kart either way, but gating the whole function is simpler and more
## obviously correct than gating each call inside it individually.
##
## LIVE RANKING (R5 Task 2). _refresh_rank_snapshot(), called once every
## _physics_process tick post-GO/pre-finish (right after _update_player_
## follower()), builds one Dictionary entry per kart -- player and every AI
## kart alike -- purely by READING numbers this session and AiKartAgent
## already maintain: LapValidator.current_lap()/progress_gates() (pure
## counters, gate crossings only) and each kart's own continuous
## SpineFollower.total_progress_m() (the player's own _player_follower,
## already updated this exact tick by _update_player_follower() one line up;
## each AI's own private follower, updated inside ITS OWN AiKartAgent.
## _physics_process(), a sibling node ticking independently -- see
## ai_kart_agent.gd's own STUCK DETECTION doc for the identical "one tick of
## staleness across sibling nodes is immaterial" precedent this shares). No
## new TrackSpine.progress_for_position()/closest-offset call is made
## anywhere in this path -- the fix-wave LOW-6 precedent this class doc's
## own TIMER section already established (computed once, threaded through,
## never recomputed) extends naturally here since every field this snapshot
## reads was ALREADY a plain counter or cached total before this task.
## RaceRanking.rank() (race_ranking.gd, pure) turns that Array[Dictionary]
## into an ordered Array of kart ids; _current_rank_order caches the result,
## and player_position()/field_size() are thin reads off that cache -- see
## their own docs.
##
## AI FINISH RECORDING. Before this task, an AI kart's own LapValidator
## (routed by _gate_validators, same as the player's) kept advancing forever
## once it crossed gate 0 -- including a &"race_complete" outcome once it
## banked its own lap_count laps -- but _on_gate_body_entered() discarded
## that outcome outright for any body other than the player's own kart (the
## `if body != _kart: return` guard, unchanged in shape, just no longer a
## silent drop). It now calls _record_finish(body, elapsed_s()) first for
## exactly that outcome, so an AI kart's own eventual gate_crossed() call
## being an ordinary &"ok"/&"out_of_order" the rest of the time costs
## nothing new -- the AI-finish check is a single StringName compare added to
## a branch already reached every gate crossing. AI KARTS KEEP DRIVING
## AFTER FINISHING (unchanged behavior -- no freeze, no is_run_active()
## change) -- LapValidator's own _laps_completed counter has no upper clamp
## (see lap_validator.gd's own SEQUENCE doc), so a still-driving AI kart
## keeps closing laps and _complete_lap() keeps returning &"race_complete"
## on every one of them (`_laps_completed >= _lap_count` stays true forever
## once it first goes true). _record_finish() is idempotent specifically to
## absorb that: only the FIRST &"race_complete" for a given kart ever writes
## an entry, so a kart's own finished_order/finish elapsed freeze at its
## true first-finish instant no matter how many more times its own
## validator re-reports the same outcome afterward. RaceRanking's own tier-1
## "finished before unfinished, unconditionally" rule is what then makes
## that frozen finished_order outrank every further lap/gate/progress that
## kart keeps racking up post-finish -- its RANK freezes even though the
## KART does not, exactly the plan's own "an AI that finishes keeps driving
## but its rank freezes at its finish slot" requirement.
##
## The player's own finish reuses the SAME _record_finish() helper --
## _finish_race() calls it first thing, before anything else, so the
## player's own finished_order/finish elapsed sit in the exact same
## dictionaries an AI kart's would, interleaved by whenever each actually
## crossed the line. Once _finished flips true, _on_gate_body_entered()'s
## own post-_finished branch drops the player's own crossings unconditionally
## and every AI kart's own further crossings ONCE THAT KART has already been
## recorded -- so, past the very same tick the player finished on (see SAME-
## TICK PHOTO FINISH below), no MORE finishes can ever be recorded, matching
## _finish_race()'s own existing "freeze the whole field" contract one
## section down: an AI kart that has not yet finished by the time the player
## does (and was not mid-dispatch on its own race_complete THAT SAME tick)
## simply never gets a finished_order at all, which is exactly what Task 3's
## own "unfinished ranked by progress at player-finish" ruling needs to read.
##
## SAME-TICK PHOTO FINISH (fix round 1, reviewer [MEDIUM]). Godot dispatches
## every Area3D body_entered signal a physics step detects in sequence,
## having already queued all of them before any one callback starts running
## -- so if the player's own crossing happens to be dispatched FIRST in a
## tick where an AI kart also crosses its own finish gate, the naive guard
## "_finished is true, drop everything" would silently discard that AI's own
## already-in-flight race_complete: finish_order_of() would read -1 for it
## forever, even though it plainly crossed the line. _on_gate_body_entered()
## now keeps processing a non-player kart's own crossing while _finished is
## already true, IF AND ONLY IF that kart has not itself already been
## recorded (finish_order_of(body) < 0) -- see _process_ai_gate_crossing()
## and that branch's own doc.
##
## R5 Task 3 correction: an earlier revision of this doc claimed a frozen
## kart "can never PHYSICALLY reach a gate again on any LATER tick (frozen =
## zero displacement)", framing this branch as catching only a literal
## same-instant artifact. That is not what set_run_active(false) actually
## does -- see KartController._physics_process()/KartMotor.decelerate_to_
## stop()'s own docs: a kart moving at speed when frozen COASTS toward a
## stop at brake_mps2 over a real, bounded, MULTI-tick window, not an
## instant clamp to zero (pre-GO is the one case where this reads as zero
## displacement, and only because forward_speed_mps is already 0 there --
## see the class doc's COUNTDOWN + START BOOST section). A coasting AI kart
## sitting close enough to a gate when the player finishes could in
## principle still drift across it a few ticks later, not merely the exact
## same tick. This branch stays correct regardless: nothing in its own
## guard (_finished true, body != _kart, finish_order_of(body) < 0) is
## time-window-limited -- it records whichever such crossing arrives,
## however many ticks of coasting it took to get there -- so the ONLY thing
## wrong was this doc's own "same-tick only" framing of why, not the code's
## behavior. The player's own crossings stay unconditionally dropped once
## _finished either way -- no post-finish lap counting for the player,
## exactly as before this fix -- and _finish_race()'s own freeze is never
## retroactively undone or re-entered by this branch (it never calls
## _finish_race() again).
##
## finish_order_of()/finish_elapsed_s_of() are exposed now (not deferred to
## Task 3) because the RECORDING this task's own brief calls for has nowhere
## else to live -- Task 3's standings panel is documented to read these two
## getters directly rather than reaching into this session's private
## dictionaries, the same "public getter, not a private field" shape every
## other per-kart stat in this class already uses (standings()/lap_times()/
## etc.).
##
## GHOST WIRING (Task 6, CTR R7 -- stretch: time-trial ghost). Two lazily-
## created children -- _ghost_recorder (RefCounted, GhostRecorder) and
## _ghost_player (Node3D, GhostPlayer, added under this session the first
## time _ensure_ghost_player() needs one, the SAME lazy-container shape
## _ai_root/_hazards_root already establish) -- see each class's own doc
## for the RECORDING/PLAYBACK/FILE FORMAT details this session never
## touches directly.
##
## SOLO-ONLY, BY CONSTRUCTION. Neither ghost object has any "is this solo"
## flag of its own. configure() decides once: a solo session (spawn_
## opponents == false) calls _ghost_player.load_for_track(track_id, _race_
## tuning) (populating it only when a real ghost file exists for this
## track); an AI-populated session calls _ghost_player.clear() instead, and
## never calls _ghost_recorder.start() at GO at all (see _start_race()).
## GhostPlayer.start_replay() is itself a no-op with no keyframes loaded, so
## an AI race's own ghost player -- always cleared -- can never show
## anything, with no second flag needed anywhere in either ghost class.
##
## CLOCK REUSE. Both ghost objects are fed this session's own already-
## computed elapsed_s each tick (_ghost_recorder.sample()/_ghost_player.
## advance(), called from _physics_process right after _elapsed_s += delta_s
## above) -- see their own class docs' CLOCK sections for why this can never
## drift from the real race timer/HUD, and is pause-correct for free the
## same way everything else driven from that identical clock already is.
##
## YAW DERIVATION. Sampling reads the kart's own world-facing yaw from
## global_transform.basis, NOT the (possibly parent-relative) rotation.y
## property directly -- the same forward-vector-then-signed_angle_to idiom
## _seed_kart_transform() already uses for spawn placement, kept consistent
## here rather than assuming this session's own local space always equals
## world space.
##
## WRITE HOOK. save_ghost() is the ONE public entry point GameRoot ever
## calls (see game_root.gd's own _on_racing_finished() GHOST PERSISTENCE
## doc) -- called only when THAT tick's finish was a genuine new best TOTAL
## time, exactly the existing "is_solo && new_best_total" branch that
## already decides whether to write racing.<track_id> to the profile at
## all. This session resolves the real user://ghosts/<track_id>.ghost path
## itself (GhostPlayer.path_for_track(), the one place that string is
## spelled out) and never pushes louder than a warning on a failed write --
## a ghost is a disposable replay aid, never authoritative save data, so a
## failure here must never look like the RACE itself failed.

const RacingInputAdapterType := preload(
	"res://src/racing/input/racing_input_adapter.gd"
)
const LapValidatorType := preload("res://src/racing/track/lap_validator.gd")
const AiKartAgentType := preload("res://src/racing/ai/ai_kart_agent.gd")
const SpineFollowerType := preload("res://src/racing/track/spine_follower.gd")
const RaceRankingType := preload("res://src/racing/flow/race_ranking.gd")
const KartSceneType := preload("res://scenes/racing/kart.tscn")
# R4 Task 4: the two spawned/applied item effects that need a real scene
# instance (missile/beaker) -- turbo/shield are pure KartController calls,
# no scene needed. See dispatch_item_use()/register_hit().
const MissileSceneType := preload("res://scenes/racing/missile.tscn")
const BeakerSceneType := preload("res://scenes/racing/beaker.tscn")
# CTR R6 Task 5: the two new items that also need a real scene instance --
# triple_turbo (like turbo/shield) is a pure KartController call, no scene.
const BombSceneType := preload("res://scenes/racing/bomb.tscn")
const TntStickSceneType := preload("res://scenes/racing/tnt_stick.tscn")
# R5 Task 1: see the class doc's COUNTDOWN + START BOOST section.
const CountdownTimerType := preload("res://src/racing/flow/countdown_timer.gd")
const StartBoostJudgeType := preload(
	"res://src/racing/flow/start_boost_judge.gd"
)
# CTR R8 Task 2 (characters/select/classes): supersedes the two hardcoded
# character consts this block used to declare (CrashCharacterSceneType /
# LabAssistantCharacterSceneType, R6 Task 3) -- every kart's mount now
# resolves through DriverRegistry by driver id (the player's own _selected_
# driver_id, each AI slot's own roster id -- see configure()'s and _spawn_
# ai_karts()'s own doc) instead of two fixed scene references. See driver_
# registry.gd's own class doc for the six-driver roster table and its
# FALLBACK rule (an unfinished/missing face silently seats the lab
# assistant, never a crash or a loud error).
const DriverRegistryType := preload("res://src/racing/roster/driver_registry.gd")
# Task 6 (CTR R7, stretch: time-trial ghost): see the class doc's own GHOST
# WIRING section below for how these two are actually driven.
const GhostRecorderType := preload("res://src/racing/flow/ghost_recorder.gd")
const GhostPlayerType := preload("res://src/racing/flow/ghost_player.gd")

signal race_finished(total_s: float, lap_times: Array)
## Fix round (H1 review): RaceHUD's RETRY button used to call
## get_tree().change_scene_to_file() directly, which frees GameRoot (the
## actual scene tree root) out from under itself -- the fresh race scene
## that replaces it never gets configure() called by anyone, since the only
## thing that ever called configure() was GameRoot, and GameRoot is now
## gone. RaceHUD now only calls request_retry(), which emits this; GameRoot
## connects to it (see game_root.gd's _render_state() racing render
## branch, Task 4 CTR R7: keyed off _race_scenes_by_level_id, built from
## RacingTrackRegistryType.TRACKS) and re-drives the exact same
## _select_level() round-trip the platformer's own working Pause -> Retry
## path already uses (quit the level, re-enter it), which re-renders and
## re-configure()s a fresh race scene while GameRoot itself stays alive
## the whole time.
signal retry_requested

## Task 9 (CTR racing mode, R2): identifies which track this session's best
## times are saved under (SaveModel.racing_record()/improved_racing_record()
## are keyed by this, not by the debug level id GameRoot dispatches on --
## see RacingTrackRegistry's own class doc (src/racing/track/track_
## registry.gd) for why those two ids are kept separate). Set per scene:
## race_time_trial.tscn authors &"graybox_loop", race_sanity_shores.tscn
## authors &"sanity_shores", race_temple_twilight.tscn authors
## &"temple_twilight" (Task 4, CTR R7). Left
## empty ("") on any instance that never sets it (e.g. a bare test fixture),
## which GameRoot treats as "nothing to save" rather than guessing.
@export var track_id: StringName = &""

## Fix-wave MEDIUM-5: solo time trial restored (spec: "time trial ships as
## race-minus-AI"). true (the default -- every pre-existing race scene/test
## keeps its ordinary AI-populated shape unmodified) spawns AiTuning.
## opponent_count AI karts as always; false spawns NONE, regardless of what
## opponent_count itself is tuned to -- this flag, not opponent_count, owns
## "is this race solo" (opponent_count keeps validating strictly positive;
## see tuning_service.gd, unchanged by this fix). Two thin scene variants
## (race_time_trial_solo.tscn/race_sanity_shores_solo.tscn -- see game_root.
## gd's own wiring) instance the ordinary race scenes and override only
## this one exported value; the RACE scenes themselves (race_time_trial.
## tscn/race_sanity_shores.tscn) are untouched and keep spawning AI by
## default, same as every task before this one shipped them. HUD placement
## display needs no extra gating here -- placement_out_of() already reads
## _ai_karts.size() + 1 (see its own doc), which naturally collapses to 1
## when spawn_opponents leaves _ai_karts empty, and race_hud.gd's own
## "m > 1" gate already hides the panel for exactly that case (see its
## _on_race_finished doc, unchanged by this fix).
@export var spawn_opponents: bool = true

## R4 Task 3: see the class doc's ITEM RNG section. 0 (the default -- every
## pre-existing race scene/test) randomizes; a non-zero value pins an exact,
## reproducible item-roll sequence.
@export var item_rng_seed: int = 0

## CTR R8 Task 2 (characters/select/classes): which of DriverRegistry's six
## roster ids the PLAYER'S OWN kart mounts and composes -- see configure_
## selected_driver()'s own doc for the one way this ever changes. Defaults
## to &"crash" (existing R6/R7 behavior, unchanged for every scene/test that
## never calls the setter): the exact driver CrashCharacterSceneType used to
## hardcode. Not an @export -- the pick is programmatic/save-driven (Task
## 3's racing.selected_driver, Task 4's select screen), never hand-authored
## per scene the way track_id/spawn_opponents/item_rng_seed above are.
var _selected_driver_id: StringName = &"crash"

var _kart: CharacterBody3D
var _camera: KartCamera
var _track: Node3D
var _spine: TrackSpine
var _router: InputRouter
var _gamepad: Node
var _touch: TouchControls
var _hud: Control
var _gates: Array[CheckpointGate] = []
# R4 Task 3: see the class doc's ITEM BOX WIRING section.
var _item_boxes: Array[ItemBox] = []
var _item_rng := RandomNumberGenerator.new()

# Task 1 (CTR R7, discharges spec debt #2): see the class doc's PAD WIRING
# section.
var _boost_pads: Array[BoostPad] = []
var _jump_pads: Array[JumpPad] = []

var _kart_tuning: KartTuning
# CTR R8 Task 2 (characters/select/classes): the PLAYER kart's own composed
# tuning -- catalog.kart.composed_with(DriverRegistry.driver_class(_selected_
# driver_id)), recomputed in both configure() and refresh_tuning() (see each
# one's own doc). Every consumer that reasons about how fast/how sharply the
# PLAYER's own kart can actually move (KartController itself, KartCamera's
# speed-ratio read, this session's own _update_player_follower() distance
# clamp) reads THIS, never the shared _kart_tuning above directly -- a
# classed player kart's real top_speed_mps/accel_mps2/steer_rate_degrees_
# per_s can differ from the shared catalog value the moment _selected_driver_
# id resolves to a non-balanced class. Consumers that only ever touch a
# field composed_with() never multiplies (kart_tint_player, gravity_mps2,
# boost_duration_s) keep reading the shared _kart_tuning directly -- see each
# such call site's own comment for why that stays correct.
var _player_kart_tuning: KartTuning
var _race_tuning: RaceTuning
var _input_tuning: InputTuning
var _ai_tuning: AiTuning
var _item_tuning: ItemTuning
var _fx_tuning: FxTuning

var _input_adapter: RacingInputAdapterType = RacingInputAdapterType.new()
var _validator: LapValidatorType = LapValidatorType.new()

# Task 5 (CTR R3 integration): opponent_count AI karts (kart.tscn + a real
# AiKartAgent each), spawned on GridSlot1..N under Track at configure() --
# see _spawn_ai_karts(). _ai_root is a plain container Node3D created lazily
# so a re-configure() (defensive; the real retry path replaces this whole
# scene via GameRoot, see retry_requested's own doc) can cleanly clear and
# rebuild it rather than leaking stale kart/agent instances.
var _ai_root: Node3D
var _ai_karts: Array[CharacterBody3D] = []
var _ai_agents: Array[AiKartAgentType] = []

# R4 Task 4: lazily-created container for spawned missile/beaker instances
# (see _ensure_hazards_root()/_spawn_missile()/_spawn_beaker()) -- mirrors
# _ai_root's own lazy-container shape one section up. Every hazard already
# self-despawns (queue_free()) on hit or its own lifetime, so this container
# needs no per-tick bookkeeping of its own; it exists only so a re-
# configure()/retry never leaves a PREVIOUS race's still-flying hazards
# parented under a fresh one (see configure()'s own defensive clear).
var _hazards_root: Node3D

# Task 6 (CTR R7, stretch: time-trial ghost): see the class doc's own GHOST
# WIRING section. _ghost_recorder is a plain RefCounted, always present;
# _ghost_player is lazily created + add_child()ed by _ensure_ghost_player()
# the first time configure() needs one, the same lazy-container shape
# _ai_root/_hazards_root establish one section up.
var _ghost_recorder: GhostRecorderType = GhostRecorderType.new()
var _ghost_player: GhostPlayerType

# Cross-kart-progress "seam ruling" (Task 5 binding contract 2): the ONLY
# thing gate crossings do per body is advance THAT body's own LapValidator,
# looked up by identity -- never a raw index or slot assumption. Player and
# every AI kart share this one dictionary and one connected handler
# (_on_gate_body_entered), so a gate never needs to know how many karts
# exist or which one just crossed it beyond "which validator does this body
# own".
var _gate_validators: Dictionary = {}

# Task 5 binding contract 3: the player's own continuous SpineFollower total
# lives here (not on the player's Kart node, which has no such concept of
# its own) so finish placement can compare it against every AiKartAgent's
# already-exposed total_progress_m() -- both sides of every comparison are
# SpineFollower totals, never a raw seam-ambiguous spine offset. Updated
# every tick in _update_player_follower(); player_total_progress_m() is the
# getter Callable every AiKartAgent receives at configure() (band_gap_m's
# own "how far behind/ahead of the player" signal, see ai_kart_agent.gd).
var _player_follower: SpineFollowerType = SpineFollowerType.new()

var _configured: bool = false
var _finished: bool = false
var _hop_was_pressed: bool = false
var _item_was_pressed: bool = false
var _elapsed_s: float
var _final_elapsed_s: float
var _last_lap_boundary_s: float
var _lap_times: Array[float] = []
var _wrong_way_elapsed_s: float
var _wrong_way_flag: bool = false

# R5 Task 1: see the class doc's COUNTDOWN + START BOOST section.
var _countdown: CountdownTimerType = CountdownTimerType.new()
var _start_boost_judge: StartBoostJudgeType = StartBoostJudgeType.new()
var _race_started: bool = false
# Set only for a &"bog" verdict (always the player's own kart -- see the
# class doc, AI never bogs) -- the kart whose set_run_active(true) is
# deferred, and how many more real seconds until it fires. null/0.0 the rest
# of the time.
var _bog_kart: CharacterBody3D
var _bog_remaining_s: float

# R5 Task 2: see the class doc's LIVE RANKING/AI FINISH RECORDING sections.
var _ranking: RaceRankingType = RaceRankingType.new()
# kart (CharacterBody3D) -> 1-based finish order; kart -> elapsed_s() at the
# instant it finished. Both written only by _record_finish(), idempotent per
# kart (first &"race_complete" wins), shared by the player and every AI kart.
var _finish_order_index: Dictionary = {}
var _finish_elapsed_s: Dictionary = {}
var _next_finish_order: int = 1
# Cached result of the most recent _refresh_rank_snapshot() -- kart ids in
# live position order. Empty before the first snapshot; player_position()/
# field_size() both read this directly rather than recomputing it.
var _current_rank_order: Array = []


## CTR R8 Task 2 (characters/select/classes): the ONE way anything outside
## this class ever changes which roster driver the player's own kart mounts
## -- Task 4's select screen calls this (with the save-persisted racing.
## selected_driver id, once Task 3 lands it) BEFORE configure(), the same
## "set the field, THEN configure() reads it" ordering track_id/spawn_
## opponents/item_rng_seed already use via @export. Not itself an @export
## (see _selected_driver_id's own doc) but otherwise the same contract:
## configure() and refresh_tuning() are the only readers, both reading
## _selected_driver_id fresh (never caching a resolved DriverEntry/Driver
## Class/PackedScene of their own), so a pick set before configure() is
## honored from the very first mount. id is stored as-is, unvalidated --
## DriverRegistry.character_scene()/driver_class() already degrade an
## unknown id gracefully (fallback mesh / null class), so a second
## validation layer here would only duplicate that contract, not strengthen
## it (Task 3's own save-load validation is the real gate against a
## corrupt/unknown save value ever reaching this setter).
func configure_selected_driver(id: StringName) -> void:
	_selected_driver_id = id


func configure(catalog: GameplayTuning) -> void:
	# M1 fix-wave: without this, process_mode stays at the INHERIT default
	# and silently picks up GameRoot's own PROCESS_MODE_ALWAYS (see
	# game_root.gd's _ready()), so this session's _physics_process would
	# keep ticking straight through GameRoot pausing the whole tree -- see
	# elapsed_s()'s own class-doc TIMER section and level_session.gd's
	# identical precedent (set as the first line of ITS OWN configure()).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_kart_tuning = catalog.kart
	_race_tuning = catalog.race
	_input_tuning = catalog.input
	_ai_tuning = catalog.ai
	_item_tuning = catalog.items

	# Task 6 (CTR R7, stretch: time-trial ghost): see the class doc's GHOST
	# WIRING section. _ghost_recorder.configure() always runs (cheap, and
	# _start_race() below is the thing that actually gates recording to
	# solo sessions only); _ghost_player is populated ONLY for a solo
	# session with a real ghost file for this track, cleared otherwise --
	# that single branch is this session's entire "is this solo" contract
	# for the ghost feature, nothing further downstream needs its own copy
	# of that check.
	_ghost_recorder.configure(_race_tuning)
	# CTR R8 Task 3 (save v3->v4 + ghost v2): threads the player's own pick
	# into the recording this session is about to make -- called AFTER
	# configure() (which always resets _ghost_recorder's own driver id back
	# to its "crash" default, see GhostRecorder.configure()'s own doc) and
	# BEFORE _start_race()/start() so a solo run's ghost is saved under the
	# id it was actually raced with, not the default every recording used to
	# imply. _selected_driver_id is already set by now -- configure_
	# selected_driver() must be called before THIS configure(), see its own
	# doc. Recorded for forward use only this round -- see GhostPlayer's own
	# GHOST MODEL doc for why nothing mounts a character on the ghost yet.
	_ghost_recorder.set_driver_id(_selected_driver_id)
	var ghost_player := _ensure_ghost_player()
	ghost_player.configure_visual(catalog.phase)
	if spawn_opponents:
		ghost_player.clear()
	else:
		ghost_player.load_for_track(track_id, _race_tuning)

	# R4 Task 3: see the class doc's ITEM RNG section -- re-seeded fresh on
	# every configure() (including a re-configure/retry) so a fixed non-zero
	# item_rng_seed always reproduces the exact same pickup sequence from
	# race start.
	if item_rng_seed == 0:
		_item_rng.randomize()
	else:
		_item_rng.seed = item_rng_seed

	_kart = get_node("Kart") as CharacterBody3D
	_camera = get_node("CameraRig") as KartCamera
	_track = get_node("Track") as Node3D
	_spine = _track.get_node("Spine") as TrackSpine
	_router = get_node("Input/InputRouter") as InputRouter
	_gamepad = get_node("Input/GamepadInput")
	_touch = get_node("UI/TouchControls") as TouchControls
	_hud = get_node("UI/RaceHUD")
	_hud.get_node("SafeArea").call("configure", _input_tuning)

	_router.call("configure", _input_tuning)
	_router.call("set_racing_mode", true)
	_gamepad.call("configure", _router, _input_tuning)
	_touch.call("configure", _router, _input_tuning, true)
	_touch.call("set_racing_layout", true)
	_touch.call(
		"set_touch_exclusion_controls",
		[_hud.get_node("SafeArea/FinishPanel/Margin/Rows/Retry")]
	)

	# CTR R8 Task 2 (characters/select/classes): every kart -- player and AI
	# alike, see _spawn_ai_karts()'s own identical shape -- receives its own
	# catalog.kart.composed_with(its_driver_class) duplicate instead of the
	# shared _kart_tuning resource directly, so a driver's own class
	# multipliers (top_speed_mps/accel_mps2/steer_rate_degrees_per_s) never
	# leak across karts. The player's own composed instance is cached on
	# _player_kart_tuning (see that field's own doc) -- every OTHER consumer
	# below that cares how fast/how sharply the player's kart can actually
	# move (the camera's own configure() call, _update_player_follower()'s
	# distance clamp) reads that same instance, never recomposes its own.
	_player_kart_tuning = _kart_tuning.composed_with(
		DriverRegistryType.driver_class(_selected_driver_id)
	)
	_kart.call("configure", _player_kart_tuning, _item_tuning)
	# Task 1 (CTR R6, circuit polish): wires the player kart's own Fx child
	# (kart.tscn always carries one, see kart_fx.gd's own class doc) with a
	# reference back to this kart and the fresh catalog.fx -- same "pass the
	# section this Task added, catalog.fx" shape catalog.kart/catalog.items
	# already get one line above.
	_fx_tuning = catalog.fx
	_kart.get_node("Fx").call("configure", _kart, _fx_tuning)
	# CTR R8 Task 2 (characters/select/classes): the player kart seats
	# whichever roster driver _selected_driver_id names -- DriverRegistry.
	# character_scene() resolves the real likeness-gated model for a gated
	# driver (still Crash by default, unchanged from R6 Task 3's own
	# CrashCharacterSceneType) or silently falls back to the lab assistant
	# for an ungated one (see that method's own FALLBACK doc). See
	# KartController.mount_character()'s own doc for why this is safe to
	# call before add_child() (kart.tscn's SeatMount marker is an authored
	# scene child, resolved via get_node_or_null() the same NODE LOOKUP NOT
	# @onready way the Fx wiring above already relies on). apply_body_tint()
	# gives the player kart its own fixed identity colour -- every kart gets
	# a tint, there is no untinted kart (see kart_tuning.gd's own Visual-
	# category doc); tints are a SLOT/seat trait, not a driver trait, so this
	# keeps reading the shared _kart_tuning.kart_tint_player directly,
	# unaffected by which driver is mounted (composed_with() never touches
	# the Visual category -- see KartTuning.composed_with()'s own doc).
	_kart.call("mount_character", DriverRegistryType.character_scene(_selected_driver_id))
	# CTR R8 Task 5 (characters/select/classes): the player's own authored
	# seat fit -- DriverEntry.seat_scale/seat_offset (driver_entry.gd's own
	# doc) -- applied right after mount_character() the same "mount, then
	# adjust" two-call shape apply_body_tint() below already establishes.
	# entry() (DriverRegistry's own null-safe-for-CALLERS lookup, not
	# character_scene()/driver_class()'s own internally-null-safe shape --
	# see that method's own doc) returns null only for an id absent from
	# the roster; _selected_driver_id is always one of the six roster ids
	# by construction (configure_selected_driver()'s own doc, Task 3's save
	# v4 migration fails closed to Crash for a corrupt/unknown id), so this
	# is defensive, not a real path -- the 1.0/ZERO fallback matches every
	# driver's own authored neutral value today regardless.
	var selected_driver_entry := DriverRegistryType.entry(_selected_driver_id)
	_kart.call(
		"apply_seat_fit",
		selected_driver_entry.seat_scale if selected_driver_entry != null else 1.0,
		(
			selected_driver_entry.seat_offset
			if selected_driver_entry != null
			else Vector3.ZERO
		)
	)
	_kart.call("apply_body_tint", _kart_tuning.kart_tint_player)
	# R5 Task 1: KartController.configure() always ends by reactivating
	# itself (set_run_active(true), see its own doc) -- immediately undone
	# here so the player spawns frozen, same as every AI kart (see _spawn_
	# ai_karts()'s own identical call). See the class doc's COUNTDOWN + START
	# BOOST section for the whole pre-GO freeze this sets up.
	_kart.call("set_run_active", false)
	# Task 5: this same "place the transform, then seed yaw as an
	# independent step" logic (HIGH-1 fix-wave bug doc below) is now shared
	# with every AI kart's own grid-slot placement via _seed_kart_transform()
	# -- see _spawn_ai_karts(). KartSpawn itself is left exactly as every
	# earlier task authored and read it (see the grid-slot doc on
	# _spawn_ai_karts() for why it is not renamed to GridSlot0): the player
	# still spawns from this one authored marker, unchanged.
	var spawn := _track.get_node_or_null("KartSpawn") as Marker3D
	if spawn != null:
		# HIGH-1 fix-wave bug: KartMotor's own yaw always starts at 0.0 and
		# _physics_process's first tick unconditionally overwrites this
		# body's rotation.y from it (see kart_controller.gd), silently
		# discarding whatever facing the transform copy above just set --
		# on both authored tracks that snapped the kart to face -Z instead
		# of the spawn's actual -90 degree authored yaw, straight across
		# the road into scenery, and zero checkpoint gates could ever
		# validate from a real drive. Seeding the motor's yaw AFTER placing
		# the transform (never before -- see set_yaw_degrees's own doc)
		# keeps the two in agreement from the very first tick. Derived from
		# the spawn's actual world-space forward rather than trusting its
		# local rotation_degrees.y directly, so this stays correct even if
		# a future track's spawn marker sits under a rotated parent.
		_seed_kart_transform(_kart, spawn)

	# CTR R8 Task 2 (characters/select/classes): KartCamera reads top_speed_
	# mps off whatever KartTuning it is handed (its own speed-ratio zoom/FOV
	# read, see kart_camera.gd) -- must be the player's own COMPOSED tuning,
	# not the shared base, or a classed player kart's camera feel would
	# quietly desync from its real top speed the moment _selected_driver_id
	# resolves to a non-balanced class.
	_camera.call(
		"configure",
		_kart,
		_camera.get_node("Camera3D"),
		_race_tuning,
		_player_kart_tuning
	)
	_spine.call("configure", catalog.camera)

	_gates = _discover_gates()
	for gate: CheckpointGate in _gates:
		# Callable equality (Godot 4) compares object+method+bound-args, so
		# a per-gate bound handler reused for both the check and the
		# connect() call correctly guards a re-configure() against a
		# duplicate connection -- comparing against the UNBOUND method here
		# would never match what actually gets connected below and could
		# never catch a repeat.
		var handler := _on_gate_body_entered.bind(gate)
		if not gate.body_entered.is_connected(handler):
			gate.body_entered.connect(handler)

	_validator.configure(_gates.size(), int(_race_tuning.lap_count))
	_input_adapter.configure(_input_tuning)

	# R4 Task 3: see the class doc's ITEM BOX WIRING section. No per-box
	# bound handler is needed here (unlike the gate loop just above) -- the
	# routing handler below reads the ENTERING BODY's own item_slot(), never
	# which box fired, so a single unbound handler shared by every box is
	# both correct and sufficient; is_connected() against that same unbound
	# method is still what guards a re-configure() against a duplicate
	# connection.
	_item_boxes = _discover_item_boxes()
	for box: ItemBox in _item_boxes:
		# Task 1 fix round 1 (CTR R6, circuit polish reviewer [MEDIUM]): the
		# original wire only ever passed _item_tuning here -- fx_tuning is
		# ItemBox.configure()'s own OPTIONAL trailing param (defaults to
		# null, see item_box.gd's own doc), so every real box discovered by
		# a real RaceSession silently kept _fx_tuning == null forever and
		# never spun/bobbed, even though every unit test in test_item_box.gd
		# passed -- they inject fx_tuning directly rather than going through
		# this call site. _fx_tuning is already set a few lines above (the
		# player kart's own Fx wiring reads it first).
		box.call("configure", _item_tuning, _fx_tuning)
		if not box.body_entered.is_connected(_on_box_body_entered):
			box.body_entered.connect(_on_box_body_entered)

	# Task 1 (CTR R7, discharges spec debt #2): see the class doc's PAD
	# WIRING section. A PER-PAD bound handler is required here (unlike the
	# item-box loop just above) -- see that section's own doc for why.
	_boost_pads = _discover_boost_pads()
	for boost_pad: BoostPad in _boost_pads:
		boost_pad.call("configure", _race_tuning)
		var boost_handler := _on_boost_pad_body_entered.bind(boost_pad)
		if not boost_pad.body_entered.is_connected(boost_handler):
			boost_pad.body_entered.connect(boost_handler)

	_jump_pads = _discover_jump_pads()
	for jump_pad: JumpPad in _jump_pads:
		jump_pad.call("configure", _race_tuning)
		var jump_handler := _on_jump_pad_body_entered.bind(jump_pad)
		if not jump_pad.body_entered.is_connected(jump_handler):
			jump_pad.body_entered.connect(jump_handler)

	# Task 5: player's own SpineFollower (binding contract 3) and the
	# body->validator routing table (binding contract 2's "gates route by
	# body identity") must both be ready before _spawn_ai_karts() below --
	# each AI kart's own AiKartAgent.configure() call reads
	# player_total_progress_m() indirectly is not required yet (its very
	# first read happens on the next physics tick), but gate routing must
	# already know about the player by the time any kart -- including one
	# spawned this same call -- could conceivably cross a gate.
	_gate_validators.clear()
	_gate_validators[_kart] = _validator
	_player_follower.configure(_spine.length_m())
	_player_follower.reset(_spine.progress_for_position(_kart.global_position))

	_spawn_ai_karts()

	# R4 Task 4: a defensive re-configure/retry clear, the same shape
	# _spawn_ai_karts() already uses for _ai_root's own children -- a
	# re-configure() on the SAME session instance must never leave a
	# PREVIOUS race's still-flying missile/beaker instances parented under
	# this fresh one. Every hazard already self-despawns on hit or its own
	# lifetime in the normal case, so this only matters for the defensive
	# reuse path, not ordinary play.
	if _hazards_root != null:
		for hazard: Node in _hazards_root.get_children():
			hazard.queue_free()

	_finished = false
	_hop_was_pressed = false
	_elapsed_s = 0.0
	_final_elapsed_s = 0.0
	_last_lap_boundary_s = 0.0
	_lap_times.clear()
	_wrong_way_elapsed_s = 0.0
	_wrong_way_flag = false

	# R5 Task 2: see the class doc's LIVE RANKING/AI FINISH RECORDING
	# sections. A re-configure()/retry must forget every previous race's
	# finish order and live ranking too, the same "restart the whole flow"
	# contract this reset block already establishes for everything above.
	_finish_order_index.clear()
	_finish_elapsed_s.clear()
	_next_finish_order = 1
	_current_rank_order.clear()

	# R5 Task 1: see the class doc's COUNTDOWN + START BOOST section. A
	# re-configure()/retry must restart the WHOLE flow, not resume whatever
	# countdown/bog state a previous call left behind -- every kart was just
	# frozen fresh above (player) and in _spawn_ai_karts() (AI), so this
	# reset must land before _configured flips true and _physics_process
	# starts driving _tick_countdown() again.
	_race_started = false
	_bog_kart = null
	_bog_remaining_s = 0.0
	_countdown.configure(_race_tuning)
	_start_boost_judge.configure(_race_tuning)

	_configured = true
	# R5 Task 2: seeds a real snapshot (every kart unfinished, at its spawn
	# progress) immediately, so field_size()/player_position() read something
	# real from the very first poll rather than the empty-cache 0 default --
	# see those getters' own docs.
	_refresh_rank_snapshot()

	_hud.call("configure", self)


func current_lap() -> int:
	return _validator.current_lap() if _configured else 1


func lap_count() -> int:
	return int(_race_tuning.lap_count) if _race_tuning != null else 1


func gate_count() -> int:
	return _gates.size()


## How many ItemBox instances were discovered under Track at configure()
## time -- exposed mainly so a test can prove the discovered count actually
## matches what a track authored (6 on both current real tracks, authored in
## R4 Task 5 -- see the class doc's ITEM BOX WIRING section) rather than only
## inferring it from the absence of a crash.
func item_box_count() -> int:
	return _item_boxes.size()


## How many BoostPad/JumpPad instances were discovered under Track at
## configure() time -- exposed the same "prove discovery, not just absence
## of a crash" reason item_box_count() is (see its own doc immediately
## above). Both real tracks currently author zero (Task 3/4 add some) --
## these simply read 0 on either until then, the same pad-less degrade the
## class doc's own PAD WIRING section documents.
func boost_pad_count() -> int:
	return _boost_pads.size()


func jump_pad_count() -> int:
	return _jump_pads.size()


## Gates validated toward the lap currently in progress -- a thin
## pass-through onto LapValidator.progress_gates(), exposed mainly so an
## out-of-order crossing's rejection is externally observable (it leaves
## this unchanged) without reaching past this session into the private
## validator it owns.
func progress_gates() -> int:
	return _validator.progress_gates() if _configured else 0


func elapsed_s() -> float:
	if _finished:
		return _final_elapsed_s
	if not _configured:
		return 0.0
	return _elapsed_s


func lap_times() -> Array[float]:
	return _lap_times.duplicate()


func is_wrong_way() -> bool:
	return _wrong_way_flag


func is_finished() -> bool:
	return _finished


## Binding contract 3's own SpineFollower total for the PLAYER -- the exact
## Callable every AiKartAgent receives as player_progress_getter at
## configure() (see _spawn_ai_karts()), and the "player's" side of every
## finish-placement comparison in _finish_race(). 0.0 before configure(),
## matching SpineFollower's own fail-closed shape one layer down.
func player_total_progress_m() -> float:
	return _player_follower.total_progress_m() if _configured else 0.0


## R4 Task 6 (RaceHUD held-item display): a thin public wrapper on
## _items_allowed() (see the class doc's SOLO TIME TRIAL DOES NOT ROLL
## section) -- RaceHUD's own duck-typed session.call() polling (the same
## shape it already uses for current_lap()/elapsed_s()/is_wrong_way()) reads
## this to gate its held-item label the exact same way _on_box_body_entered()
## already gates rolls, without reaching past this session into a private
## method it does not own.
func items_enabled() -> bool:
	return _items_allowed()


## The player's own real ItemSlot -- RaceHUD polls this every _refresh() the
## same "poll the session every frame" way it already polls current_lap()/
## elapsed_s(), to drive the held-item label and roulette flicker (see
## item_slot.gd's own rolling_display_item()/held_item() docs). null before
## configure() (mirrors player_total_progress_m()'s own "not ready yet"
## contract one section up) rather than reaching into a not-yet-real kart.
func player_item_slot() -> Object:
	return _kart.call("item_slot") if _configured and _kart != null else null


## "m" in RaceHUD's "FINISHED n / m" -- the actual number of AI karts that
## raced plus the player, NOT a blind read of AiTuning.opponent_count: if a
## track is ever missing a GridSlot marker for a configured slot (see
## _spawn_ai_karts()'s own fail-closed skip), fewer AI karts actually spawn
## than the tuning asked for, and this must reflect the race that actually
## ran, not the one that was configured.
func placement_out_of() -> int:
	return _ai_karts.size() + 1


## R5 Task 2: any kart's own LIVE 1-based race position -- see the class
## doc's LIVE RANKING section for how _current_rank_order is built. Distinct
## from standings() below (Task 3 territory): standings() is the full
## results list, re-derived on demand for the one-shot "FINISHED n / m"
## panel at the player's own finish; this is a per-tick READ that keeps
## updating for the whole post-GO/pre-finish body of the race. 0 before the
## first snapshot exists (mirrors this class's other "not ready yet"
## getters) or if the given kart has somehow gone missing from its own
## snapshot -- never a stale index. player_position() below is simply
## kart_position(_kart); kept as its own named getter since RaceHUD's own
## poll surface (and this class's other per-kart getters, e.g. lap_times())
## always addresses the player's own kart by a dedicated name, never a
## passed-in reference.
func kart_position(kart: CharacterBody3D) -> int:
	var index := _current_rank_order.find(kart)
	return index + 1 if index >= 0 else 0


## RaceHUD's own live "POS n / m" line reads this for the player's own
## position -- see kart_position()'s own doc one section up.
func player_position() -> int:
	return kart_position(_kart)


## "m" for RaceHUD's own live "POS n / m" -- the current live snapshot's own
## size. Always equal to placement_out_of() in practice (both ultimately
## count the same real roster: the player plus every spawned AI kart), but
## reads off the SAME cache player_position() does rather than re-deriving
## it from _ai_karts.size(), so the two live getters can never disagree with
## each other even if a future change ever made them diverge.
func field_size() -> int:
	return _current_rank_order.size()


## R5 Task 2: this kart's own 1-based finish order (1 = first to cross the
## line), or -1 if it has not finished yet -- see _record_finish()'s own doc.
## Works identically for the player's own kart and any AI kart; Task 3's own
## standings panel is the intended other reader, alongside finish_elapsed_s_
## of() below.
func finish_order_of(kart: CharacterBody3D) -> int:
	return int(_finish_order_index.get(kart, -1))


## This kart's own elapsed_s() reading at the exact instant it crossed the
## finish line -- 0.0 if it has not finished yet (mirrors this class's other
## "not yet" getters, e.g. kart_position()'s own 0-before-first-snapshot
## contract).
func finish_elapsed_s_of(kart: CharacterBody3D) -> float:
	return float(_finish_elapsed_s.get(kart, 0.0))


## R5 Task 3: full results standings -- RaceHUD's own finish panel reads
## this for a race (see race_hud.gd's own STANDINGS section) instead of the
## old single "FINISHED n / m" placement()/placement_out_of() pair, which
## stays exactly as it was for solo's own unmodified panel. placement()
## itself was removed in the R5 polish wave (its naive raw-progress
## comparison could disagree with this method's own correct finished-before-
## unfinished ranking -- see _player_standings_position()'s doc in tests/
## racing/test_race_session.gd for the exact scenario that proved it wrong);
## placement_out_of() alone survives as the still-live "is this a race"
## gate. One Dictionary per kart currently in
## the race, ORDERED 1..field_size():
## - position: int, 1-based standings position.
## - label: String, "YOU" for the player's own kart, "CPU n" (1-based BY
##   SLOT -- ai_kart(0) is always "CPU 1" no matter where it currently
##   ranks, see _standings_label()'s own doc) for every AI kart.
## - finished: bool, whether finish_order_of(kart) >= 0.
## - elapsed_s: float, finish_elapsed_s_of(kart) for a finished kart, 0.0 for
##   an unfinished one (mirrors this class's other "0 before it happened"
##   getters -- callers must gate display on `finished`, same as every other
##   finish-only stat in this class).
## - is_player: bool, true for exactly one entry -- the HUD's own "highlight
##   this row" flag, read straight off rather than re-deriving it from the
##   label string.
##
## ORDERING calls _refresh_rank_snapshot() again right here rather than
## trusting whatever _current_rank_order was left at by the last per-tick
## call (see that method's own LIVE RANKING class-doc section) -- every
## kart's own driving numbers have already stopped changing meaningfully
## once frozen (_finish_race() freezes player and every AI kart alike), so
## this is a safe no-op re-derivation in the ordinary case, but a kart that
## was still coasting (see the class doc's own R5 Task 3 correction on
## SAME-TICK PHOTO FINISH above -- freezing is not an instant clamp to zero)
## can cross one more gate and get its own finish_order_of() recorded a few
## ticks AFTER the last per-tick refresh ran; re-deriving here picks that up
## rather than serving a stale pre-finish snapshot. Empty before configure()
## (mirrors this class's other "not ready yet" getters).
func standings() -> Array:
	if not _configured:
		return []
	_refresh_rank_snapshot()
	var result: Array = []
	var position := 1
	for kart: CharacterBody3D in _current_rank_order:
		result.append({
			"position": position,
			"label": _standings_label(kart),
			"finished": finish_order_of(kart) >= 0,
			"elapsed_s": finish_elapsed_s_of(kart),
			"is_player": kart == _kart,
		})
		position += 1
	return result


## See standings()'s own doc -- a kart's own label is derived from its SLOT
## (its fixed index in _ai_karts, the same "GridSlot1..N in order" identity
## _spawn_ai_karts() assigns once at configure() time), never from its
## current live/finish position, so a label never changes as a kart's own
## standing moves during the race. "CPU" (no number) for a kart this session
## does not recognize at all -- defensive only, every real caller only ever
## passes _kart or a kart drawn from _ai_karts itself.
func _standings_label(kart: CharacterBody3D) -> String:
	if kart == _kart:
		return "YOU"
	var slot_index := _ai_karts.find(kart)
	return "CPU %d" % (slot_index + 1) if slot_index >= 0 else "CPU"


func ai_kart_count() -> int:
	return _ai_karts.size()


func ai_kart(index: int) -> CharacterBody3D:
	return _ai_karts[index] if index >= 0 and index < _ai_karts.size() else null


## Exposed mainly for tests that need to reach past this session into a
## specific AiKartAgent (e.g. to seed its private SpineFollower directly for
## a deterministic placement scenario) without having to rediscover it by
## scene-tree path.
func ai_agent(index: int) -> Node:
	return _ai_agents[index] if index >= 0 and index < _ai_agents.size() else null


func ai_kart_total_progress_m(index: int) -> float:
	var agent := ai_agent(index)
	return float(agent.call("total_progress_m")) if agent != null else 0.0


## Gates validated toward the AI kart's own current lap -- the AI-kart
## counterpart to progress_gates(), reading that kart's own LapValidator out
## of _gate_validators rather than the player's _validator field.
func ai_kart_progress_gates(index: int) -> int:
	var kart := ai_kart(index)
	if kart == null:
		return 0
	var validator: LapValidatorType = _gate_validators.get(kart)
	return validator.progress_gates() if validator != null else 0


## The one thing RaceHUD's RETRY button does now -- see retry_requested's
## doc above for why it no longer reloads the scene itself.
func request_retry() -> void:
	retry_requested.emit()


## Task 9 (CTR racing mode, R2): GameRoot is the only thing that ever
## touches SaveService/SaveModel (see game_root.gd's _on_racing_finished
## doc) -- this session never reads or writes the profile itself. Once
## GameRoot has compared this race's result against the saved best and
## decided whether to persist it, it calls this to hand the outcome down to
## the HUD, the same "session forwards to _hud" shape configure() already
## uses one line below its own _hud.call("configure", self).
func present_best_times(payload: Dictionary) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.call("present_best_times", payload)


## Task 6 (CTR R7, stretch: time-trial ghost): the ONE public entry point
## GameRoot ever calls for the ghost feature -- see the class doc's own
## WRITE HOOK section and game_root.gd's _on_racing_finished() GHOST
## PERSISTENCE doc for exactly when (only a genuine new best TOTAL time on
## a solo session -- the same condition that already gates the profile's
## own racing.<track_id> write). A no-op whenever _ghost_recorder recorded
## nothing at all (an AI race never starts it -- see _start_race() -- so
## this is also this method's own solo-only guard, no separate flag
## needed) -- never pushes louder than a warning on a failed write, since a
## missing/stale ghost must never look like the race itself failed.
func save_ghost() -> void:
	if not _ghost_recorder.has_keyframes():
		return
	var write_error := _ghost_recorder.save_to_file(
		GhostPlayerType.path_for_track(track_id)
	)
	if write_error != OK:
		push_warning(
			"Ghost file was not saved for %s: %s"
			% [track_id, error_string(write_error)]
		)


## Live tuning refresh (M2 fix-wave): the racing counterpart to
## LevelSession.refresh_tuning() / phase0_game.gd's refresh_tuning() -- see
## game_root.gd's _refresh_active_level_tuning(), which now has a racing
## branch calling this. Deliberately narrow, matching the platformer's own
## split between "values every live tick already reads fresh off a stored
## tuning reference" (just reassign it here) and "state a stateful sub-
## system captured once at configure() time" (leave it alone): re-running
## LapValidator.configure() here would reset _expected_gate/_laps_completed/
## _started and silently corrupt a gate sequence already in progress mid-
## race, so the validator, gate discovery, and input routing are untouched
## -- only the kart's motor+drift tuning, the camera's tuning, and this
## session's own stored tuning references (which lap_count(), the wrong-way
## grace check, etc. already read fresh off every call/tick) refresh live.
func refresh_tuning(catalog: GameplayTuning) -> void:
	if not _configured:
		return
	_kart_tuning = catalog.kart
	_race_tuning = catalog.race
	_input_tuning = catalog.input
	_item_tuning = catalog.items
	_fx_tuning = catalog.fx
	# CTR R8 Task 2 (characters/select/classes): recomputed unconditionally
	# (mirrors _kart_tuning's own unconditional reassign a few lines up),
	# not only inside the `if _kart != null` branch below -- the camera
	# refresh a few lines further down also needs the player's own fresh
	# composed instance, and both must read the SAME recompose rather than
	# each calling composed_with() a second time on their own.
	_player_kart_tuning = _kart_tuning.composed_with(
		DriverRegistryType.driver_class(_selected_driver_id)
	)
	if _kart != null and is_instance_valid(_kart):
		# See _player_kart_tuning's own field doc -- a live tuning edit must
		# reach a classed kart RECOMPOSED, not as the raw, just-reloaded
		# catalog.kart reference.
		_kart.call("refresh_tuning", _player_kart_tuning, _item_tuning)
		_kart.get_node("Fx").call("refresh_tuning", _fx_tuning)
		# Task 3 (CTR R6, circuit polish): kart_tint_player lives on the
		# shared _kart_tuning, unaffected by driver class (composed_with()
		# never touches the Visual category) -- re-applying the tint here
		# too keeps it live for the same reason the box loop below re-
		# applies fx_tuning, matching this method's own established
		# "provably live" contract. AI karts are deliberately NOT touched
		# here -- this method has never refreshed _ai_karts at all (only
		# _kart/_camera/_item_boxes), a pre-existing scope this task does
		# not change; see the class doc's own tuning-refresh precedent.
		_kart.call("apply_body_tint", _kart_tuning.kart_tint_player)
	if _camera != null and is_instance_valid(_camera):
		# See the identical camera-configure() comment above for why this
		# must be the player's own composed instance, not the shared base.
		_camera.call("refresh_tuning", _race_tuning, _player_kart_tuning)
	# Task 1 fix round 1 (CTR R6, circuit polish reviewer [MEDIUM]): every
	# discovered box needs a live fx (and item) tuning refresh too, the same
	# "the tuning loop must be provably live" contract every other consumer
	# above already honors -- ItemBox has no separate refresh_tuning() of its
	# own, so this reuses configure() itself (proven idempotent, see item_
	# box.gd's own configure() doc: it never touches _active/_respawning/
	# _spin_bob_elapsed_s, only _tuning/_fx_tuning and the pickup shape),
	# rather than inventing a near-duplicate method for a live-refresh case
	# that is otherwise identical to the initial wire.
	for box: ItemBox in _item_boxes:
		if is_instance_valid(box):
			box.call("configure", _item_tuning, _fx_tuning)
	# Task 1 (CTR R7, discharges spec debt #2): same "provably live" reason
	# as the box loop immediately above -- pad_boost_s/pad_refire_cooldown_s/
	# jump_pad_velocity_scale live on _race_tuning, just reassigned a few
	# lines up, so every discovered pad's own cached _tuning reference must
	# be refreshed too or it keeps reading the PRE-refresh RaceTuning
	# forever. BoostPad/JumpPad.configure() is likewise idempotent (it only
	# ever touches _tuning, never _elapsed_s or the cooldown Dictionary --
	# see either script's own configure() doc), so re-running it here mid-
	# race never resets an in-flight cooldown.
	for boost_pad: BoostPad in _boost_pads:
		if is_instance_valid(boost_pad):
			boost_pad.call("configure", _race_tuning)
	for jump_pad: JumpPad in _jump_pads:
		if is_instance_valid(jump_pad):
			jump_pad.call("configure", _race_tuning)


## R4 Task 4 (item 1, hit-routing foundation): the ONE place any hit source
## (missile.gd/beaker.gd's own _physics_process, and any future hazard)
## turns "this kart got hit" into the real outcome, in priority order:
## invulnerability, then shield block, then an actual spin_out. No caller
## re-implements this priority itself -- see missile.gd's/beaker.gd's own
## _check_hits(), which both just forward whichever kart they reached
## straight here via .call("register_hit", kart).
##
## &"invulnerable" -- the kart is still inside its post-hit invulnerable_
## after_hit_s window (see kart_motor.gd's own doc); apply_spin_out() is
## NOT called again -- a kart already reeling from one hit does not get
## re-stunned by a second projectile arriving during its own grace window.
## Checked FIRST, ahead of the shield (fix round 1 [MEDIUM], reviewer): a
## kart that picks up and uses a shield WHILE still invulnerable from an
## earlier hit must not lose that shield to a hit invulnerability alone
## would already have absorbed for free -- invulnerability is a strictly
## better outcome for the kart than a block (nothing is consumed either
## way), so it must win the precedence check, leaving the shield untouched
## for whenever invulnerability actually runs out. Pinned by test_race_
## session.gd's own test_register_hit_precedence_invulnerable_beats_an_
## active_shield.
## &"blocked" -- not invulnerable, but shielded; the shield is consumed
## EARLY right here (KartController.consume_shield()), not left to run out
## its own remaining duration -- CTR's "blocks exactly one hit, then it's
## gone".
## &"spin_out" -- neither of the above; the hit lands for real via the
## Task-1-fixed apply_spin_out() (see kart_controller.gd's own R4-BINDING
## FIX doc), which also starts the kart's own invulnerable_after_hit_s
## window as a side effect.
##
## ORDER-AWARENESS (ledger note, per this task's own brief): this is called
## from a projectile/hazard's own _physics_process, i.e. potentially the
## SAME physics tick KartController._physics_process already ran and
## unconditionally forwarded a same-frame slide-boost tap into KartMotor
## (see kart_controller.gd's own BINDING CONTRACT doc). apply_spin_out()
## below does NOT touch KartMotor's own _boost_time_remaining_s (see
## kart_motor.gd's apply_spin_out() -- it only dumps forward speed once by
## spin_out_speed_keep_ratio and starts the spin_out/invulnerable timers),
## so a boost that already landed in the motor THIS SAME TICK survives a
## hit landing the same tick. This is INTENTIONAL, a strict-CTR ruling (a
## boost that already fired is already committed -- a real CTR kart
## mid-boost that gets hit keeps its boost speed through the spin), not an
## ordering bug to "fix" by also zeroing boost here -- pinned by
## test_race_session.gd's own test_register_hit_does_not_cancel_a_same_
## frame_boost_already_forwarded_to_the_motor.
func register_hit(target_kart: CharacterBody3D) -> StringName:
	if bool(target_kart.call("is_invulnerable")):
		return &"invulnerable"
	if bool(target_kart.call("is_shielded")):
		target_kart.call("consume_shield")
		return &"blocked"
	target_kart.call("apply_spin_out")
	return &"spin_out"


## R4 Task 4 (item 5): the shared item-use dispatch surface. The player's
## ITEM press below (_route_input()) already calls KartController.use_item()
## itself via RacingInputAdapter.apply_item_pressed() (which returns the
## used item's name) and hands the result straight to dispatch_item_use();
## Task 5's AI item-use decision is documented to call kart.use_item()
## itself the SAME way and route its own result through THIS method, so
## neither caller re-implements its own missile/beaker/turbo/shield switch.
## Exposed as a convenience for any future caller that wants "call use_item
## AND dispatch" as one step (Task 5's AiKartAgent is the intended other
## caller once its own decision lands).
func use_item_for(kart: CharacterBody3D) -> StringName:
	var item_name: StringName = kart.call("use_item")
	dispatch_item_use(kart, item_name)
	return item_name


## &"none" (nothing was held, or use_item() was called on an empty/rolling
## slot -- see item_slot.gd's own use() doc) is a harmless no-op match.
##
## CTR R6 Task 5: &"bomb"/&"tnt_stick" spawn a real scene instance, the same
## shape &"missile"/&"beaker" already use. &"triple_turbo" falls in WITH
## &"turbo" -- dispatch_item_use() is called once PER use() (see item_slot.
## gd's own CHARGES doc: use() itself already handles the "which charge is
## this" bookkeeping and always hands back &"triple_turbo" until the last
## one), so this match only ever needs to apply ONE turbo_boost_s per call,
## identically for both names; there is no separate "apply three boosts at
## once" case anywhere in this file.
func dispatch_item_use(kart: CharacterBody3D, item_name: StringName) -> void:
	match item_name:
		&"missile":
			_spawn_missile(kart)
		&"beaker":
			_spawn_beaker(kart)
		&"turbo", &"triple_turbo":
			kart.call("apply_boost", _item_tuning.turbo_boost_s)
		&"shield":
			kart.call("set_shielded", _item_tuning.shield_duration_s)
		&"bomb":
			_spawn_bomb(kart)
		&"tnt_stick":
			_spawn_tnt_stick(kart)


func _ensure_hazards_root() -> Node3D:
	if _hazards_root == null:
		_hazards_root = Node3D.new()
		_hazards_root.name = "ItemHazards"
		add_child(_hazards_root)
	return _hazards_root


## Task 6 (CTR R7, stretch: time-trial ghost): see the class doc's GHOST
## WIRING section. Mirrors _ensure_hazards_root()'s own lazy-create-once
## shape -- this session is always already inside the live tree by the time
## configure() runs (GameRoot add_child()s a fresh race scene BEFORE
## calling configure(), see game_root.gd's own doc), so add_child() here
## fires GhostPlayer's own _ready() synchronously, before configure() can
## reach any further call on it.
func _ensure_ghost_player() -> GhostPlayerType:
	if _ghost_player == null:
		_ghost_player = GhostPlayerType.new()
		add_child(_ghost_player)
	return _ghost_player


## Spawns at the launcher's own position/facing (no offset -- see missile.
## gd's own class doc: this node has no opinion on where it starts, it just
## configures the just-instantiated missile with everything it needs to
## lock its own launch-time target and run its own hit-testing from here
## on).
func _spawn_missile(launcher: CharacterBody3D) -> void:
	var missile := MissileSceneType.instantiate()
	_ensure_hazards_root().add_child(missile)
	missile.global_transform = launcher.global_transform
	missile.call(
		"configure", self, launcher, _item_tuning, Callable(self, "_item_targets")
	)


## Dropped at the launcher's own position minus its own forward vector
## times one kart length -- see beaker.gd's own class doc SPAWN POSITION
## section and _read_kart_length_m()'s own doc for the collision-extents
## derivation.
func _spawn_beaker(launcher: CharacterBody3D) -> void:
	var beaker := BeakerSceneType.instantiate()
	_ensure_hazards_root().add_child(beaker)
	var launcher_forward := -launcher.global_transform.basis.z
	var drop_point := (
		launcher.global_position - launcher_forward * _read_kart_length_m(launcher)
	)
	beaker.global_transform = Transform3D(launcher.global_transform.basis, drop_point)
	beaker.call(
		"configure", self, launcher, _item_tuning, Callable(self, "_item_targets")
	)


## Spawns at the launcher's own position/facing -- no offset, the same
## choice missile.gd's own SPAWN section already makes and bomb.gd's own
## class doc mirrors: a lobbed arc clears the launch point within a
## fraction of a second regardless of where exactly it started. kart_tuning
## is threaded through as bomb.gd's one extra configure() parameter (gravity
## for the real ballistic arc -- see that file's own LAUNCH GEOMETRY doc).
## CTR R8 Task 2 audit: gravity_mps2 is not one of the three fields composed_
## with() ever multiplies, so it is IDENTICAL on every kart's own composed
## tuning and on the shared _kart_tuning below -- reading the shared
## reference here (rather than looking up which kart's own composed
## instance the launcher owns) is exactly as correct and avoids a lookup
## this call has no other reason to make.
func _spawn_bomb(launcher: CharacterBody3D) -> void:
	var bomb := BombSceneType.instantiate()
	_ensure_hazards_root().add_child(bomb)
	bomb.global_transform = launcher.global_transform
	bomb.call(
		"configure", self, launcher, _item_tuning, _kart_tuning, Callable(self, "_item_targets")
	)


## Dropped the same way _spawn_beaker() drops a beaker (one kart length
## behind the launcher's own facing) -- "dropped like the beaker" per the
## task brief, see tnt_stick.gd's own class doc for why its grounded phase
## reuses beaker_arm_delay_s/beaker_hit_radius_m/beaker_lifetime_s directly.
func _spawn_tnt_stick(launcher: CharacterBody3D) -> void:
	var stick := TntStickSceneType.instantiate()
	_ensure_hazards_root().add_child(stick)
	var launcher_forward := -launcher.global_transform.basis.z
	var drop_point := (
		launcher.global_position - launcher_forward * _read_kart_length_m(launcher)
	)
	stick.global_transform = Transform3D(launcher.global_transform.basis, drop_point)
	stick.call(
		"configure", self, launcher, _item_tuning, Callable(self, "_item_targets")
	)


## The targets_getter Callable handed to every spawned missile/beaker (see
## _spawn_missile()/_spawn_beaker()) -- every kart currently in the race
## (player + AI) paired with its own current SpineFollower total_progress_m(),
## the exact seam-safe shape (see spine_follower.gd's own class doc) missile.
## gd's configure() uses to lock its launch-time target, and beaker.gd's own
## configure() reads purely for kart identities. Mirrors _other_kart_
## positions()'s own "this session already knows every kart in the race"
## rationale one section up.
##
## R4 Task 5: also handed to every AiKartAgent (see _spawn_ai_karts()) as
## item_targets_getter, the SAME unbound Callable every missile/beaker
## already uses -- an AI's own target_gap_ahead_m re-scans this fresh every
## tick rather than locking it once at launch (see ai_kart_agent.gd's own
## ITEM WIRING doc).
func _item_targets() -> Array:
	var result: Array = []
	if _kart != null and is_instance_valid(_kart):
		result.append({"kart": _kart, "progress": player_total_progress_m()})
	for index in range(_ai_karts.size()):
		var ai_kart := _ai_karts[index]
		if ai_kart != null and is_instance_valid(ai_kart):
			result.append({"kart": ai_kart, "progress": ai_kart_total_progress_m(index)})
	return result


## Kart-length derivation mirrors ai_kart_agent.gd's own _read_kart_extents()
## (same BoxShape3D.size.z reading, see that file's own RESPAWN-ONTO-PLAYER
## AVOIDANCE doc) -- see the task brief's own "derive from kart collision
## extents like the respawn stepper did". 0.0 (a harmless zero offset -- the
## beaker drops exactly at the launcher's own position rather than crashing)
## for a kart with no readable CollisionShape3D, e.g. a bare test fixture.
func _read_kart_length_m(kart: CharacterBody3D) -> float:
	var collision := kart.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		return 0.0
	var box := collision.shape as BoxShape3D
	if box == null:
		return 0.0
	return box.size.z


func _physics_process(delta_s: float) -> void:
	if not _configured or _finished:
		return
	# R5 Task 1: pre-GO, this is the ENTIRE tick -- see the class doc's
	# COUNTDOWN + START BOOST section for why that alone is what makes every
	# kart provably frozen, the wrong-way flag provably quiescent, and the
	# race timer provably not-yet-started, all by construction rather than
	# by a separate guard on each.
	if not _race_started:
		_tick_countdown(delta_s)
		return
	# A &"bog" verdict left the player's own kart still frozen at GO --
	# count its penalty down here, every real tick (pause-correct for free,
	# same as elapsed_s() below), and unfreeze it exactly once when it
	# expires. See the class doc's own &"bog" paragraph.
	if _bog_kart != null:
		_bog_remaining_s -= delta_s
		if _bog_remaining_s <= 0.0:
			_bog_kart.call("set_run_active", true)
			_bog_kart = null
	# This tick simply never runs while the tree is paused (process_mode =
	# PAUSABLE, set in configure()), so summing delta_s here naturally
	# excludes paused time -- see elapsed_s()'s own class-doc TIMER section.
	_elapsed_s += delta_s
	_route_input()
	# Task 6 (CTR R7, stretch: time-trial ghost) -- see the class doc's
	# GHOST WIRING/CLOCK REUSE section. Both calls are no-ops unless this
	# is genuinely a solo session with recording/replay actually active;
	# is_recording() is what makes the sample() call itself the ONLY place
	# "is this session solo" is re-checked per tick (start() is only ever
	# reached from _start_race() when not spawn_opponents, see its own
	# doc), so this line needs no spawn_opponents check of its own.
	if _ghost_recorder.is_recording():
		var ghost_kart_forward := -_kart.global_transform.basis.z
		var ghost_kart_yaw_degrees := rad_to_deg(
			Vector3.FORWARD.signed_angle_to(ghost_kart_forward, Vector3.UP)
		)
		_ghost_recorder.sample(
			_elapsed_s,
			_kart.global_position,
			ghost_kart_yaw_degrees
		)
	_ghost_player.advance(_elapsed_s)
	# Fix-wave LOW-6: _update_wrong_way() and _update_player_follower() each
	# used to call _spine.progress_for_position(_kart.global_position)
	# independently -- the same projection, computed twice a tick for no
	# reason (TrackSpine._ensure_curve() then Curve3D.get_closest_offset()
	# both re-run). Sampled once here and threaded through to both.
	var progress := _spine.progress_for_position(_kart.global_position)
	_update_wrong_way(delta_s, progress)
	_update_player_follower(progress, delta_s)
	# R5 Task 2: see the class doc's LIVE RANKING section -- reads only
	# already-current numbers, no new closest-offset call.
	_refresh_rank_snapshot()


## R5 Task 1: drives the pure CountdownTimer/StartBoostJudge one pre-GO tick.
## Samples the PLAYER's own real HOP-held state every such tick (AI get no
## start-boost mechanic in R5 -- see the class doc) and fires _start_race()
## exactly once, on the tick CountdownTimer.tick() reports &"go" (a one-shot
## edge -- see countdown_timer.gd's own class doc).
func _tick_countdown(delta_s: float) -> void:
	var hop_held := _router.buffer.is_action_pressed(InputIntent.ACTION_JUMP)
	_start_boost_judge.sample(delta_s, hop_held)
	if _countdown.tick(delta_s) == &"go":
		_start_race()


## R5 Task 1: called exactly once, on the GO tick -- see the class doc's own
## COUNTDOWN + START BOOST section for what each verdict does and why.
func _start_race() -> void:
	_race_started = true
	# A continuous HOP hold that carries straight through the countdown-to-
	# race boundary (the &"boost"/&"bog" cases) must not also read as a
	# brand-new press edge the instant _route_input() starts running post-GO
	# -- _hop_was_pressed otherwise still sits at its configure()-time false
	# default, and a still-held HOP would look like a false -> true edge on
	# the very next tick. Seeding it from the real current state here keeps
	# the edge detector honest: only an ACTUAL release-then-press after GO
	# fires hop_pressed() again.
	_hop_was_pressed = _router.buffer.is_action_pressed(InputIntent.ACTION_JUMP)
	match _start_boost_judge.verdict():
		&"bog":
			_bog_kart = _kart
			_bog_remaining_s = _race_tuning.start_bog_penalty_s
		&"boost":
			_kart.call("set_run_active", true)
			# CTR R8 Task 2 audit: boost_duration_s is not one of the three
			# fields composed_with() ever multiplies (top_speed_mps/accel_
			# mps2/steer_rate_degrees_per_s only -- see KartTuning.composed_
			# with()'s own doc), so reading it off the shared _kart_tuning
			# here is exactly equal to reading it off _player_kart_tuning --
			# left as the shared reference rather than churning this line.
			_kart.call("apply_boost", _kart_tuning.boost_duration_s)
		_:
			_kart.call("set_run_active", true)
	for ai_kart: CharacterBody3D in _ai_karts:
		ai_kart.call("set_run_active", true)

	# Task 6 (CTR R7, stretch: time-trial ghost): recording only ever begins
	# for a solo session -- see the class doc's GHOST WIRING section. The
	# ghost player's own start_replay() is always safe to call regardless
	# (a no-op with nothing loaded, see its own doc), so no matching
	# spawn_opponents guard is needed on that side.
	if not spawn_opponents:
		_ghost_recorder.start()
	_ghost_player.start_replay()


func countdown_phase() -> StringName:
	return _countdown.phase()


func is_race_started() -> bool:
	return _race_started


## Fix round 1, reviewer [LOW-1]: the HUD's "GO!" flash (see race_hud.gd's
## own COUNTDOWN + BOOST HINT section) needs SOME real duration to hold that
## text visible for -- is_race_started() alone flips true the same tick GO
## fires (unfreezing/boost must land that same tick, see _start_race()'s own
## doc), so gating visibility on it alone made the flash invisible: hidden
## the instant it would have shown. Rather than inventing a new "how long to
## flash GO" tuning field, this exposes the same countdown_step_s every 3/2/1
## digit was already held on screen for, so the HUD can hold "GO!" for that
## identical one-phase-long beat (elapsed_s() < countdown_step_s(), see
## race_hud.gd's own _refresh_countdown_display()) -- a natural reuse, not a
## new number. 0.0 before configure() (matches this class's other "not ready
## yet" getters).
func countdown_step_s() -> float:
	return _race_tuning.countdown_step_s if _configured else 0.0


func _route_input() -> void:
	# R5 Task 1: see the class doc's own paragraph on this guard -- the ONLY
	# way this is ever reached with the player's kart inactive is the &"bog"
	# start-boost penalty (a finished race never reaches _route_input() at
	# all, see the early return at the top of _physics_process()).
	if not bool(_kart.call("is_run_active")):
		return
	_input_adapter.apply_move(_router.buffer.movement(), _kart)
	var hop_held := _router.buffer.is_action_pressed(InputIntent.ACTION_JUMP)
	if hop_held != _hop_was_pressed:
		if hop_held:
			_input_adapter.apply_hop_pressed(_kart)
		else:
			_input_adapter.apply_hop_released(_kart)
		_hop_was_pressed = hop_held
	# R4 Task 2/4: ITEM is a fire-once action (see racing_input_adapter.gd's
	# apply_item_pressed() doc) -- only the false -> true edge routes to the
	# kart, mirroring HOP's own edge-sampling above but with no release
	# counterpart, so holding the button down never re-fires use_item()
	# every tick. apply_item_pressed() now returns whichever item name
	# KartController.use_item() handed back (Task 3's own return-name-only
	# path); Task 4 routes that name through dispatch_item_use() -- see its
	# own doc for why this is the SAME shared entry point Task 5's AI
	# item-use decision is documented to call through too.
	var item_held := _router.buffer.is_action_pressed(InputIntent.ACTION_ITEM)
	if item_held and not _item_was_pressed:
		var used_item: StringName = _input_adapter.apply_item_pressed(_kart)
		dispatch_item_use(_kart, used_item)
	_item_was_pressed = item_held


func _update_wrong_way(delta_s: float, progress: float) -> void:
	var wrong_now := _spine.is_wrong_way(_kart.velocity, progress)
	if wrong_now:
		_wrong_way_elapsed_s += delta_s
	else:
		_wrong_way_elapsed_s = 0.0
	_wrong_way_flag = _wrong_way_elapsed_s >= _race_tuning.wrong_way_grace_s


## Binding contract 3: the player's own continuous SpineFollower total,
## updated every tick exactly like every AiKartAgent already updates its own
## private one (see ai_kart_agent.gd's _physics_process). max_step_m mirrors
## AiKartAgent._max_follower_step_m()'s own derivation -- the true physical
## ceiling on how far THIS kart can travel in one tick -- minus the AI-only
## rubber_band_boost_max_ratio factor, since the player is never rubber-
## banded (that is an AI-catch-up mechanic; see ai_driver.gd's RUBBER BAND
## section). Using only tuning fields, no new literal, per this file's own
## no-bare-literal rule. Fix-wave LOW-6: raw_progress is sampled ONCE per
## tick by the caller (_physics_process) and threaded through here and into
## _update_wrong_way() rather than each calling _spine.progress_for_position()
## independently -- same projection, same result, computed once instead of
## twice a tick.
##
## CTR R8 Task 2 (characters/select/classes) CARRIED-FORWARD RISK, resolved:
## reads _player_kart_tuning (the player's own composed instance), not the
## shared _kart_tuning -- a speed-class player kart's real top_speed_mps
## exceeds the shared catalog value, and this clamp existing on the
## UNCLASSED value would under-clamp the follower's max step every tick,
## the exact "reasons off the unclassed base while the kart actually races
## at the classed value" hazard Task 1's reviewer carried forward onto this
## task.
func _update_player_follower(raw_progress: float, delta_s: float) -> void:
	var max_step_m := (
		(
			_player_kart_tuning.top_speed_mps
			+ _player_kart_tuning.boost_speed_bonus_mps
		) * delta_s
	)
	_player_follower.update(raw_progress, max_step_m)


## R5 Task 2: see the class doc's LIVE RANKING section. Assembles one entry
## per kart (player first, then every AI kart in slot order -- rank() does
## not care about input order beyond its own documented stability
## tiebreaker, see race_ranking.gd) purely from already-current numbers, and
## hands the whole Array[Dictionary] to RaceRanking.rank() in one call.
func _refresh_rank_snapshot() -> void:
	var entries: Array[Dictionary] = []
	entries.append(_rank_entry(_kart, _validator, _player_follower.total_progress_m()))
	for index in range(_ai_karts.size()):
		var ai_kart := _ai_karts[index]
		var validator: LapValidatorType = _gate_validators.get(ai_kart)
		entries.append(
			_rank_entry(ai_kart, validator, ai_kart_total_progress_m(index))
		)
	_current_rank_order = _ranking.rank(entries)


## Builds one RaceRanking entry Dictionary for a single kart -- see race_
## ranking.gd's own ENTRY SHAPE doc for what each key means. laps_complete is
## deliberately validator.current_lap() - 1 (whole laps BANKED), not current_
## lap() itself (the 1-based lap currently in progress, capped at lap_count)
## -- see lap_validator.gd's own current_lap() doc.
func _rank_entry(
	kart: CharacterBody3D, validator: LapValidatorType, total_progress_m: float
) -> Dictionary:
	return {
		"id": kart,
		"finished_order": finish_order_of(kart),
		"laps_complete": (validator.current_lap() - 1) if validator != null else 0,
		"gates_this_lap": validator.progress_gates() if validator != null else 0,
		"total_progress_m": total_progress_m,
	}


func _discover_gates() -> Array[CheckpointGate]:
	var result: Array[CheckpointGate] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is CheckpointGate:
			result.append(candidate as CheckpointGate)
	result.sort_custom(
		func(a: CheckpointGate, b: CheckpointGate) -> bool:
			return a.gate_index < b.gate_index
	)
	return result


## Binding contract 2 (seam ruling): gates route to a validator by BODY
## IDENTITY, looked up in _gate_validators -- never by assuming "the only
## body that can ever enter a gate is the player's Kart", which stopped
## being true the moment AI karts started sharing these same Area3D
## triggers (CheckpointGate.monitoring is forced on for exactly this: see
## checkpoint_gate.gd's own class doc). Every kart's own validator advances
## on every crossing, unconditionally; only the PLAYER's crossing goes on to
## drive lap-time bookkeeping and the finish sequence below -- an AI kart's
## own validator exists so ITS gate sequence is tracked correctly (tests can
## observe it via ai_kart_progress_gates()), and (R5 Task 2) so its own
## &"race_complete" outcome gets recorded via _record_finish() -- see the
## class doc's own AI FINISH RECORDING section. An AI kart still cannot END
## the race on its own -- only the player's own crossing ever reaches
## _finish_race() below.
func _on_gate_body_entered(body: Node, gate: CheckpointGate) -> void:
	# Fix round 1, reviewer [LOW-2]: dormant-but-ungated pre-GO -- a frozen
	# kart can never PHYSICALLY reach a gate before GO (see the class doc's
	# COUNTDOWN + START BOOST section), so this was never reachable through
	# real play, only through a caller that reaches this private handler
	# directly (as this suite's own _force_finish() does -- every one of its
	# callers already boots through a countdown-skip helper first, so this
	# adds no behavior change there). Made structural rather than left
	# implicit: a signal path this session owns should not stay silently
	# reachable pre-GO just because nothing currently exercises it that way.
	# This guard alone stays absolute -- unlike _finished below, nothing
	# ever bypasses it.
	if not _race_started:
		return
	if _finished:
		# R5 Task 2 fix round 1 [MEDIUM]: SAME-TICK PHOTO FINISH. Godot
		# queues every Area3D body_entered signal a physics step detects
		# before any of them start running, so if the player's own crossing
		# is dispatched first this same tick (setting _finished true and
		# freezing every kart, see _finish_race() below), an AI kart's own
		# ALREADY-QUEUED crossing this identical tick still fires afterward
		# -- dropping it outright (the old, unconditional `if _finished:
		# return`) silently lost that AI's own race_complete forever:
		# finish_order_of() would read -1 permanently, misreporting a kart
		# that genuinely crossed the line as still racing.
		#
		# R5 Task 3 correction: an earlier revision of this comment claimed
		# an AI kart "can never PHYSICALLY reach a gate again on any LATER
		# tick (frozen = zero displacement)" once _finished is true, framing
		# the crossings this branch catches as literal same-instant
		# artifacts only. That overstates what set_run_active(false) does --
		# see KartMotor.decelerate_to_stop()'s own doc: a kart moving at
		# speed when frozen COASTS toward a stop at brake_mps2 over a real,
		# bounded, MULTI-tick window, not an instant clamp to zero, so a
		# kart parked close enough to a gate could in principle still drift
		# across it a few ticks after being frozen, not only this identical
		# tick. That does not make this branch wrong: its own guard below
		# (_finished true, body != _kart, finish_order_of(body) < 0) carries
		# no time-window assumption of its own -- it records whichever such
		# crossing arrives, same tick or a few ticks of coasting later,
		# always correctly, for a kart that has not itself already been
		# recorded (an already-finished AI's own further crossings, if any,
		# are ordinary and ignored -- nothing new to record, and _record_
		# finish() would no-op anyway). The player's own crossings are
		# ALWAYS dropped here regardless of dispatch order -- preserves "no
		# post-finish lap counting for the player" exactly as before this
		# fix; _finish_race()'s own freeze is not retroactively undone or
		# re-entered either way, since _finished stays true and _finish_
		# race() is never called again from this branch.
		if body != _kart and finish_order_of(body as CharacterBody3D) < 0:
			_process_ai_gate_crossing(body as CharacterBody3D, gate)
		return
	if body != _kart:
		_process_ai_gate_crossing(body as CharacterBody3D, gate)
		return
	var validator: LapValidatorType = _gate_validators.get(body)
	if validator == null:
		return
	var outcome := validator.gate_crossed(gate.gate_index)
	if outcome != &"lap_complete" and outcome != &"race_complete":
		return
	var now_elapsed := elapsed_s()
	_lap_times.append(now_elapsed - _last_lap_boundary_s)
	_last_lap_boundary_s = now_elapsed
	if outcome == &"race_complete":
		_finish_race(now_elapsed)


## Shared by the ordinary pre-finish AI path and the same-tick photo-finish
## bypass above -- see both callers' own docs. Advances the given kart's own
## validator and records its finish (idempotent, see _record_finish()'s own
## doc) if-and-only-if THIS crossing is its own race_complete; an ordinary
## &"ok"/&"out_of_order"/&"lap_complete" outcome is a harmless no-op past the
## validator update, same as before this fix -- AI karts get no lap-time
## bookkeeping at all, that stays player-only (see the caller below).
func _process_ai_gate_crossing(body: CharacterBody3D, gate: CheckpointGate) -> void:
	var validator: LapValidatorType = _gate_validators.get(body)
	if validator == null:
		return
	var outcome := validator.gate_crossed(gate.gate_index)
	if outcome == &"race_complete":
		_record_finish(body, elapsed_s())


## See the class doc's ITEM BOX WIRING and SOLO TIME TRIAL DOES NOT ROLL
## sections. Routes straight to the entering body's OWN ItemSlot -- no
## per-kart lookup table, unlike gate crossings' _gate_validators, since the
## body passed in by the native body_entered signal already IS the kart
## whose slot must roll; player and AI karts take the exact same path here.
## A body with no item_slot() method (a stray non-kart Area3D/body, or a
## bare test fixture) is silently ignored rather than erroring.
func _on_box_body_entered(body: Node) -> void:
	# Fix round 1, reviewer [LOW-2]: same structural pre-GO gate as _on_gate_
	# body_entered() above -- a frozen kart can never physically reach a box
	# before GO either. See that function's own doc for the full rationale.
	if not _race_started:
		return
	if not _items_allowed():
		return
	if body == null or not is_instance_valid(body) or not body.has_method("item_slot"):
		return
	var slot: Object = body.call("item_slot")
	if slot == null:
		return
	# CTR R6 Task 5: threads this kart's own LIVE position ratio into the
	# weighted roulette -- see item_slot.gd's own WEIGHTED MAPPING doc and
	# _position_ratio_for()'s own doc for the (position-1)/(field-1) formula.
	slot.call("start_roll", _item_rng.randf(), _position_ratio_for(body))


## See the class doc's SOLO TIME TRIAL DOES NOT ROLL section.
func _items_allowed() -> bool:
	return spawn_opponents


## CTR R6 Task 5: the position ratio ItemSlot.start_roll()'s own WEIGHTED
## MAPPING blends by -- 0.0 for the race leader, 1.0 for last place, a
## straight-line (position-1)/(field-1) fraction in between, read off THIS
## session's own already-live kart_position()/field_size() (the exact same
## per-tick ranking RaceHUD's own "POS n / m" line already reads, see those
## two getters' own class-doc LIVE RANKING section) rather than a second,
## parallel ranking computation. field_size() <= 1 (a solo/no-field session,
## or a tick before the very first _refresh_rank_snapshot() has ever run)
## has no meaningful ratio to compute -- returns the ItemSlot.start_roll()
## sentinel (-1.0, "no live position known") rather than dividing by zero,
## the graceful-degrade shape this whole file already uses for "not ready
## yet" reads. In practice this path is unreachable in production: _items_
## allowed() already gates every real call site (_on_box_body_entered())
## behind spawn_opponents, so a real box pickup only ever happens once a
## real multi-kart field exists -- this guard exists so the formula itself
## can never divide by zero, not because the gate is expected to fail.
func _position_ratio_for(kart: CharacterBody3D) -> float:
	var field := field_size()
	if field <= 1:
		return -1.0
	return float(kart_position(kart) - 1) / float(field - 1)


func _discover_item_boxes() -> Array[ItemBox]:
	var result: Array[ItemBox] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is ItemBox:
			result.append(candidate as ItemBox)
	return result


func _discover_boost_pads() -> Array[BoostPad]:
	var result: Array[BoostPad] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is BoostPad:
			result.append(candidate as BoostPad)
	return result


func _discover_jump_pads() -> Array[JumpPad]:
	var result: Array[JumpPad] = []
	for candidate: Node in _track.find_children("*", "Area3D", true, false):
		if candidate is JumpPad:
			result.append(candidate as JumpPad)
	return result


## See the class doc's PAD WIRING section. `pad` is THIS specific pad (bound
## at connect time, see configure()'s own pad-wiring loop) -- try_consume()
## is called on IT, never a different pad the same kart might also be
## sitting in, so each pad's own cooldown stays independent of every other
## one. A body with no apply_boost() method (a stray non-kart Area3D/body,
## or a bare test fixture) is silently ignored rather than erroring, the
## same shape _on_box_body_entered()'s own item_slot() check already uses.
func _on_boost_pad_body_entered(body: Node, pad: BoostPad) -> void:
	# Fix round 1, reviewer [LOW-2]-style pre-GO gate -- same structural
	# reason as _on_gate_body_entered()/_on_box_body_entered() above: a
	# frozen kart can never physically reach a pad before GO either.
	if not _race_started:
		return
	if body == null or not is_instance_valid(body) or not body.has_method("apply_boost"):
		return
	if not pad.try_consume(body):
		return
	body.call("apply_boost", _race_tuning.pad_boost_s)


## See _on_boost_pad_body_entered()'s own doc immediately above -- identical
## shape, launch() in place of apply_boost().
func _on_jump_pad_body_entered(body: Node, pad: JumpPad) -> void:
	if not _race_started:
		return
	if body == null or not is_instance_valid(body) or not body.has_method("launch"):
		return
	if not pad.try_consume(body):
		return
	body.call("launch", _race_tuning.jump_pad_velocity_scale)


## Binding contract 3: player finish placement = 1 + the number of AI karts
## whose own SpineFollower total_progress_m() exceeds the player's, sampled
## at this exact finish instant -- seam-safe by construction since both
## sides of every comparison are continuous SpineFollower totals (see the
## class doc's own "seam ruling" note on _player_follower/_gate_validators),
## never a raw, seam-ambiguous spine offset.
##
## Freezes EVERY kart (set_run_active(false), player included -- H2 review's
## original "stop it driving into the walls / force-end a mid-finish slide"
## fix, now reused for every AI kart too) BEFORE reading any AI kart's
## progress, so no kart can keep accruing distance between the placement
## read and the freeze actually taking effect. AiKartAgent's own
## is_run_active() gate (Task 5 binding contract 1) is what makes freezing
## an AI kart here safe -- a frozen AI kart's stuck-detector never fires and
## never silently reactivates it; set_physics_process(false) on top of that
## is belt-and-braces, an explicit "stop ticking at all" rather than relying
## solely on the gate reading false every tick forever.
func _finish_race(now_elapsed: float) -> void:
	# R5 Task 2: see the class doc's AI FINISH RECORDING section -- the
	# player's own finish goes through the exact same idempotent recorder
	# every AI kart's own race_complete crossing does, so both share one
	# finish-order sequence. Called first, before _finished flips true, so
	# the ordering guard in _on_gate_body_entered() cannot have already
	# blocked this same crossing from reaching here in the first place.
	_record_finish(_kart, now_elapsed)
	_finished = true
	_final_elapsed_s = now_elapsed
	# H2 review: nothing else stops the kart driving into the walls behind
	# the finish line under its own auto-throttle, and a finish caught
	# mid-slide would otherwise leave the slide latched forever. See
	# KartController.set_run_active()'s doc for exactly what this does; the
	# camera is deliberately left alone so its own easing keeps settling the
	# finish shot.
	_kart.call("set_run_active", false)
	for ai_kart: CharacterBody3D in _ai_karts:
		ai_kart.call("set_run_active", false)

	for agent: AiKartAgentType in _ai_agents:
		agent.set_physics_process(false)

	# Task 6 (CTR R7, stretch: time-trial ghost): recording stops here so
	# save_ghost() (called afterward, by GameRoot, ONLY on a genuine new
	# best -- see the class doc's WRITE HOOK section) persists exactly the
	# keyframes captured between GO and this finish, never anything
	# appended post-race. The ghost's own replay is also force-hidden here
	# even if it had not yet reached its own last keyframe (e.g. this run
	# beat the ghost it was racing against) -- see ghost_player.gd's own
	# stop_replay() doc.
	_ghost_recorder.stop()
	_ghost_player.stop_replay()

	race_finished.emit(_final_elapsed_s, _lap_times.duplicate())


## R5 Task 2: the ONE place any kart's own finish (player or AI) gets
## written into _finish_order_index/_finish_elapsed_s -- see the class doc's
## AI FINISH RECORDING section for why idempotency here specifically matters
## (a still-driving AI kart's own LapValidator keeps reporting
## &"race_complete" on every further lap it closes, see lap_validator.gd's
## own SEQUENCE doc: _laps_completed has no upper clamp). Only the FIRST
## call for a given kart ever writes anything; every later call for that
## same kart is a silent no-op, which is exactly what "a kart's rank freezes
## at its finish slot" requires.
func _record_finish(kart: CharacterBody3D, elapsed_s_at_finish: float) -> void:
	if _finish_order_index.has(kart):
		return
	_finish_order_index[kart] = _next_finish_order
	_finish_elapsed_s[kart] = elapsed_s_at_finish
	_next_finish_order += 1


## Shared "place the transform, then seed yaw as an independent step"
## sequence -- see configure()'s own HIGH-1 fix-wave doc for the original
## player-only bug this fixed, and _spawn_ai_karts() for the AI reuse
## the Task 5 brief calls for ("the spawn-yaw seeding path must keep
## working -- reuse it per kart").
func _seed_kart_transform(kart: CharacterBody3D, marker: Marker3D) -> void:
	kart.global_transform = marker.global_transform
	var spawn_forward := -marker.global_transform.basis.z
	kart.call(
		"set_yaw_degrees",
		rad_to_deg(Vector3.FORWARD.signed_angle_to(spawn_forward, Vector3.UP))
	)


## R4 Task 4 (CARRIED MEDIUM fix -- see _spawn_ai_karts()'s own SPAWN-
## TRANSFORM ORDERING doc for the probe-confirmed hazard this closes):
## the same "place the transform, then seed yaw" sequence as
## _seed_kart_transform() above, but usable on a kart that is NOT YET
## inside the tree (no parent of its own yet) -- composing against
## parent.global_transform.affine_inverse() rather than assigning kart.
## global_transform directly (which, for an orphan node, treats the parent
## chain as identity and would silently double-apply the real parent's own
## global transform once actually added as a child, unless that parent
## chain truly is world-identity). `parent` (_ai_root) is guaranteed
## already inside the tree by the time _spawn_ai_karts() calls this, so
## its own global_transform is a valid, already-resolved reference to
## compose against.
func _seed_kart_transform_for_parent(
	kart: CharacterBody3D, marker: Marker3D, parent: Node3D
) -> void:
	kart.transform = parent.global_transform.affine_inverse() * marker.global_transform
	var spawn_forward := -marker.global_transform.basis.z
	kart.call(
		"set_yaw_degrees",
		rad_to_deg(Vector3.FORWARD.signed_angle_to(spawn_forward, Vector3.UP))
	)


func _make_lap_validator() -> LapValidatorType:
	var validator := LapValidatorType.new()
	validator.configure(_gates.size(), int(_race_tuning.lap_count))
	return validator


## Fix-wave MEDIUM-4: every OTHER kart's current global_position -- the
## Callable each AiKartAgent receives (bound to ITS OWN kart, see
## _spawn_ai_karts()) as other_kart_positions_getter, so a stuck-respawn
## teleport never drops a kart on top of the player or another AI kart. This
## session is the one place that already knows every kart in the race (the
## same reason it already owns player_total_progress_m() for binding
## contract 3), so the avoidance check is handed the same shape of Callable
## rather than reaching past this session into physics overlap queries.
func _other_kart_positions(requesting_kart: CharacterBody3D) -> Array:
	var positions: Array = []
	if _kart != null and _kart != requesting_kart:
		positions.append(_kart.global_position)
	for other_kart: CharacterBody3D in _ai_karts:
		if other_kart != requesting_kart:
			positions.append(other_kart.global_position)
	return positions


## Spawns AiTuning.opponent_count AI karts (a real kart.tscn instance + a
## real, configured AiKartAgent each) on GridSlot1..N under Track -- slot 0
## is the player's own KartSpawn, untouched (see configure()'s own doc).
##
## GRID SLOTS. Both track scenes author 5 Marker3D GridSlot1..GridSlot5
## behind the start line (see scenes/racing/track_graybox_loop.tscn and
## track_sanity_shores.tscn, and the racing-track lint's track_grid_slots
## rule) -- a fixed count matching ai.tres's own opponent_count=5.0 default,
## same "the lint has no runtime access to a tuning resource" rationale
## TRACK_ROAD_WIDTH_M already documents for the gate-width rule. Fix-wave
## LOW-8: an earlier revision also authored a GridSlot0 at the exact same
## transform as the existing KartSpawn marker -- a pure duplicate that was
## never read here (the player always spawns from KartSpawn itself, see
## configure()'s own doc on why THAT marker is not renamed) and existed only
## to visually mark "this is where slot 0 sits". Deleted from both tracks
## (and every lint fixture that authored one) as a redundant second source
## of truth for the exact same transform; KartSpawn alone remains authoritative
## for the player's own spawn, and this function still only ever reads
## GridSlot1..N. A missing GridSlotN marker for a configured slot fails
## closed (push_error + skip that one slot, never a crash) rather than
## assuming every track always has enough slots for whatever opponent_count
## happens to be tuned to.
##
## RETRY / RE-CONFIGURE SAFETY. The real retry path (RaceHUD -> request_retry
## -> GameRoot re-selecting the level, see retry_requested's own doc) frees
## this entire scene and instantiates a fresh one, so every AI kart/agent
## (ordinary scene children) dies with it automatically -- no special
## cleanup needed for that path. This function is defensively idempotent
## anyway (clears and rebuilds _ai_root's children first) so a hypothetical
## second configure() call on the SAME instance never leaks or duplicates
## karts either.
##
## SPAWN-TRANSFORM ORDERING (R4 Task 4, CARRIED MEDIUM, probe-confirmed
## hazard): each kart's full spawn transform is now built via
## _seed_kart_transform_for_parent() BEFORE add_child() ever runs, not
## after (the shape this loop used until this fix). A freshly-instantiated
## CharacterBody3D that enters the tree still at its Transform3D.IDENTITY
## default registers a REAL, one-instant physics-server broadphase
## snapshot at that position the moment add_child() runs -- before any
## later transform write in the same script tick can reach it -- exactly
## the mechanism test_item_box.gd's own _new_kart_body()/_new_box() doc
## already empirically confirmed for a dynamically-added fixture (Godot/
## Jolt can queue a body_entered delivery from that one-instant placement
## for a LATER physics frame, well after this function has already moved
## the kart to its real GridSlotN position). An origin-adjacent Area3D --
## an item box authored near a track's own origin, or any future hazard
## sharing that space -- could register a transient, permanently-sticky
## pickup/trigger against that one-frame flash. Locked with a regression
## test (test_race_session.gd's test_spawning_ai_karts_does_not_flash_a_
## kart_through_the_track_origin).
## CTR R8 Task 2 (characters/select/classes): the 5 AI karts seat the 5
## drivers the player did NOT pick, in DriverRegistry's own fixed roster
## order -- see driver_registry.gd's own ROSTER ORDER doc. A plain filter,
## not a DriverRegistry method of its own (the brief's own public registry
## surface is entries()/entry()/character_scene()/driver_class() only) --
## "which driver did the PLAYER pick" stays a RaceSession-only concern, the
## same way spawn_opponents/track_id/_selected_driver_id already are.
## Exposed as its own method (not inlined into _spawn_ai_karts()'s loop) so
## it is directly, precisely testable: the roster has exactly 6 ids and
## exactly 3 of them (crash/cortex/lab_assistant) share the identical
## Balanced class, so "5 distinct, deterministic, no duplicates, excludes
## the pick" cannot be proven from a spawned kart's own tuning alone; this
## helper is what a test calls directly instead. Deterministic and
## duplicate-free by construction: ENTRIES has exactly 6 unique ids, so
## filtering out exactly one always leaves the other 5, in their existing
## relative order.
##
## R8 gate flip 2026-08-02: this doc used to also note that 4 of the 6
## roster ids shared an identical fallback mounted mesh (cortex/coco/
## ripper_roo falling back to the same lab-assistant scene lab_assistant
## itself ships for real) -- with cortex/coco/ripper_roo's own likeness
## gates now operator-accepted (docs/art/gates/2026-08-02-{cortex,coco,
## ripper-roo}/gate-record.md), that is no longer true: every roster id
## mounts its own distinct real scene, and only the shared Balanced class
## above still makes tuning-alone insufficient proof.
func _ai_fill_driver_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for candidate: DriverEntry in DriverRegistryType.entries():
		if candidate.id != _selected_driver_id:
			ids.append(candidate.id)
	return ids


func _spawn_ai_karts() -> void:
	if _ai_root == null:
		_ai_root = Node3D.new()
		_ai_root.name = "AiKarts"
		add_child(_ai_root)
	else:
		for child in _ai_root.get_children():
			_gate_validators.erase(child)
			child.queue_free()

	_ai_karts.clear()
	_ai_agents.clear()

	# Fix-wave MEDIUM-5: spawn_opponents owns solo-ness, not opponent_count
	# itself -- see the exported field's own doc.
	var opponent_count := int(_ai_tuning.opponent_count) if spawn_opponents else 0
	# CTR R8 Task 2: see _ai_fill_driver_ids()'s own doc. The roster is sized
	# for exactly the 6-kart grid (1 player + 5 AI) the design spec fixes --
	# ai_driver_ids always has exactly 5 entries in ordinary play. A slot
	# beyond that (opponent_count tuned above the roster's own AI-fill size,
	# never true of ai.tres's shipped 5.0 default) falls back to the roster's
	# own fallback id rather than an out-of-range read, the same fail-closed
	# spirit as the missing-GridSlotN branch below.
	var ai_driver_ids := _ai_fill_driver_ids()
	for slot_index in range(1, opponent_count + 1):
		var marker := _track.get_node_or_null("GridSlot%d" % slot_index) as Marker3D
		if marker == null:
			push_error(
				(
					"RaceSession._spawn_ai_karts: no GridSlot%d marker found "
					+ "under Track -- skipping this AI slot (fail closed: "
					+ "fewer AI karts than opponent_count, never a crash)."
				) % slot_index
			)
			continue

		var driver_id: StringName = (
			ai_driver_ids[slot_index - 1]
			if slot_index - 1 < ai_driver_ids.size()
			else DriverRegistryType.LAB_ASSISTANT.id
		)
		# CTR R8 Task 2 (characters/select/classes): this slot's own composed
		# tuning -- computed ONCE here and threaded through both this kart's
		# own configure() below and its AiKartAgent's configure() further
		# down, so both sides of this kart ALWAYS agree on how fast/how
		# sharply it can actually move. This resolves Task 1's reviewer-
		# carried-forward risk: before this task, AiKartAgent.configure() (and
		# through it, AiDriver's own target-speed read and this kart's own
		# _max_follower_step_m() stuck-recovery clamp) read the shared,
		# UNCLASSED _kart_tuning directly -- harmless while every kart
		# composed with null, but wrong the moment a real class multiplies
		# top_speed_mps: an AI's own driving decisions and its stuck-recovery
		# distance clamp would have reasoned off the base value while the kart
		# it actually controls raced at the classed one.
		var ai_kart_tuning := _kart_tuning.composed_with(
			DriverRegistryType.driver_class(driver_id)
		)

		var ai_kart := KartSceneType.instantiate() as CharacterBody3D
		# See this function's own SPAWN-TRANSFORM ORDERING doc: configure()
		# and the transform seed both happen BEFORE add_child(), so the
		# kart's very first physics-server registration already carries its
		# real GridSlotN position -- never a one-frame flash at the origin.
		ai_kart.call("configure", ai_kart_tuning, _item_tuning)
		# Task 1 (CTR R6, circuit polish): see the player's own identical
		# wiring in configure() above -- every AI kart shares the same
		# kart.tscn packed scene, so it carries the same Fx child. Safe to
		# call this BEFORE add_child() below (kart_fx.gd's own NODE LOOKUP
		# doc): configure() looks its particle nodes up lazily via get_node_
		# or_null() instead of trusting @onready, which would not have fired
		# yet on this still-detached subtree.
		ai_kart.get_node("Fx").call("configure", ai_kart, _fx_tuning)
		# CTR R8 Task 2 (characters/select/classes): this slot's own roster
		# driver -- DriverRegistry.character_scene() resolves the real model
		# for a gated driver or silently falls back to the lab assistant for
		# an ungated one (see that method's own FALLBACK doc; every AI driver
		# except crash and lab_assistant is fallback-active today, so most
		# slots resolve to the same lab-assistant mesh R6 Task 3 always
		# mounted, unchanged visually). Body tint stays a SLOT trait, exactly
		# tint_for_slot(slot_index) off the shared _kart_tuning -- see that
		# call's own doc immediately below and the design spec's own "per-
		# slot personalities and tints stay slot traits, untouched" ruling
		# (brief pin: tints must never become a per-driver trait).
		ai_kart.call("mount_character", DriverRegistryType.character_scene(driver_id))
		# CTR R8 Task 5 (characters/select/classes): this slot's own driver
		# seat fit -- see the player's own identical wiring in configure()
		# above for the full doc (entry()'s own null-safety-for-callers
		# shape, why the 1.0/ZERO fallback is defensive not a real path).
		var slot_driver_entry := DriverRegistryType.entry(driver_id)
		ai_kart.call(
			"apply_seat_fit",
			slot_driver_entry.seat_scale if slot_driver_entry != null else 1.0,
			(
				slot_driver_entry.seat_offset
				if slot_driver_entry != null
				else Vector3.ZERO
			)
		)
		# Task 3 (CTR R6, circuit polish): every AI kart gets a per-slot body
		# tint from the same KartTuning the player's own kart_tint_player line
		# above reads. tint_for_slot() is 1-based and wraps deterministically
		# past 5 slots (see kart_tuning.gd's own doc) -- slot_index here is
		# this loop's own 1-based GridSlot number, never re-derived.
		ai_kart.call("apply_body_tint", _kart_tuning.tint_for_slot(slot_index))
		# R5 Task 1: see the player's own identical call in configure() for
		# why this immediately undoes configure()'s own set_run_active(true)
		# -- every AI kart spawns frozen too, unfrozen plainly at GO (see the
		# class doc's COUNTDOWN + START BOOST section).
		ai_kart.call("set_run_active", false)
		_seed_kart_transform_for_parent(ai_kart, marker, _ai_root)
		_ai_root.add_child(ai_kart)

		_gate_validators[ai_kart] = _make_lap_validator()

		var agent := AiKartAgentType.new()
		ai_kart.add_child(agent)
		agent.call(
			"configure",
			ai_kart,
			_spine,
			_ai_tuning,
			# CTR R8 Task 2 CARRIED-FORWARD RISK, resolved: this slot's own
			# composed ai_kart_tuning, not the shared _kart_tuning -- see this
			# loop's own comment above ai_kart_tuning's declaration.
			ai_kart_tuning,
			_race_tuning,
			slot_index,
			Callable(self, "player_total_progress_m"),
			# Fix-wave MEDIUM-4: see ai_kart_agent.gd's own RESPAWN-ONTO-PLAYER
			# AVOIDANCE doc -- bound per kart so each agent's own blocking
			# check never sees ITS OWN position in the "other karts" list.
			Callable(self, "_other_kart_positions").bind(ai_kart),
			# R4 Task 5: see ai_kart_agent.gd's own ITEM WIRING doc.
			# item_targets_getter is UNBOUND, same as every missile/beaker's
			# own copy of this exact Callable -- it takes no arguments.
			# use_item_dispatcher is also unbound: use_item_for()'s own kart
			# argument is supplied at call time by AiKartAgent, not bound in
			# here, so this stays the identical shared entry point the
			# player's own ITEM-press path already routes through (see use_
			# item_for()'s own doc).
			_item_tuning,
			Callable(self, "_item_targets"),
			Callable(self, "use_item_for")
		)

		_ai_karts.append(ai_kart)
		_ai_agents.append(agent)
