# CLAUDE.md — crash-remix

Rules for any agent (Claude or Codex) working in this repo. `/root/CLAUDE.md` still
applies on top of this — especially: this tree is shared, never `git add -A`, never
`git checkout -- <path>`, stage explicit paths only, and this repo stays **local**
(no remote, no push, no PRs).

## What this is

A 3D mascot platformer for Android in Godot 4 — a greatest-hits rebuild of the
Crash Bandicoot PS1 trilogy. **Personal fan project, sideload only, never distributed.**

Design doc: `docs/superpowers/specs/2026-07-23-crash-remix-design.md`. It is the source
of truth. If the code and the spec disagree, that is a bug in one of them — say which,
don't silently pick.

## The rules that exist because the last project broke them

The predecessor project (`/root/reaper-rush/`) was built to a full MVP by an agent, and
shipped with a core loop nobody had played and a config system that was silently
dead-wired — the runtime used a hardcoded catalog and never loaded the authored assets.
Every rule below exists to make that specific failure impossible here.

### 1. No gameplay numbers in code. [hard]

Every gameplay-affecting number lives in a typed `Resource` under `data/tuning/`
(`MoveTuning`, `CameraTuning`, `InputTuning`, `EconomyTuning`, per-enemy `EnemyTuning`,
per-level `LevelMeta`). Numeric literals in `src/gameplay/**` are banned apart from
`0`, `1` and `-1`, and a pre-commit lint enforces it. If you need a new number, add a
field to a tuning resource — do not inline it "for now".

### 2. The tuning loop must be provably live. [hard]

Debug builds dump every loaded tuning resource path plus a **fingerprint hash of all
values** to the debug HUD at boot. Change a value, redeploy, and if the hash does not
move, the loop is dead-wired and the build is broken — regardless of what the code
looks like. Do not ship a change to the tuning system without checking the hash moves.

The Phase 0 acceptance test (spec §11.4) is: edit gravity in the repo `.tres`, deploy,
see the jump change on device; change it again on-device, restart, see it persist; and
confirm the fingerprint moved both times. All three, or the tuning system does not exist.

### 3. Gates are human-only. [hard]

Gate F (feel), Gate F2 (traversal) and the likeness gate are passed by the operator, on
a real phone, by thumb — or by named friends in the blind-transfer and likeness tests.
**An agent may never mark a gate passed, infer that it passed, or proceed past one.**
Report the gate is ready to run and stop. No level content, art or systems work starts
before Gate F passes.

### 4. Never claim a thing works without having run it.

Report test counts. Report what you did not test. "Should work" is not a status.

## Working conventions

- TDD: failing test first, then the fix. GUT for the pure logic — FSM transitions,
  buffer/coyote timing simulated headless, medal math, save round-trip and migration,
  economy counts against `LevelMeta`.
- The **author lint** walks each level and asserts the spec's authoring rules: every
  required jump passes the ≥15° camera rule (or the wall-run substitute rule), checkpoint
  spacing ≤60s at design pace, crate count matches `LevelMeta`. Keep it green.
- Pure logic stays separate from `Node`/MonoBehaviour-equivalent glue, so it can be
  tested headless. This is the one thing the predecessor got right — keep it.
- Grep every call site of a changed function signature before calling the change done.
- Assets: nothing extracted from any shipped Crash game, ever. CC0 base meshes are fine
  for graybox only; final assets are hand-made. This will be tempting around hour 400.

## Layout

```
src/gameplay/   pure logic + controllers (the lint applies here)
src/ui/         HUD, menus, touch controls
src/debug/      tuning drawer, fingerprint HUD, perf/thermal readout
data/tuning/    *.tres — the single source of truth for every number
scenes/         player, levels, segments, props, enemies
assets/         models, textures, audio (all self-made)
docs/           specs, plans, audits, qa
```
