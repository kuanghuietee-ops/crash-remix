# CTR Racing Mode — R1+R2 (Kart + Circuit + Time Trial) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ridable kart with CTR drift/slide-boost feel, racing on a looped island circuit with laps and a time-trial mode, installable as an APK — per `docs/superpowers/specs/2026-07-30-ctr-racing-mode-design.md` (R1+R2; AI/items/race-flow are follow-up plans).

**Architecture:** New `src/racing/` beside the platformer. Pure-logic cores (drift state machine, boost windows, lap validator) are plain RefCounted classes tested headless; scene glue mirrors the platformer's controller pattern. Track spine = looped `RailCurveBuilder` curve; checkpoints = ordered Area3D gates.

**Tech Stack:** Godot 4.7.1 GDScript, GUT (`bash scripts/run_gut.sh`), Python lints via pre-commit, tuning via TuningService.

## Global Constraints

- No gameplay numbers in code: numeric literals in `src/racing/**` (add this dir to the lint's scan — Task 1) limited to `0`, `1`, `-1`; every value in `data/tuning/racing/*.tres`.
- Tuning provably live: new sections registered in TuningService — fingerprint enumeration, validation ranges, `LEGACY_FIELD_GROUPS_BY_SECTION` entries (racing sections are NEW sections — follow how a whole new section is declared, see `SECTION_NAMES`), on-device panel pickup.
- TDD: failing test seen first for every behavioral unit.
- Shared tree: stage explicit paths only; never `git add -A`; never stage `docs/qa/phase05-gate-f2.md` or `docs/superpowers/specs/2026-07-23-crash-remix-design.md`.
- Suites green before every commit: GUT 729 baseline + Python 229 baseline + 5 lint scripts. Grep raw GUT output for 'Parse Error' (GUT can swallow them silently). Known rare flakes: renderer-cull / hog-anim timing in shared batch — re-run isolated to confirm.
- Feel gates are human-only: report "ready to test", never certify feel.
- The platformer must stay green and untouched except the explicitly shared files listed per task.

---

### Task 1: Racing tuning resources + service registration

**Files:**
- Create: `src/tuning/kart_tuning.gd`, `src/tuning/race_tuning.gd`, `data/tuning/racing/kart.tres`, `data/tuning/racing/race.tres`
- Modify: `src/tuning/tuning_service.gd` (new sections `kart`, `race`), `src/tuning/gameplay_tuning.gd` (catalog fields), `data/tuning/gameplay.tres` (wire the two new subresources), `scripts/lint_gameplay_numbers.py` (scan `src/racing/**` too)
- Test: `tests/tuning/test_tuning_service.gd` (extend), `tests/lint` python (numeric lint covers src/racing — fixture)

**Interfaces (produced, consumed by all later tasks):**
- `KartTuning` exports: `top_speed_mps=18.0`, `reverse_speed_mps=6.0`, `accel_mps2=14.0`, `brake_mps2=22.0`, `coast_drag_mps2=6.0`, `steer_rate_degrees_per_s=95.0`, `steer_speed_falloff=0.35`, `hop_height_m=0.6`, `gravity_mps2=24.0`, `slide_min_steer=0.25`, `slide_yaw_bonus_degrees_per_s=55.0`, `slide_counter_yaw_degrees_per_s=30.0`, `slide_min_duration_s=0.25`, `boost_window_open_s=0.55`, `boost_window_close_s=0.85`, `boost_window_shrink_factor=0.8`, `boost_speed_bonus_mps=5.0`, `boost_duration_s=1.1`, `boost_stack_max=3.0`, `spin_out_duration_s=1.2`, `spin_out_speed_keep_ratio=0.35`, `invulnerable_after_hit_s=1.5`
- `RaceTuning` exports: `lap_count=3.0`, `countdown_step_s=1.0`, `start_boost_window_s=0.3`, `start_bog_penalty_s=1.0`, `wrong_way_grace_s=1.5`, `checkpoint_tolerance_m=2.0`, `respawn_drop_height_m=2.0`, `camera_trail_m=4.6`, `camera_height_m=2.2`, `camera_fov_base=60.0`, `camera_fov_speed_gain=12.0`, `camera_yaw_lag_s=0.18`, `camera_drift_yaw_degrees=8.0`
- Values are starting points; validation: all strictly positive except listed ratios in (0,1].

- [ ] Steps: failing tuning-service test (new sections present in fingerprint + validation rejects nonpositive top_speed) → implement → numeric-lint fixture proving `src/racing/` is scanned (a temp bad file fails) → full suites → commit.

### Task 2: Drift + boost state machine (pure logic)

**Files:**
- Create: `src/racing/kart/drift_state_machine.gd` (class_name DriftStateMachine, RefCounted)
- Test: `tests/racing/test_drift_state_machine.gd`

**Interfaces:** `configure(kart_tuning)`, `hop_pressed()`, `hop_released()`, `steer(value)`, `tick(delta_s, grounded)`, → state getters `is_sliding()`, `slide_direction()` (−1/1), `boost_stage()` (0-3), `boost_tap()` → returns &"fired"/&"mistimed"/&"ignored", `consume_boost()` → seconds of boost to apply, signals-free (poll model like player FSM). Boost window: stage n opens at `boost_window_open_s * shrink^n` after slide start/last fire, closes at `boost_window_close_s * shrink^n`; tap inside = fired (stage+1), before open = mistimed → slide ends, after close with slide alive = ignored.
- [ ] Steps: failing tests for — slide requires hop+steer≥slide_min_steer on landing; direction locks; three timed taps stack then cap; early tap kills slide; release before min duration = no slide; consume_boost returns stacked duration → implement → suites → commit.

### Task 3: Kart motor + body controller

**Files:**
- Create: `src/racing/kart/kart_motor.gd` (pure: velocity/yaw integration from inputs+tuning), `src/racing/kart/kart_controller.gd` (CharacterBody3D glue), `scenes/racing/kart.tscn` (graybox box kart + collision + blob shadow instance)
- Test: `tests/racing/test_kart_motor.gd`

**Interfaces:** motor consumes (steer −1..1, throttle auto, hop/slide state from DriftStateMachine, grounded, delta) → (velocity, yaw_delta). Controller owns move_and_slide, ground check, exposes `speed_mps()`, `is_sliding()`, `apply_spin_out()`, `apply_boost(seconds)`. Reuses BlobShadow.
- [ ] Steps: failing motor tests (accel to top speed asymptote; steer rate falls off with speed by `steer_speed_falloff`; slide adds yaw bonus toward slide dir, counter-steer uses `slide_counter_yaw`; boost raises target speed by bonus for duration; spin-out keeps `spin_out_speed_keep_ratio` and zeroes steer authority for duration) → implement → suites → commit.

### Task 4: Racing input mode

**Files:**
- Modify: `src/gameplay/input/input_router.gd` (racing mode flag: bypass corridor magnet + corridor mapping — raw stick), `src/ui/touch_controls.gd` or the racing HUD scene adds HOP button (reuse button infra; ITEM button placeholder hidden in R1)
- Test: extend `tests/gameplay/test_input_adapters.gd`

**Interfaces:** `set_racing_mode(enabled)`; in racing mode `push_move` routes raw stick (still dead-zone filtered), corridor axis calls are ignored. Gamepad: left stick steer, A hop.
- [ ] Steps: failing test (racing mode: diagonal input arrives unmagnetized; corridor mode unchanged) → implement → suites → commit.

### Task 5: Kart chase camera

**Files:**
- Create: `src/racing/camera/kart_camera.gd`
- Test: `tests/racing/test_kart_camera.gd`

**Interfaces:** follows kart: position = kart − kart_forward·trail + up·height, yaw eased with `camera_yaw_lag_s`, `fov = base + gain·speed/top_speed`, drift adds `camera_drift_yaw_degrees` into slide direction. Uses RaceTuning only.
- [ ] Steps: failing tests (trail/height geometry; fov at rest vs top speed; yaw lag converges; drift yaw sign) → implement → suites → commit.

### Task 6: Looped spine + lap/checkpoint logic

**Files:**
- Modify: `src/gameplay/common/rail_curve_builder.gd` (optional `closed: bool` — wraps neighbor indices for handles and closes the curve)
- Create: `src/racing/track/lap_validator.gd` (pure), `src/racing/track/track_spine.gd` (closed Path3D helper: progress, tangent, wrong-way test), `src/racing/track/checkpoint_gate.gd` (Area3D)
- Test: `tests/racing/test_lap_validator.gd`, extend `tests/gameplay/test_rail_curve_builder.gd` (closed loop: point_count, first/last handle continuity)

**Interfaces:** LapValidator: `configure(gate_count, lap_count)`, `gate_crossed(index)` → &"ok"/&"out_of_order"/&"lap_complete"/&"race_complete", `current_lap()`, `progress_gates()` (ratio dropped: no length denominator; seam constraint documented in TrackSpine). Wrong-way: velocity·tangent < 0 sustained beyond `wrong_way_grace_s` → HUD warning flag.
- [ ] Steps: failing tests (in-order gates lap; skipping a gate doesn't; closed-curve handles wrap) → implement → suites → commit.

### Task 7: Graybox loop + race session + time-trial HUD (R1 APK checkpoint)

**Files:**
- Create: `scenes/racing/track_graybox_loop.tscn` (oval-with-two-corners loop, spine markers, 6 gates, start line), `src/racing/race_session.gd` (wires kart+camera+input mode+validator+timer; time-trial only), `scenes/racing/race_hud.tscn` (lap X/Y, timer, wrong-way flash), mode entry: extend the level list overlay (`scenes/ui/level_list_overlay.tscn` + its script) with a "Racing (prototype)" entry that loads the race scene
- Test: `tests/racing/test_race_session.gd` (headless: session over the graybox scene — kart placed, gates fire via teleport, lap counts, timer runs), integration scene-open test
- [ ] Steps: failing session test → build scene+session → suites → commit → **build APK, report R1 ready for operator kart-feel test**.

### Task 8: Sanity Shores Circuit + track author-lint (R2)

**Files:**
- Create: `scenes/racing/track_sanity_shores.tscn` — closed circuit from kit pieces (beach/jungle straights, two hairpins, one boost pad line, sea on the outside, walls/fences from kit), 10-14 gates, start/finish arch from kit posts
- Modify: `scripts/lint_level_authoring.py` (track rules behind a "racing track" scene marker: gates monotonic along spine, gate boxes span road width, spine closed, start line present)
- Test: python lint fixtures good/bad, scene-open + session integration on the circuit
- [ ] Steps: lint fixtures failing → implement lint → author circuit until lint+session tests green → suites → commit.

### Task 9: Time-trial results + best-time save + verification (R2 APK)

**Files:**
- Create/modify: results overlay reuse (`scenes/ui/results_screen.tscn` pattern) for time trial (lap splits, best), save best times via the existing save/progression system (find `src/gameplay/progression/` conventions), mode select polish
- Test: save round-trip test following existing save tests
- [ ] Steps: TDD save round-trip → wire results → full suites + all lints → commit → **build APK, TG summary, report R2 ready; STOP for operator feel verdict before R3 (AI) plan is written**.

## Self-Review
- Spec coverage: R1 = Tasks 1-7, R2 = Tasks 8-9; AI/items/race-flow deliberately deferred to follow-up plans per spec phasing.
- Interfaces named consistently (DriftStateMachine/KartTuning/RaceTuning/LapValidator used by Tasks 3,5,6,7).
- No placeholders; starting tuning values stated; every task carries its test path.
