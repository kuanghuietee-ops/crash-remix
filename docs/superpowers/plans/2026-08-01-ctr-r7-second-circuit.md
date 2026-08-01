# CTR R7 — Second Circuit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Temple Twilight, pads, kart contact, and the Cup — per `docs/superpowers/specs/2026-08-01-ctr-r7-second-circuit-design.md`.

**Architecture:** Pads = Area3D nodes + RaceTuning fields + lint rules (the R4 item-box precedent shape). Contact = move_and_slide collision post-processing in KartController with KartTuning caps. Temple Twilight follows the Sanity Shores authoring playbook under the Papu-night mood. Cup = a session-orchestration layer above RaceSession + save v2→v3. Ghost = out-of-profile keyframe files.

## Global Constraints

Same as R6's (literals 0/1/-1 in `src/racing/**`; tuning provably live; TDD; suites green each commit — GUT 1329 / Py 258 / 5 lints + export verifier baseline; grep raw GUT for 'Parse Error'; known flakes island_slice/camera_archetypes/main_boot-renderer-cull — re-run isolated; stage explicit paths; never stage the two other-agent WIP docs; FOREGROUND suites only). Save schema changes carry v1→v2-grade migration rigor (scratch-verified). Seam ruling stands. The operator's two R6 feedback fixes (front-grid player, seated assistants) must survive untouched on the new track.

---

### Task 1: Pad mechanics (boost + jump) + lint
**Files:** Create `src/racing/track/boost_pad.gd`+scene, `src/racing/track/jump_pad.gd`+scene (Area3D, kart-mask, per-kart refire cooldown via instance id map; boost → kart.apply_boost(race.pad_boost_s); jump → vertical impulse scaled from hop kinematics × jump_pad_velocity_scale — read the hop v0 derivation and reuse); RaceTuning fields `pad_boost_s=1.0`, `pad_refire_cooldown_s=1.5`, `jump_pad_velocity_scale=2.2` (registration per precedent); pad visuals: flat glowing quads from palette cells (unshaded, palette material conventions; pulse via the fx section ONLY if free — no new fx fields unless required, document); lint rule: pads on-road + clear of gates/boxes/origin (grid-slot rule precedent) + fixtures.
- [ ] TDD: pad fires once per pass per kart (cooldown), boost reaches motor, jump impulse math vs hop kinematics, lint fixtures. Suites → commit.

### Task 2: Kart-to-kart contact
**Files:** `src/racing/kart/kart_controller.gd` (+`kart_motor.gd` if impulse lives there): after move_and_slide, inspect slide collisions for other karts (collider is a kart — duck-check); apply symmetric lateral separation impulse to BOTH (direction = contact normal flattened; magnitude = relative speed × bump_impulse_scale, min gate bump_min_relative_speed_mps, cap bump_lateral_cap_mps); KartTuning fields (those three, defaults 0.6 / 1.5 / 4.0; registration per precedent). The impulse must decay (motor lateral velocity is synthetic — design where the impulse lives: a decaying lateral offset velocity in the motor summed into velocity(), decay via existing drag fields — document; no new literals).
- [ ] TDD: two karts colliding at speed separate laterally, both sides, capped; below min speed = no bump; AI 6-kart bump-heavy race (tight grid, real physics 15s) — no stuck-detector spam (respawns ≤ baseline+1), no error spam; player run-active freeze unaffected. Suites → commit.

### Task 3: Temple Twilight
**Files:** Create `scenes/racing/track_temple_twilight.tscn` + `scenes/racing/race_temple_twilight.tscn` (+ solo variant): closed circuit ~600-750m from the village/interior kit under the firelit-night mood (Papu-night + brazier precedents: night Environment, torch posts with warm omnis where budget allows — shadowless, the platformer's brazier pattern), 10-14 gates with flags, arch, grid (player front — the R6 fix convention), 6+ item boxes (origin-clearance rule), pads: one boost strip on the main straight + one jump-pad corner cut (the jump must clear its gap: verify the trajectory vs the hop×scale math numerically), dressing to racing density, all lint rules green (the full track lint battery now: spine/gates/flags/arch/grid/boxes/pads/dressing-clearance).
- [ ] Track lint + scene tests + session integration (teleport-lap test + a bounded real-physics AI race — the East-turn-style wedge check for the NEW geometry: 20s, every AI healthy-or-recovered; tune corner radii if an AI wedges). Suites → commit.

### Task 4: Pad retrofits + menu/track registry
**Files:** Sanity Shores + graybox get 1-2 boost strips each (on-road, lint-clean); menu: refactor the now-6-entry racing menu into a small registry table (track id → display name → race/solo scenes) in game_root or a dedicated const table — mechanical, keep behavior identical, Temple entries added (RACE + TIME TRIAL).
- [ ] Registry refactor keeps all existing menu tests green (port, never weaken); Temple entries wired; retrofit pads lint-clean. Suites → commit.

### Task 5: The Cup (+save v3)
**Files:** Create `src/racing/flow/cup_session.gd` (orchestrates: race 1 Sanity Shores → standings interstitial → race 2 Temple Twilight → final cup standings; points from tuning `cup_points_by_place` — a per-place float array field? Godot tuning fields are scalars by precedent — design: 6 fields cup_points_place1..6 (8.0/6.0/5.0/4.0/3.0/2.0), registration per precedent; carry AI lineup/tints across races; player placement per race from the existing standings), HUD/UI: between-race standings panel + final cup podium text (label conventions), menu CUP entry (registry), save v2→v3: racing section gains `cups: {cup_id: {best_placement}}` — full migration rigor (v1→v3 chain: v1 file must still load through BOTH migrations; scratch-verify like the v1→v2 precedent; validation fail-closed).
- [ ] TDD: points math, cup flow state machine (headless: two races driven via the teleport-finish pattern, standings accumulate, final placement correct), save chain migration scratch tests (v1→v3, v2→v3, corrupt cups), menu wiring. Suites → commit.

### Task 6: Time-trial ghost (stretch — defer if strained)
**Files:** `src/racing/flow/ghost_recorder.gd` + `ghost_player.gd`: record player kart transform keyframes at a fixed interval (tuning field ghost_keyframe_interval_s=0.1) during SOLO runs; on a NEW best (the existing best-time write path), persist to `user://ghosts/<track_id>.ghost` (version header + interval + keyframes; corrupt/absent = no ghost, never errors); replay next solo run as a translucent kart visual (no collision, no character, palette-ghost material) interpolating keyframes. If implementation strains the phase, STOP, record the debt, and report — the Cup ships first.
- [ ] TDD: record/persist/load round-trip, corrupt-file silence, replay interpolation math, best-time-gated persistence. Suites → commit.

### Task 7: Integration, verification, R7 APK readiness
- [ ] E2E: a full Cup run headless (both tracks, real countdown/GO, teleport-finish races, standings chain, save write) with zero error spam; pads fired in a real race; a bump exchanged in a real race; full sweep (GUT/Py/lints/export verifier — new fields in pack); spec debt bookkeeping (debt #2 RESOLVED; ghost shipped-or-deferred; new debts); R7 summary. Orchestrator merges + builds.

## Self-Review
- Spec coverage: A→T1+T4, B→T2, C→T3, D→T5, E→T6, verification→T7. Menu registry folded into T4 where the 6-entry pain actually lands. Save v3 rigor named. No placeholders; defaults stated; tests per task.
