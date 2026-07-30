# CTR Racing Mode — R3 (AI Opponents) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five AI karts racing the player on both tracks with CTR-style rubber-banding — per the racing spec's R3 phase (`docs/superpowers/specs/2026-07-30-ctr-racing-mode-design.md`; item use deferred to R4 since items don't exist yet).

**Architecture:** AI karts are ordinary `kart.tscn` instances driven by a virtual thumb: a pure-logic `AiDriver` produces steer/brake/hop/boost decisions each tick and an `AiKartAgent` node feeds them into the same `KartController` API the human uses — one physics code path, AI cannot cheat except through the explicit, tuning-capped rubber-band speed scalar. Progress comparison uses a new seam-safe `SpineFollower` (the primitive the spec's R5 seam ruling requires).

**Tech Stack:** Godot 4.7.1 GDScript, GUT, Python lints, TuningService (new section `&"ai"`).

## Global Constraints

- Numeric literals in `src/racing/**` limited to `0`, `1`, `-1`; every value in `data/tuning/racing/ai.tres`. TDD failing-first per behavioral unit. Suites green before every commit: GUT 889 baseline + Python 244 + 5 lints; grep raw GUT output for 'Parse Error'; known flakes (renderer-cull, hog-anim, 'Parameter m is null', warp-room ObjectDB leak) — re-run isolated to confirm. Stage explicit paths only; never `git add -A`; never stage `docs/qa/phase05-gate-f2.md` or `docs/superpowers/specs/2026-07-23-crash-remix-design.md`. Feel/fairness verdicts are the operator's; ship "ready to test".
- **Seam ruling (spec Recorded debts + track_spine.gd doc): never compare raw `progress_for_position` across the start/finish seam.** All cross-kart progress goes through `SpineFollower` (Task 2).
- The R4-binding spin-out ruling is untouched here — nothing calls `apply_spin_out()` in R3.
- Platformer stays untouched; RaceSession changes must keep both existing time-trial tests green.

---

### Task 1: AiTuning resource + section registration

**Files:** Create `src/tuning/ai_tuning.gd`, `data/tuning/racing/ai.tres`; modify `src/tuning/tuning_service.gd`, `src/tuning/gameplay_tuning.gd`, `data/tuning/gameplay.tres`; extend `tests/tuning/test_tuning_service.gd`.

**Interfaces (consumed by Tasks 2-5):** `AiTuning` exports: `opponent_count=5.0`, `lookahead_min_m=6.0`, `lookahead_speed_gain_s=0.55` (lookahead = min + speed×gain), `steer_gain=2.2` (pursuit-angle→steer), `corner_speed_curvature_gain=34.0` (target speed = top × clamp(1 − gain×curvature, floor, 1)), `corner_speed_floor_ratio=0.45`, `brake_margin_ratio=1.12` (brake when speed > target×margin), `slide_trigger_curvature=0.035` (1/m), `slide_exit_curvature=0.018`, `boost_tap_enabled=1.0` (0/1 flag), `lateral_slot_spacing_m=1.7` (per-slot offset: slot_i × spacing, centered), `rubber_band_full_gap_m=60.0`, `rubber_band_boost_max_ratio=0.18` (max +18% target speed when far behind), `rubber_band_drag_max_ratio=0.12` (max −12% when far ahead), `respawn_stuck_speed_mps=1.5`, `respawn_stuck_after_s=3.0`, `respawn_drop_gap_m=4.0`. Validation: all strictly positive except the two ratio caps in (0,1) and `boost_tap_enabled` in {0,1}; follow the established new-section pattern (SECTION_NAMES, catalog field, gameplay.tres wiring, migration coverage, fingerprint).
- [ ] Failing tuning tests → implement → suites → commit.

### Task 2: SpineFollower — seam-safe monotonic progress (pure logic)

**Files:** Create `src/racing/track/spine_follower.gd` (class_name SpineFollower, RefCounted); test `tests/racing/test_spine_follower.gd`.

**Interfaces:** `configure(spine_length_m: float)`; `reset(progress_m: float)`; `update(raw_progress_m: float, max_step_m: float) -> float` — returns hysteresis-filtered progress: candidate deltas are wrapped into (−length/2, +length/2] (seam wrap), clamped to ±max_step_m, accumulated into a continuous `total_progress_m()` (never wraps; grows across laps); `lap_progress_m()` = total mod length. This is THE primitive for cross-kart comparison: gap between karts = difference of `total_progress_m()`.
- [ ] Failing tests: crossing the seam forward continues total (no ~length jump backward); a raw jump of ~length (seam ambiguity, the documented 99%↔0% case) filtered to ≤max_step; reverse driving decreases; multi-lap totals accumulate → implement → suites → commit.

### Task 3: AiDriver (pure logic — the virtual thumb)

**Files:** Create `src/racing/ai/ai_driver.gd` (class_name AiDriver, RefCounted); test `tests/racing/test_ai_driver.gd`.

**Interfaces:** `configure(ai_tuning, kart_tuning)`; `decide(state: Dictionary) -> Dictionary`. Input state keys: `position: Vector3`, `forward: Vector3`, `speed_mps: float`, `is_sliding: bool`, `boost_window_open: bool` (from controller/drift API — Task 4 supplies), `lookahead_point: Vector3`, `curvature_ahead: float` (1/m at lookahead), `lateral_target_m: float`, `lateral_error_m: float` (signed, target − actual), `band_gap_m: float` (player total_progress − this kart's; positive = behind player). Output keys: `steer: float` (−1..1), `brake: bool`, `hop: bool` (edge — press this tick), `boost_tap: bool` (edge), `speed_scale: float` (rubber band: 1 + boost_max×clamp(gap/full_gap,0,1) when behind, 1 − drag_max×clamp(−gap/full_gap,0,1) when ahead).
Steering: signed angle from `forward` to (lookahead_point − position) flattened to XZ, × steer_gain, + lateral correction (small gain derived from steer_gain — no new literal; document), clamped. Brake: speed > corner target × brake_margin. Slide: hop=true edge when curvature_ahead ≥ slide_trigger AND not sliding AND grounded-implied (state has no airborne — controller gates); while sliding and `boost_window_open` and boost_tap_enabled → boost_tap=true; slide naturally ends when the driver straightens (curvature < slide_exit lowers steer below the sustain threshold — verify with the real DriftStateMachine in Task 4 integration).
- [ ] Failing tests: straight → steer≈0 no brake; curve ahead → steer sign toward curve; overspeed into hairpin → brake; tight curvature triggers hop edge exactly once; boost_tap fires only when window open and sliding; rubber-band scale formula both directions capped; lateral error steers toward slot → implement → suites → commit.

### Task 4: AiKartAgent node + controller hooks

**Files:** Create `src/racing/ai/ai_kart_agent.gd` (Node); modify `src/racing/kart/kart_controller.gd` (add `set_speed_scale(ratio: float)` → motor target-speed multiplier, and `boost_window_open() -> bool` proxy from DriftStateMachine — add the FSM query if missing: window open for the CURRENT stage now), `src/racing/kart/kart_motor.gd` (speed-scale multiplier on target speed, default 1); tests `tests/racing/test_ai_kart_agent.gd` + extend motor tests.

**Interfaces:** `AiKartAgent.configure(kart: Node, spine: TrackSpine, ai_tuning, kart_tuning, slot_index: int, player_follower_getter: Callable)`; per physics tick: updates its own SpineFollower from kart position (max_step from kart top speed × delta — computed, not literal), computes lookahead point on the spine (progress + lookahead), curvature (sample tangent at ±lookahead via spine — add `curvature_at_progress(progress_m, sample_span_m) -> float` to TrackSpine: angle between tangents / span; TDD in track spine tests), lateral target (slot offset perpendicular to tangent), assembles state, calls AiDriver.decide, routes outputs to the controller (`steer()`, `hop_pressed()/hop_released()` edges, `boost_tap()`, brake flag, `set_speed_scale()`). Stuck detection: speed < respawn_stuck_speed for respawn_stuck_after_s → teleport to (filtered progress − respawn_drop_gap) on the centerline facing the tangent, reset follower (uses RaceTuning.respawn_drop_height_m — first consumer of a recorded-debt field; note it in the report and strike it from the spec's unread-fields debt line).
- [ ] Failing tests: agent drives a real kart around the graybox loop's first corner from spawn (real physics, no teleport — SpineFollower total progress strictly increases over N seconds); speed_scale reaches motor target; stuck kart respawns on line → implement → suites → commit.

### Task 5: Grid, session integration, finish placement

**Files:** Modify `scenes/racing/track_graybox_loop.tscn` + `track_sanity_shores.tscn` (6 GridSlot Marker3Ds behind the start line, staggered 2×3), `src/racing/race_session.gd` (spawn `opponent_count` AI karts on slots 1-5 — player takes slot 0; per-kart LapValidator + SpineFollower routing via gate `body_entered` body identity; freeze ALL karts on player finish via set_run_active(false); finish placement = 1 + number of karts with total_progress > player's at player-finish instant — seam-safe by construction), `src/racing/ui/race_hud.gd` (results panel adds "FINISHED n / m"), plus scene lint: grid slots ≥ opponent_count+1 rule in the racing track lint; tests: extend `tests/racing/test_race_session.gd` + sanity-shores twin (AI karts spawn, gates route to the right validator, player finish freezes AI and computes placement; a seeded AI ahead → placement 2/6), lint fixture.
- [ ] Failing tests → implement → suites → commit. RaceSession's existing solo time-trial tests MUST stay green unmodified (opponent_count comes from tuning; tests may pin 0 opponents via tuning override — decide cleanly, document).

### Task 6: Verification + R3 APK readiness

- [ ] Full GUT + Python + 5 lints + `scripts/verify_exported_tuning.sh` (ai.tres in pack). Both tracks' AI integration tests green. Update the spec's Recorded-debts (strike the now-consumed respawn_drop_height_m from debt #3; note boost pads still unbuilt). Report suite counts + what remains for R4/R5.

## Self-Review
- Spec R3 coverage: racing line (spine+lateral slots), per-curvature speed, rubber-band capped, hop/slide on tight corners — Tasks 3-5; item use explicitly deferred (R4). 5 opponents = opponent_count default.
- Seam ruling honored via SpineFollower everywhere cross-kart progress appears (Tasks 2, 4, 5).
- Interfaces named consistently across tasks; no placeholders; every task carries tests.
