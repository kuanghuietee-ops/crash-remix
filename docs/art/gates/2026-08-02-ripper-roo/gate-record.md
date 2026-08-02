# Ripper Roo — likeness gate record

> **Human-only gate.** The coding agent cannot run, judge, certify, or fill
> in a result below. Nothing on this page marks the face accepted. Per the
> R8 plan's own Global Constraints: "an agent NEVER marks a face accepted,
> flips a fallback to a real scene without an explicit operator acceptance
> in the conversation, or describes a gate as passed."

**Result: ACCEPTED BY OPERATOR, 2026-08-02** (explicit conversation
directive: "flip all 3", after reviewing the three delivered render sets).
Transcribed by agent per the human-only gate rule — the judgment is the
operator's.

## What this gate blocks

`data/racing/drivers/ripper_roo.tres` stays `character_scene_path = ""`
(fallback-active — Ripper Roo resolves to the lab-assistant mesh at mount
time, `DriverRegistry`'s own documented fallback rule) until the operator
accepts this face in conversation. The flip itself is a one-line data change
the operator authorizes; nothing in this task performs it.

## Prerequisites

| Item | Record |
|---|---|
| Date | 2026-08-02 |
| Builder script | `scripts/blender/create_ripper_roo.py` |
| Model file | `assets/models/characters/SK_ripper_roo.glb` |
| Triangle count | 11288 (hero band 10000–12000, `data/tuning/art_budget.tres`) |
| Vertices / faces | 5732 / 5852 |
| Actions | `A_ripper_roo_idle` (springy vertical-bounce idle, 41 frames), `A_crash_hog_ride` (seated mount clip, static 2-key hold, deeper thigh/shin fold than Cortex's/Coco's own to tuck the big feet onto the cowl) |
| Rig | Compact custom skeleton (`RIG_ripper_roo`, `create_rig()`), not Rigify — plain bone names, same convention as Cortex's/Coco's own, but a DISTINCT body plan/proportions (not the Crash family) |
| Proportion sheet | `docs/art/references/ripper-roo-likeness-proportions.svg` |
| Shown how | Gate renders below (Blender headless, EEVEE, GPU-dependent flags off) |

## Gate renders

Three views, captured by `create_gate_renders()` inside
`scripts/blender/create_ripper_roo.py` (part of the same build that exports
the GLB — regenerate both together by re-running the builder):

1. `01-front.png` — front-on, standing idle pose (frame 1).
2. `02-three-quarter.png` — three-quarter angle, standing idle pose (frame
   1; the elongated kangaroo foot reads most clearly from this angle).
3. `03-seated-on-kart.png` — seated action, mounted (illustratively) on a
   render-only kart mesh reused from `build_kart.py`'s own real geometry,
   camera placed at the actual gameplay chase-camera numbers
   (`data/tuning/racing/race.tres`: `camera_trail_m=4.6`,
   `camera_height_m=2.2`, `camera_look_height_m=1.0`,
   `camera_fov_base=60°`). The camera trails behind the kart exactly like
   the real in-race chase camera, so this view shows Ripper Roo's
   back/seated silhouette (tall ears above the cowl) against the kart body,
   not his face — the front/three-quarter renders above are the
   face-likeness views; this one is the in-race scale/fit view.

**What the seated-on-kart render does and does not prove:** it is a
reasonable illustrative approximation of the runtime mount (Blender's own
Z-up, "-Y-forward" authoring space, not a reproduction of `kart.tscn`'s
exact node hierarchy or the Visual node's authored 180° yaw correction).
The real numeric fit — head clears the kart's own real Visual-mesh AABB,
hands stay within its real body width, feet stay grounded — is proven
separately, in actual Godot space, by
`tests/racing/test_kart_controller.gd`'s
`test_ripper_roo_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width`,
using the exact same authored values below. That GUT test mounts
`SK_ripper_roo.glb` directly (not through `DriverRegistry`/
`ripper_roo.tres`), so it proves the asset's fit without touching the
registry or flipping anything.

## Authored fit values (for the operator's eventual flip)

If accepted, `data/racing/drivers/ripper_roo.tres` would take:

```
character_scene_path = "res://assets/models/characters/SK_ripper_roo.glb"
seat_scale = 0.85
seat_offset = Vector3(0, -0.08, 0)
```

These are the same `GATE_SEAT_SCALE` / `GATE_SEAT_OFFSET_GODOT` constants
authored in `create_ripper_roo.py` and the same `RIPPER_ROO_SEAT_SCALE` /
`RIPPER_ROO_SEAT_OFFSET` constants the GUT mounted-fit test above uses —
proven against the real mounted scene, not assumed from the authoring math.
Measured directly: with these values, head clears the kart's own real
Visual-mesh AABB top by ≈0.28 m (well under the test's own +0.9 m ceiling),
both hands stay within the kart body's real X-width (±0.028 m against a
±0.89 m body), and the left foot rests at y≈0.61 m, grounded between the
kart's own floor and its cowl top (y≈0.79 m) — no iteration on the scale
itself was needed once the rig's own proportions were fixed, similar to
Cortex's own first-measurement success. Deliberately re-verified with teeth
during this task: temporarily setting `RIPPER_ROO_SEAT_SCALE` to an absurd
`4.0` in the test made the same assertions fail with the expected specific
messages (head towering to `head_y=3.88` past the `kart_top_y+0.9=1.85`
ceiling, the left foot floating at `foot_l_y=1.68` above the cowl) before
being reverted to the authored `0.85` — the bounds are not tautological.

## Likeness traits authored (task brief's own four)

- **Straitjacket torso, a single wrapped silhouette** — one big
  `add_cone_between` canvas body (not a jacket layered over a separate bare
  torso), three horizontal buckle straps (`add_rounded_box`), and both
  sleeves modelled as extra-thick canvas tubes that converge and cinch
  together at a single cuff in front of the belly — "arms bound in the
  jacket," not free-swinging bare arms. Authored geometry and vertex colour
  only, no texture.
- **Oversized kangaroo feet** — an elongated foot-pad sphere plus a tapered
  forward toe cone per foot, with the underlying `foot` bone itself
  authored roughly 1.4x the ankle-to-toe span Cortex's own boot uses (not
  just a bigger mesh riding on a normal-sized bone).
- **Tongue-out head read** — a wide grin (a single broad mouth box, pushed
  out past the jaw sphere's own front surface so it reads as a raised grin
  rather than sitting embedded in the head mesh), a dangling tongue
  (authored tapered-cone geometry hanging well past the chin, not a
  texture), and tall ears (two long thin cones reaching to ≈1.50 m,
  well above the cranium's own ≈1.16 m apex) — the single largest
  silhouette departure from Cortex's bald dome or Coco's ponytail.
- **Blue fur palette** — distinct from Crash's orange, Cortex's sallow
  skin, and Coco's warm orange; a saturated blue fur with a darker
  blue-grey toe-pad accent, paired with a cream straitjacket canvas and
  dark leather straps/cuffs.

Behavioural traits (not silhouette, but also brief-named): a springy
vertical-bounce idle (`A_ripper_roo_idle` drives a much larger `root`
Z-location swing than Cortex's/Coco's own small standing sway, plus
thigh/shin compression — a genuine hop cycle, not a reuse of the other two
builders' sway shape) and a seated action with a deeper thigh/shin fold than
Cortex's/Coco's own `SEATED_POSE` to tuck the big feet up onto the kart's
own cowl.

No stitches, no bandages, no chain, no other Ripper-Roo-canon iconography —
the brief names exactly the four traits above (YAGNI, same shape as Coco's
own "no laptop" precedent). Enforced by
`tests/lint/test_ripper_roo_builder.py`'s own
`test_no_props_beyond_the_straitjacket_read`, scoped to `build_parts()`'s
body.

## A real non-determinism found and fixed during this task

The first authored cranium (a single `add_sphere` at `segments=46,
rings=26`) produced a real, intermittent (roughly 1-in-4) triangle-index-set
mismatch between two independent builds, isolated by bisection to the
cranium's own vertex range — a UV-seam tie-break ambiguity in Blender's
`smart_project()` at that sphere's size, not a `--threads` scheduling
artifact (pinning `--threads 1` did not stabilize it). Reverting the
cranium to Cortex's own proven-stable `segments=40, rings=22` (same
technique, smaller single island) eliminated it: 14/14 independent two-build
comparisons showed zero triangle-set difference afterward, and the
determinism test in `tests/lint/test_ripper_roo_builder.py` was re-run three
full times with zero failures before this task was treated as done. The
triangle count this cost (11908 → 11288) stayed comfortably inside the
10000–12000 hero band.

## If the operator declines

Ripper Roo re-enters the builder loop (adjust
`scripts/blender/create_ripper_roo.py`, rebuild, re-render the gate images,
update this record) without blocking Cortex, Coco, or anything else in the
roster — the fallback rule means an unfinished face never breaks a race or
blocks the round.

## Flip checklist (once accepted)

CTR R8 final-review fix wave (whole-branch reviewer [IMPORTANT], docs-only):
each gate record above describes the flip as "a one-line data change," but
flipping ANY of cortex/coco/ripper_roo also breaks five test files that
hardcode which driver ids are still fallback-active. Papu's own flip
(commits `0b7945a` / `709ec70`) is the worked template for both halves of
this — follow the same shape here.

**1. The data change** (mirrors papu's own diff in `0b7945a`, the exact
`data/racing/drivers/papu.tres` before/after):

`data/racing/drivers/ripper_roo.tres` — set:
```
character_scene_path = "res://assets/models/characters/SK_ripper_roo.glb"
seat_scale = 0.85
seat_offset = Vector3(0, -0.08, 0)
```
(the same values already recorded above under "Authored fit values",
proven against the real mounted scene by
`test_ripper_roo_seated_fit_clears_the_kart_cowl_and_stays_within_the_body_width`).

**2. The five test files that must be updated in the same commit** (each
still hard-codes ripper_roo as fallback-active; the driver id count/list is
not derived at runtime):

- `tests/integration/test_race_flow_r6_e2e.gd` — remove `"ripper_roo"` from
  the `_EXPECTED_FALLBACK_DRIVER_IDS` array and decrement the
  `expected_fallback_warning_count` assertion from 3 to 2 (one warning per
  fallback driver, one race).
- `tests/integration/test_cup_flow_e2e.gd` — remove `"ripper_roo"` from its
  own `_EXPECTED_FALLBACK_DRIVER_IDS` array and decrement the count
  assertion from 6 to 4 (two remaining fallback drivers × two races).
- `tests/integration/test_r8_papu_cup_reload_e2e.gd` — same shape: remove
  `"ripper_roo"` from `_EXPECTED_FALLBACK_DRIVER_IDS`, decrement the count
  assertion from 6 to 4.
- `tests/ui/test_driver_select_overlay.gd` — in
  `test_fallback_active_drivers_render_the_fallback_never_lie()`: remove
  `"ripper_roo"` from the "must show FALLBACK" id list and add it to the
  "must NOT show FALLBACK" id list (the same list papu's own id moved into
  on his flip).
- `tests/racing/roster/test_driver_registry.gd` — remove `"ripper_roo"`
  from the fallback-id loop in
  `test_character_scene_falls_back_to_lab_assistant_for_an_empty_path()`,
  and add a dedicated
  `test_character_scene_resolves_ripper_roo_to_the_real_...` test mirroring
  the existing `test_character_scene_resolves_papu_to_the_real_seated_model`
  case.

**3. Full-suite green requirement.** As with papu's own flip: rebuild the
GLB if anything in `create_ripper_roo.py` changed, re-run the GLB-dependent
GUT tests, then run the FULL suite (`bash scripts/run_gut.sh`) foreground
and confirm it is fully green (baseline GUT count at the time of this
checklist: 1555; grep raw GUT output for `Parse Error` and confirm zero)
before treating the flip as done — never partial-suite or a single-file
run.

Operator name / date:
