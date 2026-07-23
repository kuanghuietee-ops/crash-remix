# N4 camera-assertion fix handback

Date: 2026-07-23

Starting revision: `7d7c313`

Implementation revision: `fea1a3f`

## Outcome

N4 is fixed without changing camera behavior, tuning values, authored
geometry, or scenes. The existing horizon checks remain, and each traversal
archetype now also asserts the screen-axis dominance of the shot that actually
ships. One new live-canyon test checks the slot shot's readability guarantee.

The exact dated operator decision was appended to design §5.5. Gate F and Gate
F2 remain human-only; neither was run, judged, scored, filled in, or inferred.

## Derived camera characters

The derivation used `data/tuning/camera.tres` and the offset-axis mapping in
`CameraRailController.update_camera`:

| Archetype | Authored offset and live placement | Required dominance | Plan table |
| --- | --- | --- | --- |
| Wall-run | `(6, 1.5, 0)` is remapped to trail 6 m along the strip, rise 1.5 m, and add no lateral displacement. The look target is 8 m forward from the camera, with only the 0.85 m vertical and 0.45 m screen-bias deltas. | Depth axis: `abs(z) > abs(x)` | Matched |
| Grind | `(0, 3.5, -7)` places the camera 7 m ahead along the rail and 3.5 m up, with zero lateral displacement. The look target is 5 m back from the camera along the rail, plus the vertical and screen-bias deltas. | Depth axis: `abs(z) > abs(x)` | Matched |
| Swing | `(7, 1, 0)` places the camera 7 m lateral and 1 m up. Swing look-ahead is zero, so the view has no tangent component. | Side-on: `abs(x) > abs(z)` | Matched |

The original `tangent_on_screen.y ≈ 0` assertion remains for all three
archetypes. It is now paired with the applicable dominance assertion.

The grind observation in the plan is confirmed: its current lateral component
is zero even though §5.5 says the camera side-biases. No tuning value was
changed.

## Required 90-degree failure proof

Before the scratch cases were removed, each controller-derived view direction
was rotated with:

`view_direction.rotated(Vector3.UP, deg_to_rad(90.0))`

`Vector3.UP` is the derived surface up for both tested wall normals, the rail
up for grind, and the swing-plane up for the tested pendulum plane.

The red run produced **220/223 passing with three failing tests**:

- Wall-run, both `Vector3.RIGHT` and `Vector3.LEFT` surface normals: the new
  depth check failed with `|z| ≈ 0.055848` versus `|x| ≈ 0.998439`.
- Grind: the new depth check failed with `|z| ≈ 0.077952` versus
  `|x| ≈ 0.996957`.
- Swing: the new side-on check failed with `|x| ≈ 0.053359` versus
  `|z| ≈ 0.998575`. The pre-existing tangent/view and side-sign assertions
  also failed under this intentionally inverted shot.

The three temporary rotation statements were then removed. No scratch case
remains in the committed test.

## Live-canyon frustum result

**Passed on both strips.**

`test_wall_run_detach_target_is_visible_before_detach_on_both_walls`
instantiates the authored wall-run canyon, the real player scene, and the real
camera controller. It attaches at the non-zero distance **4.0 m** on
`LeftStrip` and `RightStrip`, settles the real wall-run camera, confirms the
player is still in `wall_run`, and calls
`Camera3D.is_position_in_frustum()` for the authored `LandingPad` detach
target. Both checks pass before detachment.

No camera, tuning, or test threshold was changed to obtain this result.

## Final automated verification

| Check | Result |
| --- | --- |
| GUT | **224/224 passing**, **1,826 assertions**, 20 scripts |
| Python unittest discovery | **22/22 passing** |
| Gameplay numeric-literal lint | Passed |
| Content-vocabulary tripwire | Passed |
| Traversal authoring lint | Passed, exit 0 with no findings |
| Exported-tuning verifier | Passed, `EXIT=0` |

The GUT count increased from 223 to 224. No test was deleted, weakened,
skipped, or marked pending.

## Scope and audit notes

- Implementation commit: `fea1a3f` —
  `Make the camera archetype assertions falsifiable and record the slot-shot decision`.
- No file under `src/gameplay/camera/`, `data/tuning/`, or `scenes/` changed.
- Waves 2 and 3 were not touched.
- No APK was rebuilt and no device or human-feel test was performed.
- The audit's N4 diagnosis was correct: the old `y ≈ 0` assertion could not
  distinguish opposite shots. Its description of side-on as the intended
  wall-run shot is superseded by the operator's explicit down-the-slot
  decision; that is a contract decision, not a technical error in the
  pre-decision audit. There are no other audit disagreements.
