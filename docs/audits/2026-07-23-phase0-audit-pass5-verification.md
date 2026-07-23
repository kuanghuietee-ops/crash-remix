# Phase 0 audit — pass 5 (final fix verification)

**Date:** 2026-07-23
**Auditor:** Claude (Opus 4.8), read-only static pass
**Verifies:** `2026-07-23-phase0-audit-pass4-disposition.md` against the actual repository
**Chain:** static audit → disposition → pass-2 verification → pass-2 disposition →
pass-3 verification → pass-3 disposition → pass-4 verification → pass-4 disposition →
**this document**
**Method:** static reading only. Nothing executed — no Godot, no GUT, no hooks, no lint, no
build, no APK installation, no adb, no network. No repository file was modified by this audit.
**Repo state:** uncommitted (`git log` at `0c569ef`), no remote, no push. No device
installation, device acceptance, or Gate F was performed or marked passed.

**Scope of this pass:** the two items dispositioned in pass four, plus regression checks
across the areas closed in passes one through four.

---

## Result

**All claims in the pass-four disposition verify.** No remaining findings. One minor
test-quality observation and one process note are recorded below; neither is a defect and
neither blocks the device session.

Files changed since the pass-four audit — `src/gameplay/player/player_motor.gd`,
`src/gameplay/player/player_controller.gd`, `tests/gameplay/test_player_motor.gd`,
`tests/gameplay/test_player_controller.gd`, and the disposition itself. No tuning resource,
scene, script, hook or export file was touched, which is consistent with the claim that the
authored fingerprint `8cc9cc6a…` is unchanged.

---

## Point-by-point verification

### 1. Body slam explicitly excluded from the airborne momentum model — **CONFIRMED**

`src/gameplay/player/player_motor.gd:18-26` introduces
`uses_airborne_momentum_model(state) -> bool`, matching `STATE_AIRBORNE → true` and
`STATE_BODY_SLAM → false`, with the intent documented in place:

> *"A committed descent deliberately brakes horizontal drift so the panic verb can target a
> nearby landing rather than overshoot it."*

`STATE_BODY_SLAM` is declared at `:7`. `horizontal_velocity:54` now dispatches through the
helper instead of a bare `state == STATE_AIRBORNE` comparison, so a slamming player falls
through to the ground branch at `:92-103` and retains committed-descent braking. Runtime
behaviour is unchanged from pass four, exactly as Option 1 specified — the change converts a
branch-ordering accident into a named, commented policy decision.

The airborne branch itself (`:54-90`) is byte-for-byte the model verified in pass four, with an
added comment at `:79-80` recording that higher momentum intentionally turns through a smaller
angle for the same acceleration budget.

### 2. `test_body_slam_explicitly_uses_committed_ground_braking` can genuinely fail — **CONFIRMED**

`tests/gameplay/test_player_motor.gd:118-155`. Three independent assertions:

1. **Policy exists** — walks `get_script_method_list()` for `uses_airborne_momentum_model` and
   asserts it is present. This is the assertion the disposition's red phase records as failing
   before the method existed.
2. **Classification** — `assert_true(… "airborne")` and `assert_false(… "body_slam")`.
3. **Real deceleration** — calls `horizontal_velocity` with a slide-jump launch speed
   (`horizontal_speed_for_jump(5.5, 1.4)` ≈ 8.589 m/s), zero input, state `body_slam`, one
   1/60 frame. Asserts the result equals `8.589 − run_speed_mps / stop_time_s × 1/60`
   ≈ **5.672 m/s** within `FLOAT_TOLERANCE` (0.0001), and separately asserts
   `velocity.length() < current_speed`.

Mutation-checked by reading:

| Mutation | Caught? |
|---|---|
| `STATE_BODY_SLAM: return true` | ✅ classification assert fails **and** deceleration assert fails (momentum branch would return 8.589 unchanged) |
| Remove `uses_airborne_momentum_model` entirely | ✅ method-existence assert fails |
| `STATE_AIRBORNE: return false` | ✅ classification assert fails; the three finding-A tests also fail |
| Route `body_slam` into the momentum branch | ✅ both deceleration asserts fail |

The 5.672 m/s figure is consistent with the pass-three disposition's independently recorded
red-phase value of 5.672149 m/s, which corroborates the arithmetic across documents. The
expected value mirrors the implementation formula, but the paired `assert_lt` means the test
is not tautological — it verifies real horizontal deceleration, not just formula agreement.

*See the test-quality observation below for the one mutation this test does not catch.*

### 3. `respawn` restores the authored normal jump-release profile — **CONFIRMED**

`src/gameplay/player/player_controller.gd` — `respawn()` now contains:

```gdscript
if _move_tuning != null:
    _active_jump_tap_height_m = _move_tuning.jump_tap_height_m
```

placed alongside the other reset state (state machine, velocity, fall apex, intent buffer), and
correctly guarded against unconfigured tuning.

`tests/gameplay/test_player_controller.gd` —
`test_respawn_restores_default_jump_release_profile` drives the controller through a real
crouch → high-jump, asserts the active profile is the `0.0` fixed-height sentinel, calls
`respawn()`, then asserts the profile equals `jump_tap_height_m`. It would fail at 0.0 vs 0.9
without the fix, matching the recorded red-phase values.

### 4. High-jump and slide-jump remain fixed-height — **CONFIRMED**

`tap_height_for_impulse` (`player_controller.gd:171-182`) returns a height only for
`IMPULSE_DOUBLE_JUMP` and `IMPULSE_JUMP`; `IMPULSE_HIGH_JUMP` and `IMPULSE_SLIDE_JUMP` fall
through to `return 0.0`. `jump_kinematics.gd:82` no-ops on `tap_height_m <= 0.0`.
`advance_logic:114-115` still writes the sentinel for every jump impulse except body slam, so
the stale-profile path closed in pass four remains closed. Regressions intact at
`test_player_controller.gd:114` (high jump) and `:138` (slide jump).

### 5. Normal and double jumps remain variable-height — **CONFIRMED**

`IMPULSE_JUMP → jump_tap_height_m`, `IMPULSE_DOUBLE_JUMP → double_jump_tap_height_m`.
Covered by `test_controller_applies_variable_release_and_terminal_fall_speed:53` and
`test_double_jump_release_uses_its_own_tap_height:75`, the latter a differential test that
overrides `double_jump_tap_height_m` to 1.3 on a tuning variant and asserts the release honours
it rather than the ground-jump value.

### 6. Full-airtime slide-jump distance and airborne momentum intact — **CONFIRMED**

All three finding-A regressions present and unmodified:
`test_slide_jump_travels_authored_distance_across_full_airtime:190`,
`test_releasing_stick_in_air_preserves_slide_jump_momentum:229`,
`test_air_input_steers_without_spending_slide_jump_boost:260`. The first still integrates the
motor at 1/60 across the full `air_time_for_height(slide_jump_height_m)` and asserts travelled
distance against `slide_jump_distance_m` at `DISTANCE_TOLERANCE_M = 0.01`. The airborne branch
they guard is unchanged.

### 7. No regressions introduced — **CONFIRMED**

| Check | Result |
|---|---|
| Numeric literals in `src/gameplay/**` | Clean — nothing beyond `0`/`1` |
| Phase 0.5 vocabulary in `src/`, `scenes/`, `data/tuning/` | Clean |
| `horizontal_velocity` signature | Unchanged (6 params); sole runtime call site `player_controller.gd:92`; all test call sites consistent |
| `uses_airborne_momentum_model` | New; called from `player_motor.gd:54` and the test only |
| Tuning wiring | No `data/tuning/**` or `src/tuning/**` file changed since pass four — fingerprint claim consistent |
| Duplicate test names | None |
| Test quality | No new tautological tests; both new tests fail under real mutations |

### 8. Static test counts — **CONFIRMED**

`grep -c '^func test_'` across `tests/**/*.gd` → **102**.
`grep -c '    def test_'` across `tests/**/*.py` → **16**.
Both match the disposition exactly.

### 9. APK hash — **CONFIRMED**

`build/crash-remix-debug.apk` (83,929,480 bytes, 05:54) hashes to:

```
cb2b4b279a976602650542c3e93f49e9a731b253649ea1a786252f21d3463c0d
```

Byte-identical to the disposition and to the hash supplied for verification. The package was
**not** opened or installed, so its manifest, SDK levels, ABI, permissions and signature remain
unverified by this pass.

---

## Observation (not a defect, no change requested)

**The `assert_false(uses_airborne_momentum_model("body_slam"))` assertion is
non-discriminating for the documentation intent.** `uses_airborne_momentum_model` returns
`false` from its default branch as well as from the explicit `STATE_BODY_SLAM` case, so
deleting the explicit case and its comment would leave behaviour identical and the assertion
still green.

This is the one mutation the test does not catch, and it is close to untestable — no assertion
can prove a comment exists. The method-existence check at `:120-127` does lock the more
important property: that the policy remains a named, callable decision point rather than
dissolving back into branch ordering. Recording it so nobody later reads that assertion as
stronger than it is.

---

## Process note

The working tree now carries **51 uncommitted entries** across five fix batches, still at
`0c569ef`. Not a defect, and the repo rules correctly forbid unprompted commits — but this tree
is shared with other agents, and there is no baseline to diff the next batch against. Worth an
explicit-path commit before any further work, per `/root/CLAUDE.md` git hygiene.

---

## Unverified by this pass

Nothing was executed. The following remain claims I did not reproduce: GUT 102/102 with 554
assertions; Python 16/16; both red-phase reproductions (100/101 and 101/102); the numeric lint,
vocabulary tripwire, pre-commit hook, Bash syntax and `git diff --check` results; the headless
120-frame boot; the Vulkan Forward Mobile smoke test; the authored tuning fingerprint
`8cc9cc6a…`; and certificate SHA-256 `1075362a…`. The APK **hash** was verified; the package
contents were not.

**Still open and operator-only:** H4 (landing-ring query budget — real-phone profile and
20-minute thermal soak), H11 (runtime-authored `.tres` loading inside the signed APK — device
acceptance step B), L9 (combat targets and hit callbacks, blocked until after Gate F), pass-two
finding 10 (ledge-nudge stickiness on deliberate short hops — a Gate F feel observation),
device acceptance A–C, and Gate F itself.

---

## Assessment

The audit chain closes clean. Every finding raised across five passes is now either fixed and
independently verified, or explicitly deferred to a human gate with the gate named. The two
pass-four items were small and both were fixed at the right layer: the body-slam policy became
an explicit documented decision without changing behaviour, and the respawn reset landed
alongside the state it belongs with.

Phase 0 is ready for the operator to run the §11.4 device acceptance test (A, B, C) and then
Gate F. Neither is passed, attempted, or inferred here — and per `CLAUDE.md` rule 3, no agent
may mark either one.
