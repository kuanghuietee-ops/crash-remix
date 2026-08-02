"""Build Coco Bandicoot's original vertex-painted racing likeness for Godot.

R8 Task 7 (characters/select/classes): the second of three NEW-build face
gates (Cortex/Coco/Ripper Roo -- design spec's own "G. Faces pipeline"
section). Follows the exact reuse shape ``create_cortex.py`` already
established on top of ``character_asset_common.py`` -- one vertex-coloured
mesh, one compact custom skeleton (plain bone names, not Rigify ``DEF-*``),
built entirely from the shared primitive kit (``add_sphere``/``add_cylinder_
between``/``add_cone_between``/``add_rounded_box``). Per the plan, Coco
reuses Crash's own proportion *language* (``create_crash_likeness.py``'s
module doc: "same family" -- compact frame, oversized head, kart-racer
chibi massing) rather than that file's own local Rigify-basic-human
pipeline, which this task never touches, exactly the same substitution
Cortex's own module doc already made explicit for itself.

LIKENESS READ AT KART DISTANCE (the task brief's own framing): silhouette
only, three authored traits --
  - a blonde ponytail, built as authored geometry (two chained tapered
    cones off the back of the skull plus a small hair-tie band and a
    forelock tuft) -- the single biggest silhouette departure from both
    Crash's bare head and Cortex's bulbous bald cranium
  - a smaller, slighter frame than Crash's own model (and Cortex's, which
    was itself authored close to Crash's scale) -- narrower shoulders and
    hips, thinner limbs, a shorter overall rig height
  - her own original palette, distinct from both Crash's and Cortex's:
    warm fur/tan-muzzle in the same "bandicoot family" register as Crash's
    own fur, but a magenta racing tank top + khaki cargo shorts + white
    sneakers rather than Crash's blue shorts or Cortex's coat, so the
    silhouette reads as her own character at a glance, not a recolour
No laptop, no props of any kind -- the plan explicitly calls this out as
YAGNI for this task (a tech/gadget angle was considered and dropped).
Every vertex here is original, authored from this task's own proportion
sheet (docs/art/references/coco-likeness-proportions.svg) -- nothing is
extracted, traced, or copied from any external reference.

SEATED ACTION. Bakes ``A_crash_hog_ride`` -- the literal StringName kart_
controller.gd's ``SEAT_ANIMATION_CLIP`` matches (see create_cortex.py's own
module doc for why this is the ONLY working mount path for a custom-rig,
non-Rigify model) -- as a completely STATIC two-keyframe hold (frame 1 ==
last frame, no mid-cycle variation), the exact same shape Cortex's own
seated action uses and for the same reason: a static pose still satisfies
``AnimationPlayer.has_animation()`` and plays correctly (see ``_play_seat_
pose()``), and skipping any mid-frame exception avoids the doc/behaviour
drift Papu's own fix-round-1 review caught.

GATE. coco.tres' own ``character_scene_path`` was fallback-active until the
operator accepted the face in conversation 2026-08-02 -- this script builds
and exports a gate-ready asset; it did not and does not perform that flip
itself. Per the plan's own Global Constraints: "an agent NEVER marks a face
accepted, flips a fallback to a real scene without an explicit operator
acceptance in the conversation, or describes a gate as passed." See docs/
art/gates/2026-08-02-coco/gate-record.md for the ACCEPTED record (the
"Result" line, transcribed into a separate flip commit -- not this script)
and this task's own authored seat_scale/seat_offset values, now live in
coco.tres unchanged from what this script always exported.

Run from the repository root:

    blender --background --factory-startup \\
        --python scripts/blender/create_coco.py
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
ASSET_NAME = "SK_coco"
ASSET_KEY = "coco"
RIG_NAME = "RIG_coco"
MATERIAL_NAME = "M_coco_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_coco.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/characters/SK_coco.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_coco.png"

## Gate renders (committed, unlike build/art-previews/ above) -- the task
## brief's own "capture gate renders ... into docs/art/gates/2026-08-02-
## coco/" requirement. docs/art/gates/ is not covered by .gitignore's
## "build/" rule, so these three PNGs ship with the commit for the
## operator's review.
GATE_DIR = REPO_ROOT / "docs/art/gates/2026-08-02-coco"
KART_BUILDER_PATH = REPO_ROOT / "scripts/blender/build_kart.py"

## Authored fit values for the "seated-on-kart" gate render below AND for
## the operator's eventual one-line DriverEntry flip -- see docs/art/gates/
## 2026-08-02-coco/gate-record.md and tests/racing/test_kart_controller.gd's
## own COCO_SEAT_SCALE/COCO_SEAT_OFFSET consts, which prove this exact
## scale clears the kart's real Visual-mesh cowl and stays within its body
## width against the REAL mounted Godot scene -- not assumed from this
## Blender-only illustration. seat_offset is authored in Godot's own Y-up
## metres (DriverEntry.seat_offset's own space); this render approximates
## the analogous Blender Z-up placement for illustration only (see
## create_gate_renders()'s own doc for exactly what is and is not proven by
## this specific image). Coco's own raw rig is authored smaller than
## Cortex's (her own "smaller/slighter frame" trait), so unlike Cortex's
## 0.90 down-scale, her fit lands close to 1:1 -- measured against the real
## mounted scene the same way, not assumed from the size difference alone.
GATE_SEAT_SCALE = 1.0
GATE_SEAT_OFFSET_GODOT = (0.0, -0.03, 0.0)

IDLE = "A_coco_idle"
## The literal clip name kart_controller.gd's SEAT_ANIMATION_CLIP checks for
## -- see this module's own doc above and create_cortex.py's identical
## constant. Not a per-character name: the mount code matches this exact
## StringName regardless of which driver's model carries it.
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

# --- palette (bandicoot-family fur read with Crash's own, an entirely
# fresh original outfit palette -- see module doc's "LIKENESS READ"
# section) ------------------------------------------------------------
FUR = (0.80, 0.365, 0.095, 1.0)
FUR_SHADE = (0.52, 0.225, 0.050, 1.0)
MUZZLE = (0.93, 0.70, 0.42, 1.0)
TOP = (0.80, 0.095, 0.42, 1.0)
TOP_DARK = (0.50, 0.048, 0.27, 1.0)
SHORTS = (0.60, 0.545, 0.325, 1.0)
SHORTS_DARK = (0.38, 0.345, 0.195, 1.0)
SHOE = (0.94, 0.94, 0.90, 1.0)
SHOE_SOLE = (0.11, 0.10, 0.10, 1.0)
HAIR = (0.90, 0.705, 0.265, 1.0)
EYE_WHITE = (0.95, 0.93, 0.85, 1.0)
PUPIL = (0.055, 0.185, 0.205, 1.0)
NOSE = (0.045, 0.028, 0.028, 1.0)
MOUTH = (0.33, 0.075, 0.08, 1.0)


def build_rig() -> bpy.types.Object:
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.07), None),
        ("pelvis", (0.0, 0.0, 0.395), (0.0, -0.008, 0.50), "root"),
        ("spine", (0.0, -0.008, 0.49), (0.0, -0.016, 0.615), "pelvis"),
        ("chest", (0.0, -0.016, 0.605), (0.0, -0.03, 0.735), "spine"),
        ("neck", (0.0, -0.03, 0.725), (0.0, -0.038, 0.79), "chest"),
        ("head", (0.0, -0.038, 0.78), (0.0, -0.135, 1.155), "neck"),
        ("jaw", (0.0, -0.125, 0.825), (0.0, -0.235, 0.755), "head"),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones.extend(
            [
                (
                    f"upper_arm.{side}",
                    (0.135 * sign, -0.028, 0.705),
                    (0.222 * sign, 0.00, 0.550),
                    "chest",
                ),
                (
                    f"forearm.{side}",
                    (0.222 * sign, 0.00, 0.550),
                    (0.235 * sign, -0.045, 0.400),
                    f"upper_arm.{side}",
                ),
                (
                    f"hand.{side}",
                    (0.235 * sign, -0.045, 0.400),
                    (0.242 * sign, -0.078, 0.325),
                    f"forearm.{side}",
                ),
                (
                    f"thigh.{side}",
                    (0.075 * sign, 0.0, 0.395),
                    (0.079 * sign, -0.005, 0.195),
                    "pelvis",
                ),
                (
                    f"shin.{side}",
                    (0.079 * sign, -0.005, 0.195),
                    (0.079 * sign, -0.018, 0.050),
                    f"thigh.{side}",
                ),
                (
                    f"foot.{side}",
                    (0.079 * sign, -0.018, 0.050),
                    (0.079 * sign, -0.115, 0.018),
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

    # --- legs (thin -- "smaller/slighter frame" is one of the three
    # brief-named silhouette traits) ----------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh_bone = f"thigh.{side}"
        shin_bone = f"shin.{side}"
        foot_bone = f"foot.{side}"
        hip = (0.075 * sign, 0.0, 0.390)
        knee = (0.079 * sign, -0.005, 0.195)
        ankle = (0.079 * sign, -0.018, 0.050)
        toe = (0.079 * sign, -0.115, 0.028)
        sphere(f"hip_wrap_{side}", hip, (0.064, 0.060, 0.056), SHORTS, thigh_bone, 18, 10)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"thigh_{side}", hip, knee, 0.050, FUR, material, thigh_bone, 18
            )
        )
        sphere(f"knee_{side}", knee, (0.046, 0.044, 0.046), FUR, shin_bone, 14, 8)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"shin_{side}", knee, ankle, 0.040, FUR, material, shin_bone, 18
            )
        )
        sphere(
            f"shoe_{side}",
            (ankle[0], ankle[1] - 0.036, ankle[2] - 0.004),
            (0.054, 0.090, 0.048),
            SHOE,
            foot_bone,
            24,
            14,
        )
        sphere(f"shoe_toe_{side}", toe, (0.046, 0.054, 0.038), SHOE, foot_bone, 16, 9)
        sphere(
            f"shoe_sole_{side}",
            (ankle[0], ankle[1] - 0.040, ankle[2] - 0.024),
            (0.052, 0.084, 0.016),
            SHOE_SOLE,
            foot_bone,
            16,
            8,
        )

    # --- torso (tank top + waistband silhouette) -----------------------
    sphere("pelvis_base", (0.0, -0.004, 0.400), (0.100, 0.090, 0.078), SHORTS, "pelvis", 18, 10)
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "torso_body",
            (0.0, -0.008, 0.390),
            (0.0, -0.028, 0.735),
            0.082,
            0.098,
            TOP,
            material,
            "chest",
            26,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "strap_L",
            (0.058, -0.055, 0.760),
            (0.032, 0.075, 0.14),
            TOP_DARK,
            material,
            "chest",
            rotation=(0.0, 0.0, 0.30),
            bevel=0.010,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "strap_R",
            (-0.058, -0.055, 0.760),
            (0.032, 0.075, 0.14),
            TOP_DARK,
            material,
            "chest",
            rotation=(0.0, 0.0, -0.30),
            bevel=0.010,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "waistband",
            (0.0, -0.014, 0.400),
            (0.205, 0.062, 0.038),
            SHORTS_DARK,
            material,
            "pelvis",
            bevel=0.010,
        )
    )
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "neck",
            (0.0, -0.030, 0.725),
            (0.0, -0.036, 0.790),
            0.046,
            FUR,
            material,
            "neck",
            16,
        )
    )

    # --- arms -------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = f"upper_arm.{side}"
        forearm_bone = f"forearm.{side}"
        hand_bone = f"hand.{side}"
        shoulder = (0.135 * sign, -0.026, 0.705)
        elbow = (0.222 * sign, 0.00, 0.550)
        wrist = (0.235 * sign, -0.045, 0.400)
        hand = (0.240 * sign, -0.072, 0.335)
        sphere(f"shoulder_{side}", shoulder, (0.064, 0.062, 0.066), FUR, upper_bone, 18, 10)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"upper_arm_{side}", shoulder, elbow, 0.046, FUR, material, upper_bone, 16
            )
        )
        sphere(f"elbow_{side}", elbow, (0.040, 0.038, 0.040), FUR, forearm_bone, 14, 8)
        parts.append(
            add_cylinder_between(
                ASSET_KEY, f"forearm_{side}", elbow, wrist, 0.040, FUR, material, forearm_bone, 16
            )
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"wristband_{side}",
                wrist,
                (0.074, 0.066, 0.026),
                TOP_DARK,
                material,
                forearm_bone,
                bevel=0.008,
            )
        )
        sphere(f"hand_{side}", hand, (0.046, 0.052, 0.042), FUR, hand_bone, 20, 12)
        sphere(
            f"thumb_{side}",
            (0.256 * sign, -0.038, 0.362),
            (0.018, 0.020, 0.030),
            FUR,
            hand_bone,
            10,
            6,
        )

    # --- head (the focal read -- ponytail, muzzle, compact skull) -----
    # The muzzle sits BELOW and forward of the cranium (mirrors Cortex's
    # own cranium/jaw z-separation, and Crash's own tapered-head/nose-wedge
    # split) rather than overlapping it -- eyes/brows live on the
    # cranium's own lower-front surface, above the muzzle, so the two
    # volumes read as a distinct rounded skull + forward snout rather than
    # merging into one blob at kart-distance silhouette.
    sphere("cranium", (0.0, -0.040, 0.975), (0.158, 0.150, 0.148), FUR, "head", 44, 24)
    sphere("muzzle", (0.0, -0.205, 0.815), (0.072, 0.108, 0.062), MUZZLE, "jaw", 24, 14)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"ear_{side}",
                (0.118 * sign, -0.020, 1.045),
                (0.155 * sign, 0.010, 1.155),
                0.048,
                0.008,
                FUR,
                material,
                "head",
                14,
            )
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"brow_{side}",
                (0.060 * sign, -0.140, 0.948),
                (0.086, 0.018, 0.022),
                FUR_SHADE,
                material,
                "head",
                rotation=(0.0, 0.0, -0.10 * sign),
                bevel=0.007,
            )
        )
        sphere(f"eye_white_{side}", (0.058 * sign, -0.150, 0.905), (0.036, 0.026, 0.030), EYE_WHITE, "head", 18, 10)
        sphere(f"pupil_{side}", (0.058 * sign, -0.172, 0.902), (0.014, 0.011, 0.016), PUPIL, "head", 10, 6)
    sphere("nose", (0.0, -0.300, 0.815), (0.024, 0.040, 0.028), NOSE, "jaw", 12, 8)
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "mouth",
            (0.0, -0.288, 0.775),
            (0.072, 0.011, 0.015),
            MOUTH,
            material,
            "jaw",
            bevel=0.005,
        )
    )
    # Ponytail -- the task brief's own headline silhouette trait. Two
    # chained tapered segments off the back of the skull (forward is -Y
    # per character_asset_common.create_rig()'s own "forward_axis"
    # convention, so the ponytail sweeps out toward +Y, down and back),
    # plus a hair-tie band where it meets the skull and a small forelock
    # tuft up front so the top of the head doesn't read as bare fur.
    ponytail_base = (0.0, 0.130, 1.015)
    ponytail_mid = (0.0, 0.255, 0.855)
    ponytail_tip = (0.0, 0.315, 0.655)
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "ponytail_upper",
            ponytail_base,
            ponytail_mid,
            0.052,
            0.036,
            HAIR,
            material,
            "head",
            16,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "ponytail_lower",
            ponytail_mid,
            ponytail_tip,
            0.036,
            0.010,
            HAIR,
            material,
            "head",
            16,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "hair_tie",
            (0.0, 0.148, 1.005),
            (0.062, 0.032, 0.048),
            TOP,
            material,
            "head",
            rotation=(0.35, 0.0, 0.0),
            bevel=0.010,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "forelock",
            (0.0, -0.048, 1.095),
            (0.0, -0.092, 1.150),
            0.052,
            0.012,
            HAIR,
            material,
            "head",
            14,
        )
    )
    return parts


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, IDLE, IDLE_LAST_FRAME)
    key_pose(rig, 1)
    key_pose(
        rig,
        11,
        {
            "spine": (2.0, 0.0, 1.5),
            "chest": (-1.5, 0.0, -1.5),
            "neck": (-2.0, 0.0, 1.5),
            "head": (2.5, 0.0, -2.0),
            "jaw": (1.0, 0.0, 0.0),
            "upper_arm.L": (3.0, 0.0, -3.0),
            "upper_arm.R": (-2.5, 0.0, 2.5),
        },
        {"root": (0.0, 0.0, 0.008)},
    )
    key_pose(
        rig,
        21,
        {
            "spine": (-2.0, 0.0, -1.5),
            "chest": (1.5, 0.0, 1.5),
            "neck": (2.0, 0.0, -1.5),
            "head": (-2.5, 0.0, 2.0),
            "jaw": (-0.5, 0.0, 0.0),
            "upper_arm.L": (-2.5, 0.0, 3.0),
            "upper_arm.R": (3.0, 0.0, -2.5),
        },
        {"root": (0.0, 0.0, 0.015)},
    )
    key_pose(
        rig,
        31,
        {
            "spine": (1.0, 0.0, 0.5),
            "head": (1.5, 0.0, -1.0),
            "jaw": (0.5, 0.0, 0.0),
            "upper_arm.L": (1.5, 0.0, -1.5),
            "upper_arm.R": (-1.5, 0.0, 1.5),
        },
        {"root": (0.0, 0.0, 0.005)},
    )
    key_pose(rig, IDLE_LAST_FRAME)
    return finish_action(action, "idle", True)


## Static two-keyframe hold -- see this module's own doc for why the seated
## action deliberately carries no mid-cycle variation. Only the eight limb
## bones below are ever given a non-identity rotation; head/jaw/neck/spine/
## pelvis are never touched, so the face/ponytail silhouette this gate
## renders are exactly what the seated pose ships.
SEATED_POSE = {
    "thigh.L": (-80.0, -18.0, -12.0),
    "thigh.R": (-80.0, 18.0, 12.0),
    "shin.L": (95.0, 0.0, 0.0),
    "shin.R": (95.0, 0.0, 0.0),
    "upper_arm.L": (30.0, 0.0, -20.0),
    "upper_arm.R": (30.0, 0.0, 20.0),
    "forearm.L": (42.0, 0.0, 0.0),
    "forearm.R": (42.0, 0.0, 0.0),
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

    Same pattern create_cortex.py uses on build_kart.py: spec_from_file_
    location() under a name other than "__main__" so build_kart.py's own
    ``if __name__ == "__main__": main()`` guard never fires, while its
    create_material()/build_kart() stay callable off the loaded module. The
    kart geometry this produces is never exported by this script -- only
    used, unexported, as render-only set dressing for the "seated-on-kart"
    gate image below -- so reusing build_kart.py's own real authored
    numbers (rather than re-guessing the seat/floor/cowl coordinates by
    hand) is both less work and the only way this illustration can claim
    any correspondence to the real kart at all.
    """
    spec = importlib.util.spec_from_file_location(
        "coco_gate_kart_builder",
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
    preview() has no parameter for. create_cortex.py's own identically-
    named function duplicates this same block for the same reason.
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
    geometry rather than a hand-guessed stand-in -- and poses Coco in
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
    of the runtime mount. The REAL fit -- "does Coco's head clear the
    kart's own real Visual-mesh AABB, do her hands stay within its real
    width, do her feet stay grounded" -- is proven in actual Godot space by
    tests/racing/test_kart_controller.gd's own test_coco_seated_fit_clears_
    the_kart_cowl_and_stays_within_the_body_width, using the exact same
    GATE_SEAT_SCALE/GATE_SEAT_OFFSET_GODOT values. This image exists for
    the operator's LIKENESS judgment (does the face/silhouette read at
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

    _setup_gate_lighting_and_world((1.0, 0.72, 0.55))

    # --- FRONT --------------------------------------------------------
    camera.location = (0.0, -2.30, 0.72)
    camera_data.lens = 60.0
    point_at(camera, Vector((0.0, -0.05, 0.64)))
    bpy.context.scene.render.filepath = str(gate_dir / "01-front.png")
    bpy.ops.render.render(write_still=True)

    # --- THREE-QUARTER --------------------------------------------------
    camera.location = (1.65, -2.10, 0.95)
    camera_data.lens = 58.0
    point_at(camera, Vector((0.0, -0.05, 0.64)))
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
    rig.location = (0.0, 0.16, 0.42)
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
    tests/lint/test_coco_builder.py's own determinism/export tests, which
    need independent builds written to a scratch directory rather than the
    real committed GLB, and skip both GPU-dependent EEVEE render passes
    (the build/art-previews/ thumbnail and the docs/art/gates/ likeness
    renders alike -- neither affects whether the exported glTF itself is
    correct). Mirrors create_cortex.py's own ``main()`` keyword shape.
    """
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.80)
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
            target=(0.0, -0.10, 0.68),
            camera_location=(1.85, -2.85, 1.15),
            floor_size=6.0,
            poses=((IDLE, 1, "A_coco_idle_pose.png"),),
            key_color=(1.0, 0.72, 0.55),
        )
    if render_gate:
        create_gate_renders(gate_dir=gate_dir, character=character, rig=rig)
    print(
        "COCO_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_coco "
        f"animations={len(actions)}"
    )
    print(f"COCO_SOURCE={source_path}")
    print(f"COCO_GLB={export_path}")
    print(f"COCO_PREVIEW={preview_path}")
    if render_gate:
        print(f"COCO_GATE_DIR={gate_dir}")


if __name__ == "__main__":
    main()
