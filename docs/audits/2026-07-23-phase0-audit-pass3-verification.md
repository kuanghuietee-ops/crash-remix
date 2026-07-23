# Phase 0 audit — pass 3 (fix verification)

**Date:** 2026-07-23
**Auditor:** Claude (Opus 4.8), read-only static pass
**Verifies:** `2026-07-23-phase0-audit-pass2-disposition.md` against the actual code
**Chain:** `2026-07-23-phase0-static-audit.md` → `…-fix-disposition.md` →
`…-pass2-verification.md` → `…-pass2-disposition.md` → **this document**
**Method:** static reading only. Nothing was executed — no Godot, no GUT, no pre-commit hook,
no lint, no vocabulary check, no build, no APK inspection, no adb, no network. No file in the
repo was modified by this audit.
**Repo state:** uncommitted (`git log` still at `0c569ef`), no remote push. No device
installation, device acceptance, or Gate F was performed.

> **Nothing below was confirmed by running anything.** Every number in the pass-2
> disposition's "Independent automated verification" section — GUT 95/95 with 530 assertions,
> Python 16/16, hook/lint/tripwire/bash/`git diff --check` results, headless boot, the Vulkan
> smoke test, fingerprint `8cc9cc6a…`, certificate SHA-256 `1075362a…`, APK SHA-256
> `14515da0…` — is **unverified by this pass**. The APK at `build/crash-remix-debug.apk`
> (83.9 MB) was not opened or inspected.

---

## Verdict on pass 2: all twelve dispositions verify

Traced independently against the code, not against the disposition's own evidence.

| # | Claim | Verified at |
|---|---|---|
| 1 | Air JUMP+DOWN discards the losing DOWN edge | `src/gameplay/player/player_state_machine.gd:198` consumes **before** the `_pending_impulse` check at `:199`, so the press cannot re-fire next frame. Test `tests/gameplay/test_player_state_machine.gd:263` now asserts `none`. Matches the ratified ground policy at `:99-107`. |
| 2 | Hurtbox non-monitorable | `scenes/player/player.tscn:64` — layer-2 self-detection by Spin/Slam masks closed. |
| 3 | D-pad precedence during motion events | `src/gameplay/input/gamepad_input.gd:41-47`, mirroring `:59-68`. |
| 4 | Poll accumulator-gated | `src/ui/touch_controls.gd:89-97`; interval from `layout_metrics_poll_interval_s = 0.5`; `size_changed` still connected at `:28`. |
| 5 | Keystore pinned and verified | `scripts/android_debug_keystore.b64` (confirmed **not** gitignored), restored at `scripts/deploy_android.sh:87`, SHA-256 verified at `:94-99`, `INSTALL_FAILED_UPDATE_INCOMPATIBLE` caught at `:136-141` with the explicit `user://tuning/override.tres` warning. |
| 6 | Validator guarantees playability | `src/tuning/tuning_service.gd:120-147` — fall speed, respawn floor, jump/coyote/action windows, tap/full relationships, poll interval. |
| 7 | Renamed, identifier-scoped tripwire | `scripts/check_phase0_vocabulary.py` tokenizes `.gd`, strips comments and quoted prose, matches structural `.tscn` names. |
| 8 | Drawer rebuild removes before freeing | `src/debug/tuning_debug_ui.gd:151-152`. |
| 9 | O(1) probe predicate | `src/gameplay/depth/depth_prediction.gd:59`; per-frame allocation and linear `.has()` scan gone. |
| 10 | Deferred to Gate F | No movement change made; `docs/qa/phase0-device-acceptance.md` updated to call out deliberate short hops. |
| 11 | Multiple exclusion controls | `src/ui/touch_controls.gd:221-226`; both HUD and Drawer registered at `src/core/phase0_game.gd:38-45`. |
| 12 | Independent double-jump tap height | `src/gameplay/player/player_controller.gd:171-182`, tracked in `_active_jump_tap_height_m`, seeded at `configure:57`, only overwritten when `> 0.0` (`:114-115`) so `IMPULSE_NONE`/`IMPULSE_BODY_SLAM` can never zero it. `velocity_after_release` signature change propagated to its single call site (`:325`) and both tests (`test_player_state_machine.gd:303`, `:311`). |

Both dispositions I disputed in pass 2 (finding 1 and finding 5) are properly resolved.

Independent static checks run by this pass: test counts match the disposition exactly
(**95** `func test_`, **16** `def test_`); `src/gameplay/**` contains no numeric literal other
than `0`/`1`; no prohibited Phase 0.5 vocabulary appears in `src/`, `scenes/` or `data/tuning/`;
the only stale reference to the old `check_phase0_scope.py` name is inside the pass-2 audit
document, which is a historical record and correct to leave.

---

## For the agent fixing this

Rules unchanged. Read `/root/CLAUDE.md` and `/root/crash-remix/CLAUDE.md` first.

- **TDD.** Failing test first. For finding A below, the test must assert the *authored
  distance actually travelled*, not the impulse velocity — the existing tests pass while the
  bug is live precisely because they stop at the impulse.
- **No gameplay numeric literals** in `src/gameplay/**`. New air-control numbers go in
  `MoveTuning` + `data/tuning/move.tres`, and must be added to `catalog_is_usable`.
- **Grep every call site** of any changed signature. `PlayerMotor.horizontal_velocity` is
  called from `player_controller.gd:90` and from `tests/gameplay/test_player_motor.gd`.
- **Stage explicit paths.** Never `git add -A`, `git add .`, `git commit -a`,
  `git checkout -- <path>`.
- **Never mark a gate passed.** Gate F and §11.4 acceptance are operator-only.
- **Baseline for comparison:** 95 GUT test functions, 16 Python test functions (counted
  statically, not by running them).

**Fix order:** A first — it is the only thing that should block the device session. B is an
operator decision and must not be changed blind.

---

## A. HIGH — no air-control model; the slide-jump's authored distance never reaches the player

**File:** `src/gameplay/player/player_motor.gd:42-53`

`horizontal_velocity` branches on `STATE_SLIDING` (`:32-40`) and `STATE_CROUCHED` (`:43-44`)
only. **Airborne falls through to the identical ground acceleration and deceleration.** There
is no `STATE_AIRBORNE` branch anywhere in the motor.

### A1. The slide-jump boost is erased in about two physics frames

`impulse_velocity:84-88` sets horizontal speed to
`horizontal_speed_for_jump(slide_jump_distance_m=5.5, slide_jump_height_m=1.4)`.

Computed from the authored tuning (`gravity_mps2=24`, `apex_gravity_multiplier=0.85`,
`fall_gravity_multiplier=1.6`, `apex_velocity_threshold_mps=1.0`):

```
apex_band_height = 1² / (2 × 20.4)                       ≈ 0.0245 m
upward_speed(1.4) = sqrt(1 + 2×24×(1.4 − 0.0245))        ≈ 8.187 m/s
rise_time  = (8.187 − 1)/24 + 1/20.4                     ≈ 0.3485 s
fall_time  = 1/20.4 + (−1 + sqrt(1 + 2×38.4×1.3755))/38.4 ≈ 0.2919 s
air_time(1.4)                                            ≈ 0.6404 s
horizontal_speed_for_jump = 5.5 / 0.6404                 ≈ 8.59 m/s
```

On the **next** frame the state is `airborne`, so the motor targets `run_speed_mps` (7.0) with
`maximum_change = run_speed_mps / run_time_to_speed_s × delta` = `7.0 / 0.08 × 1/60`
≈ 1.46 m/s per frame. The velocity decays 8.59 → 7.13 → 7.00 in roughly 33 ms.

**Actual travel ≈ 7.0 × 0.640 ≈ 4.5 m, against an authored 5.5 m.**

`slide_jump_distance_m` is therefore effectively a dead tuning value: raising it to 8.0 would
alter two frames and nothing else. This is the dead-wire class CLAUDE.md rule 2 exists to
catch, and **the fingerprint tripwire structurally cannot see it** — the hash moves, the value
loads correctly, and `run_speed_mps` governs the outcome regardless. Verifying the tuning loop
does not verify that a tuned number reaches the behaviour it names.

### A2. Releasing the stick mid-air stops horizontal motion in about 40 ms

With zero input, `:49-51` sets `transition_time = stop_time_s` (0.04) and
`transition_speed = run_speed_mps` (7.0), giving
`maximum_change = 7.0 / 0.04 × 1/60` ≈ 2.92 m/s per frame — 7.0 m/s to zero in ~2.4 frames.
The player drops vertically.

This contradicts §4.2's "Double jump … full air steering" and makes every gap crossing require
a continuously held stick. On touch, a thumb that lifts or slides off the floating stick
mid-jump is a death.

### Why this blocks the device session

Authored gaps in `scenes/game.tscn:64-82`: LongGapLaunch→PadA **4.5 m**, PadA→PadB **5.0 m**,
PadB→PadC **5.0 m**. With A1 applied, a *held* slide-jump reaches ~4.5 m — marginal on the
first gap and short on the other two.

- **Gate F criterion 4** — "slide-jump chain across 3 authored long gaps, clean by attempt
  five" — can fail for a reason that is not feel.
- **Gate F criterion 3** — ten into-screen jumps onto small pads — is exposed to A2.

### Honest provenance

**This is pre-existing, not a regression introduced by any fix batch.** `player_motor.gd:42-53`
is unchanged in substance since the original Phase 0 build. I missed it in audit passes 1 and 2.

### Fix direction

Add an airborne branch to `horizontal_velocity` with its own tuned constants — at minimum an
air-acceleration and an air-friction, both new `MoveTuning` fields with entries in
`data/tuning/move.tres` and validation in `catalog_is_usable`. Two shapes worth considering:

1. **Momentum-preserving** (matches the trilogy and the spec's framing of slide-jump as a tech
   move): in air, do not decelerate toward `run_speed_mps` at all. Allow the stick to steer
   direction and to accelerate *up to* `run_speed_mps`, but never reduce a horizontal speed
   already above it. Zero input in air preserves the current velocity rather than braking.
2. **Explicit air constants**: separate `air_acceleration_mps2` and `air_friction_mps2`, both
   far smaller than the ground values, applied only when `state == STATE_AIRBORNE`.

Prefer (1) unless the operator says otherwise — it makes `slide_jump_distance_m` mean what it
says and removes A2 without adding tuning surface.

**Test first, and test the right thing.** The existing motor tests pass while this bug is live
because they stop at the impulse. The new test must integrate: apply the slide-jump impulse,
step the motor at 1/60 for `air_time(slide_jump_height_m)`, and assert the horizontal distance
travelled is within tolerance of `slide_jump_distance_m`. Add a second test that asserts zero
stick input in air does not reduce horizontal speed below the value the impulse set.

Note `run_time_to_speed_s` and `stop_time_s` must keep their current ground behaviour — the
four partial-frame motor tests fixed in H9 cover that and must stay green.

---

## B. MEDIUM — slide-jump and high-jump inherit the variable-height tap clamp

**File:** `src/gameplay/player/player_controller.gd:178-181`

`tap_height_for_impulse` maps `IMPULSE_JUMP`, `IMPULSE_HIGH_JUMP` **and** `IMPULSE_SLIDE_JUMP`
to `jump_tap_height_m` (0.9 m). A JUMP release shorter than `minimum_hop_release_s` (90 ms)
therefore clamps all three to a 0.9 m apex.

- **High jump** is authored at 2.9 m. `HighJumpLedge` tops out at 2.6 m
  (`scenes/game.tscn:95-97`). A tapped high jump reaches 0.9 m and cannot reach the ledge at all.
- **Slide-jump** authored at 1.4 m. Tapped, air time falls from ~0.640 s to ~0.519 s, cutting
  distance to ~3.6 m once finding A is applied.

Both are triggered by DOWN-then-JUMP in fast succession, where a short hold is the natural
thumb motion. So "cleared the gap" versus "fell short" is decided invisibly by contact
duration. §4.2 describes slide-jump as a fixed tech move ("~5.5m at 1.4m height"), not a
variable-height jump.

The behaviour predates this batch, but finding 12's fix turned the mapping into an explicit
enumeration without asking whether those two belong in it.

**Do not change blind — this is an operator decision.** The options are: exempt
`IMPULSE_HIGH_JUMP` and `IMPULSE_SLIDE_JUMP` from the clamp entirely (return `0.0` and let
`velocity_after_release` no-op, which it already does for non-positive tap heights); give each
its own tap-height tuning field as was done for double jump; or keep the current shared clamp
as intended tech depth. Ask before implementing.

---

## Notes (no code change requested)

- `src/tuning/tuning_service.gd:133` — `respawn_floor_y_m >= 0.0` is a sign check, not a
  geometry check. `-0.01` passes validation but sits above the play surface at y = 0, so
  floor-snap dip could trigger respawn. Bounded and recoverable via RESET TO AUTHORED; worth a
  comment rather than a code change.
- `scripts/check_phase0_vocabulary.py:70-94` — the `.gd` tokenizer path silently degrades to
  line-based regex scanning on `TokenError`/`IndentationError`. This is the *opposite* of the
  H8 numeric-lint problem and is correct here: the fallback scans more aggressively, erring
  toward false positives, and this script is an explicit early-warning tripwire rather than a
  hard gate.

---

## Still gated on the operator / a device

- **H4** — landing-ring query budget. Finding 9 removed the selection overhead; the ray
  workload still needs a real-phone profile and the 20-minute thermal soak.
- **H11** — signed-APK loading of a runtime-authored `.tres` override still requires
  acceptance step B. Finding 5's pinned certificate removes the reinstall hazard that
  compounded this.
- **L9** — combat targets and hit callbacks correctly blocked until after Gate F.
- **Pass-2 finding 10** — ledge-nudge stickiness on deliberate short hops is a Gate F feel
  observation, now written into the device procedure.
- **Device acceptance A–C and Gate F** — not run, not marked passed.

---

## Assessment

The pass-2 batch is clean: all twelve fixes are real, both previously disputed dispositions are
properly resolved, and the one changed signature was propagated everywhere including tests.

Finding A is the single thing worth fixing before the operator spends a session on the phone.
It is not a regression from any fix batch — it has been there since the original build and I
missed it twice — but Gate F criteria 3 and 4 can fail on it for reasons that have nothing to
do with feel, which is the worst possible outcome for a gate whose entire purpose is to
measure feel.
