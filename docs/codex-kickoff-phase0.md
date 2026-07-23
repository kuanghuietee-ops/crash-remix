# Codex kickoff — Phase 0 only

Paste the block below into Codex. It is deliberately scoped to Phase 0 and tells Codex
to stop at the feel gate. Do not widen it — the whole point of the phase structure is
that the core feel gets validated on a real phone before any content is built.

Subsequent phases get their own kickoff once Gate F passes.

---

```
Work in /root/crash-remix. It is a local git repo with no remote — never push, never add a remote.

Read these first, in this order, before writing any code:
  1. CLAUDE.md — the repo rules. The three hard rules are non-negotiable.
  2. docs/superpowers/specs/2026-07-23-crash-remix-design.md — the design doc.
     Sections 4.2, 5.2, 5.3, 5.4, 11 and 12 constrain this task directly.
  3. /root/CLAUDE.md — box-wide rules (shared tree, git hygiene).

Build PHASE 0 ONLY, as defined in spec §12. That is:
  - One flat graybox gauntlet scene — no art, no enemies, no crates, no level content.
  - Full input layer: touch (floating stick + JUMP/SPIN/DOWN) and Bluetooth gamepad,
    both emitting a unified buffered, timestamped InputIntent.
  - Character controller: run, jump (variable height), double jump, spin, crouch,
    slide, slide-jump, body slam. Numbers from §4.2 as starting values.
  - Camera rail: Path3D spine + CameraRegion volumes that blend on overlap.
  - Depth aids: constant hard blob shadow, and the ballistic landing ring (§5.4).
  - Forgiveness windows exactly as tabled in §5.3.
  - The ENTIRE tuning system per §11.4: typed .tres resources under data/tuning/,
    the pre-commit lint banning numeric literals in src/gameplay/**, the boot-time
    fingerprint hash on the debug HUD, the on-device slider drawer, and override
    save/load to user://tuning/override.tres.
  - One-click deploy to an Android device.
  - GUT tests for the pure logic: FSM transitions, buffer/coyote timing simulated
    headless, and the tuning resource load path.

Do NOT build: wall-run, rail grind, rope swing, phase-shift (those are Phase 0.5),
any enemy, any crate, any level, any menu beyond what the debug HUD needs, any art.

Hard constraints:
  - Typed GDScript. Not C#.
  - No numeric gameplay literals outside data/tuning/*.tres. The lint must pass.
  - Godot 4.7.x, Mobile (Vulkan) renderer, Jolt, physics 60Hz, physics interpolation on.
  - project.godot in the repo encodes these but is unverified — open it in the editor,
    validate every key against the actual Godot version, and fix what is stale.
  - TDD: failing test first, then the fix.
  - Stage explicit paths when committing. Never `git add -A`, never `git add .`,
    never `git checkout -- <path>`.

STOP when Phase 0 is built and the §11.4 acceptance test passes:
  (a) edit gravity in the repo .tres, deploy, jump changes on device;
  (b) change it on-device, restart the app, the value persists;
  (c) the fingerprint hash moved both times.

Then hand back. Do NOT attempt Gate F. Gate F is the operator playing it on a real
phone by thumb, and no agent may mark it passed or proceed past it.

Report: what you built, the test count, the acceptance-test result, anything in the
spec you could not implement as written and why, and any place the spec was ambiguous
or wrong. Do not report a gate as passed. Do not claim anything works that you did
not run.
```
