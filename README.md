# crash-remix

**Crash Bandicoot: N. Sanity Remix** — a trilogy greatest-hits 3D platformer for Android,
built in Godot 4.

**Personal fan project. Sideloaded to the operator and friends only. Never publicly
distributed, never monetised.** No assets are extracted from the PS1 discs or the
N. Sane Trilogy — every model, texture and audio file in this repo is built from scratch.
Audio is original, composed in the style of the originals, not taken from them.

## Start here

**`docs/superpowers/specs/2026-07-23-crash-remix-design.md`** is the design document.
Read it before writing anything. The sections that constrain implementation most:

| Section | What it locks down |
|---|---|
| §4.2 | The verb table — every move and its starting numbers |
| §5.2–5.3 | Touch layout, and the forgiveness windows (buffer/coyote/nudge) |
| §5.4–5.5 | The depth-aid stack, and how the camera survives wall-run/grind |
| §9.4 | Performance budget — draw calls, triangles, texture, lighting |
| §11 | Godot architecture: renderer, language, physics, scene tree, save |
| §11.4 | **The tuning system.** Non-negotiable. See CLAUDE.md. |
| §12 | Phases and the gates that block them |

`docs/superpowers/plans/` holds implementation plans, `docs/audits/` holds audit
findings, `docs/qa/` holds manual test procedures. Same layout as `/root/reaper-rush/`.

## Locked technical decisions

- **Godot 4.7.x**, pinned per phase, upgraded only at phase boundaries — never mid-world.
- **Mobile renderer (Vulkan).** Not Forward+, not Compatibility. Min spec: Vulkan-capable
  Android ~10+.
- **Typed GDScript**, not C#. (§11.3 — the reason is the on-device tuning loop.)
- **Jolt physics**, 60Hz, with 3D physics interpolation on. Gravity and jump arcs are
  hand-integrated in the controller; physics only resolves collision.
- **All lighting baked** (LightmapGI per segment). Blob shadows are a gameplay element,
  not a lighting one — constant size and opacity regardless of light.
- Landscape orientation only. arm64-v8a only.

`project.godot` in this repo is a minimal starting point that encodes those choices.
Open it once in the pinned Godot version and let the editor validate and fill in the
rest — treat the checked-in file as intent, not as a verified-complete config.

## Status

Design drafted 2026-07-23, awaiting sign-off on the 11 open questions in §14 of the
spec. **No implementation has started.** Nothing in `src/`, `scenes/` or `data/` yet.

The archived earlier draft — an original-mascot version of the same design, before the
decision to use the real character — is at
`/root/game-concepts/2026-07-23-mobile-platformer-concept-draft.md`, kept in case any of
that fiction is worth reusing.

## Scope, honestly

The full 25-level plan is ~32–40 months part-time, with self-taught character art on the
critical path (~24 rigged characters, ~800–1,200 hours). The plan is deliberately shaped
so three complete games fall out of it: **Island Cut** (~month 6–9), **Warp Rooms 1–2**
(~month 17, the formal decision point), and the **15-level Trilogy Sampler** (~month 21).
See §13. Build in that order.
