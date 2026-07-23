# Phase 0 audit — pass 2 (fix verification)

**Date:** 2026-07-23
**Auditor:** Claude (Opus 4.8), read-only static pass
**Verifies:** `2026-07-23-phase0-audit-fix-disposition.md` against the actual code
**Source audit:** `2026-07-23-phase0-static-audit.md`
**Method:** static reading only. Nothing was executed — no Godot, no GUT, no pre-commit
hook, no lint, no scope check, no build, no APK, no adb, no network. No file in the repo
was modified by this audit.
**Repo state at time of audit:** uncommitted (`git log` still at `0c569ef`), no remote push.
Device acceptance and Gate F remain unpassed and are not addressed here.

> **Nothing below was confirmed by running anything.** Every claim in the disposition's
> "Final automated verification" section — 90/90 GUT, 12/12 Python, lint/scope/hook results,
> headless boot, Vulkan smoke test, fingerprint `b112f12b…`, APK SHA-256 `42938dc4…` — is
> **unverified by this pass**. I read code; I did not reproduce those results.

---

## For the agent fixing this

Same rules as pass 1. Read `/root/CLAUDE.md` and `/root/crash-remix/CLAUDE.md` first.

- **TDD.** Failing test first, then the fix. Finding 1 below exists partly *because* a test
  was written that asserts the surviving defect as correct — check what a test locks in
  before you trust it.
- **No gameplay numeric literals** in `src/gameplay/**`. The `ScalarMath` relocation
  (`src/core/scalar_math.gd`) is the accepted pattern for universal math constants; do not
  put gameplay values there.
- **Stage explicit paths.** Never `git add -A`, `git add .`, `git commit -a`,
  `git checkout -- <path>`. Shared tree — run `git status --porcelain` first.
- **Never mark a gate passed.** Gate F and the §11.4 acceptance test are operator-only.
- **Report test counts.** Current baseline for comparison: 90 GUT test functions, 12 Python
  test functions (counted statically from `func test_` / `def test_`, not by running them).

**Suggested fix order:** 1 → 3 → 4 → 5 → 2 → the rest.
1, 3, 4 and 5 should land before the device session. 2 should land before any hit callback
exists. 6 and 7 are scope/documentation decisions rather than defects — see "Operator
decisions still needed".

---

## Dispositions I could not accept as written

Two entries in the disposition are marked FIXED but do not hold up.

| ID | Claimed | Actual | See |
|---|---|---|---|
| B1 | FIXED | Mechanism changed; player-visible outcome unchanged. The slam now fires one frame later instead of overwriting the impulse. The regression test asserts this as correct. | Finding 1 |
| M13 | FIXED | The keystore *procedure* is reproducible; the *certificate* is not. Regeneration breaks `adb install -r` and the natural recovery wipes `user://`. | Finding 5 |

Everything else in the disposition verified. Independently traced and confirmed fixed:
**B2, H1, H2, H3, H5, H7, H8, H9, H10, H12, M1–M6, M8–M12, M14, M15, M17, L1, L2, L4–L8.**
**H4, H11, L9** remain correctly DEFERRED. **M16 NOT APPLICABLE** verified — `velocity_after_release`
only clamps positive `velocity.y`, and every positive Phase 0 impulse is jump-family.

Independent checks run by this pass (static, by grep): `src/gameplay/**` contains no numeric
literal other than `0`/`1`; no prohibited Phase 0.5 term appears in `src/`, `scenes/` or
`data/tuning/`.

---

## HIGH

### 1. B1 is fixed in mechanism but not in outcome — the slam lands one frame later

**Files:** `src/gameplay/player/player_state_machine.gd:192-193`
**Contradicted by:** `src/gameplay/player/player_state_machine.gd:99-107`
**Locked in by:** `tests/gameplay/test_player_state_machine.gd:242-264`

`_process_air_down` now returns early when `_pending_impulse != IMPULSE_NONE`, so the double
jump is no longer overwritten. But it returns **before** `consume_pressed`, so the DOWN press
remains in the buffer with its full 150 ms `action_buffer_s` window.

**Failure scenario.** Airborne, ground jump spent. JUMP and DOWN pressed together.

1. Frame N: `_process_jump` fires `double_jump`, consumes JUMP, clears `_double_jump_available`,
   sets state `airborne`. `_process_air_down` bails at `:192`. DOWN stays queued.
2. Frame N+1 (16.6 ms later): `_pending_impulse` is `IMPULSE_NONE`, state is still `airborne`,
   DOWN is still inside its window → body slam fires.
3. `velocity.y` goes from `upward_speed_for_height(1.8)` to `-22.0` after roughly 0.16 m of rise.

From the thumb this is the original blocker: *pressed JUMP, slammed instead, double jump gone*.
Gate F criterion 3 is affected exactly as before.

**The test asserts the defect.** `test_double_jump_wins_one_frame_without_consuming_buffered_slam`
asserts `body_slam` on the second frame (line 263). The suite will not surface this.

**Internally inconsistent with the ground path.** `_process_ground_actions:99-107` explicitly
consumes and discards the losing DOWN press so it cannot re-fire next frame — which is the
M15 policy the operator ratified ("discards the losing DOWN edge, preventing … a next-frame
slam"). The air path does the opposite for the same input pattern. Only the ground policy was
signed off.

**Fix direction.** Apply the ratified M15 policy to the air path: when JUMP wins arbitration
in air, consume and discard the losing DOWN press, matching `:99-107`. Then rewrite the test
to assert the slam does **not** fire on the following frame. If the operator instead wants the
queued slam to survive, that is a different decision and needs stating — but it should not
differ between ground and air.

---

## MEDIUM

### 2. The new Hurtbox sits on layer 2, which the player's own attack areas mask

**Files:** `scenes/player/player.tscn:60-63` (Hurtbox), `:80-82` (SpinArea), `:90-92` (SlamArea)
**Runtime enablement:** `src/gameplay/player/player_controller.gd:384`, `:366`

`Area3D.monitorable` defaults to `true`. SpinArea and SlamArea explicitly set
`monitorable = false`; the new Hurtbox does not — it sets only `collision_layer = 2`,
`collision_mask = 0`, `monitoring = false`. Both attack areas carry `collision_mask = 2`, and
both have `monitoring` switched on at runtime (spin while spinning, slam during recovery).

Result: while spinning, `SpinArea` monitors layer 2 and the player's own Hurtbox is a
monitorable body on layer 2, with no self-exclusion.

Nothing is connected to `area_entered` yet, so there is no failure today. The first hit
callback wired in Phase 1 will register the player hitting themselves on frame one. The H10
fix introduced this layer collision; it is one line now and a confusing bug later.

**Fix direction.** Set `monitorable = false` on the Hurtbox until something needs to detect
it, or move the player's hurtbox to a dedicated layer that player-owned attack volumes do not
mask, and exclude self in whatever hit callback lands first.

### 3. D-pad movement is cancelled by analog-stick motion events

**Files:** `src/gameplay/input/gamepad_input.gd:33-48` (motion) vs `:51-61` (button)

`_handle_button` correctly prefers `_dpad` and falls back to the stick. `_handle_motion` does
not — it pushes `_apply_dead_zone(_left_stick)` unconditionally and ignores `_dpad`.

**Failure scenario.** Player holds D-pad right; `_dpad = (1,0)` and movement is pushed. The
analog stick emits a resting-drift `InputEventJoypadMotion`, which is routine on real
hardware. `_handle_motion` computes `_apply_dead_zone(_left_stick)`, gets `Vector2.ZERO` from
inside the dead zone, and pushes it. `InputIntentBuffer._movement` becomes zero and the player
stops while the D-pad is still held. Continued drift produces stutter.

Newly introduced by the L8 fix — it breaks the feature that fix added. Gamepad is "verified,
never the gate" per §5.2, but the D-pad path is currently unusable on any pad with both inputs.

**Fix direction.** Give `_handle_motion` the same precedence as `_handle_button`: if `_dpad`
is non-zero, push `_dpad`; otherwise push the dead-zoned stick. Test with a D-pad press
followed by a sub-dead-zone motion event.

### 4. Touch layout polls two DisplayServer calls every rendered frame

**Files:** `src/ui/touch_controls.gd:27` (`set_process(true)`), `:79-85` (`_process`)

`_process` calls `DisplayServer.get_display_safe_area()` and `DisplayServer.screen_get_dpi()`
on every frame to catch same-size orientation flips. On Android both cross into platform code
— `screen_get_dpi` goes through display metrics — so this is a per-frame JNI round-trip in the
build used for the ≤100 ms touch-latency measurement and the 20-minute thermal soak.

This is the same class of problem as the per-frame SHA-256 that H5 just removed, reintroduced
by the M1 fix. The `size_changed` signal already connected at `:28` covers ordinary resizes;
the poll exists solely for the same-size safe-area flip, which does not need 60 Hz.

**Fix direction.** Move the safe-rect/DPI comparison onto a low-frequency `Timer` (or an
accumulator gated to a few checks per second) and keep `size_changed` for the common case.
Assert the poll interval in a test so it cannot silently return to per-frame.

### 5. Regenerated debug keystore can force an uninstall that wipes the tuning override

**Files:** `export_presets.cfg:37`, `.gitignore:10`, `scripts/deploy_android.sh:77-94`, `:128`

`keystore/debug="build/debug.keystore"` lives under `build/`, which is gitignored.
`deploy_android.sh:83-92` regenerates it with `keytool -genkeypair` whenever absent, and
`-genkeypair` produces a **new random key each time**. So the procedure is reproducible; the
signing certificate is not — it differs after any `build/` clean, on a second machine, and on
a fresh clone.

Android rejects `adb install -r` (line 128) across a certificate change with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`. The script has no handling for it. The operator's
natural recovery — uninstall, reinstall — deletes `user://`, destroying the on-device override
that **acceptance step B exists to prove persists**. The install failure is loud; the data loss
that follows is not.

**Fix direction.** Make the certificate stable. Either commit `debug.keystore` (it holds no
secret — the password is literally `android` and it signs debug builds only) at a path outside
the ignored `build/` tree and point `keystore/debug` at it, or generate it once into a
non-ignored location and document that deleting it forces a reinstall. Additionally, have the
deploy script detect `INSTALL_FAILED_UPDATE_INCOMPATIBLE` and stop with an explicit warning
that continuing will destroy `user://tuning/override.tres`, rather than leaving the operator
to reach for `adb uninstall`.

Also correct the disposition wording: "reproducible debug keystore" is not accurate as built.

### 6. `catalog_is_usable` covers the hard-brick set but not the soft-brick set

**File:** `src/tuning/tuning_service.gd:91-169`

The validator is a genuine B2 fix — it rejects non-finite values and every layout/DPI field
that could make the touch controls unreachable. Fields it does **not** check, all still live
sliders:

| Field | Effect if set badly | Where |
|---|---|---|
| `move.respawn_floor_y_m` | Raised above platform tops → `request_respawn` re-triggers every frame; permanent respawn loop | `player_controller.gd:275-276`; omitted from the `move` block at `:112-123` |
| `move.maximum_fall_speed_mps` | `0.0` clamps descent to zero; the player never falls | `player_controller.gd:289-292` |
| `input.jump_buffer_s`, `action_buffer_s`, `coyote_time_s` | Negative → `_prune` discards every queued press; no jump, spin or slam registers | `input_intent_buffer.gd:103-115` |

All three remain **recoverable**: the drawer is GUI and survives broken gameplay tuning, so
RESET TO AUTHORED still works. That bounds the severity — this is degradation, not a brick.
But the validator's coverage is narrower than the disposition implies.

**Fix direction.** Either extend `catalog_is_usable` to cover the gameplay-liveness set above,
or document explicitly (in the validator's docstring and the device acceptance doc) that it
guarantees *recoverability*, not *playability*. The second is cheaper and arguably the right
contract — but it should be stated, not assumed.

### 7. The Phase 0.5 scope check is a keyword filter presented as a scope guard

**File:** `scripts/check_phase0_scope.py:18-25`

`PROHIBITED_PATTERNS` greps `src/`, `scenes/` and `data/tuning/` for the literal words
*enemy*, *crate*, *wall_run*, *grind*, *swing*, *phase_shift*. This does fire, which is a real
improvement over M8's vacuous group assertion. But it enforces **naming**, not scope: a
wall-run implemented as `LedgeAttach`, or a rail as `SplineRider`, passes untouched. The
mutation test cited in the disposition uses a synthetic *untagged enemy*, which confirms the
mechanism is lexical.

It also creates friction the design doc will hit. §5.5 describes the camera that "swings to a
side-on view"; the `swing` pattern at line 23 matches on lowercased lines, so documenting that
behaviour in any `src/` comment blocks the commit.

**Fix direction.** Keep the scanner — a lexical tripwire is worth having — but rename it and
its output so it does not read as a scope proof (e.g. "Phase 0.5 vocabulary check"), and scope
the patterns to identifiers rather than prose (exclude comment lines, or require a
word-boundary match against `class_name`/`func`/node-name contexts). Record in the audit trail
that scope compliance is still established by review, not by this script.

---

## LOW

**8.** `src/debug/tuning_debug_ui.gd:150-151` — `_build_drawer` calls `queue_free()` on
existing rows then immediately adds replacements. Deletion is deferred to end of frame, so
after RESET TO AUTHORED the drawer renders every row twice for one frame. `_controls` and
`_property_count` rebuild correctly, so this is cosmetic only. Fix by removing children
immediately (`remove_child` + `queue_free`) rather than relying on deferred deletion.

**9.** `src/gameplay/depth/landing_ring.gd:75-78`, `:89` — `collision_probe_indices` allocates
a fresh `PackedInt32Array` every physics frame, and `probe_indices.has(index)` is a linear
scan executed once per trajectory segment. Negligible at 76 points, but it partly offsets the
H4 stride saving. Prefer `index % stride == 0 or index == last` over building and searching an
array.

**10.** `src/gameplay/player/player_controller.gd:146-159` — the nudge now sorts directions to
try `-travel` first. Correct for the overshoot case §5.3 describes ("foot-center past a lip"),
but it also makes a *deliberate* short hop off a ledge stickier than before, since the
recovery direction is now first rather than arbitrary. **Do not change blind** — this is a
feel question for Gate F. Flagging so the operator knows to watch for it.

**11.** `src/core/phase0_game.gd:38-41` — only `$Drawer` is registered as the touch-exclusion
control; the HUD panel holding the TUNE button is not. Safe at current values (HUD bottom 232
vs stick top 270 at the 1080p design viewport), but `stick_region_top_exclusion_ratio` is a
live slider, and lowering it lets a TUNE tap also spawn the floating stick. Register the HUD
as a second exclusion rect, or make the exclusion accept an array of controls.

**12.** `src/gameplay/player/jump_kinematics.gd:81-86` via
`src/gameplay/player/player_controller.gd:303-308` — a tapped double jump clamps to
`jump_tap_height_m` (0.9 m, the *ground* jump's tap height) because there is no
`double_jump_tap_height_m`. Pre-existing rather than new, and arguably fine, but it is a
tuning gap the drawer cannot express. **Operator decision** — do not add the field without
asking.

---

## Operator decisions still needed

1. **Air arbitration policy (finding 1).** Should a losing DOWN press be discarded in air, as
   it already is on the ground, or survive to fire the slam next frame? The ground policy was
   ratified; the air one was not. These should match.
2. **Scope-check honesty (finding 7).** Is a lexical vocabulary tripwire the intended
   guarantee, or is a stronger structural check wanted?
3. **Validator contract (finding 6).** Should `catalog_is_usable` guarantee recoverability
   only, or playability?
4. **Keystore location (finding 5).** Commit the debug keystore, or keep it generated and
   accept that a `build/` clean forces a reinstall?
5. **`double_jump_tap_height_m` (finding 12)** — add the tuning field, or leave the base tap
   height shared?

---

## Still not verifiable statically

- **H4** (landing-ring query cost) — the stride reduces worst-case probes from ~150 to ~100
  per frame; only a real-phone profile and the 20-minute thermal soak settle it.
- **H11** (acceptance step B) — runtime-authored `.tres` resolution inside the signed APK with
  `script_export_mode=2` still requires a device. Finding 5 now compounds this: a certificate
  change mid-test both blocks the reinstall and endangers the override being tested.
- **Everything in the disposition's "Final automated verification" section.** This pass ran
  nothing. Treat those numbers as claims pending independent reproduction.
