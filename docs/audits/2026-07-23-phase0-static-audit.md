# Phase 0 static audit — crash-remix

**Date:** 2026-07-23
**Auditor:** Claude (Opus 4.8), read-only static pass
**Subject:** the complete Phase 0 implementation, tracked and untracked
**Method:** static reading only. Nothing was executed — no Godot, no GUT, no pre-commit
hook, no build, no APK, no adb, no network. No file in the repo was modified by this audit.
**Coverage:** 5,232 LOC across `src/`, `scenes/`, `data/tuning/`, `tests/`, `scripts/`,
`.githooks/`, `project.godot`, `export_presets.cfg`. Enumerated via `git status --short`
plus a full filesystem walk, because almost everything is untracked and `git diff` sees none of it.

> **No finding below was confirmed by running anything.** Severities are judgements from
> reading code and tracing failure paths. Anything marked NOT VERIFIABLE needs a device or
> a run to settle. Do not treat this document as evidence that a fix worked — that requires
> a failing test first, per CLAUDE.md.

---

## For the agent fixing this

Read `/root/CLAUDE.md` and `/root/crash-remix/CLAUDE.md` first. The rules that bite here:

- **TDD.** Failing test first, then the fix. Several findings below exist *because* a test
  was written that cannot fail — do not repeat that.
- **No gameplay numeric literals** in `src/gameplay/**`. If a fix needs a number, add a
  field to a tuning resource. Do not write `1.0 + 1.0` to launder the lint (finding L1).
- **Stage explicit paths.** Never `git add -A`, `git add .`, `git commit -a`,
  `git checkout -- <path>`. This tree is shared with other agents; run
  `git status --porcelain` before any git operation and assume unstaged work is someone else's.
- **Never mark a gate passed.** Gate F is the operator, on a phone, by thumb. The §11.4
  acceptance test is also operator-run. An agent may report "ready to run" and nothing more.
- **Report test counts.** "Should work" is not a status.
- Grep every call site of any changed function signature before calling a fix done.

**Suggested fix order:** B1 → B2 → H1 → H2/H12 → H6 → H8 → H9 → H10 → H5/H4 → the rest.
B1, B2, H1, H6 block the device session. H2, H8, H12 are enforcement-mechanism integrity —
they decide whether the acceptance test means anything. H9 must be fixed before its area is
touched, or the new work inherits tests that cannot fail.

---

## 1. Blockers

### B1 — Double jump is silently eaten by the body slam in the same frame

**Files:** `src/gameplay/player/player_state_machine.gd:64-66`, `:100-114`, `:146-161`

In the airborne branch of `step()`, `_process_jump()` runs first and `_process_air_down()`
runs second. Both write the same `_pending_impulse` field; the second overwrites the first.

**Failure scenario.** Player is airborne with the ground jump already spent. JUMP is pressed
at t=0, DOWN at t=0.08. On the next physics tick both are inside their buffers (120 ms and
150 ms):

1. `_process_jump` matches → `_pending_impulse = double_jump`, **consumes the JUMP press**,
   sets `_double_jump_available = false`.
2. `_process_air_down` matches → consumes DOWN, **overwrites** `_pending_impulse = body_slam`,
   sets state `body_slam`.
3. `decision.impulse` is `body_slam`. The double jump is gone and cannot be re-attempted —
   its availability flag was already cleared.

Reachable on touch because the DOWN and JUMP hit circles physically overlap (M2): one fumbled
thumb produces both presses. Hits Gate F criterion 3 (ten into-screen jumps) and the spec's
framing of double jump as "the depth-correction eraser" (§2.2, §4.2).

**Fix direction.** Make impulse selection exclusive for the frame. Either have
`_process_air_down` bail when `_pending_impulse != IMPULSE_NONE`, or resolve a single winner
from all buffered air actions with an explicit documented priority. If DOWN is to win, JUMP
must not be consumed and `_double_jump_available` must not be cleared.

**Test first.** Airborne, ground jump spent, both JUMP and DOWN buffered in one `step()`:
assert exactly one impulse fires and that whichever verb loses is still available afterwards.

---

### B2 — A bad on-device override bricks the app with no in-app recovery

**Files:** `src/core/phase0_game.gd:17-19`, `src/tuning/tuning_service.gd:32-33`,
`scenes/debug/tuning_debug_ui.tscn:117-131`

`load_from_paths` returns `ERR_INVALID_DATA` when the override resource fails to load. It does
**not** fall back to the authored catalog. `PhaseZeroGame._ready()` then `push_error`s and
returns before configuring input, the player, the camera or the HUD — leaving a running app
with no controls and no on-screen diagnostics.

The drawer makes this reachable. `_build_drawer` (`src/debug/tuning_debug_ui.gd:119-153`)
auto-generates a control for *every* exported property, including `millimeters_per_inch`,
`fallback_dpi` and `control_scale`. Set `millimeters_per_inch` to 0 and save: `pixels_per_mm`
becomes infinite (`src/ui/touch_control_layout.gd:11-13`), the touch layout collapses, the
buttons become unreachable — and the value is now persisted to `user://tuning/override.tres`.
The drawer footer has SAVE OVERRIDE and CLOSE only. There is no revert.

Recovery requires `adb shell pm clear com.personal.crashremix`, which destroys the override
that acceptance step B exists to validate.

**Fix direction.** Three separate changes:
1. On override load failure, keep the authored catalog, set a visible "OVERRIDE REJECTED"
   state, and continue booting. Never leave the game unconfigured.
2. Add a RESET TO AUTHORED button that reloads from `res://data/tuning/gameplay.tres` and
   deletes the override file.
3. Exclude layout-critical and unit-conversion properties from the drawer, or clamp them to
   sane ranges. `millimeters_per_inch` is a physical constant, not a tuning knob.

---

## 2. High

### H1 — The tuning drawer sits on the floating-stick region and both consume the same touches

**Files:** `scenes/debug/tuning_debug_ui.tscn:83-89`, `src/ui/touch_controls.gd:53-56`

Drawer rect is (18,246)–(940,1062) on a 1920×1080 design viewport. The stick region is the
left 42% below the top 25% — x 0–806, y 270–1080. They overlap almost completely.

`TouchControls` listens on `_input()`, which fires before GUI picking, and never calls
`get_viewport().set_input_as_handled()`. Every slider drag and every tap on SAVE also spawns
and drives the floating stick, so the character runs around while the operator tunes. This is
directly in the path of acceptance step B.

**Fix direction.** Have `TouchControls` ignore touches whose position falls inside a visible
drawer rect, or route touch through `_unhandled_input` so GUI consumption wins, or move the
drawer to a region that cannot overlap the stick or the button cluster.

---

### H2 — `rail_bake_interval_m` never reaches the runtime at boot, and the bug is invisible

**File:** `src/gameplay/camera/camera_rail_controller.gd:18-21`, `:43`, `:58-59`, `:128-139`

`_ready()` calls `_ensure_curve_from_markers()` while `_camera_tuning` is still null, so the
`curve.bake_interval` assignment at `:135` is skipped. `configure()` calls it again at `:43`
but it early-returns at `:131-132` because the curve now has points — and `configure()` never
sets `bake_interval` itself. Only `refresh_tuning()` does, and that is reached solely from
`_on_tuning_changed`. The value is therefore dead until the operator touches the drawer.

It goes unnoticed because `rail_bake_interval_m = 0.2` happens to equal Godot's own default
for `Curve3D.bake_interval`. This is the Reaper Rush failure mode in miniature — a dead wire
hidden by a coincidental default.

**Fix direction.** Set `bake_interval` in `configure()` unconditionally, before the curve
guard. Then add a test that asserts a non-default authored value reaches `curve.bake_interval`
after boot.

---

### H3 — The rail magnet is hardwired to screen-up; the corridor axis is never fed to it

**File:** `src/gameplay/input/input_router.gd:38-44`

`set_corridor_axis()` has **no callers anywhere** in the project — grep across `src/`,
`scenes/` and `tests/` returns only the definition and the getter. `_corridor_axis` stays at
its initialiser `Vector2.UP` forever.

`CameraRailController` computes `_corridor_forward` every frame and pushes it to the *player*
(`camera_rail_controller.gd:120-121`) but never to the router. On the current straight −Z rail
this coincidentally produces correct behaviour; on any curved spine the ±15° magnet cone
(§5.2) pulls toward the wrong axis.

**Fix direction.** Have the camera rig project `_corridor_forward` into screen space and call
`InputRouter.set_corridor_axis()` alongside the existing `set_corridor_forward()` call. Test
with a non-`Vector2.UP` axis.

---

### H4 — The landing ring issues up to 150 physics queries per physics frame

**File:** `src/gameplay/depth/landing_ring.gd:70-91`, with `src/gameplay/depth/depth_prediction.gd:7-31`

`trajectory_points` builds 76 samples (`prediction_horizon_s 3.0 / prediction_step_s 0.04`),
allocating a fresh `PackedVector3Array` every tick. `_first_trajectory_hit` then walks them
issuing one `intersect_ray` **and** one `get_rest_info` sphere probe per segment, returning
only on the first hit. Over open air — precisely the long-gap section the gauntlet is built
around — that is the full 150 queries at 60 Hz.

Gate F criterion 2 is a 20-minute thermal soak holding 60 fps with dynamic resolution never
below 0.7. Measure this before that soak.

**Fix direction.** Options, roughly in order of value: skip the shape probe unless the ray
missed; coarse-step the trajectory and refine only near the first crossing; recompute only
when velocity changes materially rather than every tick; cap the horizon by predicted
time-to-ground instead of a fixed 3 s.

---

### H5 — The debug HUD hashes the entire tuning catalog every rendered frame

**File:** `src/debug/tuning_debug_ui.gd:114-116`, with `src/tuning/tuning_service.gd:45-55`

`_process` calls `_service.fingerprint()` unconditionally. That walks four resources via
`get_property_list()`, builds ~100 strings through `var_to_str`, sorts a `PackedStringArray`,
joins and SHA-256s the result — per frame, forever, in the build the operator uses to measure
frame time and touch latency.

**Fix direction.** Recompute the fingerprint on an explicit dirty flag set by `set_live_value`
and by override load, not by polling. If polling must stay, throttle it to a low frequency.

---

### H6 — The edge-landing nudge teleports without a collision check, in eight world directions

**File:** `src/gameplay/player/player_controller.gd:121-141`, called from `:227-229`

Fires on any descending frame where no walkable floor is within `floor_snap_length_m` (0.2 m)
directly below. It then probes RIGHT, LEFT, FORWARD, BACK and the four diagonals in fixed
order and applies `global_position += offset` — a raw teleport with no wall-clearance test,
before `move_and_slide()`.

Two consequences. The directions are world axes rather than travel- or camera-relative, so the
first match can be **backward**, snapping the player onto the ledge they just deliberately
left. And the teleport can embed them in adjacent geometry, leaving depenetration to clean up.

§5.3 specifies this as "landings only, never into hazards". The hazard half is unenforceable
in practice because nothing ever joins group `"hazard"` (M6).

**Fix direction.** Bias direction selection toward the surface the player is actually
descending onto (or away from travel direction), use `move_and_collide` / `test_move` rather
than a raw position write, and gate on proximity to a landing rather than on every descending
frame.

---

### H7 — Respawn teleports with physics interpolation on and never resets it

**File:** `src/gameplay/player/player_controller.gd:188-199`

`respawn()` assigns `global_transform = _spawn_transform` with no
`reset_physics_interpolation()` call. `physics_interpolation=true` is set in
`project.godot:37` and asserted by `tests/config/test_project_configuration.gd:32-35`, so the
render transform interpolates across the teleport — the player visibly streaks from the death
point to the spawn point.

Respawn speed is a "never cut" item (§13) and §5.3's ≤2.0 s window is about *felt* retry cost.
The same applies to the edge-nudge teleport (H6) and, less visibly, to `BlobShadow` and
`LandingRing`, which are `top_level = true` and reposition in `_physics_process`.

**Fix direction.** Call `reset_physics_interpolation()` after any transform teleport on the
player and on both depth aids.

---

### H8 — The literal lint fails open and still reports success

**File:** `scripts/lint_gameplay_numbers.py:42-46`, with `:99-103`

`find_numeric_literals` wraps the token loop in
`try/except (IndentationError, tokenize.TokenError): pass` and returns whatever it collected
before the error. `main()` then prints "Gameplay numeric-literal lint passed" and exits 0 if
that partial list is empty. A GDScript file that trips Python's tokenizer is silently
unscanned and reported clean.

This lint is CLAUDE.md rule 1, marked `[hard]`, and rule 2's entire thesis is that enforcement
mechanisms must be provably live. An enforcement path that fails open is the wrong default.

The hook itself *is* correctly wired: `core.hooksPath = .githooks` is configured, and
`.githooks/pre-commit` invokes the lint with no arguments, which correctly picks up the
`src/gameplay` default.

**Fix direction.** Fail closed: on a tokenizer error, report the file as unscannable and
return non-zero naming it. Add a test that a file which trips the tokenizer produces a
non-zero exit.

---

### H9 — Four tests cannot fail

**Files:** `tests/gameplay/test_player_motor.gd:16-33`, `:35-52`, `:54-69`;
`tests/gameplay/test_camera_blend.gd:31-46`

`PlayerMotor.horizontal_velocity` computes
`maximum_change = transition_speed / transition_time * delta_s`
(`src/gameplay/player/player_motor.gd:47-52`).

`test_run_reaches_authored_speed_in_authored_acceleration_time` passes
`delta_s = run_time_to_speed_s`, so the terms cancel and the step size is exactly `run_speed`.
`move_toward` lands on the target for **any** value of `run_time_to_speed_s` — and would still
land on it if the implementation dropped `delta_s` entirely. The same cancellation makes
`test_stopping_uses_authored_near_instant_stop_time` and `test_crouched_movement_uses_crawl_speed`
vacuous.

`test_region_change_reaches_target_in_authored_blend_time` passes `delta_s = region_blend_s`,
giving `weight = clampf(1.0)` and an exact arrival — true for any blend time
(`src/gameplay/camera/camera_blend.gd:24-27`).

None of the four tests the curve it is named after.

**Fix direction.** Step with a realistic frame delta (1/60) and assert the *partial* progress,
or assert across several steps that full speed is reached at approximately the authored time
and not before. A correct test must fail if `delta_s` is removed from the formula.

---

### H10 — The hurtbox ratio is applied to the movement collider, and it opens the crouch tunnel

**Files:** `src/gameplay/player/player_controller.gd:267-299`; `scenes/game.tscn:54-57`;
locked in by `tests/gameplay/test_player_controller.gd:128-132`

`_apply_character_dimensions` sets the `CharacterBody3D`'s own `CylinderShape3D.height` to
`player_height_m × hurtbox_visual_ratio` = 1.1 × 0.725 = 0.7975 m, while the visual capsule
stays 1.1 m. §5.3's 70–75% figure is a *hurtbox* ratio — what damage tests against — not the
physics capsule.

**Concrete consequence.** `TunnelRoof` sits at y=1.0 with thickness 0.3, so its underside is
at y=0.85. The authored 1.0 m collider would be blocked; the runtime 0.7975 m collider walks
under it upright, with the visual head clipping through the slab. The crouch/crawl verb the
tunnel exists to exercise is never required, so Gate F silently skips it.

**Fix direction.** Decide whether hurtbox and movement collider are the same body. If not
(recommended), give the player a separate hurtbox `Area3D` carrying the ratio and leave the
movement collider at full visual height, then re-author the tunnel clearance. Either way,
`test_controller_applies_global_fair_hitbox_ratios` currently asserts the questionable
behaviour as correct and must be revisited alongside the fix. **Ask the operator before
choosing** — see Questions §5.

---

### H11 — Acceptance criterion (b) is not covered by anything the suite can prove *(NOT VERIFIABLE statically)*

**Files:** `export_presets.cfg:19`; `tests/tuning/test_tuning_service.gd:88-109`;
`tests/debug/test_tuning_debug_ui.gd:32-54`

The override round-trip tests are real and well written, but they run on desktop against loose
files. The acceptance test's actual risk lives elsewhere: `ResourceSaver.save()` writes a
**text** `.tres` at runtime carrying `[ext_resource type="Script" path="res://src/tuning/*.gd"]`,
and the export preset sets `script_export_mode=2` (compressed binary tokens), so those script
paths exist in the PCK only through the exporter's remap table.

Whether a runtime-authored `.tres` re-resolves them on the next cold boot inside a signed APK
is the single thing that decides acceptance step B, and it cannot be established without a
device.

**Action.** Treat a green suite as evidence for the desktop loop only. Verify step B on the
phone before declaring the tuning system exists. If it fails, the fallback is to serialise the
override as JSON or `ConfigFile` keyed by section/property name rather than as a
script-bearing Resource.

---

### H12 — A moving fingerprint does not prove the value you changed is live

**File:** `src/tuning/tuning_service.gd:45-55`

The fingerprint hashes every exported property across all four resources. Five reach nothing
at runtime:

| Property | Status |
|---|---|
| `input.bounce_timing_s` | zero call sites in `src/` (bounce crates are a later phase) |
| `input.touch_response_target_s` | zero call sites — a measurement target, not a runtime knob |
| `input.touch_response_hard_fail_s` | zero call sites — same |
| `camera.minimum_jump_depression_degrees` | referenced only by a test; the §5.4.1 author-time lint does not exist yet |
| `camera.rail_bake_interval_m` | dead at boot — see H2 |

Editing any of those moves the hash while changing nothing. CLAUDE.md rule 2 states the
contrapositive correctly ("hash unchanged → dead-wired"), but the operator will read the
passing direction as proof of liveness, and for these five it is false.

The acceptance test itself uses `gravity_mps2`, which *is* live (six call sites), so the test
as written is valid. The inference it invites is not.

**Fix direction.** Either wire or remove the inert properties, or split the fingerprint into
per-section hashes and display them separately so a dead section is visible. Document
explicitly that the hash proves *something* changed, not that *your* change is live.

---

## 3. Medium

| ID | File:line | Finding |
|---|---|---|
| M1 | `src/ui/touch_controls.gd:137-143` | `_recalculate_layout()` is called only from `configure()` and `set_layout_override()`. No handler for viewport resize, orientation change or safe-area change. `orientation=4` (sensor landscape) permits a 180° flip that moves the notch to the other edge; buttons stay put. |
| M2 | `src/ui/touch_controls.gd:124-134` + `data/tuning/input.tres:29-37` | Hit circles overlap and priority is hardcoded DOWN → SPIN → JUMP → catch-all. DOWN sits 17 mm above JUMP but their hit radii sum to 17.55 mm (`button_hit_radius_scale = 1.35`); SPIN is 14 mm from JUMP with the same sum. A JUMP press biased high registers as DOWN — a body slam, in air. §5.2 calls JUMP "the verb that must never miss". |
| M3 | `src/gameplay/depth/blob_shadow.gd:35-42` | The ray starts at `_target.global_position`, which is the player's feet — essentially on the surface when grounded. Grazing-origin raycasts are unreliable, and §5.4.2 requires the shadow to be constant, always. Start the ray above the body. |
| M4 | `src/gameplay/input/input_intent_buffer.gd:34` | `consume_released` is called only for JUMP (`player_controller.gd:252`). SPIN and DOWN release intents are appended forever and never pruned — `_prune` runs only from `_consume`/`has_buffered_pressed`, and the latter touches press queues only. Unbounded growth across a 20-minute soak. |
| M5 | `src/gameplay/depth/depth_prediction.gd:24-28` vs `player_controller.gd:97,230` | Prediction advances position with the *pre-gravity* velocity; the controller applies gravity and then moves. The landing ring is systematically biased long/high relative to where the player actually lands — the exact error the ring exists to eliminate. |
| M6 | `scenes/game.tscn:34-92`; `src/graybox/graybox_platform.gd:24-25` | `GrayboxPlatform` exports `hazard`, but no instance in `game.tscn` sets it. Nothing ever joins group `"hazard"`, so `depth.hazard_color`, the red-ring branch (`landing_ring.gd:65-66`) and both probe exclusions (`player_controller.gd:364-365`, `:391-392`) are unreachable. §5.4.3's green/red requirement cannot be demonstrated at Gate F. |
| M7 | `scenes/game.tscn:119` | No `OS.is_debug_build()` anywhere in the project. The fingerprint HUD and the tuning drawer are unconditional scene children, so they ship in release builds and occlude gameplay during the latency and thermal measurements. §11.4 scopes them to debug builds. |
| M8 | `tests/integration/test_phase0_scenes.gd:45-46` | `assert_eq(get_tree().get_nodes_in_group("enemy").size(), 0)` is vacuously true — nothing in the project ever joins those groups. It would stay green if enemies were added without group tags. This is the only automated guard on Phase 0.5 scope. |
| M9 | `tests/integration/test_phase0_scenes.gd:63` | Asserts the landing ring is visible while the player stands still. That passes only because the sphere probe at `points[1]` hits the ground at the player's own feet, pinning the ring under them. The test encodes a probable defect as the expectation. |
| M10 | `tests/tuning/test_tuning_service.gd:29-51` | `test_authored_values_match_phase_zero_contract` mirrors fifteen `.tres` constants. It fails the first time the operator blesses a device-tuned value back into the repo — i.e. the moment the tuning loop is used as designed. |
| M11 | `tests/deploy/test_deploy_script.py:23-36` | Three assertions that the shell script *contains* substrings. No behaviour exercised. `bash -n` (`:13-21`) is a syntax check only. |
| M12 | `tests/lint/*.py`, `tests/deploy/*.py` vs `.gutconfig.json` | GUT scans `res://tests` for `.gd` only, so the eight Python tests are invisible to it. There is no pytest config, no CI, and the pre-commit hook runs only the lint. Any reported GUT count excludes them. State both counts separately. |
| M13 | `export_presets.cfg:36` | `package/signed=true` with no `keystore/debug*` keys in the preset. Signing falls back to editor settings not in the repo, so `scripts/deploy_android.sh` is not reproducible on a clean box despite pinning Godot, templates and adb paths. |
| M14 | `docs/qa/phase0-device-acceptance.md:42-43` | Step B.4 asks the operator to confirm the "step-1 fingerprint" persists. Step 1 is section A's *pre-edit* fingerprint; what must persist is the one recorded in B.2. As written the check inverts the pass condition. One-line doc fix — do this before the operator reads the checklist. |
| M15 | `src/gameplay/player/player_state_machine.gd:129-143` | On the ground, `_process_ground_down` runs before `_process_jump`. Same-frame DOWN+JUMP while running sets `STATE_SLIDING` and then immediately reads it as a slide-jump, yielding a 5.5 m launch with zero slide. Plausibly desirable tech, but unstated and untested. **Ask the operator.** |
| M16 | `src/gameplay/player/player_controller.gd:251-264` | The jump *release* is consumed against `action_buffer_s` (150 ms) rather than a jump-specific window, and `velocity_after_release` is applied to `velocity.y` unconditionally — including when the rise came from a different impulse. |
| M17 | `src/gameplay/player/player_controller.gd:159`, `:378` | The landing-assist "is there floor below me" probe uses `depth.shadow_ray_length_m` (12 m) as its search depth. Retuning the blob shadow silently retunes landing assist. Give the assist its own tuned depth. |

---

## 4. Low

- **L1** — `1.0 + 1.0` is used to express 2.0 and satisfy the literal ban:
  `src/gameplay/player/jump_kinematics.gd:14`, `src/gameplay/player/player_controller.gd:278`,
  `:286`, `:293`. The lint measures syntax, not intent, and the code already routes around it.
- **L2** — Lint scope is `src/gameplay/` only (`scripts/lint_gameplay_numbers.py:85`), leaving
  `src/ui/touch_control_layout.gd:33`'s hardcoded `0.5` catch-all width unguarded even though
  §5.2 button geometry is a gameplay number. Note `jump_catchall_top_ratio` *is* tuned — the
  width is not. Inconsistent.
- **L3** — `addons/gut` is 259 untracked, un-ignored files. Vendoring decision never made
  explicit. **Ask the operator** whether it is committed or installed per-machine.
- **L4** — `src/tuning/tuning_service.gd:70` sets `override_active` on save but never appends
  the override path to `_loaded_resource_paths`, so the HUD path list is stale until reboot.
- **L5** — `scenes/game.tscn:89-92` — `HighJumpLedge` tops out at y=2.0 and clears on a normal
  2.2 m jump, so it does not exercise the 2.9 m high jump.
- **L6** — `src/gameplay/camera/camera_rail_controller.gd:47` passes `region_blend_s` where a
  `delta_s` is expected. Harmless today (`_initialized` is false so it snaps) but a semantic trap.
- **L7** — `src/gameplay/camera/camera_blend.gd:26` is frame-rate-dependent exponential
  smoothing, not a fixed-duration blend. Settle time is roughly 3× `region_blend_s`.
- **L8** — `src/gameplay/input/gamepad_input.gd:71-79` — D-pad unmapped; left stick only.
- **L9** — `scenes/player/player.tscn:67-84` — spin and slam areas mask layer 2, which nothing
  occupies, and no `area_entered`/`body_entered` signal is connected anywhere. Expected for
  Phase 0 (nothing to break), but it means `spin_radius_m`, `attack_visual_ratio` and
  `body_slam_shockwave_radius_m` size inert volumes and have no gameplay effect yet.

---

## 5. Questions requiring an operator decision

Do not guess these. Each changes what the fix should be.

1. **Is `hurtbox_visual_ratio` meant to shrink the physics collider?** (H10) §5.3's 70–75% is
   a damage figure. Applying it to `CharacterBody3D`'s own shape is a different decision with
   visible consequences, and a test currently asserts it as correct. If deliberate, the tunnel
   geometry needs re-authoring; if not, the hurtbox becomes a separate `Area3D`.
2. **Is the same-frame DOWN+JUMP zero-length slide-jump intended tech?** (M15) Either way it
   should be named and tested.
3. **Should the debug HUD and drawer be release-gated?** (M7) §11.4 says "debug builds"; the
   code has no gate. For a sideload-only build, shipping them may be wanted — but they occupy
   screen space during the very measurements Gate F takes.
4. **Should the drawer expose non-gameplay layout constants** (`millimeters_per_inch`,
   `fallback_dpi`, `control_scale`)? (B2) Excluding them removes most of B2's blast radius.
5. **Is `addons/gut` meant to be committed** (259 files), or ignored and installed per-machine? (L3)
6. **Which fingerprint does acceptance step B.4 mean?** (M14) Read as B.2's; the document says step 1.
7. **Where do touch-layout constants live?** (L2) Either extend the lint's scope to `src/ui/`
   or move the catch-all width into `InputTuning`.

---

## 6. Requirement-by-requirement

PASS / PARTIAL / FAIL / NOT VERIFIABLE. "NOT VERIFIABLE" means it needs a device or a run —
this audit executed nothing.

| # | Requirement (kickoff / §12 / §11.4) | Verdict | Evidence |
|---|---|---|---|
| 1 | Flat graybox gauntlet, no art/enemies/crates/levels | PASS | `scenes/game.tscn` — 12 `GrayboxPlatform` instances, one `WorldEnvironment`, one light. Nothing else. |
| 2 | Touch: floating stick | PASS | `touch_controls.gd:75-79`, `:95-121`; mm via `screen_get_dpi` + `get_display_safe_area` (`:141`, `:147`). Sizes, dead zone, full-run, opacity all match §5.2. |
| 3 | Touch: JUMP/SPIN/DOWN + catch-all | PARTIAL | Present and correctly sized (`touch_control_layout.gd:16-53`); hit circles overlap with JUMP lowest priority — M2. |
| 4 | Bluetooth gamepad, first-class | PARTIAL | A/X/B/R1 mapped (`gamepad_input.gd:71-79`); magnet disable above 0.6 correct; Y correctly absent. D-pad unmapped — L8. |
| 5 | Unified buffered timestamped `InputIntent` | PASS | `input_intent.gd`, `input_intent_buffer.gd`, `input_router.gd`; `MonotonicClock` used identically by both adapters and `_physics_process`. |
| 6 | `Input.set_use_accumulated_input(false)` (§5.3) | PASS | `phase0_game.gd:12`. |
| 7 | Run / variable jump / double jump | **FAIL** | Kinematics correct, but B1 destroys the double jump under a reachable input pattern. |
| 8 | Spin — no movement, 0.45 s, once-per-airtime stall | PASS | `player_state_machine.gd:164-195`; `jump_kinematics.gd:113-114`. Spin applies no impulse. |
| 9 | Crouch / slide / slide-jump | PARTIAL | Transitions correct; the gauntlet's only crouch obstacle does not require crouching — H10. |
| 10 | Body slam, uncancellable | PASS | `player_state_machine.gd:54` gates all input during `body_slam`/`slam_recovery`. |
| 11 | High jump (§4.2, not in kickoff list) | PASS | `player_state_machine.gd:96-97`; `high_jump_height_m = 2.9`. |
| 12 | Camera rail: Path3D spine | PASS | `camera_rig.tscn:15-30`, five markers; curve built at `camera_rail_controller.gd:128-139`. |
| 13 | CameraRegion volumes blending on overlap | PASS | Close region z −44…−6, side-on z −69…−35 — a genuine 9 m overlap. `CameraBlend.resolve_offset` averages; `advance_offset` smooths. |
| 14 | Blob shadow, constant size/opacity | PARTIAL | Shader and wiring correct (`blob_shadow.gdshader`, `blob_shadow.gd:19-27`); ray origin makes "always" fragile — M3. |
| 15 | Ballistic landing ring (§5.4.3) | PARTIAL | Green path works. Red/hazard path unreachable — M6. Integration bias — M5. Cost — H4. |
| 16 | Soft landing assist, 0.5 touch / 0 pad | PASS | `landing_assist.gd:5-39`; last-30% gate and stick-fighting rejection both correct and genuinely tested. |
| 17 | Forgiveness windows exactly as §5.3 | PARTIAL | 120 / 140 / 150 / 90 / 220 ms, 0.12 m nudge, ≤2.0 s respawn all authored and consumed. `bounce_timing_s` has no consumer; hurtbox/attack ratios applied to the wrong body — H10. |
| 18 | Typed `.tres` under `data/tuning/` | PASS | Five resources, five typed scripts, all `@export`-typed. |
| 19 | Pre-commit lint banning literals in `src/gameplay/**` | PARTIAL | Hook installed (`core.hooksPath=.githooks`) and scoped correctly; fails open — H8; laundered by `1.0 + 1.0` — L1. |
| 20 | Boot-time fingerprint hash on the debug HUD | PARTIAL | Works (`tuning_service.gd:45-55`, HUD `tuning_debug_ui.gd:442-457`); per-frame cost H5, no debug gate M7, and does not mean what it appears to mean — H12. |
| 21 | On-device slider drawer | PARTIAL | Complete and reflection-driven; overlaps the stick H1, no reset B2, exposes bricking values B2. |
| 22 | Override save/load to `user://tuning/override.tres` | NOT VERIFIABLE | Desktop round-trip implemented and tested; in-PCK behaviour is the open question — H11. |
| 23 | One-click Android deploy | PARTIAL | `deploy_android.sh` clean, guarded, non-destructive; not reproducible without an out-of-repo keystore and SDK config — M13. |
| 24 | GUT tests: FSM, buffer/coyote headless, tuning load path | PARTIAL | All three areas covered; four tests cannot fail — H9; several assert constants rather than behaviour. |
| 25 | Godot 4.7.x, Mobile renderer, Jolt, 60 Hz, interpolation | PASS | `project.godot:13`, `:36-38`, `:43-44`; asserted by `test_project_configuration.gd`. |
| 26 | Typed GDScript, not C# | PASS | All 27 scripts typed; no C#. |
| 27 | arm64-v8a only, min SDK 29 | PASS | `export_presets.cfg:26`, `:28-31`. |
| 28 | No Phase 0.5 scope | PASS | Grep across `src/`, `scenes/`, `tests/`, `data/`: zero hits for wall-run, grind, swing, phase-shift, PHASE button, enemies, crates, gems, checkpoints, menus. Clean. |
| 29 | Acceptance (a) repo edit → device | NOT VERIFIABLE | Needs a device. `gravity_mps2` is genuinely live (six call sites), so the mechanism is sound. |
| 30 | Acceptance (b) on-device edit → persists | NOT VERIFIABLE | H11; B2 makes a mid-test brick possible. |
| 31 | Acceptance (c) fingerprint moved both times | NOT VERIFIABLE | Will move; see H12 for what that does and does not prove. |
| 32 | Gate F not self-certified | PASS | `docs/qa/phase0-device-acceptance.md:60-61` reserves both the acceptance test and Gate F to the operator. |

---

## 7. Security, destructive operations, deployment safety

No issues found.

`scripts/deploy_android.sh` uses `set -euo pipefail`, contains no `rm -rf`, no `sudo`, no
`curl`/`wget`, and no network access. Its only writes are `mkdir -p`, an `unzip` of the
official Godot Android template into `android/build/`, and the `android/.build_version` marker.
adb use is non-destructive: `install -r` (which preserves app data — required for acceptance
step B), `force-stop`, and a `monkey` launch. Multiple-device and no-device cases are both
guarded (`:92-105`). No secrets or credentials anywhere in the repo.

Repo hygiene on generated files is correct: `build/`, `android/build/`, `.godot/` and
`__pycache__/` are all covered by `.gitignore` (verified with `git check-ignore -v`). The one
open decision is `addons/gut` — 259 untracked, un-ignored files (L3).

Tests do not write to live state: both override tests use `user://test_sandbox/` and clean up
in `before_each`/`after_each` (`test_tuning_service.gd:8-13`, `test_tuning_debug_ui.gd:9-14`).

---

## 8. Recommendation

**Fix first. Do not run the §11.4 acceptance test or Gate F yet.**

The build is closer to correct than the finding count suggests: the tuning architecture is
well-factored, scope discipline against Phase 0.5 is genuinely clean, and several tests
(landing assist, differential impulse-vs-tuning, touch multitouch, override round-trip, camera
depression) are real work. Three things must land before a device session is worth the
operator's time.

**B1 and H6 corrupt the two Gate F criteria that matter most.** A swallowed double jump and a
backward ledge-snap both read to the operator as "the controller feels wrong", and neither is
diagnosable by thumb. Running Gate F over them risks a false *fail* on feel and a wasted week.

**B2 plus H1 make acceptance step B hazardous.** The drawer sits on the stick, and one bad
slider value written to the override brings the app back with no controls and no recovery
short of wiping app data — losing the very override the test is validating.

**H2, H8 and H12 undercut the tripwire itself.** The one thing this project cannot afford is a
tuning loop that *appears* live. `rail_bake_interval_m` is already dead and invisible because
its authored value happens to match the engine default — caught here only by that collision.

H4, H5 and H11 need a device rather than a fix: measure the per-frame query and hash costs
before the thermal soak, and settle the exported-PCK override round-trip before declaring the
tuning system exists. Everything in Medium and Low can be deferred to a follow-up batch,
except M14, which is a one-line doc fix that should land before the operator reads that checklist.
