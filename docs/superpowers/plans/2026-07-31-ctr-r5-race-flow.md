# CTR Racing Mode — R5 (Race Flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The finale of the CTR loop per the racing spec's R5 phase: 3-2-1 countdown with the timed start boost, live position HUD, full results standings — plus resolution of the ledgered R5-binding debts (#6 countdown gating, #9 shared best-times).

**Architecture:** Pure cores (CountdownTimer, StartBoostJudge, RaceRanking) + session/HUD wiring. Karts spawn frozen (`set_run_active(false)`); GO unfreezes everyone — the AI agents' existing `is_run_active()` gate (R3 binding) makes countdown-freezing safe for the stuck detector BY CONSTRUCTION (verify with a test, don't assume). Ranking uses laps+gates+SpineFollower totals only (seam ruling).

## Global Constraints

Same as R4's (literals 0/1/-1 in `src/racing/**`; tuning provably live; TDD; suites green each commit — GUT 1136 / Py 250 / 5 lints baseline; grep raw GUT output for 'Parse Error'; known flakes island_slice stale-slide + camera_archetypes swing-frustum — re-run isolated; stage explicit paths; never stage the two other-agent WIP docs; feel gates human-only). Consumes the ledgered RaceTuning fields: `countdown_step_s`, `start_boost_window_s`, `start_bog_penalty_s` (leaving only `checkpoint_tolerance_m` unread — keep in debts).

---

### Task 1: Countdown + start boost

**Files:** Create `src/racing/flow/countdown_timer.gd` (pure: configure(race_tuning); tick(delta) → phase &"three"/&"two"/&"one"/&"go"/&"running" from `countdown_step_s`; elapsed accessors) and `src/racing/flow/start_boost_judge.gd` (pure: samples hop-held state each tick pre-GO; verdict at GO — held into the GO window (last `start_boost_window_s` before GO) → &"boost"; held earlier/longer than the window start → &"bog"; not held → &"none"). Modify `race_session.gd` (karts spawn frozen incl. player; countdown runs pre-race (PAUSABLE); at GO: `set_run_active(true)` all karts, apply verdict — boost → `apply_boost(turbo_boost_s`? NO — a dedicated field is wrong to invent; REUSE `boost_duration_s` from KartTuning for the launch boost seconds — document; bog → throttle held at zero for `start_bog_penalty_s` via a new controller hold... simplest: delay that kart's `set_run_active(true)` by `start_bog_penalty_s` — document the choice); the race timer starts AT GO (not during countdown); wrong-way + stuck detection quiescent pre-GO (verify via the run-active gates — TEST IT); AI get no start boost in R5 (document: player-skill mechanic; AI unfreeze plain at GO). `race_hud.gd`: countdown display (3/2/1/GO text), hold-to-boost affordance text. Retry resets the whole flow.
- [ ] TDD: countdown phase math; judge verdicts (held-into-window/held-too-early/not-held boundaries); karts frozen pre-GO (drive 1s of physics during countdown → zero displacement all karts, zero stuck respawns); timer starts at GO; bog delays one kart; boost applies same-tick at GO; pause mid-countdown freezes it; retry resets. Suites → commit.

### Task 2: Live position ranking

**Files:** Create `src/racing/flow/race_ranking.gd` (pure: rank entries {kart_id, laps_complete, gates_this_lap, total_progress_m, finished_at_order} — composite sort: finished (by finish order) > laps > gates > total progress; seam-safe by construction — totals only). Modify `race_session.gd` (per-kart ranking snapshot per tick — reuse the once-per-tick progress values (LOW-6 precedent: no duplicate closest-offset calls); AI validators' `race_complete` now RECORDED (finish order list + their elapsed at completion) — an AI that finishes keeps driving (unchanged) but its rank freezes at its finish slot). `race_hud.gd`: live "POS n / m" during the race (races only; hidden solo).
- [ ] TDD: ranking composite (each tier decisive; ties by totals); AI-finished-first freezes its slot while it keeps driving; HUD live updates; solo hidden. Suites → commit.

### Task 3: Results standings + best-times mode split (debt #9)

**Files:** `race_session.gd` + `race_hud.gd`: finish panel becomes full standings — ordered list 1..m (finished karts with their race elapsed; unfinished ranked by progress at player-finish, marked without times), player row highlighted; RULING lands debt #9 with ZERO schema risk: best total/lap times are WRITTEN only from solo time-trial sessions (`spawn_opponents == false` guard at the save call site in game_root's finish handler — read where store happens); races still DISPLAY the time-trial best as reference ("TT BEST mm:ss.mmm"). Spec debt #9 → RESOLVED with this ruling.
- [ ] TDD: standings order + times for finished/unfinished; race session finish does NOT write best times (seeded better race time → save unchanged) while solo still does; HUD reference line. Suites → commit.

### Task 4: Integration, verification, R5 APK readiness

- [ ] End-to-end: full race from countdown through standings on both tracks (seeded, real physics bounded); pause during countdown/race; retry mid-countdown; solo time-trial unaffected by countdown?? — DECISION: solo gets the countdown too (same start ritual, start boost works solo — it's a skill mechanic; document) but timer-starts-at-GO keeps TT times comparable (previous TT times started at spawn — note the epoch change in the report and TG summary: old best times remain but the start ritual changed). Full sweep (GUT/Py/lints/export verifier). Spec bookkeeping: strike consumed fields (leaving `checkpoint_tolerance_m` in debt #3), debt #6 RESOLVED (countdown gating verified), #9 RESOLVED. R5 summary report.

## Self-Review
- Spec R5 coverage: countdown+start boost, live positions, results screen, one-tap retry (exists since R1) — Tasks 1-3; APK step in Task 4.
- Bindings honored: #6 countdown gates via run-active (tested); #9 resolved save-side without schema change; seam ruling via totals-only ranking; 3 of 4 unread fields consumed.
- No placeholders; pure cores testable headless; every task carries tests.
