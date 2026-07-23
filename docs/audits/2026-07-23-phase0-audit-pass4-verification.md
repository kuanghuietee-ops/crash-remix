# Phase 0 audit — pass 4 (fix verification)

**Date:** 2026-07-23
**Auditor:** Claude (Opus 4.8), read-only static pass
**Verifies:** `2026-07-23-phase0-audit-pass3-disposition.md` against the actual code
**Chain:** static audit → disposition → pass-2 verification → pass-2 disposition →
pass-3 verification → pass-3 disposition → **this document**
**Method:** static reading only. Nothing executed — no Godot, no GUT, no hooks, no lint, no
build, no adb, no network. No repo file was modified by this audit.
**Repo state:** uncommitted (`git log` at `0c569ef`), no remote, no push. No device
installation, device acceptance, or Gate F was performed.

---

## Verdict: findings A and B both genuinely fixed

**Finding A — airborne momentum.** `src/gameplay/player/player_motor.gd:42-76` now has a real
`STATE_AIRBORNE` branch (constant declared `:6`). Zero input returns `horizontal` unchanged
(`:43-44`). With input, speed only ever increases toward `run_speed_mps × input_length`
(`:55-59`) and never decreases, so the slide-jump's ~8.59 m/s boost survives the flight.
Steering rotates the current direction toward the desired one by `maximum_change / current_speed`
radians (`:67-75`) — a sound arc-length turn-rate model. No new tuning constant, as claimed.

The regression at `tests/gameplay/test_player_motor.gd:148` is the correct test: it integrates
the motor at 1/60 across the full `air_time_for_height(slide_jump_height_m)` and asserts
travelled distance against `slide_jump_distance_m` with a tight `DISTANCE_TOLERANCE_M = 0.01`.
Zero-input momentum (`:187`) and steering (`:218`) are covered separately. The recorded
red-phase value **4.484751 m** matches the ~4.5 m derived independently in pass 3.

**Finding B — fixed-height high/slide jump.** `tap_height_for_impulse`
(`src/gameplay/player/player_controller.gd:171-182`) returns a height only for `IMPULSE_JUMP`
and `IMPULSE_DOUBLE_JUMP`; high-jump and slide-jump fall through to the `0.0` sentinel. Both
plumbing repairs verified:

- **Stale state** — `advance_logic:114-115` now writes the sentinel for every jump impulse
  (excluding only body slam), replacing the old `if tap_height_m > 0.0` guard. Without it, a
  slide-jump immediately after a normal jump would have inherited the previous 0.9 m clamp.
  This path was **not** in the pass-3 audit; it was found during the red phase and is real.
- **Zero-height no-op** — `src/gameplay/player/jump_kinematics.gd:82` returns unchanged
  velocity when `tap_height_m <= 0.0`, closing the path where the mapping change alone drove
  both moves to zero.

Controller regressions at `tests/gameplay/test_player_controller.gd:114` and `:139` exercise
the full path with a 10 ms hold and assert the authored launch speed survives.

**Independent static checks:** `src/gameplay/**` numeric-literal scan clean; Phase 0.5
vocabulary scan clean; **100** `func test_` and **16** `def test_`, matching the disposition;
`build/crash-remix-debug.apk` hashes to
`b5d069945be0237853ac55a85f19213611388fccb07fff91c7a775d856fbc8e5`, matching the disposition
exactly. The unchanged fingerprint `8cc9cc6a…` is consistent with a wiring-only batch.

---

## For the agent fixing this

Read `/root/CLAUDE.md` and `/root/crash-remix/CLAUDE.md` first.

- **TDD.** Failing test first, then the fix.
- **No gameplay numeric literals** in `src/gameplay/**`. New numbers go in `MoveTuning` +
  `data/tuning/move.tres` and must be added to `catalog_is_usable`.
- **Grep every call site** of any changed signature. `PlayerMotor.horizontal_velocity` is
  called from `player_controller.gd:92` and from `tests/gameplay/test_player_motor.gd`.
- **Stage explicit paths.** Never `git add -A`, `git add .`, `git commit -a`,
  `git checkout -- <path>`.
- **Never mark a gate passed.** Gate F and §11.4 acceptance are operator-only.
- **Baseline:** 100 GUT test functions, 16 Python test functions (counted statically).
- **Finding 1 below is an operator decision.** Do not implement a behaviour change until the
  operator has chosen. Finding 2 and the notes are safe to action.

---

## 1. MEDIUM — body slam is an airborne state that still receives ground braking

**File:** `src/gameplay/player/player_motor.gd:42` (branch condition), `:78-89` (ground branch
it falls through to), reached via `src/gameplay/player/player_controller.gd:90-98`

The new branch matches only `STATE_AIRBORNE`. `STATE_BODY_SLAM` falls through to the ground
branch, so a slamming player is braked with ground constants. Before this batch every airborne
state braked, so behaviour was uniform; now the two diverge, and the divergence is a
consequence of branch ordering rather than a stated decision.

**Measured from the authored tuning.** From a slide-jump at 8.589 m/s:

- Stick released → `transition_time = stop_time_s` (0.04), `transition_speed = run_speed_mps`
  (7.0) → `maximum_change` ≈ 2.92 m/s per frame → horizontal reaches zero in three frames
  (~50 ms); the player drops near-vertically.
- Stick held → settles to 7.0 m/s and keeps travelling.

Honest magnitude: over a slam from ~1.4 m the landing-position difference is roughly 0.25 m;
from ~4 m about 1 m. Small — but it is the same invisible input-dependence that finding B just
removed from high-jump and slide-jump.

It matters where slam is used as intended. §4.2 calls it the "end this jump NOW" panic verb, so
a player sailing past a small pad will slam to drop onto it. Whether they brake or keep 7 m/s
decides whether they land on `PrecisionPadB` (1.4 m deep, `scenes/game.tscn:44-47`) or past it
— Gate F criterion 3 territory.

**Options — operator picks one:**

1. **Brake during slam (current behaviour, made explicit).** Add `STATE_BODY_SLAM` to the
   condition at `:42` as a deliberate *exclusion* with a comment explaining that a committed
   descent kills horizontal drift on purpose. No behaviour change; removes the fall-through.
2. **Preserve momentum during slam.** Include `STATE_BODY_SLAM` in the airborne branch so slam
   inherits the same momentum rule. Makes slam a pure vertical *addition* to the existing arc.
3. **Separate slam constant.** New `MoveTuning` field for slam horizontal damping, validated in
   `catalog_is_usable`, so the operator can tune it at the drawer.

Recommendation if asked: option 1 — it preserves the current feel, costs one line plus a
comment, and turns an accident into a decision. Option 3 only if Gate F says the slam feels
wrong.

Whichever is chosen, add a motor test asserting slam horizontal behaviour explicitly, so this
cannot silently change again.

## 2. LOW — `respawn()` does not reset the release profile

**File:** `src/gameplay/player/player_controller.gd` — `respawn()`; field declared `:33`,
seeded `:57`, written `:115`, read `:326`

`respawn()` resets the state machine, velocity, fall apex and intent buffer, but not
`_active_jump_tap_height_m`. Verified: zero occurrences of the field inside the function.

Harmless today, because every jump impulse writes the profile earlier in the same frame than
`_apply_jump_release` reads it. But if any future path consumes a release before an impulse, a
respawned player inherits the previous life's profile. One line alongside the other reset
state, ideally re-seeding from `_move_tuning.jump_tap_height_m` as `configure:57` does.

---

## Notes (no change requested)

- Air steering authority is now inversely proportional to speed
  (`src/gameplay/player/player_motor.gd:67`). At the slide-jump's 8.59 m/s that is ~0.17
  rad/frame (~583°/s); at run speed ~0.21 rad/frame (~717°/s). Both ample, so no defect — but
  it is an undocumented emergent property of the chosen model. Worth a comment so nobody later
  "fixes" it as a bug.
- Incidental improvement: the momentum-preserving branch makes the landing ring *more*
  accurate. `DepthPrediction.trajectory_points` propagates horizontal velocity unchanged, which
  previously disagreed with a motor that decayed it toward `run_speed_mps`. Prediction and
  simulation now share the same horizontal model with no input, and prediction is merely
  conservative with input.

---

## Unverified by this pass

Nothing was executed. GUT 100/100 with 544 assertions, Python 16/16, both red-phase
reproductions, the lint/tripwire/hook/bash/call-site scans, `git diff --check`, the headless
boot, the Vulkan smoke test, and certificate SHA-256 `1075362a…` are claims not reproduced
here. The APK **hash** was verified; the package itself was not opened, so its manifest, SDK
levels, ABI and signature remain unverified by me.

H4, H11, L9, pass-2 finding 10, device acceptance A–C and Gate F all remain correctly open and
operator-only.

**Assessment:** the cleanest batch of the four. Finding A is fixed at the right layer with an
end-to-end test rather than an impulse-level one, and the stale-state path found during the red
phase was a genuine defect absent from the pass-3 audit. Nothing here blocks the device
session; item 1 is worth resolving before Gate F only because it is cheap and touches
criterion 3.
