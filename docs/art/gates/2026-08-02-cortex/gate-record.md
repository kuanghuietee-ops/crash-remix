# Dr. Neo Cortex — likeness gate record

> **Human-only gate.** The coding agent cannot run, judge, certify, or fill
> in a result below. Nothing on this page marks the face accepted. Per the
> R8 plan's own Global Constraints: "an agent NEVER marks a face accepted,
> flips a fallback to a real scene without an explicit operator acceptance
> in the conversation, or describes a gate as passed."

**Result: PENDING OPERATOR.**

## What this gate blocks

`data/racing/drivers/cortex.tres` stays `character_scene_path = ""`
(fallback-active — Cortex resolves to the lab-assistant mesh at mount time,
`DriverRegistry`'s own documented fallback rule) until the operator accepts
this face in conversation. The flip itself is a one-line data change the
operator authorizes; nothing in this task performs it.

## Prerequisites

| Item | Record |
|---|---|
| Date | 2026-08-02 |
| Builder script | `scripts/blender/create_cortex.py` |
| Model file | `assets/models/characters/SK_cortex.glb` |
| Triangle count | 11044 (hero band 10000–12000, `data/tuning/art_budget.tres`) |
| Vertices / faces | 5626 / 5874 |
| Actions | `A_cortex_idle` (standing idle, 41 frames), `A_crash_hog_ride` (seated mount clip, static 2-key hold) |
| Rig | Compact custom skeleton (`RIG_cortex`, `create_rig()`), not Rigify — plain bone names |
| Proportion sheet | `docs/art/references/cortex-likeness-proportions.svg` |
| Shown how | Gate renders below (Blender headless, EEVEE, GPU-dependent flags off) |

## Gate renders

Three views, captured by `create_gate_renders()` inside
`scripts/blender/create_cortex.py` (part of the same build that exports the
GLB — regenerate both together by re-running the builder):

1. `01-front.png` — front-on, standing idle pose.
2. `02-three-quarter.png` — three-quarter angle, standing idle pose.
3. `03-seated-on-kart.png` — seated action, mounted (illustratively) on a
   render-only kart mesh reused from `build_kart.py`'s own real geometry,
   camera placed at the actual gameplay chase-camera numbers
   (`data/tuning/racing/race.tres`: `camera_trail_m=4.6`,
   `camera_height_m=2.2`, `camera_look_height_m=1.0`,
   `camera_fov_base=60°`). The camera trails behind the kart exactly like
   the real in-race chase camera, so this view shows Cortex's back/seated
   silhouette against the kart body, not his face — the front/three-quarter
   renders above are the face-likeness views; this one is the in-race
   scale/fit view.

**What the seated-on-kart render does and does not prove:** it is a
reasonable illustrative approximation of the runtime mount (Blender's own
Z-up, "-Y-forward" authoring space, not a reproduction of `kart.tscn`'s
exact node hierarchy or the Visual node's authored 180° yaw correction).
The real numeric fit — head clears the kart's own real Visual-mesh AABB,
hands stay within its real body width, feet stay grounded — is proven
separately, in actual Godot space, by
`tests/racing/test_kart_controller.gd`'s
`test_cortex_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width`,
using the exact same authored values below. That GUT test mounts
`SK_cortex.glb` directly (not through `DriverRegistry`/`cortex.tres`), so it
proves the asset's fit without touching the registry or flipping anything.

## Authored fit values (for the operator's eventual flip)

If accepted, `data/racing/drivers/cortex.tres` would take:

```
character_scene_path = "res://assets/models/characters/SK_cortex.glb"
seat_scale = 0.90
seat_offset = Vector3(0, -0.05, 0)
```

These are the same `GATE_SEAT_SCALE` / `GATE_SEAT_OFFSET_GODOT` constants
authored in `create_cortex.py` and the same `CORTEX_SEAT_SCALE` /
`CORTEX_SEAT_OFFSET` constants the GUT mounted-fit test above uses — proven
against the real mounted scene, not assumed from the authoring math (the
mounted-fit test passed against these exact values on first measurement;
no iteration was needed the way Papu's larger 0.62 scale required in Task
5, consistent with Cortex being authored close to Crash's own scale rather
than Papu's oversized-boss proportions).

## Likeness traits authored (task brief's own four)

- **Oversized, bulbous cranium** — the single largest silhouette departure
  from Crash's own compact wedge head; built from two overlapping spheres
  (a full cranium plus a forward forehead bulge), the same "overlapping
  primitives" technique every other builder in this repo uses (no custom
  per-vertex sculpting).
- **Bold "N" forehead mark** — three thin rounded boxes (two verticals, one
  diagonal), authored geometry and vertex colour only, no texture.
- **Pointed goatee** — a tapered cone off the jaw bone, deliberately
  pointed rather than Papu's round beard.
- **Small body** — thin limbs and a compact coat torso relative to the
  oversized head, the same "small body, big head" kart-racer chibi
  exaggeration Crash's own proportion sheet already established, carried
  further here since the brief names both traits explicitly.

## If the operator declines

Cortex re-enters the builder loop (adjust `scripts/blender/create_cortex.py`,
rebuild, re-render the gate images, update this record) without blocking
Coco, Ripper Roo, or anything else in the roster — the fallback rule means
an unfinished face never breaks a race or blocks the round.

Operator name / date:
