# Coco Bandicoot — likeness gate record

> **Human-only gate.** The coding agent cannot run, judge, certify, or fill
> in a result below. Nothing on this page marks the face accepted. Per the
> R8 plan's own Global Constraints: "an agent NEVER marks a face accepted,
> flips a fallback to a real scene without an explicit operator acceptance
> in the conversation, or describes a gate as passed."

**Result: PENDING OPERATOR.**

## What this gate blocks

`data/racing/drivers/coco.tres` stays `character_scene_path = ""`
(fallback-active — Coco resolves to the lab-assistant mesh at mount time,
`DriverRegistry`'s own documented fallback rule) until the operator accepts
this face in conversation. The flip itself is a one-line data change the
operator authorizes; nothing in this task performs it.

## Prerequisites

| Item | Record |
|---|---|
| Date | 2026-08-02 |
| Builder script | `scripts/blender/create_coco.py` |
| Model file | `assets/models/characters/SK_coco.glb` |
| Triangle count | 10700 (hero band 10000–12000, `data/tuning/art_budget.tres`) |
| Vertices / faces | 5450 / 5648 |
| Actions | `A_coco_idle` (standing idle, 41 frames), `A_crash_hog_ride` (seated mount clip, static 2-key hold) |
| Rig | Compact custom skeleton (`RIG_coco`, `create_rig()`), not Rigify — plain bone names, same shape as Cortex's own |
| Proportion sheet | `docs/art/references/coco-likeness-proportions.svg` |
| Shown how | Gate renders below (Blender headless, EEVEE, GPU-dependent flags off) |

## Gate renders

Three views, captured by `create_gate_renders()` inside
`scripts/blender/create_coco.py` (part of the same build that exports the
GLB — regenerate both together by re-running the builder):

1. `01-front.png` — front-on, standing idle pose.
2. `02-three-quarter.png` — three-quarter angle, standing idle pose (the
   ponytail reads most clearly from this angle).
3. `03-seated-on-kart.png` — seated action, mounted (illustratively) on a
   render-only kart mesh reused from `build_kart.py`'s own real geometry,
   camera placed at the actual gameplay chase-camera numbers
   (`data/tuning/racing/race.tres`: `camera_trail_m=4.6`,
   `camera_height_m=2.2`, `camera_look_height_m=1.0`,
   `camera_fov_base=60°`). The camera trails behind the kart exactly like
   the real in-race chase camera, so this view shows Coco's back/seated
   silhouette against the kart body, not her face — the front/three-quarter
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
`test_coco_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width`,
using the exact same authored values below. That GUT test mounts
`SK_coco.glb` directly (not through `DriverRegistry`/`coco.tres`), so it
proves the asset's fit without touching the registry or flipping anything.

## Authored fit values (for the operator's eventual flip)

If accepted, `data/racing/drivers/coco.tres` would take:

```
character_scene_path = "res://assets/models/characters/SK_coco.glb"
seat_scale = 1.0
seat_offset = Vector3(0, -0.03, 0)
```

These are the same `GATE_SEAT_SCALE` / `GATE_SEAT_OFFSET_GODOT` constants
authored in `create_coco.py` and the same `COCO_SEAT_SCALE` /
`COCO_SEAT_OFFSET` constants the GUT mounted-fit test above uses — proven
against the real mounted scene, not assumed from the authoring math (the
mounted-fit test passed against these exact values on first measurement;
no iteration was needed, consistent with Coco being authored to a smaller/
slighter raw rig size than Cortex's own — her scale lands close to 1:1
rather than needing Cortex's 0.90 down-scale or Papu's 0.62). Deliberately
re-verified with teeth during this task: temporarily setting
`COCO_SEAT_SCALE` to an absurd `4.0` in the test made the same assertions
fail with the expected specific messages (head towering past the +0.9m
ceiling, both hands clipped outside the kart body width) before being
reverted to the authored `1.0` — the bounds are not tautological.

## Likeness traits authored (task brief's own three)

- **Blonde ponytail (authored geometry)** — two chained tapered cone
  segments off the back of the skull, a hair-tie band where it meets the
  head, and a small forelock tuft up front so the crown doesn't read as
  bare fur. This is the single largest silhouette departure from both
  Crash's bare head and Cortex's bald bulbous cranium, and is the primary
  distinguishing read at kart distance from the back/three-quarter angles.
- **Smaller, slighter frame than Crash's own model (and Cortex's, which
  was itself authored close to Crash's scale)** — narrower shoulders and
  hips, thinner limb cylinders, and a shorter overall rig height (skull
  apex at 1.155m vs. Cortex's 1.32m on the same unscaled-rig convention).
- **Her own original palette** — warm orange fur / tan muzzle in the same
  "bandicoot family" register as Crash's own fur (so the two read as
  related characters), paired with an entirely fresh outfit: a magenta
  racing tank top with dark straps, khaki cargo shorts, a dark waistband,
  and white sneakers — nothing recoloured from Crash's or Cortex's own
  constants.

No laptop, no props of any kind — explicitly out of scope for this task
(YAGNI; a tech/gadget angle was considered in planning and dropped).
Enforced by `tests/lint/test_coco_builder.py`'s own
`test_no_laptop_geometry`, scoped to `build_parts()`'s body.

## If the operator declines

Coco re-enters the builder loop (adjust `scripts/blender/create_coco.py`,
rebuild, re-render the gate images, update this record) without blocking
Ripper Roo or anything else in the roster — the fallback rule means an
unfinished face never breaks a race or blocks the round.

## Flip checklist (once accepted)

CTR R8 final-review fix wave (whole-branch reviewer [IMPORTANT], docs-only):
each gate record above describes the flip as "a one-line data change," but
flipping ANY of cortex/coco/ripper_roo also breaks five test files that
hardcode which driver ids are still fallback-active. Papu's own flip
(commits `0b7945a` / `709ec70`) is the worked template for both halves of
this — follow the same shape here.

**1. The data change** (mirrors papu's own diff in `0b7945a`, the exact
`data/racing/drivers/papu.tres` before/after):

`data/racing/drivers/coco.tres` — set:
```
character_scene_path = "res://assets/models/characters/SK_coco.glb"
seat_scale = 1.0
seat_offset = Vector3(0, -0.03, 0)
```
(the same values already recorded above under "Authored fit values",
proven against the real mounted scene by
`test_coco_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width`).

**2. The five test files that must be updated in the same commit** (each
still hard-codes coco as fallback-active; the driver id count/list is not
derived at runtime):

- `tests/integration/test_race_flow_r6_e2e.gd` — remove `"coco"` from the
  `_EXPECTED_FALLBACK_DRIVER_IDS` array and decrement the
  `expected_fallback_warning_count` assertion from 3 to 2 (one warning per
  fallback driver, one race).
- `tests/integration/test_cup_flow_e2e.gd` — remove `"coco"` from its own
  `_EXPECTED_FALLBACK_DRIVER_IDS` array and decrement the count assertion
  from 6 to 4 (two remaining fallback drivers × two races).
- `tests/integration/test_r8_papu_cup_reload_e2e.gd` — same shape: remove
  `"coco"` from `_EXPECTED_FALLBACK_DRIVER_IDS`, decrement the count
  assertion from 6 to 4.
- `tests/ui/test_driver_select_overlay.gd` — in
  `test_fallback_active_drivers_render_the_fallback_never_lie()`: remove
  `"coco"` from the "must show FALLBACK" id list and add it to the "must
  NOT show FALLBACK" id list (the same list papu's own id moved into on his
  flip).
- `tests/racing/roster/test_driver_registry.gd` — remove `"coco"` from
  the fallback-id loop in
  `test_character_scene_falls_back_to_lab_assistant_for_an_empty_path()`,
  and add a dedicated `test_character_scene_resolves_coco_to_the_real_...`
  test mirroring the existing
  `test_character_scene_resolves_papu_to_the_real_seated_model` case.

**3. Full-suite green requirement.** As with papu's own flip: rebuild the
GLB if anything in `create_coco.py` changed, re-run the GLB-dependent GUT
tests, then run the FULL suite (`bash scripts/run_gut.sh`) foreground and
confirm it is fully green (baseline GUT count at the time of this checklist:
1555; grep raw GUT output for `Parse Error` and confirm zero) before
treating the flip as done — never partial-suite or a single-file run.

Operator name / date:
