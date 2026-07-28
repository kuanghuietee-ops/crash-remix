"""Build the original low-poly Papu Papu boss for Godot.

The production asset is one vertex-painted mesh with a compact custom rig.
Bold face paint, a feather crown, a heavy staff, and exaggerated body masses
keep the boss readable on a phone without relying on textures.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy

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
    reset_scene,
    save_source_and_export,
    validate_asset,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_NAME = "SK_papu"
ASSET_KEY = "papu"
RIG_NAME = "RIG_papu"
MATERIAL_NAME = "M_papu_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_papu.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/bosses/SK_papu.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_papu.png"

IDLE = "A_papu_idle"
TAUNT = "A_papu_taunt"
SLAM = "A_papu_slam"
HIT = "A_papu_hit"
PHASE = "A_papu_phase"
DEFEAT = "A_papu_defeat"
ACTION_NAMES = (IDLE, TAUNT, SLAM, HIT, PHASE, DEFEAT)

SKIN = (0.48, 0.19, 0.075, 1.0)
SKIN_LIGHT = (0.72, 0.34, 0.14, 1.0)
SKIN_DARK = (0.28, 0.075, 0.025, 1.0)
HAIR = (0.025, 0.012, 0.008, 1.0)
HAIR_LIGHT = (0.12, 0.035, 0.018, 1.0)
WHITE = (0.98, 0.84, 0.58, 1.0)
EYE_WHITE = (1.0, 0.92, 0.64, 1.0)
PUPIL = (0.008, 0.005, 0.004, 1.0)
PAINT_RED = (0.86, 0.045, 0.025, 1.0)
PAINT_TEAL = (0.02, 0.55, 0.57, 1.0)
PAINT_YELLOW = (1.0, 0.58, 0.035, 1.0)
CLOTH = (0.58, 0.025, 0.055, 1.0)
CLOTH_DARK = (0.22, 0.008, 0.018, 1.0)
WOOD = (0.19, 0.055, 0.018, 1.0)
WOOD_LIGHT = (0.48, 0.17, 0.035, 1.0)
LEAF = (0.08, 0.34, 0.07, 1.0)


def build_rig() -> bpy.types.Object:
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.18), None),
        ("pelvis", (0.0, 0.0, 0.82), (0.0, -0.01, 1.12), "root"),
        ("spine", (0.0, -0.01, 1.08), (0.0, -0.04, 1.48), "pelvis"),
        ("chest", (0.0, -0.04, 1.42), (0.0, -0.09, 1.75), "spine"),
        ("neck", (0.0, -0.09, 1.72), (0.0, -0.15, 1.93), "chest"),
        ("head", (0.0, -0.15, 1.91), (0.0, -0.29, 2.27), "neck"),
        ("jaw", (0.0, -0.28, 2.05), (0.0, -0.50, 1.98), "head"),
        (
            "headdress",
            (0.0, -0.08, 2.20),
            (0.0, 0.01, 2.68),
            "head",
        ),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones.extend(
            [
                (
                    f"upper_arm.{side}",
                    (0.40 * sign, -0.04, 1.64),
                    (0.68 * sign, -0.09, 1.40),
                    "chest",
                ),
                (
                    f"forearm.{side}",
                    (0.68 * sign, -0.09, 1.40),
                    (0.72 * sign, -0.30, 1.15),
                    f"upper_arm.{side}",
                ),
                (
                    f"hand.{side}",
                    (0.72 * sign, -0.30, 1.15),
                    (0.72 * sign, -0.48, 1.05),
                    f"forearm.{side}",
                ),
                (
                    f"thigh.{side}",
                    (0.24 * sign, 0.03, 0.86),
                    (0.30 * sign, -0.01, 0.48),
                    "pelvis",
                ),
                (
                    f"shin.{side}",
                    (0.30 * sign, -0.01, 0.48),
                    (0.28 * sign, -0.10, 0.14),
                    f"thigh.{side}",
                ),
                (
                    f"foot.{side}",
                    (0.28 * sign, -0.10, 0.14),
                    (0.28 * sign, -0.38, 0.08),
                    f"shin.{side}",
                ),
            ]
        )
    bones.append(
        (
            "staff",
            (-0.77, -0.42, 0.06),
            (-0.77, -0.42, 1.78),
            "root",
        )
    )
    return create_rig(RIG_NAME, bones, "boss")


def build_parts(material: bpy.types.Material) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    def sphere(
        name: str,
        location: tuple[float, float, float],
        scale: tuple[float, float, float],
        color: tuple[float, float, float, float],
        bone: str,
        segments: int = 24,
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

    # Hair is authored first so its silhouette frames the face without
    # obscuring the painted facial planes.
    sphere(
        "hair_back",
        (0.0, 0.01, 2.06),
        (0.43, 0.26, 0.48),
        HAIR,
        "head",
        36,
        18,
    )
    sphere("hips", (0.0, 0.03, 0.87), (0.43, 0.34, 0.31), SKIN_DARK, "pelvis", 36, 18)
    sphere("belly", (0.0, -0.07, 1.19), (0.56, 0.44, 0.51), SKIN, "spine", 48, 24)
    sphere("chest", (0.0, -0.08, 1.53), (0.53, 0.37, 0.43), SKIN, "chest", 44, 22)
    sphere(
        "belly_highlight",
        (0.0, -0.465, 1.18),
        (0.35, 0.075, 0.31),
        SKIN_LIGHT,
        "spine",
        30,
        15,
    )
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "neck",
            (0.0, -0.08, 1.65),
            (0.0, -0.16, 1.91),
            0.23,
            SKIN_DARK,
            material,
            "neck",
            22,
        )
    )
    sphere("head", (0.0, -0.19, 2.06), (0.38, 0.34, 0.41), SKIN, "head", 42, 21)
    sphere("jaw", (0.0, -0.40, 1.96), (0.35, 0.27, 0.25), SKIN_LIGHT, "jaw", 36, 18)
    sphere("nose", (0.0, -0.545, 2.12), (0.135, 0.12, 0.14), SKIN_DARK, "head", 24, 12)
    sphere("beard", (0.0, -0.38, 1.78), (0.29, 0.20, 0.27), HAIR, "jaw", 30, 15)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        sphere(
            f"ear_{side}",
            (0.35 * sign, -0.20, 2.06),
            (0.10, 0.07, 0.15),
            SKIN_LIGHT,
            "head",
            18,
            9,
        )
        sphere(
            f"cheek_{side}",
            (0.225 * sign, -0.455, 2.02),
            (0.14, 0.075, 0.12),
            SKIN_LIGHT,
            "head",
            20,
            10,
        )
        sphere(
            f"eye_{side}",
            (0.145 * sign, -0.505, 2.20),
            (0.085, 0.038, 0.075),
            EYE_WHITE,
            "head",
            16,
            8,
        )
        sphere(
            f"pupil_{side}",
            (0.145 * sign, -0.542, 2.20),
            (0.034, 0.017, 0.044),
            PUPIL,
            "head",
            12,
            6,
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"eye_paint_{side}",
                (0.205 * sign, -0.522, 2.20),
                (0.20, 0.022, 0.055),
                PAINT_TEAL,
                material,
                "head",
                rotation=(0.0, 0.0, math.radians(12.0 * sign)),
                bevel=0.012,
            )
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"cheek_paint_{side}",
                (0.245 * sign, -0.525, 1.99),
                (0.13, 0.020, 0.045),
                PAINT_RED,
                material,
                "head",
                rotation=(0.0, 0.0, math.radians(-14.0 * sign)),
                bevel=0.01,
            )
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"earring_{side}",
                (0.38 * sign, -0.22, 1.99),
                (0.40 * sign, -0.22, 1.82),
                0.042,
                0.012,
                PAINT_YELLOW,
                material,
                "head",
                12,
            )
        )

    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "nose_paint",
            (0.0, -0.565, 2.25),
            (0.055, 0.022, 0.17),
            WHITE,
            material,
            "head",
            bevel=0.012,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "mouth",
            (0.0, -0.652, 1.97),
            (0.23, 0.025, 0.042),
            CLOTH_DARK,
            material,
            "jaw",
            bevel=0.015,
        )
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"mouth_tusk_{side}",
                (0.18 * sign, -0.61, 1.96),
                (0.20 * sign, -0.65, 1.86),
                0.040,
                0.005,
                WHITE,
                material,
                "jaw",
                12,
            )
        )

    # Feather crown: large alternating color blocks read as a crown rather
    # than noisy detail when the camera is pulled back.
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "crown_band",
            (0.0, -0.10, 2.38),
            (0.73, 0.15, 0.16),
            PAINT_YELLOW,
            material,
            "headdress",
            bevel=0.025,
        )
    )
    feather_colors = (
        PAINT_RED,
        PAINT_TEAL,
        PAINT_YELLOW,
        WHITE,
        PAINT_YELLOW,
        PAINT_TEAL,
        PAINT_RED,
    )
    for index, (x_position, color) in enumerate(
        zip((-0.39, -0.27, -0.14, 0.0, 0.14, 0.27, 0.39), feather_colors)
    ):
        height = 2.72 + (0.20 if index == 3 else 0.08 if index in (2, 4) else 0.0)
        sphere(
            f"feather_{index}",
            (x_position, -0.04, (2.43 + height) * 0.5),
            (0.085, 0.055, (height - 2.43) * 0.58),
            color,
            "headdress",
            16,
            8,
            (0.0, math.radians(-10.0 * x_position), 0.0),
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"feather_tip_{index}",
                (x_position, -0.04, height - 0.12),
                (x_position, -0.04, height + 0.10),
                0.075,
                0.006,
                color,
                material,
                "headdress",
                14,
            )
        )

    # Necklace and cloth add strong value breaks across the large torso.
    for index, x_position in enumerate((-0.30, -0.20, -0.10, 0.0, 0.10, 0.20, 0.30)):
        z_position = 1.59 - (0.12 - abs(x_position) * 0.22)
        sphere(
            f"necklace_bead_{index}",
            (x_position, -0.438, z_position),
            (0.055, 0.035, 0.055),
            PAINT_TEAL if index % 2 == 0 else PAINT_YELLOW,
            "chest",
            12,
            6,
        )
    for index, x_position in enumerate((-0.18, 0.0, 0.18)):
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"necklace_tooth_{index}",
                (x_position, -0.445, 1.49),
                (x_position, -0.475, 1.35),
                0.045,
                0.005,
                WHITE,
                material,
                "chest",
                12,
            )
        )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "belt",
            (0.0, -0.07, 0.89),
            (0.88, 0.53, 0.16),
            PAINT_YELLOW,
            material,
            "pelvis",
            bevel=0.035,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "loincloth_front",
            (0.0, -0.34, 0.63),
            (0.48, 0.10, 0.55),
            CLOTH,
            material,
            "pelvis",
            rotation=(math.radians(-8.0), 0.0, 0.0),
            bevel=0.035,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "loincloth_mark",
            (0.0, -0.402, 0.66),
            (0.12, 0.035, 0.38),
            PAINT_TEAL,
            material,
            "pelvis",
            rotation=(math.radians(-8.0), 0.0, 0.0),
            bevel=0.018,
        )
    )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = f"upper_arm.{side}"
        forearm_bone = f"forearm.{side}"
        hand_bone = f"hand.{side}"
        shoulder = (0.43 * sign, -0.06, 1.64)
        elbow = (0.69 * sign, -0.10, 1.40)
        wrist = (0.72 * sign, -0.31, 1.15)
        hand = (0.72 * sign, -0.43, 1.06)
        sphere(
            f"shoulder_{side}",
            shoulder,
            (0.20, 0.20, 0.22),
            SKIN_DARK,
            upper_bone,
            24,
            12,
        )
        parts.append(
            add_cylinder_between(
                ASSET_KEY,
                f"upper_arm_{side}",
                shoulder,
                elbow,
                0.16,
                SKIN,
                material,
                upper_bone,
                20,
            )
        )
        sphere(
            f"elbow_{side}",
            elbow,
            (0.16, 0.15, 0.16),
            SKIN_LIGHT,
            forearm_bone,
            20,
            10,
        )
        parts.append(
            add_cylinder_between(
                ASSET_KEY,
                f"forearm_{side}",
                elbow,
                wrist,
                0.145,
                SKIN,
                material,
                forearm_bone,
                20,
            )
        )
        sphere(
            f"hand_{side}",
            hand,
            (0.16, 0.19, 0.15),
            SKIN_LIGHT,
            hand_bone,
            24,
            12,
        )
        parts.append(
            add_rounded_box(
                ASSET_KEY,
                f"wrist_band_{side}",
                wrist,
                (0.25, 0.16, 0.12),
                PAINT_TEAL if side == "L" else PAINT_RED,
                material,
                forearm_bone,
                bevel=0.025,
            )
        )

        thigh_bone = f"thigh.{side}"
        shin_bone = f"shin.{side}"
        foot_bone = f"foot.{side}"
        hip = (0.25 * sign, 0.01, 0.84)
        knee = (0.30 * sign, -0.02, 0.47)
        ankle = (0.28 * sign, -0.10, 0.14)
        foot = (0.28 * sign, -0.29, 0.085)
        parts.append(
            add_cylinder_between(
                ASSET_KEY,
                f"thigh_{side}",
                hip,
                knee,
                0.19,
                SKIN_DARK,
                material,
                thigh_bone,
                22,
            )
        )
        sphere(
            f"knee_{side}",
            knee,
            (0.18, 0.17, 0.17),
            SKIN_LIGHT,
            shin_bone,
            20,
            10,
        )
        parts.append(
            add_cylinder_between(
                ASSET_KEY,
                f"shin_{side}",
                knee,
                ankle,
                0.15,
                SKIN,
                material,
                shin_bone,
                20,
            )
        )
        sphere(
            f"foot_{side}",
            foot,
            (0.21, 0.32, 0.11),
            SKIN_DARK,
            foot_bone,
            28,
            14,
        )
        for toe_index, toe_x in enumerate((-0.09, 0.0, 0.09)):
            sphere(
                f"toe_{side}_{toe_index}",
                (foot[0] + toe_x, -0.555, 0.085),
                (0.055, 0.11, 0.045),
                WHITE,
                foot_bone,
                12,
                6,
            )

    # Staff geometry has its own deform bone so the slam reads as a single
    # heavy lever rather than a loose accessory.
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "staff_shaft",
            (-0.77, -0.42, 0.05),
            (-0.77, -0.42, 1.83),
            0.075,
            WOOD,
            material,
            "staff",
            22,
        )
    )
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "staff_grip",
            (-0.77, -0.42, 0.91),
            (-0.77, -0.42, 1.24),
            0.10,
            WOOD_LIGHT,
            material,
            "staff",
            18,
        )
    )
    sphere(
        "staff_mask",
        (-0.77, -0.42, 1.96),
        (0.22, 0.14, 0.25),
        WHITE,
        "staff",
        24,
        12,
    )
    sphere(
        "staff_eye_left",
        (-0.85, -0.545, 2.02),
        (0.042, 0.025, 0.052),
        PAINT_RED,
        "staff",
        12,
        6,
    )
    sphere(
        "staff_eye_right",
        (-0.69, -0.545, 2.02),
        (0.042, 0.025, 0.052),
        PAINT_RED,
        "staff",
        12,
        6,
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "staff_leaf_left",
            (-0.84, -0.42, 2.12),
            (-1.08, -0.42, 2.34),
            0.10,
            0.012,
            LEAF,
            material,
            "staff",
            14,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "staff_leaf_right",
            (-0.70, -0.42, 2.12),
            (-0.47, -0.42, 2.34),
            0.10,
            0.012,
            LEAF,
            material,
            "staff",
            14,
        )
    )
    return parts


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, IDLE, 41)
    key_pose(rig, 1)
    key_pose(
        rig,
        11,
        {
            "spine": (2.5, 0.0, 2.0),
            "chest": (-2.0, 0.0, -2.0),
            "neck": (-3.0, 0.0, 2.0),
            "head": (3.0, 0.0, -3.0),
            "jaw": (4.0, 0.0, 0.0),
            "upper_arm.L": (4.0, 0.0, -4.0),
            "upper_arm.R": (-3.0, 0.0, 3.0),
            "staff": (0.0, 0.0, 2.0),
        },
        {"root": (0.0, 0.0, 0.025)},
    )
    key_pose(
        rig,
        21,
        {
            "spine": (-2.5, 0.0, -2.0),
            "chest": (2.0, 0.0, 2.0),
            "neck": (3.0, 0.0, -2.0),
            "head": (-3.0, 0.0, 3.0),
            "jaw": (-2.0, 0.0, 0.0),
            "upper_arm.L": (-3.0, 0.0, 4.0),
            "upper_arm.R": (4.0, 0.0, -3.0),
            "staff": (0.0, 0.0, -2.0),
        },
        {"root": (0.0, 0.0, 0.045)},
    )
    key_pose(
        rig,
        31,
        {
            "spine": (1.5, 0.0, 1.0),
            "head": (2.0, 0.0, -2.0),
            "jaw": (3.0, 0.0, 0.0),
            "upper_arm.L": (2.0, 0.0, -2.0),
            "upper_arm.R": (-2.0, 0.0, 2.0),
        },
        {"root": (0.0, 0.0, 0.015)},
    )
    key_pose(rig, 41)
    return finish_action(action, "idle", True)


def create_taunt(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, TAUNT, 25)
    key_pose(rig, 1)
    key_pose(
        rig,
        6,
        {
            "spine": (12.0, 0.0, 0.0),
            "head": (-12.0, 0.0, 0.0),
            "upper_arm.L": (-38.0, -8.0, -38.0),
            "forearm.L": (-42.0, 0.0, 0.0),
            "upper_arm.R": (-25.0, 6.0, 22.0),
            "forearm.R": (-32.0, 0.0, 0.0),
            "jaw": (12.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.04, -0.08)},
    )
    key_pose(
        rig,
        13,
        {
            "spine": (-10.0, 0.0, 0.0),
            "chest": (-8.0, 0.0, 0.0),
            "head": (16.0, 0.0, 0.0),
            "upper_arm.L": (-78.0, -12.0, -58.0),
            "forearm.L": (-55.0, 0.0, 0.0),
            "upper_arm.R": (-65.0, 10.0, 46.0),
            "forearm.R": (-48.0, 0.0, 0.0),
            "jaw": (22.0, 0.0, 0.0),
            "staff": (-12.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.0, 0.18)},
    )
    key_pose(
        rig,
        19,
        {
            "spine": (6.0, 0.0, 0.0),
            "head": (-7.0, 0.0, 0.0),
            "upper_arm.L": (-25.0, 0.0, -20.0),
            "upper_arm.R": (-20.0, 0.0, 16.0),
            "jaw": (8.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.0, 0.04)},
    )
    key_pose(rig, 25)
    return finish_action(action, "taunt", False)


def create_slam(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SLAM, 25)
    key_pose(rig, 1)
    key_pose(
        rig,
        6,
        {
            "spine": (-16.0, 0.0, 4.0),
            "chest": (-12.0, 0.0, -4.0),
            "neck": (10.0, 0.0, 0.0),
            "head": (8.0, 0.0, 0.0),
            "upper_arm.R": (-82.0, 8.0, 34.0),
            "forearm.R": (-58.0, 0.0, 0.0),
            "hand.R": (-18.0, 0.0, 0.0),
            "upper_arm.L": (-35.0, 0.0, -28.0),
            "forearm.L": (-28.0, 0.0, 0.0),
            "staff": (-32.0, 0.0, 0.0),
        },
        {
            "root": (0.0, 0.12, 0.12),
            "staff": (0.0, 0.0, 0.25),
        },
    )
    key_pose(
        rig,
        12,
        {
            "spine": (24.0, 0.0, -4.0),
            "chest": (18.0, 0.0, 4.0),
            "neck": (-18.0, 0.0, 0.0),
            "head": (-13.0, 0.0, 0.0),
            "upper_arm.R": (62.0, 0.0, 12.0),
            "forearm.R": (58.0, 0.0, 0.0),
            "hand.R": (18.0, 0.0, 0.0),
            "upper_arm.L": (28.0, 0.0, -18.0),
            "forearm.L": (32.0, 0.0, 0.0),
            "thigh.L": (-15.0, 0.0, 0.0),
            "thigh.R": (-15.0, 0.0, 0.0),
            "shin.L": (25.0, 0.0, 0.0),
            "shin.R": (25.0, 0.0, 0.0),
        },
        {
            "root": (0.0, -0.12, -0.08),
            "staff": (0.0, 0.0, 0.08),
        },
    )
    key_pose(
        rig,
        16,
        {
            "spine": (18.0, 0.0, 0.0),
            "chest": (12.0, 0.0, 0.0),
            "head": (-8.0, 0.0, 0.0),
            "upper_arm.R": (48.0, 0.0, 10.0),
            "forearm.R": (42.0, 0.0, 0.0),
            "upper_arm.L": (18.0, 0.0, -12.0),
            "thigh.L": (-10.0, 0.0, 0.0),
            "thigh.R": (-10.0, 0.0, 0.0),
            "shin.L": (18.0, 0.0, 0.0),
            "shin.R": (18.0, 0.0, 0.0),
        },
        {
            "root": (0.0, -0.08, -0.05),
            "staff": (0.0, 0.0, 0.05),
        },
    )
    key_pose(rig, 25)
    return finish_action(action, "attack", False)


def create_hit(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, HIT, 13)
    key_pose(rig, 1)
    key_pose(
        rig,
        5,
        {
            "root": (-6.0, 0.0, -12.0),
            "spine": (-18.0, 0.0, 8.0),
            "chest": (-16.0, 0.0, -8.0),
            "neck": (14.0, 0.0, 0.0),
            "head": (18.0, 0.0, 10.0),
            "jaw": (12.0, 0.0, 0.0),
            "upper_arm.L": (22.0, 0.0, -28.0),
            "upper_arm.R": (25.0, 0.0, 24.0),
        },
        {"root": (0.16, 0.12, 0.03)},
    )
    key_pose(
        rig,
        9,
        {
            "root": (3.0, 0.0, 5.0),
            "spine": (8.0, 0.0, -3.0),
            "head": (-8.0, 0.0, -4.0),
        },
        {"root": (-0.05, -0.02, 0.0)},
    )
    key_pose(rig, 13)
    return finish_action(action, "hit", False)


def create_phase(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, PHASE, 29)
    key_pose(rig, 1)
    key_pose(
        rig,
        7,
        {
            "spine": (16.0, 0.0, 0.0),
            "head": (-14.0, 0.0, 0.0),
            "upper_arm.L": (18.0, 0.0, -25.0),
            "upper_arm.R": (18.0, 0.0, 25.0),
            "forearm.L": (38.0, 0.0, 0.0),
            "forearm.R": (38.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.05, -0.10)},
    )
    key_pose(
        rig,
        15,
        {
            "spine": (-14.0, 0.0, 0.0),
            "chest": (-10.0, 0.0, 0.0),
            "neck": (12.0, 0.0, 0.0),
            "head": (18.0, 0.0, 0.0),
            "jaw": (20.0, 0.0, 0.0),
            "upper_arm.L": (-72.0, -8.0, -58.0),
            "upper_arm.R": (-68.0, 8.0, 52.0),
            "forearm.L": (-45.0, 0.0, 0.0),
            "forearm.R": (-45.0, 0.0, 0.0),
        },
        {"root": (0.0, -0.02, 0.20)},
    )
    key_pose(
        rig,
        22,
        {
            "spine": (5.0, 0.0, 0.0),
            "head": (-5.0, 0.0, 0.0),
            "upper_arm.L": (-20.0, 0.0, -16.0),
            "upper_arm.R": (-18.0, 0.0, 15.0),
        },
        {"root": (0.0, 0.0, 0.04)},
    )
    key_pose(rig, 29)
    return finish_action(action, "phase", False)


def create_defeat(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, DEFEAT, 41)
    key_pose(rig, 1)
    key_pose(
        rig,
        8,
        {
            "root": (-5.0, 0.0, -14.0),
            "spine": (-20.0, 0.0, 8.0),
            "chest": (-18.0, 0.0, -8.0),
            "head": (22.0, 0.0, 12.0),
            "jaw": (16.0, 0.0, 0.0),
            "upper_arm.L": (28.0, 0.0, -34.0),
            "upper_arm.R": (30.0, 0.0, 28.0),
        },
        {"root": (0.14, 0.05, 0.02)},
    )
    key_pose(
        rig,
        17,
        {
            "root": (10.0, 0.0, 24.0),
            "spine": (18.0, 0.0, -10.0),
            "head": (-18.0, 0.0, -12.0),
            "upper_arm.L": (-26.0, 0.0, -18.0),
            "upper_arm.R": (-20.0, 0.0, 18.0),
            "thigh.L": (-18.0, 0.0, 0.0),
            "thigh.R": (12.0, 0.0, 0.0),
        },
        {"root": (-0.18, 0.04, -0.06)},
    )
    key_pose(
        rig,
        29,
        {
            "root": (4.0, 0.0, 78.0),
            "spine": (12.0, 0.0, -4.0),
            "chest": (8.0, 0.0, 4.0),
            "head": (-12.0, 0.0, -8.0),
            "upper_arm.L": (20.0, 0.0, -45.0),
            "upper_arm.R": (-12.0, 0.0, 35.0),
            "thigh.L": (-25.0, 0.0, 0.0),
            "thigh.R": (20.0, 0.0, 0.0),
        },
        {"root": (-0.15, 0.0, 0.12)},
    )
    key_pose(
        rig,
        41,
        {
            "root": (4.0, 0.0, 82.0),
            "spine": (8.0, 0.0, -3.0),
            "head": (-8.0, 0.0, -5.0),
            "upper_arm.L": (16.0, 0.0, -42.0),
            "upper_arm.R": (-10.0, 0.0, 32.0),
            "thigh.L": (-22.0, 0.0, 0.0),
            "thigh.R": (18.0, 0.0, 0.0),
        },
        {"root": (-0.20, 0.0, 0.08)},
    )
    return finish_action(action, "defeat", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        TAUNT: create_taunt(rig),
        SLAM: create_slam(rig),
        HIT: create_hit(rig),
        PHASE: create_phase(rig),
        DEFEAT: create_defeat(rig),
    }


def main() -> None:
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.82)
    rig = build_rig()
    character = join_and_skin(
        ASSET_NAME,
        ASSET_KEY,
        "boss",
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
        required_bones=(
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
            "staff",
        ),
        minimum_triangles=15000,
        maximum_triangles=25000,
        minimum_colors=10,
    )
    save_source_and_export(
        source_path=SOURCE_PATH,
        export_path=EXPORT_PATH,
        character=character,
        rig=rig,
    )
    create_preview(
        preview_path=PREVIEW_PATH,
        character=character,
        rig=rig,
        target=(0.0, -0.15, 1.35),
        camera_location=(3.35, -5.35, 2.65),
        floor_size=7.0,
        poses=(
            (IDLE, 21, "A_papu_idle_pose.png"),
            (SLAM, 12, "A_papu_slam_pose.png"),
            (PHASE, 15, "A_papu_phase_pose.png"),
            (DEFEAT, 29, "A_papu_defeat_pose.png"),
        ),
        key_color=(1.0, 0.50, 0.22),
    )
    print(
        "PAPU_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_papu "
        f"animations={len(actions)}"
    )
    print(f"PAPU_SOURCE={SOURCE_PATH}")
    print(f"PAPU_GLB={EXPORT_PATH}")
    print(f"PAPU_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
