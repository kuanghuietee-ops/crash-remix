# Phase 0.5 plan review — three-Fable pre-handover audit

**Date:** 2026-07-23
**Subject:** `handover/phase05/01-PLAN.md`, reviewed before handover to Codex.
**Reviewers:** three Fable agents, bounded and non-overlapping — spec conformance; integration
with the existing Phase 0 code; Godot 4.7 feasibility, repo rules and task ordering.
**Outcome:** 2 P0, 20 P1, 23 P2. All dispositioned below. The plan was revised in place; task
numbers below refer to the **revised** plan (15 tasks, up from 13).

The two P0s and the four tuning-pipeline P1s are the same defect wearing different hats: the
plan added four tuning sections without touching the machinery that enumerates sections, so
the traversal tuning layer would have been dead-wired end to end while every test in the plan
passed. That is the reaper-rush failure, reproduced inside the plan written to prevent it.

## FIXED

| # | Finding | Fix | Verified by |
|---|---|---|---|
| F1 | `TuningService` hand-enumerates the 4 sections in 5 functions; `_clone_catalog` drops new slots, so `service.catalog.wall_run` is null at runtime even with correct `.tres` | Task 2 now lists `tuning_service.gd`, names all five functions, and tests against `service.catalog` after `load_from_paths` — never the raw `.tres` | `test_service_catalog_exposes_traversal_sections` |
| F2 | `verify_exported_tuning.sh:44` hardcodes `gameplay move input camera depth`; old Step 9 "Expected: PASS" was vacuous | Task 3 extended the shell loop, but its `rg` assertions could not run on the normal system `PATH`, so the claimed failure guarantee remained vacuous. Corrected 2026-07-23: R1 uses `grep -qE`; the verifier exits 0 for the real pack and exits 1 for a deliberately incomplete runtime log. | `test_export_verifier_reports_success_on_a_good_pack`; manual corrupted-log rejection |
| F3 | `TuningDebugUI.SECTION_NAMES` hardcoded to 4 — operator could not tune any traversal value at Gate F2 | Task 3 extends it; gate-blocking, so it ships before any verb | `test_debug_drawer_lists_traversal_sections` |
| F4 | Old `user://tuning/override.tres` has null new slots → rejected → operator's Phase 0 hand-tuning silently reset on first install | Task 3 backfills null sections from the authored catalog before validation | `test_old_shape_override_is_migrated_not_rejected` |
| F5 | PHASE button never unlocks in the toybox (no Warp Room 4) → Gate F2 criterion 3 unrunnable by thumb, yet handback would claim READY | Task 4 sets `phase_button_unlocked = true` in the toybox `input.tres`, with a note that Phase 1 restores progressive gating | `test_gauntlet_presents_phase_button` |
| F6 | `TouchControlLayout.button_zones` does not exist | Real API is `calculate(safe_rect: Rect2, dpi: float, input_tuning: InputTuning) -> Dictionary`, flat keys (`"jump_center"`, `"jump_radius"`). Task 4 test rewritten; `TouchControls._action_at()` and `_draw()` added to Files | `test_phase_button_absent_until_unlocked` |
| F7 | `adapter.call("_on_joy_button", ...)` does not exist; adapter stamps its own timestamps | Task 4 uses `InputEventJoypadButton` + `handle_input(event)`, house idiom | `test_gamepad_y_emits_phase_intent` |
| F8 | `Vector3.FORWARD` is `(0,0,-1)`; the "should attach" arcs at `z=+1..+3` sat >1m off the rail and would fail a *correct* solver | Rail fixtures rebuilt along `Vector3.BACK` | `test_rail_attach_hits_when_arc_passes_within_snap` |
| F9 | Untyped `Array` passed via `.call()` into an `Array[TraversalSample]` param hard-errors on 4.7.1; method never runs | Task 7 requires helpers to return runtime-typed `Array[TraversalSample]`; stated explicitly | `test_rail_attach_*` |
| F10 | Grind hop used bare JUMP; §4.2 is "stick+JUMP hops between parallel rails; JUMP exits" — as written you could never jump-exit a rail with a neighbour | Task 9 requires lateral stick for the hop; bare JUMP always exits. Both tests rewritten | `test_stick_and_jump_hops_to_parallel_rail`, `test_bare_jump_exits_the_rail` |
| F11 | FSM has no channel to know whether a parallel neighbour exists, so it cannot choose hop vs exit | New Task 8 adds the decision channel explicitly and greps every `step()` call site per repo rule | `test_hop_requires_neighbour_channel` |
| F12 | New states fall through `PlayerMotor.horizontal_velocity` into the ground branch, take full gravity, and trigger landing-assist / edge-nudge mid-grind | New Task 8 adds motor arms, gravity suppression, and assist gating for all three states | `test_traversal_states_bypass_ground_motor` |
| F13 | `PlayerController.configure()` takes `(move, input, depth, intents)` — no route for traversal tuning; `phase0_game.gd` calls it in two places | Task 8 extends the signature and both call sites | `test_controller_receives_traversal_tuning` |
| F14 | `player_frame_decision.gd` carries the new impulses but appeared in no Files list | Added to Task 8 | — |
| F15 | `minimum_entry_speed_mps` invented a speed floor that narrows §5.3's cone-plus-input window, and a test enshrined it | Initial value 0.0 (inert); walking-attach test dropped. Retained as a tuning field for the §5.2 mitigation ladder only | Task 7 |
| F16 | §5.5's "the landing ring draws on the detach target" covered by no task | Task 13 extends the ring to `STATE_WALL_RUN` | `test_ring_draws_on_wall_run_detach_target` |
| F17 | `seg_phase_gauntlet.tscn` used by Task 5's test and Task 13's chain, created by no task | Created in Task 6, with its commit | — |
| F18 | Directory-level `git add` in 9 tasks sweeps co-agent WIP in a shared tree | Every commit step now stages explicit files, preceded by `git status --porcelain` scope check | — |
| F19 | Task 5 edited `player_controller.gd` outside its Files list and commit; Task 10 staged `blob_shadow.gd` unlisted | Both corrected | — |
| F20 | Spline hold fights the engine in four specific ways | Task 8 states the mechanism: `MOTION_MODE_FLOATING` during spline states, `reset_physics_interpolation()` after attach snaps and hops, exit velocity from tuning never inherited, rail/strip meshes off the player collision mask | — |
| F21 | Ghost shader: object-space `NORMAL*width` breaks metre-width under node scale; BoxMesh split normals tear the shell; `cull_front` with no body pass is a silhouette blob, not a rim | Task 6 decides up front: inflate in view space, `normalize(VERTEX)*width` for centered convex primitives, and the blob look is accepted as compatible with §5.5's ~30% ghost | — |
| F22 | Phase-toggle invariant test awaits 2 frames and so cannot catch a transient both-solid overlap | Task 5 adds a same-frame assertion immediately after `request_toggle`. Ordering claim corrected: collision setters hit the PhysicsServer immediately, so any synchronous single-pass flip is atomic — the real hazards are mixing `set_deferred` with direct sets, and toggling from a locked-space physics callback. Both called out | `test_no_both_solid_frame_after_toggle` |
| F23 | Task 5's test never feeds `PhaseState` its `PhaseTuning` (no `phase0_game` running), so `request_toggle` had no cooldown source | Task 6 states how the test configures it | — |
| F24 | `PhaseState.register()` plus groups is a dual mechanism; the persistent autoload registry holds freed nodes across tests | `register()` dropped; groups iterated at apply time | — |
| F25 | 8 test helpers used but nonexistent; GUT files share no helpers | Task 7 onward name each helper as new, and the FSM helper block is explicitly copied per file | — |
| F26 | Task 2 snippets use `TUNING_PATH`; that file's const is `BASE_CATALOG_PATH` | Corrected | — |
| F27 | Task 4 tests mutate the cached `input.tres` without `duplicate()`, leaking `phase_button_unlocked=true` across the run | `duplicate()` per house idiom | — |
| F28 | `wait_frames` is deprecated in GUT 9.7.1 and logs noise | Switched to `wait_physics_frames`, house style | — |
| F29 | Task 14's rule-violating fixture scenes under `scenes/` would be flagged by the lint's own repo run | Moved to `tests/fixtures/`, outside all scan roots and the export filter | — |
| F30 | `wall_run_bank_degrees: 90.0` labelled **[spec]**; the spec fixes a *constraint* (tangent horizontal on screen), not a number, and 90° only satisfies it on vertical walls | Relabelled **[proposed]**; derived from the strip normal. Task 12's tangent-horizontal test is the real spec artifact | — |
| F31 | `rail_predicted_color` cited §5.3; "rail-orange" is §5.4, and the exact `Color` is a proposal frozen under **[spec]** | Citation corrected; value relabelled **[proposed]** | — |
| F32 | Task 14 claimed all three lint rules are "stated exactly as §5.5 states them"; rule 3 appears in neither §5.5 nor §11.5 | Rule kept, labelled plan-added | — |
| F33 | Task 11 miscited §4.2 for `release_boost_mps`; §4.2 says only "JUMP releases at current arc point" | Citation dropped; value already **[proposed]** | — |
| F34 | Gate F2 criterion 4 dropped the spec's designated person and pass bar | Restored verbatim: the camera never disorients **the blind-transfer friend** — asked, not assumed | — |
| F35 | Scope section credited the tripwire with blocking levels/gems/relics/save/warp rooms; Task 1 narrows it to exactly `enemy` and `crate` | Claim corrected to what the lint actually enforces | — |
| F36 | Task 15's "checkpoint between each" is Phase-1-adjacent (checkpoint crates are crate economy) | Reworded to a bare debug respawn point | — |
| F37 | Task 1 nits: fixture yields 5 findings not 4; renaming the test import before the script dies with `ModuleNotFoundError` instead of the intended assertion failure; `main()`'s printed strings still say "Phase 0.5"; `git rm` vs `git mv` implied but unstated | All four corrected | — |
| F38 | Rule-1 trap: collision layer masks like `1 << 2` trip the numeric lint in `phase_state.gd` | Task 6 uses `CollisionShape3D.disabled` / 0-1 layer values, called out | — |
| F39 | Task 12's existing readability test (`test_camera_blend.gd:84-100`, depression ≥15°) fails with the new offsets (wall-run ≈14.0°, swing ≈8.1°) — correct per the suspended rule, but Codex would "fix" the offsets | Task 12 states the exemption and asserts it deliberately | — |
| F40 | Camera bank had no channel — `update_camera` ends in `look_at(target, Vector3.UP)` and the rig never learns FSM state; where a `Basis` is consumed and blended was unspecified | Task 12 specifies the channel and the blend over `region_blend_s` | — |
| F41 | `LandingRing.configure()` is `(target, move, depth)` — no source for `rail_samples`; same gap for swing release state and the wall-run blob shadow | Task 13 names the mechanism; blob shadow confirmed to only raycast down (`blob_shadow.gd:46`) and extended in Task 12 | — |

## DEFERRED

| # | Finding | Why deferred | What would unblock |
|---|---|---|---|
| D1 | `solve_wall_attach` tests **velocity** heading; §5.3/§4.2/§5.2 define attach on **input** direction | Velocity is a faithful proxy while the only entry is a run, and the input-heading channel does not exist in the solver's pure signature. Documented in the plan as a known approximation rather than silently decided | If Gate F2 shows unwanted attaches, pass the input heading — it is also step 1 of §5.2's mitigation ladder |
| D2 | §4.2's "JUMP detaches on an **authored** outward arc" read as two global tuning constants; "authored" plausibly means per-strip | Two constants are the cheaper build and are revertible; per-strip authoring is a `.tscn` schema change | Listed in the handback's "ambiguous in the spec" section for the operator to rule on |
| D3 | `-gtest=` does not actually narrow the run — `.gutconfig.json` sets `dirs=["res://tests"]` and gut_config unions config dirs with cmdline tests, so every "single-file" command runs the full suite | Results are correct, only slower; changing it means touching shared test config mid-phase | Post-Gate-F2 cleanup if the loop feels slow |

## NOT APPLICABLE

| # | Finding | Evidence |
|---|---|---|
| N1 | Concern that spline-constrained states + `move_and_slide` are incoherent in Godot 4 | Verified sound — it is the existing Phase 0 pattern (hand-integrated velocity, single `move_and_slide()` at `player_controller.gd:301`) extended. The four engine-fight notes are fixed under F20 |
| N2 | Concern that `rail_bake_interval_m` is a number with no home | Confirmed an existing `CameraTuning` field; no action |
| N3 | Concern that autoloads may not resolve under `-s` SceneTree scripts | Verified empirically on the pinned 4.7.1 binary; `/root/PhaseState` resolves under `gut_cmdln` |
| N4 | Concern that Task 2's field additions break existing Phase 0 tests | They break only if `tuning_service` is extended incompletely, and then they break *loudly* (`test_tuning_service.gd:184`, `tuning_service.gd:72`). The silent risks were F1/F4, both fixed |
| N5 | Concern that reusing `InputTuning.jump_buffer_s` for detach and hop is wrong | Verified correct per §5.3 ("same 120ms buffer"; "Detach is a jump; it inherits jump's forgiveness") and §4.2 ("hop window = jump buffer"). A separate field would permit divergence the spec forbids |
| N6 | Concern that §11.8's phase invariants were under-tested | Task 5's exactly-one-solid assertion is strictly stronger than never-both-solid and implies it; cooldown covered. Only the frame-timing hole was real (F22) |
| N7 | Task ordering dependency inversions | All 13 original tasks walked; every Consumes satisfied by an earlier task or existing code. The sole hole was F17 |
| N8 | Git safety of the plan | No `git push`, no remote, no `checkout --`, no `reset` anywhere. `git rm` refuses on modified files by default. The only real issue was F18's directory-level staging |
| N9 | GUT 9.7.1 idiom availability | All verified present in the vendored source: `assert_ne` :894, `assert_almost_eq` :929, `assert_lt` :1027, `assert_gt` :980, `add_child_autofree` :2780, `-gtest` :116, `-gexit` :129 |
| N10 | Four `[spec]` numbers other than the two mislabels | Verified exact against the design doc: 25.0° (§4.2/§5.3), 0.35m (§4.2/§5.3), 0.25s (§4.2/§5.3), ~30% ghost opacity (§5.5), 10mm PHASE (§5.2). No `[proposed]` number is actually fixed by the spec |

## One spec problem to pass upstream

§5.4 item 1 says the ≥15° rule is "replaced, see 5.6", but the substitute rule actually lives
in §5.5. The plan cites §5.5 correctly; the design doc's cross-reference is wrong and should be
corrected at the next spec edit.
