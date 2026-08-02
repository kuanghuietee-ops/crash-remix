"""Build Ripper Roo's original vertex-painted racing likeness for Godot.

R8 Task 8 (characters/select/classes): the third and last of three NEW-build
face gates (Cortex/Coco/Ripper Roo -- design spec's own "G. Faces pipeline"
section). Follows the exact reuse shape ``create_cortex.py``/``create_coco.py``
already established on top of ``character_asset_common.py`` -- one
vertex-coloured mesh, one compact custom skeleton (plain bone names, not
Rigify ``DEF-*``), built entirely from the shared primitive kit
(``add_sphere``/``add_cylinder_between``/``add_cone_between``/
``add_rounded_box``).

DISTINCT BODY PLAN. Unlike Cortex and Coco (both explicitly "same family" as
Crash's own compact frame/proportion language), the task brief calls Ripper
Roo out as "the most builder work of the three -- a DISTINCT body plan, not
the Crash family". Nothing here reuses Crash's/Cortex's/Coco's own rig
proportions or part shapes; every measurement below is authored fresh for a
squat, springy, straitjacketed hopper.

LIKENESS READ AT KART DISTANCE (the task brief's own framing): silhouette
only, four authored traits --
  - a straitjacket torso authored as a SINGLE wrapped silhouette (one big
    ``add_cone_between`` canvas body, not a jacket-over-a-separate-torso
    layering) with three horizontal buckle straps (``add_rounded_box``) and
    the two sleeves modelled as extra-thick canvas cylinders that converge
    and cinch together in front of the belly at a single cuff -- "arms
    bound in the jacket", not free-swinging bare arms
  - oversized kangaroo feet -- an elongated foot-pad sphere plus a tapered
    forward toe cone, riding on a ``foot`` bone itself authored roughly
    1.4x the ankle-to-toe span Cortex's own boot uses (see the ``foot``
    bone's own comment in ``build_rig()`` below)
  - a tongue-out head read: a wide grin (a single broad ``add_rounded_box``
    mouth, wider than Cortex's or Coco's own), a dangling tongue (a tapered
    cone hanging well past the chin, authored geometry, not a texture) and
    tall ears (two long thin cones reaching well above the cranium apex --
    the single biggest silhouette departure from Cortex's bald dome or
    Coco's ponytail)
  - his own blue fur palette, distinct from Crash's orange, Cortex's sallow
    skin, and Coco's warm orange -- see the palette block below
No stitches, no bandages, no chain, no other Ripper-Roo-canon iconography --
the brief names exactly these four traits and the plan's own YAGNI framing
(see Coco's "no laptop" precedent) applies the same way here: nothing beyond
the straitjacket read.
Every vertex here is original, authored from this task's own proportion
sheet (docs/art/references/ripper-roo-likeness-proportions.svg) -- nothing
is extracted, traced, or copied from any external reference.

SPRINGY IDLE. Unlike Cortex's/Coco's own idle (a small standing sway that
never touches thigh/shin), ``A_ripper_roo_idle`` poses ``thigh.L/R``/
``shin.L/R`` AND drives a much larger ``root`` Z-location swing --
crouch/anticipation -> stretched launch (root high, legs extended) -> soft
landing crouch -> rest -- a genuine vertical bounce cycle matching "his own
hopping character" per the brief, not a reuse of the other two builders'
sway shape. Nothing in ``character_asset_common.py`` or any test restricts
which bones an IDLE clip may pose (the allowlist test below is scoped to
``SEATED_POSE`` only, the same as Cortex's/Coco's own), so this is a free
authored choice, not a rule bypass.

SEATED ACTION. Bakes ``A_crash_hog_ride`` -- the literal StringName kart_
controller.gd's ``SEAT_ANIMATION_CLIP`` matches (see create_cortex.py's own
module doc for why this is the ONLY working mount path for a custom-rig,
non-Rigify model) -- as a completely STATIC two-keyframe hold (frame 1 ==
last frame, no mid-cycle variation), the exact same shape Cortex's/Coco's
own seated actions use and for the same reason (a static pose still
satisfies ``AnimationPlayer.has_animation()`` and plays correctly -- see
``_play_seat_pose()``). The bend angles themselves differ from Cortex's/
Coco's own ``SEATED_POSE`` (deeper thigh/shin fold) specifically to tuck his
oversized feet up onto the kart's own cowl -- the brief's own "seated action
tucks the big feet onto the kart cowl" requirement -- while staying inside
the exact same eight-bone allowlist (``thigh.L/R``, ``shin.L/R``,
``upper_arm.L/R``, ``forearm.L/R``) the other two builders already
established and this file's own lint test re-derives live from the
``SEATED_POSE`` dict literal.

GATE. ripper_roo.tres' own ``character_scene_path`` was fallback-active
until the operator accepted the face in conversation 2026-08-02 -- this
script builds and exports a gate-ready asset; it did not and does not
perform that flip itself. Per the plan's own Global Constraints: "an agent
NEVER marks a face accepted, flips a fallback to a real scene without an
explicit operator acceptance in the conversation, or describes a gate as
passed." See docs/art/gates/2026-08-02-ripper-roo/gate-record.md for the
ACCEPTED record (the "Result" line, transcribed into a separate flip
commit -- not this script) and this task's own authored seat_scale/
seat_offset values, now live in ripper_roo.tres unchanged from what this
script always exported.

Run from the repository root:

    blender --background --factory-startup \\
        --python scripts/blender/create_ripper_roo.py
"""

from __future__ import annotations

import importlib.util
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from character_asset_common import (  # noqa: E402
    add_cone_between,
    add_cylinder_between,
    add_rounded_box,
    add_sphere,
    begin_action,
    configure_metric_scene,
    create_preview,
    create_rig,
    create_vertex_material,
    finish_action,
    join_and_skin,
    key_pose,
    point_at,
    reset_scene,
    save_source_and_export,
    validate_asset,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_NAME = "SK_ripper_roo"
ASSET_KEY = "ripper_roo"
RIG_NAME = "RIG_ripper_roo"
MATERIAL_NAME = "M_ripper_roo_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_ripper_roo.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/characters/SK_ripper_roo.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_ripper_roo.png"

## Gate renders (committed, unlike build/art-previews/ above) -- the task
## brief's own "capture gate renders ... into docs/art/gates/2026-08-02-
## ripper-roo/" requirement. docs/art/gates/ is not covered by .gitignore's
## "build/" rule, so these three PNGs ship with the commit for the
## operator's review.
GATE_DIR = REPO_ROOT / "docs/art/gates/2026-08-02-ripper-roo"
KART_BUILDER_PATH = REPO_ROOT / "scripts/blender/build_kart.py"

## Authored fit values for the "seated-on-kart" gate render below AND for
## the operator's eventual one-line DriverEntry flip -- see docs/art/gates/
## 2026-08-02-ripper-roo/gate-record.md and tests/racing/test_kart_
## controller.gd's own RIPPER_ROO_SEAT_SCALE/RIPPER_ROO_SEAT_OFFSET consts,
## which prove this exact scale clears the kart's real Visual-mesh cowl and
## stays within its body width against the REAL mounted Godot scene -- not
## assumed from this Blender-only illustration. seat_offset is authored in
## Godot's own Y-up metres (DriverEntry.seat_offset's own space); this
## render approximates the analogous Blender Z-up placement for
## illustration only (see create_gate_renders()'s own doc for exactly what
## is and is not proven by this specific image). Ripper Roo's own rig is
## authored close to Cortex's own scale (tall ears aside, his standing
## height lands near Cortex's 1.32m unscaled apex), so his down-scale lands
## in the same neighbourhood as Cortex's own 0.90 -- measured against the
## real mounted scene the same way, not assumed from the proportion sheet
## alone.
GATE_SEAT_SCALE = 0.85
GATE_SEAT_OFFSET_GODOT = (0.0, -0.08, 0.0)

IDLE = "A_ripper_roo_idle"
## The literal clip name kart_controller.gd's SEAT_ANIMATION_CLIP checks for
## -- see this module's own doc above and create_cortex.py's/create_coco.
## py's identical constant. Not a per-character name: the mount code
## matches this exact StringName regardless of which driver's model carries
## it.
SEATED_ACTION_NAME = "A_crash_hog_ride"
ACTION_NAMES = (IDLE, SEATED_ACTION_NAME)
IDLE_LAST_FRAME = 41
SEATED_LAST_FRAME = 25

REQUIRED_BONES = (
    "pelvis",
    "spine",
    "chest",
    "head",
    "upper_arm.L",
    "upper_arm.R",
    "forearm.L",
    "forearm.R",
    "thigh.L",
    "thigh.R",
)

# --- palette (blue fur, distinct from Crash's orange / Cortex's sallow skin
# / Coco's warm orange -- see module doc's "LIKENESS READ" section) -------
FUR = (0.145, 0.395, 0.795, 1.0)
FUR_SHADE = (0.075, 0.220, 0.470, 1.0)
FUR_TOE = (0.050, 0.135, 0.290, 1.0)
CANVAS = (0.835, 0.780, 0.655, 1.0)
CANVAS_DARK = (0.550, 0.495, 0.395, 1.0)
STRAP = (0.200, 0.150, 0.110, 1.0)
CUFF = (0.300, 0.220, 0.160, 1.0)
EYE_WHITE = (0.930, 0.910, 0.800, 1.0)
PUPIL = (0.760, 0.790, 0.100, 1.0)
MOUTH_DARK = (0.100, 0.030, 0.050, 1.0)
TONGUE = (0.815, 0.200, 0.280, 1.0)


def build_rig() -> bpy.types.Object:
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.08), None),
        ("pelvis", (0.0, 0.0, 0.40), (0.0, -0.01, 0.52), "root"),
        ("spine", (0.0, -0.01, 0.51), (0.0, -0.02, 0.64), "pelvis"),
        ("chest", (0.0, -0.02, 0.63), (0.0, -0.04, 0.78), "spine"),
        ("neck", (0.0, -0.04, 0.77), (0.0, -0.05, 0.85), "chest"),
        ("head", (0.0, -0.05, 0.84), (0.0, -0.16, 1.18), "neck"),
        ("jaw", (0.0, -0.14, 0.90), (0.0, -0.27, 0.82), "head"),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones.extend(
            [
                (
                    f"upper_arm.{side}",
                    (0.145 * sign, -0.03, 0.715),
                    (0.050 * sign, -0.15, 0.600),
                    "chest",
                ),
                (
                    f"forearm.{side}",
                    (0.050 * sign, -0.15, 0.600),
                    (0.022 * sign, -0.205, 0.500),
                    f"upper_arm.{side}",
                ),
                (
                    f"hand.{side}",
                    (0.022 * sign, -0.205, 0.500),
                    (0.014 * sign, -0.225, 0.470),
                    f"forearm.{side}",
                ),
                (
                    f"thigh.{side}",
                    (0.095 * sign, 0.0, 0.40),
                    (0.100 * sign, -0.01, 0.205),
                    "pelvis",
                ),
                (
                    f"shin.{side}",
                    (0.100 * sign, -0.01, 0.205),
                    (0.105 * sign, -0.03, 0.05),
                    f"thigh.{side}",
                ),
                # Oversized kangaroo foot -- ankle-to-toe spans ~0.19m in
                # -Y, roughly 1.4x Cortex's own 0.135m boot span, the
                # brief's own "oversized kangaroo feet" trait carried into
                # the rig itself (not just the mesh riding on top of it).
                (
                    f"foot.{side}",
                    (0.105 * sign, -0.03, 0.05),
                    (0.105 * sign, -0.22, 0.025),
                    f"shin.{side}",
                ),
            ]
        )
    return create_rig(RIG_NAME, bones, "hero")


def build_parts(material: bpy.types.Material) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    def sphere(
        name: str,
        location: tuple[float, float, float],
        scale: tuple[float, float, float],
        color: tuple[float, float, float, float],
        bone: str,
        segments: int = 20,
        rings: int = 12,
        rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ) -> None:
        parts.append(
            add_sphere(
                ASSET_KEY,
                name,
                location,
                scale,
                color,
                material,
                bone,
                segments,
                rings,
                rotation,
            )
        )

    # --- legs (bare blue fur -- the straitjacket covers the torso/arms
    # only) with oversized kangaroo feet, the brief's own second silhouette
    # trait ----------------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh_bone = f"thigh.{side}"
        shin_bone = f"shin.{side}"
        foot_bone = f"foot.{side}"
        hip = (0.095 * sign, 0.0, 0.395)
        knee = (0.100 * sign, -0.01, 0.205)
        ankle = (0.105 * sign, -0.03, 0.05)
        toe = (0.105 * sign, -0.22, 0.025)
        sphere(f"hip_wrap_{side}", hip, (0.080, 0.074, 0.078), FUR, thigh_bone, 20, 11)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"thigh_{side}", hip, knee, 0.064, FUR, material, thigh_bone, 20
            )
        )
        sphere(f"knee_{side}", knee, (0.058, 0.056, 0.058), FUR, shin_bone, 16, 9)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"shin_{side}", knee, ankle, 0.056, FUR, material, shin_bone, 20
            )
        )
        sphere(f"heel_{side}", (ankle[0], ankle[1] - 0.01, ankle[2] - 0.005), (0.055, 0.050, 0.052), FUR_SHADE, foot_bone, 16, 9)
        # Big elongated foot-pad + tapered forward toe -- the oversized
        # kangaroo-foot silhouette. Roughly 2x Cortex's own boot-sphere
        # radius and reaching well past the shin's own X-footprint.
        sphere(
            f"foot_pad_{side}",
            (ankle[0], ankle[1] - 0.095, ankle[2] - 0.012),
            (0.098, 0.150, 0.078),
            FUR_TOE,
            foot_bone,
            34,
            20,
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"foot_toe_{side}",
                (ankle[0], ankle[1] - 0.170, ankle[2] - 0.010),
                (toe[0], toe[1], toe[2]),
                0.072,
                0.018,
                FUR_TOE,
                material,
                foot_bone,
                22,
            )
        )

    # --- torso: straitjacket as a SINGLE wrapped silhouette --------------
    sphere("pelvis_base", (0.0, -0.005, 0.400), (0.115, 0.100, 0.085), CANVAS_DARK, "pelvis", 18, 10)
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "straitjacket_wrap",
            (0.0, -0.01, 0.395),
            (0.0, -0.045, 0.775),
            0.165,
            0.150,
            CANVAS,
            material,
            "chest",
            28,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "collar",
            (0.0, -0.065, 0.790),
            (0.230, 0.085, 0.055),
            CANVAS_DARK,
            material,
            "chest",
            bevel=0.014,
        )
    )
    # Three horizontal buckle straps wrapping the front -- the brief's own
    # "buckle straps as raised boxes" requirement, at three heights across
    # the wrapped torso.
    for index, strap_z in enumerate((0.470, 0.575, 0.680)):
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"buckle_strap_{index}",
                (0.0, -0.155 - 0.010 * index, strap_z),
                (0.255 - 0.012 * index, 0.052, 0.042),
                STRAP,
                material,
                "chest",
                bevel=0.010,
            )
        )
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "neck",
            (0.0, -0.045, 0.775),
            (0.0, -0.055, 0.850),
            0.055,
            FUR,
            material,
            "neck",
            16,
        )
    )

    # --- arms: straitjacket sleeves, thick canvas tubes that converge and
    # cinch together in front of the belly at a single cuff -- "arms bound
    # in the jacket", the single wrapped silhouette carried into the limbs
    # rather than free bare arms ------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = f"upper_arm.{side}"
        forearm_bone = f"forearm.{side}"
        hand_bone = f"hand.{side}"
        shoulder = (0.145 * sign, -0.03, 0.715)
        elbow = (0.050 * sign, -0.15, 0.600)
        wrist = (0.022 * sign, -0.205, 0.500)
        cuff = (0.014 * sign, -0.225, 0.470)
        sphere(f"shoulder_sleeve_{side}", shoulder, (0.095, 0.090, 0.098), CANVAS, upper_bone, 18, 10)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"upper_sleeve_{side}", shoulder, elbow, 0.072, CANVAS, material, upper_bone, 18
            )
        )
        sphere(f"elbow_sleeve_{side}", elbow, (0.062, 0.060, 0.062), CANVAS, forearm_bone, 16, 9)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"forearm_sleeve_{side}", elbow, wrist, 0.060, CANVAS, material, forearm_bone, 18
            )
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"cuff_{side}",
                cuff,
                (0.095, 0.085, 0.065),
                CUFF,
                material,
                hand_bone,
                bevel=0.014,
            )
        )

    # --- head (the focal read -- tall ears, wide grin, dangling tongue) --
    sphere("cranium", (0.0, -0.045, 0.985), (0.190, 0.178, 0.178), FUR, "head", 40, 22)
    sphere("jaw", (0.0, -0.135, 0.850), (0.140, 0.108, 0.092), FUR_SHADE, "jaw", 26, 14)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        # Tall ears -- the single largest silhouette departure from
        # Cortex's bald dome or Coco's ponytail, reaching well above the
        # cranium's own apex (~1.16m) up to ~1.50m.
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"ear_{side}",
                (0.100 * sign, -0.020, 1.095),
                (0.135 * sign, -0.035, 1.495),
                0.058,
                0.012,
                FUR,
                material,
                "head",
                20,
            )
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"brow_{side}",
                (0.075 * sign, -0.235, 0.985),
                (0.100, 0.020, 0.026),
                FUR_SHADE,
                material,
                "head",
                rotation=(0.0, 0.0, -0.30 * sign),
                bevel=0.007,
            )
        )
        sphere(f"eye_white_{side}", (0.078 * sign, -0.180, 0.965), (0.050, 0.038, 0.042), EYE_WHITE, "head", 22, 12)
        sphere(f"pupil_{side}", (0.080 * sign, -0.212, 0.960), (0.021, 0.017, 0.023), PUPIL, "head", 12, 8)
    sphere("nose", (0.0, -0.290, 0.895), (0.028, 0.045, 0.032), FUR_SHADE, "jaw", 14, 9)
    # Wide grin -- a single broad mouth box, wider than Cortex's or Coco's
    # own, the brief's own "wide grin" trait. Pushed out to y=-0.250 (past
    # the jaw sphere's own front surface at this height, ~-0.235 by the
    # sphere's own ellipsoid radii) so it reads as a raised grin rather
    # than sitting embedded inside the jaw mesh.
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "mouth",
            (0.0, -0.250, 0.812),
            (0.170, 0.028, 0.052),
            MOUTH_DARK,
            material,
            "jaw",
            bevel=0.008,
        )
    )
    # Dangling tongue -- authored geometry, not a texture, hanging well
    # past the chin. The brief's own third head trait alongside the grin
    # and the tall ears. Starts at the mouth box's own bottom-front edge
    # (not its centre) so it reads as hanging out of the open grin rather
    # than emerging from the middle of a solid block.
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tongue",
            (0.0, -0.246, 0.788),
            (0.0, -0.220, 0.560),
            0.030,
            0.016,
            TONGUE,
            material,
            "jaw",
            14,
        )
    )
    return parts


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    """Springy vertical-bounce idle -- see this module's own doc for why
    this deliberately poses thigh/shin AND drives a much larger root
    Z-location swing than Cortex's/Coco's own small standing sway, matching
    the brief's own "springy idle action (vertical bounce per his hopping
    character)" requirement. Nothing restricts which bones an IDLE clip may
    pose (the allowlist test below only scopes SEATED_POSE), so this is a
    free authored choice matching his own hopping character rather than a
    reuse of the other two builders' shape.
    """
    action = begin_action(rig, IDLE, IDLE_LAST_FRAME)
    key_pose(rig, 1)
    # Crouch / anticipation -- sink down, legs compress, lean forward.
    key_pose(
        rig,
        11,
        {
            "spine": (9.0, 0.0, 0.0),
            "chest": (-4.0, 0.0, 0.0),
            "neck": (-3.0, 0.0, 0.0),
            "head": (5.0, 0.0, -1.5),
            "jaw": (2.0, 0.0, 0.0),
            "thigh.L": (16.0, -6.0, -4.0),
            "thigh.R": (16.0, 6.0, 4.0),
            "shin.L": (-24.0, 0.0, 0.0),
            "shin.R": (-24.0, 0.0, 0.0),
            "upper_arm.L": (4.0, 0.0, -3.0),
            "upper_arm.R": (-3.0, 0.0, 3.0),
        },
        {"root": (0.0, 0.0, -0.028)},
    )
    # Launch / peak of the hop -- root high, legs extended and stretched,
    # head tilted back, ears (riding on the head bone) read as perked.
    key_pose(
        rig,
        21,
        {
            "spine": (-7.0, 0.0, 0.0),
            "chest": (4.0, 0.0, 0.0),
            "neck": (3.0, 0.0, 0.0),
            "head": (-6.0, 0.0, 2.0),
            "jaw": (-2.0, 0.0, 0.0),
            "thigh.L": (-11.0, -4.0, -3.0),
            "thigh.R": (-11.0, 4.0, 3.0),
            "shin.L": (9.0, 0.0, 0.0),
            "shin.R": (9.0, 0.0, 0.0),
            "upper_arm.L": (-8.0, 0.0, -6.0),
            "upper_arm.R": (8.0, 0.0, 6.0),
        },
        {"root": (0.0, 0.0, 0.075)},
    )
    # Landing settle -- softer crouch than the anticipation frame, root
    # sinking again before returning to rest.
    key_pose(
        rig,
        31,
        {
            "spine": (4.0, 0.0, 0.0),
            "chest": (-2.0, 0.0, 0.0),
            "head": (2.0, 0.0, -1.0),
            "jaw": (1.0, 0.0, 0.0),
            "thigh.L": (8.0, -3.0, -2.0),
            "thigh.R": (8.0, 3.0, 2.0),
            "shin.L": (-12.0, 0.0, 0.0),
            "shin.R": (-12.0, 0.0, 0.0),
            "upper_arm.L": (2.0, 0.0, -2.0),
            "upper_arm.R": (-2.0, 0.0, 2.0),
        },
        {"root": (0.0, 0.0, -0.012)},
    )
    key_pose(rig, IDLE_LAST_FRAME)
    return finish_action(action, "idle", True)


## Static two-keyframe hold -- see this module's own doc for why the seated
## action deliberately carries no mid-cycle variation. Only the eight limb
## bones below are ever given a non-identity rotation; head/jaw/neck/spine/
## pelvis are never touched, so the face/ears/tongue silhouette this gate
## renders are exactly what the seated pose ships. Deeper thigh/shin fold
## than Cortex's/Coco's own SEATED_POSE (-95/118 here vs. their -80/95) --
## deliberately tucking the oversized foot up onto the kart's own cowl
## rather than letting it hang the way the other two characters' own
## smaller feet do, the brief's own "seated action tucks the big feet onto
## the kart cowl" requirement.
SEATED_POSE = {
    "thigh.L": (-95.0, -18.0, -12.0),
    "thigh.R": (-95.0, 18.0, 12.0),
    "shin.L": (118.0, 0.0, 0.0),
    "shin.R": (118.0, 0.0, 0.0),
    "upper_arm.L": (25.0, 0.0, -15.0),
    "upper_arm.R": (25.0, 0.0, 15.0),
    "forearm.L": (35.0, 0.0, 0.0),
    "forearm.R": (35.0, 0.0, 0.0),
}


def create_seated(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SEATED_ACTION_NAME, SEATED_LAST_FRAME)
    key_pose(rig, 1, SEATED_POSE)
    key_pose(rig, SEATED_LAST_FRAME, SEATED_POSE)
    return finish_action(action, "ride", True)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        SEATED_ACTION_NAME: create_seated(rig),
    }


def load_kart_builder():
    """Load build_kart.py as a plain module, never running its own main().

    Same pattern create_cortex.py/create_coco.py use on build_kart.py:
    spec_from_file_location() under a name other than "__main__" so build_
    kart.py's own ``if __name__ == "__main__": main()`` guard never fires,
    while its create_material()/build_kart() stay callable off the loaded
    module. The kart geometry this produces is never exported by this
    script -- only used, unexported, as render-only set dressing for the
    "seated-on-kart" gate image below -- so reusing build_kart.py's own real
    authored numbers (rather than re-guessing the seat/floor/cowl
    coordinates by hand) is both less work and the only way this
    illustration can claim any correspondence to the real kart at all.
    """
    spec = importlib.util.spec_from_file_location(
        "ripper_roo_gate_kart_builder",
        KART_BUILDER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load kart builder helpers from {KART_BUILDER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _setup_gate_lighting_and_world(key_color: tuple[float, float, float]) -> None:
    """The same three-point rig + world/render-engine setup character_
    asset_common.create_preview() uses, duplicated rather than imported --
    this function also has to run once for a scene that additionally
    carries a kart mesh with its own separate material, which create_
    preview() has no parameter for. create_cortex.py's/create_coco.py's own
    identically-named function duplicates this same block for the same
    reason.
    """
    for name, energy, size, location, color in (
        ("_gate_key", 720.0, 3.2, (-2.6, -3.0, 4.0), key_color),
        ("_gate_fill", 460.0, 2.8, (2.8, -1.2, 2.7), (0.35, 0.68, 1.0)),
        ("_gate_rim", 560.0, 2.4, (-1.4, 2.8, 3.0), (0.55, 0.88, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 0.6)))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.009,
        0.018,
        0.034,
        1.0,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.30

    scene = bpy.context.scene
    render_engines = {
        item.identifier
        for item in scene.bl_rna.properties["render"].fixed_type.properties[
            "engine"
        ].enum_items
    }
    scene.render.engine = (
        "BLENDER_EEVEE_NEXT"
        if "BLENDER_EEVEE_NEXT" in render_engines
        else "BLENDER_EEVEE"
    )
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 24
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass


def create_gate_renders(
    *,
    gate_dir: Path,
    character: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    """Front / three-quarter / seated-on-kart likeness gate renders.

    FRONT and THREE_QUARTER are plain standing-idle shots (frame 1 of
    ``IDLE``) -- the same silhouette-at-a-glance framing character_asset_
    common.create_preview() already uses for every other builder's own
    preview, just split into two fixed camera angles instead of one.

    SEATED_ON_KART additionally builds a real (unexported, render-only)
    kart mesh via build_kart.py's own build_kart() -- see load_kart_
    builder()'s own doc for why this reuses that module's real authored
    geometry rather than a hand-guessed stand-in -- and poses Ripper Roo in
    ``SEATED_ACTION_NAME`` at ``GATE_SEAT_SCALE``, translated to roughly
    build_kart.py's own seat_cushion/seat_back coordinates (0.0, 0.05-0.30,
    0.34-0.46 in that module's Blender-space numbers). The camera is placed
    at data/tuning/racing/race.tres' own real gameplay chase-camera numbers
    (``camera_trail_m=4.6``, ``camera_height_m=2.2``, ``camera_look_
    height_m=1.0``, ``camera_fov_base=60.0`` degrees) so this image shows
    the operator roughly what the in-race chase camera actually sees.

    WHAT THIS RENDER DOES NOT PROVE: Blender's working space here is the
    same Z-up, "-Y-forward" local space every other builder in this repo
    authors in (see character_asset_common.create_rig()'s own "forward_
    axis" convention) -- it is NOT a re-creation of kart.tscn's own node
    hierarchy (SeatMount's exact local offset, the Visual node's authored
    180-degree yaw correction, etc.), so the seat placement here is a
    reasonable illustrative approximation, not a pixel-exact reproduction
    of the runtime mount. The REAL fit -- "does Ripper Roo's head clear the
    kart's own real Visual-mesh AABB, do his hands stay within its real
    width, do his feet stay grounded" -- is proven in actual Godot space by
    tests/racing/test_kart_controller.gd's own test_ripper_roo_seated_fit_
    clears_the_kart_cowl_and_stays_within_the_body_width, using the exact
    same GATE_SEAT_SCALE/GATE_SEAT_OFFSET_GODOT values. This image exists
    for the operator's LIKENESS judgment (does the face/silhouette read at
    gameplay distance), not as a second proof of the numeric fit.
    """
    gate_dir.mkdir(parents=True, exist_ok=True)
    rig.hide_render = False
    bpy.context.view_layer.objects.active = character
    rig.animation_data.action = bpy.data.actions[IDLE]
    bpy.context.scene.frame_set(1)

    bpy.ops.mesh.primitive_plane_add(size=7.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.active_object
    floor.name = "_gate_floor"
    floor_material = bpy.data.materials.new("_gate_floor_material")
    floor_material.diffuse_color = (0.028, 0.048, 0.075, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_gate_camera")
    camera = bpy.data.objects.new("_gate_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    _setup_gate_lighting_and_world((0.55, 0.78, 1.0))

    # --- FRONT -- pulled back and raised slightly further than Cortex's/
    # Coco's own front shots so the tall ears (apex ~1.50m) stay in frame.
    camera.location = (0.0, -2.75, 0.86)
    camera_data.lens = 58.0
    point_at(camera, Vector((0.0, -0.05, 0.80)))
    bpy.context.scene.render.filepath = str(gate_dir / "01-front.png")
    bpy.ops.render.render(write_still=True)

    # --- THREE-QUARTER --------------------------------------------------
    camera.location = (1.95, -2.55, 1.10)
    camera_data.lens = 56.0
    point_at(camera, Vector((0.0, -0.05, 0.80)))
    bpy.context.scene.render.filepath = str(gate_dir / "02-three-quarter.png")
    bpy.ops.render.render(write_still=True)

    # --- SEATED ON KART, AT GAMEPLAY CAMERA DISTANCE --------------------
    kart_module = load_kart_builder()
    kart_material = kart_module.create_material()
    kart = kart_module.build_kart(kart_material)
    kart.hide_render = False

    rig.animation_data.action = bpy.data.actions[SEATED_ACTION_NAME]
    bpy.context.scene.frame_set(1)
    # Approximate seat placement -- see this function's own "WHAT THIS
    # RENDER DOES NOT PROVE" doc above.
    rig.location = (0.0, 0.16, 0.40)
    rig.scale = (GATE_SEAT_SCALE, GATE_SEAT_SCALE, GATE_SEAT_SCALE)

    # race.tres' own real chase-camera numbers (camera_trail_m/camera_
    # height_m/camera_look_height_m/camera_fov_base) -- kart faces -Y here
    # (build_kart.py's own "forward_axis": "-Y"), so "trailing" is +Y.
    camera_trail_m = 4.6
    camera_height_m = 2.2
    camera_look_height_m = 1.0
    camera_fov_base_degrees = 60.0
    camera.location = (0.0, camera_trail_m, camera_height_m)
    camera_data.angle = math.radians(camera_fov_base_degrees)
    point_at(camera, Vector((0.0, 0.0, camera_look_height_m)))
    bpy.context.scene.render.filepath = str(gate_dir / "03-seated-on-kart.png")
    bpy.ops.render.render(write_still=True)

    # Restore standing scale/pose and remove the render-only kart so this
    # function leaves no trace in the saved .blend source beyond the gate
    # images themselves.
    rig.location = (0.0, 0.0, 0.0)
    rig.scale = (1.0, 1.0, 1.0)
    rig.animation_data.action = bpy.data.actions[IDLE]
    bpy.context.scene.frame_set(1)
    bpy.data.objects.remove(kart, do_unlink=True)


def main(
    *,
    export_path: Path = EXPORT_PATH,
    source_path: Path = SOURCE_PATH,
    preview_path: Path = PREVIEW_PATH,
    render_preview: bool = True,
    gate_dir: Path = GATE_DIR,
    render_gate: bool = True,
) -> None:
    """Build and export the gate-ready GLB.

    The ``*_path``/``gate_dir`` keywords and ``render_preview``/``render_
    gate`` exist for exactly one caller outside ``__main__`` below --
    tests/lint/test_ripper_roo_builder.py's own determinism/export tests,
    which need independent builds written to a scratch directory rather
    than the real committed GLB, and skip both GPU-dependent EEVEE render
    passes (the build/art-previews/ thumbnail and the docs/art/gates/
    likeness renders alike -- neither affects whether the exported glTF
    itself is correct). Mirrors create_cortex.py's/create_coco.py's own
    main() keyword shape.
    """
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.85)
    rig = build_rig()
    character = join_and_skin(
        ASSET_NAME,
        ASSET_KEY,
        "hero",
        build_parts(material),
        material,
        rig,
        ACTION_NAMES,
    )
    actions = create_actions(rig)
    vertices, faces, triangles = validate_asset(
        asset_name=ASSET_NAME,
        character=character,
        rig=rig,
        actions=actions,
        action_names=ACTION_NAMES,
        required_bones=REQUIRED_BONES,
        minimum_triangles=10000,
        maximum_triangles=12000,
        minimum_colors=10,
    )
    save_source_and_export(
        source_path=source_path,
        export_path=export_path,
        character=character,
        rig=rig,
    )
    if render_preview:
        create_preview(
            preview_path=preview_path,
            character=character,
            rig=rig,
            target=(0.0, -0.10, 0.80),
            camera_location=(2.10, -3.25, 1.35),
            floor_size=6.0,
            poses=((IDLE, 1, "A_ripper_roo_idle_pose.png"),),
            key_color=(0.55, 0.78, 1.0),
        )
    if render_gate:
        create_gate_renders(gate_dir=gate_dir, character=character, rig=rig)
    print(
        "RIPPER_ROO_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_ripper_roo "
        f"animations={len(actions)}"
    )
    print(f"RIPPER_ROO_SOURCE={source_path}")
    print(f"RIPPER_ROO_GLB={export_path}")
    print(f"RIPPER_ROO_PREVIEW={preview_path}")
    if render_gate:
        print(f"RIPPER_ROO_GATE_DIR={gate_dir}")


if __name__ == "__main__":
    main()
