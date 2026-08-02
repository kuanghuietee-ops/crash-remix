# CTR R8 — Characters, Select, Classes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six-driver roster with a select screen and CTR handling classes — per `docs/superpowers/specs/2026-08-02-ctr-r8-characters-design.md` (approach A: mechanics first, faces stream in behind likeness gates).

**Architecture:** A `DriverEntry` resource table (the `track_registry.gd` precedent) replaces RaceSession's two hardcoded character consts; a `DriverClass` resource multiplies three base `KartTuning` fields onto a per-kart copy at configure (shared resource never mutated, live-refresh recomposes); select screen is a menu overlay in front of race starts; save v3→v4 carries the pick; ghost file v2 carries the driver id. Three new Blender builders follow `character_asset_common.py`; likeness gates are operator-only and asynchronous — fallback mesh until accepted.

**Tech Stack:** Godot 4 / GDScript, GUT + Python suites, Blender headless builders.

## Global Constraints

Same as R7's (literals 0/1/-1 in `src/racing/**`; tuning provably live; TDD; suites green each commit — baseline GUT 1473 / Py 262 / lints + export verifier; grep raw GUT output for 'Parse Error'; known flakes island_slice/camera_archetypes/main_boot-renderer-cull — re-run isolated; stage explicit paths; never stage the two other-agent WIP docs (`docs/qa/phase05-gate-f2.md`, `docs/superpowers/specs/2026-07-23-crash-remix-design.md`); FOREGROUND suites only). Save schema changes carry the scratch-verified migration rigor. **Likeness gates are human-only (repo rule 3): an agent NEVER marks a face accepted, flips a fallback to a real scene without an explicit operator acceptance in the conversation, or describes a gate as passed.** Every asset byte original. Operator's R6 fixes (front-grid player, seated assistants) and R7 behavior survive untouched.

---

### Task 1: DriverClass resource + per-kart composition

**Files:** Create `src/tuning/driver_class.gd` (`class_name DriverClass extends Resource`; `@export var top_speed_mult: float`, `@export var accel_mult: float`, `@export var steer_rate_mult: float`); create `data/tuning/racing/classes/balanced.tres` (1.0/1.0/1.0), `speed.tres` (1.06/0.97/0.90), `accel.tres` (0.98/1.12/1.02), `turning.tres` (0.96/1.0/1.12) — these defaults are feel-gate fodder, not sacred, but they ARE the shipped values until the operator says otherwise; modify `src/tuning/kart_tuning.gd` with `func composed_with(driver_class: DriverClass) -> KartTuning` — `duplicate()` then multiply exactly `top_speed_mps`, `accel_mps2`, `steer_rate_degrees_per_s`; nothing else changes, `null` class returns a plain duplicate. Modify the kart configure path in `src/racing/race_session.gd`: every kart (player AND AI) receives `catalog.kart.composed_with(its_driver_class)` instead of the shared resource. **Tuning-live:** find the live-refresh path (the same one that re-applies `kart_tint_player` around race_session.gd:1119) and make it recompose base×class — a mid-race tuning edit must reach a classed kart. Registration per precedent (classes load beside the existing `data/tuning/racing/*.tres` catalog; follow how `ai.tres`/`fx.tres` got registered, including the debug fingerprint).

**Interfaces:** Produces `DriverClass` (three floats) and `KartTuning.composed_with(DriverClass) -> KartTuning`. Task 2 assigns classes to drivers; until then RaceSession composes with `null` (behavior identical — pin that with a test).

- [ ] TDD: composed copy multiplies exactly the three fields and no others; shared resource unmutated after compose; null class = identical values; live-refresh recompose reaches a configured kart; fingerprint moves when a class value changes. Suites → commit.

### Task 2: Driver registry + RaceSession mounting/fill

**Files:** Create `src/racing/roster/driver_entry.gd` (`class_name DriverEntry extends Resource`: `@export var id: StringName`, `display_name: String`, `character_scene_path: String`, `driver_class_path: String`, `seat_scale: float`, `seat_offset: Vector3`); create `src/racing/roster/driver_registry.gd` (the `track_registry.gd` shape: const table of the six entries in fixed order crash, papu, cortex, coco, ripper_roo, lab_assistant; `entries() -> Array[DriverEntry]`, `entry(id: StringName) -> DriverEntry`, `character_scene(id) -> PackedScene` — loads `character_scene_path`, and a missing/empty/unloadable path returns the lab-assistant scene silently (the spec's fallback rule; push_warning once, never an error), `driver_class(id) -> DriverClass` with null-safe load); create `data/racing/drivers/{crash,papu,cortex,coco,ripper_roo,lab_assistant}.tres` — crash + lab_assistant point at the existing GLBs; papu/cortex/coco/ripper_roo ship with EMPTY `character_scene_path` (fallback active) until their own tasks/gates land; class assignments: crash/cortex/lab_assistant→balanced, papu→speed, coco→accel, ripper_roo→turning. Modify `src/racing/race_session.gd`: delete the `CrashCharacterSceneType`/`LabAssistantCharacterSceneType` consts; player kart mounts `registry.character_scene(selected_driver_id)` (a `configure_selected_driver(id: StringName)` setter, default `&"crash"`); `_spawn_ai_karts` (the mount at ~line 2058) seats the five drivers the player did NOT pick, registry order, slot order — deterministic, no duplicates; `apply_body_tint` stays exactly `tint_for_slot(slot_index)` / `kart_tint_player` (tints are slot traits — pin it); each kart composes its driver's class (this makes Task 1's composition real: player and AI both).

**Interfaces:** Consumes `KartTuning.composed_with` (Task 1). Produces `DriverRegistry.entries()/entry()/character_scene()/driver_class()` and `RaceSession.configure_selected_driver(StringName)` — Tasks 3-5 rely on these exact names.

- [ ] TDD: registry resolution + fallback (empty path → lab assistant, no error); AI fill excludes the pick, deterministic, 5 distinct; player mounts pick; tints unchanged per slot; per-class Temple Twilight health race — 20s real-physics 6-kart with classes ACTIVE, every AI healthy-or-recovered, respawns ≤ R7 baseline, run once per non-balanced class (speed/accel/turning as the player-absent field mix): the Speed-on-hairpins named risk gets its dedicated bound here. Suites → commit.

### Task 3: Save v3→v4 + ghost file v2

**Files:** Modify `src/core/save_model.gd`: `SCHEMA_VERSION` 3→4; `_migrate_v3_to_v4` adds `racing.selected_driver: "crash"`; the migrate match gains `3:` per the existing chain shape; validation: `selected_driver` not a String or not a registry id → fail closed to `"crash"` (validate against `DriverRegistry` ids). Modify `src/core/save_service.gd` only if the service surface needs a getter/setter per precedent of how `cups` got exposed. Modify `src/racing/flow/ghost_recorder.gd` + `ghost_player.gd`: `FILE_VERSION` 1→2, store the driver id (pascal string) immediately after the version word; loader accepts v1 (driver = `"crash"`) AND v2; corrupt id → treat file as absent (the existing corrupt-file silence contract).

**Interfaces:** Consumes `DriverRegistry` ids (Task 2). Produces `racing.selected_driver` in the save and a driver id on loaded ghosts — Task 4 reads/writes the save field; ghost replay may mount the ghost driver's mesh translucently ONLY if the existing ghost visual already mounts meshes (it does not — it is a palette-ghost kart; keep it, record the id for forward use, do not add a character to the ghost this round).

- [ ] TDD: scratch chains v1→v4, v2→v4, v3→v4 (existing bests + cups survive), corrupt/unknown driver → crash, future-version refusal intact; ghost v1 file loads with crash id, v2 round-trips, corrupt id silent. Suites → commit.

### Task 4: CHOOSE DRIVER select screen + cup pick-once

**Files:** Create `src/ui/driver_select_overlay.gd` + `scenes/ui/driver_select_overlay.tscn` (follow `level_list_overlay.gd`'s registry-driven shape): six tiles from `DriverRegistry.entries()` — display name + class chip (chip text from the class resource file name per entry mapping; no new literals — strings are UI copy, fine), tile for a fallback-active driver renders the fallback (never lies); confirm writes `racing.selected_driver` via the save path Task 3 built and calls `RaceSession.configure_selected_driver`. Modify the racing menu flow in `src/core/game_root.gd` (+ `src/ui/level_list_overlay.gd` if entries route there): RACE / TIME TRIAL / CUP entries route through the select overlay first (skip = keep last pick, default crash); CUP picks ONCE at cup start and `src/racing/flow/cup_session.gd` holds the id for both races (AI lineup continuity already free from the grid-slot scheme — pin with a test that race 2's field equals race 1's).

**Interfaces:** Consumes `DriverRegistry.entries()` (Task 2), save field (Task 3), `configure_selected_driver` (Task 2).

- [ ] TDD: overlay lists six in registry order; confirm persists + reload shows the pick; race spawns the picked driver; cup holds the pick and the SAME AI field across both races; menu tests ported not weakened. Suites → commit.

### Task 5: Papu seated variant + seat fit

**Files:** Modify `scripts/blender/create_papu.py` (or a sibling `create_papu_seated.py` reusing its builders — implementer judgment, byte-deterministic either way) to export a seated action per the R6 Crash seated precedent (see how the existing seated pose is applied at mount — `data/tuning/racing/seat_pose.tres` and the R6 Task 3 notes; reuse that path, do not invent a second seating mechanism); output `assets/models/characters/SK_papu_seated.glb` (characters dir, racing-facing) OR reuse `SK_papu.glb` with the seat-pose path if the existing mechanism poses at mount — read first, pick the one the R6 precedent actually supports, document which and why in the commit; author `seat_scale`/`seat_offset` on papu's DriverEntry so he FITS (he is much larger than Crash — the fit is authored: kart visual not clipped, head above cowl, test asserts mounted AABB within authored bounds vs the kart body). Flip papu's `character_scene_path` live — his likeness was already operator-accepted in the platformer; the seated POSE is new posing of a gated mesh, not a new face. **If the seated read materially changes the likeness (implementer doubt = it does), STOP the flip, leave fallback, and flag for the operator's gate instead.**

**Interfaces:** Consumes DriverEntry fields (Task 2). Produces the first non-Crash real face in the field.

- [ ] TDD: builder determinism (two runs byte-identical GLB — the existing builder-determinism test shape), mounted-fit AABB bound, registry now resolves papu to the real scene, art-budget lint green. Suites → commit.

### Task 6: Cortex builder (likeness gate: OPERATOR)

**Files:** Create `scripts/blender/create_cortex.py` on `character_asset_common.py` (one vertex-coloured mesh, compact skeleton, idle + seated actions per the Papu/Crash precedent): the read at kart distance is the silhouette — oversized head, N-forehead mark (authored geometry/vertex colour, no textures beyond the palette conventions), goatee, small body; proportion reference sheet added under `docs/art/references/` (the crash-likeness-proportions precedent); export `assets/models/characters/SK_cortex.glb`; cortex DriverEntry stays FALLBACK; capture gate renders (front/three-quarter/seated-on-kart at gameplay camera distance) into `docs/art/gates/2026-08-02-cortex/` + a gate record doc stating PENDING OPERATOR. **Do not flip the registry entry. The operator's acceptance in conversation is the only flip authorization (Global Constraints).**

**Interfaces:** Consumes builder commons + DriverEntry (Task 2). Produces a gate-ready face; the flip is a one-line data change on acceptance.

- [ ] TDD: builder determinism, GLB self-contained (no external refs — export verifier), art-budget lint, mounted-fit AABB with cortex's authored seat fields. Suites → commit.

### Task 7: Coco builder (likeness gate: OPERATOR)

**Files:** Create `scripts/blender/create_coco.py` — reuse `create_crash_likeness.py`'s proportion scaffolding (same skeleton family, smaller frame, ponytail as authored geometry, laptop NOT included — YAGNI): export `assets/models/characters/SK_coco.glb`; proportion sheet + gate renders `docs/art/gates/2026-08-02-coco/` + PENDING OPERATOR record; DriverEntry stays FALLBACK; same flip rule as Task 6 verbatim.

**Interfaces:** Same shape as Task 6.

- [ ] TDD: builder determinism, self-contained GLB, art-budget lint, mounted-fit AABB. Suites → commit.

### Task 8: Ripper Roo builder (likeness gate: OPERATOR)

**Files:** Create `scripts/blender/create_ripper_roo.py` — distinct body plan (most builder work of the three: straitjacket torso as a single wrapped silhouette, oversized feet, tongue-out head read; springy idle action, seated action tucks the feet onto the cowl): export `assets/models/characters/SK_ripper_roo.glb`; proportion sheet + gate renders `docs/art/gates/2026-08-02-ripper-roo/` + PENDING OPERATOR record; DriverEntry stays FALLBACK; same flip rule as Task 6 verbatim.

**Interfaces:** Same shape as Task 6.

- [ ] TDD: builder determinism, self-contained GLB, art-budget lint, mounted-fit AABB. Suites → commit.

### Task 9: Integration, verification, R8 APK readiness

- [ ] E2E: select papu → full cup (both tracks, real countdown race 1, teleport-finish, standings chain) → save write → fresh reload shows the pick and papu seated; per-class health-race battery green (Task 2's) re-run on the merged tree; ghost v1 compat + v2 round-trip re-verified; full sweep (GUT/Py/lints/export verifier — new .tres + GLBs in pack); spec bookkeeping (fallback-active drivers listed honestly; new debts recorded; gate records PENDING OPERATOR — never "passed"); R8 summary. Orchestrator merges + builds APK.

## Self-Review

- Spec coverage: B→T1, A+D→T2, E+F→T3, C→T4, G→T5-T8, testing/gates→each task + T9. Roster order fixed in T2 so AI fill is deterministic everywhere.
- Class defaults stated numerically (T1); the spec's named Speed-on-hairpins risk has a dedicated bound (T2).
- Type consistency: `DriverClass` three mults (T1) = the three fields `composed_with` touches (T1) = what T2 composes; `configure_selected_driver(StringName)` used in T2/T3/T4; registry method names identical across T2-T5.
- Human-gate rule appears in Global Constraints AND per-face tasks — an implementer reading only their task cannot miss it.
