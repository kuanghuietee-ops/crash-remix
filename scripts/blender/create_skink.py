"""Build the original low-poly Beach skink enemy for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_skink.py

The generated asset is original scripted geometry.  It exports one
vertex-painted skinned mesh, one compact custom skeleton, and six clips that
match the existing skink telegraph/dart/cooldown gameplay states.
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
ASSET_NAME = "SK_skink"
ASSET_KEY = "skink"
RIG_NAME = "RIG_skink"
MATERIAL_NAME = "M_skink_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_skink.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/enemies/SK_skink.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_skink.png"

IDLE = "A_skink_idle"
TELEGRAPH = "A_skink_telegraph"
DART = "A_skink_dart"
RETURN = "A_skink_return"
HIT = "A_skink_hit"
DEFEAT = "A_skink_defeat"
ACTION_NAMES = (IDLE, TELEGRAPH, DART, RETURN, HIT, DEFEAT)

BODY = (0.055, 0.48, 0.27, 1.0)
BODY_LIGHT = (0.12, 0.76, 0.43, 1.0)
BODY_DARK = (0.018, 0.19, 0.14, 1.0)
STRIPE = (1.0, 0.68, 0.055, 1.0)
STRIPE_DARK = (0.78, 0.24, 0.025, 1.0)
BELLY = (0.72, 0.92, 0.40, 1.0)
EYE = (1.0, 0.96, 0.63, 1.0)
PUPIL = (0.008, 0.012, 0.010, 1.0)
MOUTH = (0.20, 0.018, 0.025, 1.0)
TOE = (0.92, 0.34, 0.055, 1.0)


def build_rig() -> bpy.types.Object:
    return create_rig(
        RIG_NAME,
        [
            ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.12), None),
            ("body", (0.0, 0.15, 0.28), (0.0, -0.20, 0.38), "root"),
            ("head", (0.0, -0.25, 0.38), (0.0, -0.62, 0.39), "body"),
            ("jaw", (0.0, -0.55, 0.32), (0.0, -0.78, 0.29), "head"),
            ("tail", (0.0, 0.32, 0.30), (0.0, 0.72, 0.23), "body"),
            ("tail.001", (0.0, 0.70, 0.23), (0.0, 1.13, 0.10), "tail"),
            (
                "leg_front.L",
                (0.22, -0.24, 0.29),
                (0.43, -0.26, 0.11),
                "body",
            ),
            (
                "leg_front.R",
                (-0.22, -0.24, 0.29),
                (-0.43, -0.26, 0.11),
                "body",
            ),
            (
                "leg_back.L",
                (0.23, 0.24, 0.28),
                (0.45, 0.29, 0.10),
                "body",
            ),
            (
                "leg_back.R",
                (-0.23, 0.24, 0.28),
                (-0.45, 0.29, 0.10),
                "body",
            ),
        ],
        "enemy",
    )


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
            )
        )

    sphere("body", (0.0, 0.0, 0.33), (0.32, 0.52, 0.25), BODY, "body", 28, 14)
    sphere(
        "belly",
        (0.0, -0.075, 0.205),
        (0.245, 0.40, 0.105),
        BELLY,
        "body",
        18,
        10,
    )
    sphere(
        "back_stripe",
        (0.0, 0.02, 0.535),
        (0.205, 0.43, 0.055),
        STRIPE,
        "body",
        20,
        10,
    )
    for index, y_position in enumerate((-0.25, -0.02, 0.22)):
        sphere(
            f"back_mark_{index}",
            (0.0, y_position, 0.58),
            (0.105, 0.075, 0.035),
            STRIPE_DARK,
            "body",
            12,
            8,
        )

    sphere("head", (0.0, -0.49, 0.39), (0.28, 0.31, 0.245), BODY_LIGHT, "head", 24, 12)
    sphere(
        "snout",
        (0.0, -0.715, 0.325),
        (0.225, 0.155, 0.13),
        BODY,
        "head",
        18,
        10,
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "mouth",
            (0.0, -0.855, 0.31),
            (0.27, 0.028, 0.047),
            MOUTH,
            material,
            "jaw",
            bevel=0.012,
        )
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        sphere(
            f"eye_{side}",
            (0.13 * sign, -0.69, 0.49),
            (0.105, 0.075, 0.115),
            EYE,
            "head",
            14,
            8,
        )
        sphere(
            f"pupil_{side}",
            (0.13 * sign, -0.755, 0.50),
            (0.040, 0.025, 0.060),
            PUPIL,
            "head",
            12,
            8,
        )
        sphere(
            f"brow_{side}",
            (0.13 * sign, -0.72, 0.575),
            (0.12, 0.04, 0.035),
            BODY_DARK,
            "head",
            12,
            6,
        )

    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_base",
            (0.0, 0.33, 0.31),
            (0.0, 0.76, 0.22),
            0.22,
            0.14,
            BODY,
            material,
            "tail",
            18,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_mid",
            (0.0, 0.72, 0.22),
            (0.0, 1.02, 0.13),
            0.15,
            0.075,
            BODY_LIGHT,
            material,
            "tail.001",
            18,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_tip",
            (0.0, 0.98, 0.13),
            (0.0, 1.25, 0.055),
            0.08,
            0.012,
            STRIPE,
            material,
            "tail.001",
            16,
        )
    )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        for label, y_position, bone in (
            ("front", -0.24, f"leg_front.{side}"),
            ("back", 0.24, f"leg_back.{side}"),
        ):
            hip = (0.22 * sign, y_position, 0.29)
            knee = (0.38 * sign, y_position - 0.015, 0.16)
            ankle = (0.44 * sign, y_position - 0.06, 0.055)
            toe = (0.52 * sign, y_position - 0.13, 0.045)
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"upper_{label}_{side}",
                    hip,
                    knee,
                    0.055,
                    BODY_DARK,
                    material,
                    bone,
                    12,
                )
            )
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"lower_{label}_{side}",
                    knee,
                    ankle,
                    0.043,
                    BODY_LIGHT,
                    material,
                    bone,
                    12,
                )
            )
            sphere(
                f"knee_{label}_{side}",
                knee,
                (0.07, 0.065, 0.065),
                STRIPE,
                bone,
                12,
                8,
            )
            sphere(
                f"foot_{label}_{side}",
                ankle,
                (0.075, 0.085, 0.045),
                BODY,
                bone,
                12,
                8,
            )
            for toe_index in range(2):
                toe_x = toe[0] + (toe_index - 0.5) * 0.035 * sign
                parts.append(
                    add_cone_between(
                        ASSET_KEY,
                        f"toe_{label}_{side}_{toe_index}",
                        ankle,
                        (toe_x, toe[1] - toe_index * 0.025, toe[2]),
                        0.025,
                        0.006,
                        TOE,
                        material,
                        bone,
                        8,
                    )
                )
    return parts


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, IDLE, 25)
    key_pose(rig, 1)
    key_pose(
        rig,
        7,
        {
            "body": (1.5, 0.0, 2.0),
            "head": (-3.0, 0.0, -4.0),
            "tail": (0.0, 0.0, 8.0),
            "tail.001": (0.0, 0.0, -11.0),
        },
        {"root": (0.0, 0.0, 0.012)},
    )
    key_pose(
        rig,
        13,
        {
            "body": (-1.5, 0.0, -2.0),
            "head": (2.0, 0.0, 5.0),
            "tail": (0.0, 0.0, -8.0),
            "tail.001": (0.0, 0.0, 12.0),
        },
        {"root": (0.0, 0.0, 0.022)},
    )
    key_pose(
        rig,
        19,
        {
            "head": (-2.0, 0.0, -2.0),
            "tail": (0.0, 0.0, 4.0),
            "tail.001": (0.0, 0.0, -6.0),
        },
        {"root": (0.0, 0.0, 0.008)},
    )
    key_pose(rig, 25)
    return finish_action(action, "idle", True)


def create_telegraph(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, TELEGRAPH, 13)
    key_pose(rig, 1)
    key_pose(
        rig,
        5,
        {
            "body": (10.0, 0.0, 0.0),
            "head": (-14.0, 0.0, 0.0),
            "tail": (0.0, 0.0, 18.0),
            "tail.001": (0.0, 0.0, 22.0),
            "leg_front.L": (-12.0, 0.0, -9.0),
            "leg_front.R": (-12.0, 0.0, 9.0),
            "leg_back.L": (10.0, 0.0, -8.0),
            "leg_back.R": (10.0, 0.0, 8.0),
        },
        {"root": (0.0, 0.055, -0.045)},
    )
    key_pose(
        rig,
        9,
        {
            "body": (7.0, 0.0, -3.0),
            "head": (-9.0, 0.0, 5.0),
            "tail": (0.0, 0.0, -18.0),
            "tail.001": (0.0, 0.0, -24.0),
            "leg_front.L": (-10.0, 0.0, -8.0),
            "leg_front.R": (-10.0, 0.0, 8.0),
        },
        {"root": (0.0, 0.035, -0.035)},
    )
    key_pose(
        rig,
        13,
        {
            "body": (9.0, 0.0, 0.0),
            "head": (-12.0, 0.0, 0.0),
            "tail": (0.0, 0.0, 14.0),
            "tail.001": (0.0, 0.0, 18.0),
        },
        {"root": (0.0, 0.05, -0.04)},
    )
    return finish_action(action, "telegraph", False)


def locomotion_pose(
    rig: bpy.types.Object,
    frame: int,
    reverse: bool,
) -> None:
    phase = math.tau * (frame - 1) / 16.0
    stride = math.sin(phase)
    lift = abs(math.cos(phase))
    reverse_sign = -1.0 if reverse else 1.0
    key_pose(
        rig,
        frame,
        {
            "body": (2.0 * stride, 0.0, 4.0 * stride),
            "head": (-3.0 * stride, 0.0, -4.0 * stride * reverse_sign),
            "tail": (0.0, 0.0, -18.0 * stride * reverse_sign),
            "tail.001": (0.0, 0.0, 26.0 * stride * reverse_sign),
            "leg_front.L": (24.0 * stride * reverse_sign, 0.0, -13.0 * stride),
            "leg_front.R": (-24.0 * stride * reverse_sign, 0.0, -13.0 * stride),
            "leg_back.L": (-24.0 * stride * reverse_sign, 0.0, 13.0 * stride),
            "leg_back.R": (24.0 * stride * reverse_sign, 0.0, 13.0 * stride),
        },
        {"root": (0.0, 0.0, 0.018 * lift)},
    )


def create_dart(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, DART, 17)
    for frame in (1, 5, 9, 13, 17):
        locomotion_pose(rig, frame, False)
    return finish_action(action, "locomotion", True)


def create_return(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, RETURN, 17)
    for frame in (1, 5, 9, 13, 17):
        locomotion_pose(rig, frame, True)
    return finish_action(action, "locomotion", True)


def create_hit(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, HIT, 9)
    key_pose(rig, 1)
    key_pose(
        rig,
        3,
        {
            "body": (-15.0, 0.0, 24.0),
            "head": (22.0, 0.0, -28.0),
            "jaw": (18.0, 0.0, 0.0),
            "tail": (0.0, 0.0, -26.0),
            "tail.001": (0.0, 0.0, -32.0),
            "leg_front.L": (20.0, 0.0, 18.0),
            "leg_front.R": (-20.0, 0.0, -18.0),
        },
        {"root": (0.07, 0.02, 0.08)},
    )
    key_pose(
        rig,
        6,
        {
            "body": (7.0, 0.0, -9.0),
            "head": (-8.0, 0.0, 11.0),
            "tail": (0.0, 0.0, 13.0),
        },
        {"root": (-0.02, 0.0, 0.02)},
    )
    key_pose(rig, 9)
    return finish_action(action, "reaction", False)


def create_defeat(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, DEFEAT, 19)
    key_pose(rig, 1)
    key_pose(
        rig,
        6,
        {
            "body": (42.0, 0.0, -22.0),
            "head": (-28.0, 0.0, 28.0),
            "jaw": (28.0, 0.0, 0.0),
            "tail": (0.0, 0.0, 34.0),
            "tail.001": (0.0, 0.0, -42.0),
            "leg_front.L": (30.0, 0.0, 34.0),
            "leg_front.R": (-30.0, 0.0, -34.0),
            "leg_back.L": (-28.0, 0.0, -30.0),
            "leg_back.R": (28.0, 0.0, 30.0),
        },
        {"root": (0.0, 0.0, 0.22)},
    )
    final_pose = {
        "body": (94.0, 0.0, 14.0),
        "head": (-34.0, 0.0, -22.0),
        "jaw": (32.0, 0.0, 0.0),
        "tail": (0.0, 0.0, -38.0),
        "tail.001": (0.0, 0.0, 48.0),
        "leg_front.L": (40.0, 0.0, 38.0),
        "leg_front.R": (-40.0, 0.0, -38.0),
        "leg_back.L": (-36.0, 0.0, -34.0),
        "leg_back.R": (36.0, 0.0, 34.0),
    }
    key_pose(rig, 13, final_pose, {"root": (0.0, 0.04, 0.07)})
    key_pose(rig, 19, final_pose, {"root": (0.0, 0.04, 0.02)})
    return finish_action(action, "defeat", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        TELEGRAPH: create_telegraph(rig),
        DART: create_dart(rig),
        RETURN: create_return(rig),
        HIT: create_hit(rig),
        DEFEAT: create_defeat(rig),
    }


def main() -> None:
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.79)
    rig = build_rig()
    character = join_and_skin(
        ASSET_NAME,
        ASSET_KEY,
        "enemy",
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
            "body",
            "head",
            "tail.001",
            "leg_front.L",
            "leg_front.R",
            "leg_back.L",
            "leg_back.R",
        ),
        minimum_triangles=3000,
        maximum_triangles=6000,
        minimum_colors=7,
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
        target=(0.0, 0.0, 0.36),
        camera_location=(1.65, -2.65, 1.28),
        floor_size=5.0,
        poses=(
            (DART, 5, "A_skink_dart_pose.png"),
            (TELEGRAPH, 7, "A_skink_telegraph_pose.png"),
            (HIT, 3, "A_skink_hit_pose.png"),
            (DEFEAT, 16, "A_skink_defeat_pose.png"),
        ),
        key_color=(1.0, 0.72, 0.36),
    )
    print(
        "SKINK_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_skink "
        f"animations={len(actions)}"
    )
    print(f"SKINK_SOURCE={SOURCE_PATH}")
    print(f"SKINK_GLB={EXPORT_PATH}")
    print(f"SKINK_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
