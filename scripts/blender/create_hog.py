"""Build the original low-poly Hog Wild rideable for Godot.

The rig applies the gait, airborne tuck, and landing-compression lessons from
the deliberately unshipped practice quadruped.  The production result exports
as one vertex-painted mesh inside the operator-approved 6k-10k rideable band.
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
ASSET_NAME = "SK_hog"
ASSET_KEY = "hog"
RIG_NAME = "RIG_hog"
MATERIAL_NAME = "M_hog_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_hog.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/rideables/SK_hog.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_hog.png"

IDLE = "A_hog_idle"
RUN = "A_hog_run"
JUMP = "A_hog_jump"
LAND = "A_hog_land"
ACTION_NAMES = (IDLE, RUN, JUMP, LAND)

HIDE = (0.34, 0.105, 0.035, 1.0)
HIDE_LIGHT = (0.64, 0.25, 0.07, 1.0)
HIDE_DARK = (0.16, 0.035, 0.018, 1.0)
BELLY = (0.82, 0.43, 0.15, 1.0)
MANE = (0.095, 0.018, 0.012, 1.0)
SNOUT = (0.78, 0.29, 0.22, 1.0)
NOSE = (0.105, 0.025, 0.035, 1.0)
TUSK = (1.0, 0.88, 0.56, 1.0)
EYE = (1.0, 0.84, 0.35, 1.0)
PUPIL = (0.008, 0.006, 0.005, 1.0)
HOOF = (0.075, 0.04, 0.028, 1.0)
ACCENT = (1.0, 0.46, 0.055, 1.0)


def build_rig() -> bpy.types.Object:
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.15), None),
        ("spine", (0.0, 0.38, 0.78), (0.0, -0.18, 0.84), "root"),
        ("chest", (0.0, -0.12, 0.84), (0.0, -0.50, 0.88), "spine"),
        ("neck", (0.0, -0.43, 0.88), (0.0, -0.72, 1.04), "chest"),
        ("head", (0.0, -0.68, 1.04), (0.0, -1.04, 0.96), "neck"),
        ("snout", (0.0, -0.98, 0.96), (0.0, -1.30, 0.88), "head"),
        ("tail", (0.0, 0.56, 0.82), (0.0, 0.88, 0.86), "spine"),
        ("tail.001", (0.0, 0.86, 0.86), (0.0, 1.05, 0.98), "tail"),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones.extend(
            [
                (
                    f"leg_front.{side}",
                    (0.30 * sign, -0.37, 0.76),
                    (0.31 * sign, -0.42, 0.40),
                    "chest",
                ),
                (
                    f"shin_front.{side}",
                    (0.31 * sign, -0.42, 0.40),
                    (0.29 * sign, -0.48, 0.10),
                    f"leg_front.{side}",
                ),
                (
                    f"leg_back.{side}",
                    (0.31 * sign, 0.37, 0.73),
                    (0.36 * sign, 0.43, 0.40),
                    "spine",
                ),
                (
                    f"shin_back.{side}",
                    (0.36 * sign, 0.43, 0.40),
                    (0.30 * sign, 0.35, 0.10),
                    f"leg_back.{side}",
                ),
            ]
        )
    return create_rig(RIG_NAME, bones, "rideable")


def build_parts(material: bpy.types.Material) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    def sphere(
        name: str,
        location: tuple[float, float, float],
        scale: tuple[float, float, float],
        color: tuple[float, float, float, float],
        bone: str,
        segments: int = 20,
        rings: int = 10,
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

    sphere("body", (0.0, 0.10, 0.80), (0.48, 0.72, 0.43), HIDE, "spine", 34, 17)
    sphere("rump", (0.0, 0.46, 0.80), (0.45, 0.44, 0.41), HIDE_DARK, "spine", 28, 14)
    sphere("chest", (0.0, -0.37, 0.84), (0.50, 0.43, 0.48), HIDE_LIGHT, "chest", 30, 15)
    sphere("belly", (0.0, 0.02, 0.57), (0.36, 0.55, 0.18), BELLY, "spine", 24, 12)
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "neck",
            (0.0, -0.42, 0.86),
            (0.0, -0.72, 1.03),
            0.31,
            HIDE_DARK,
            material,
            "neck",
            18,
        )
    )
    sphere("head", (0.0, -0.78, 1.02), (0.39, 0.42, 0.37), HIDE_LIGHT, "head", 28, 14)
    sphere("cheek", (0.0, -0.88, 0.91), (0.36, 0.34, 0.25), HIDE, "head", 22, 11)
    sphere("snout", (0.0, -1.11, 0.89), (0.34, 0.28, 0.22), SNOUT, "snout", 24, 12)
    sphere("nose", (0.0, -1.36, 0.89), (0.24, 0.10, 0.15), NOSE, "snout", 20, 10)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        sphere(
            f"nostril_{side}",
            (0.105 * sign, -1.455, 0.91),
            (0.040, 0.022, 0.035),
            PUPIL,
            "snout",
            10,
            6,
        )
        sphere(
            f"eye_{side}",
            (0.20 * sign, -1.08, 1.13),
            (0.095, 0.065, 0.105),
            EYE,
            "head",
            14,
            8,
        )
        sphere(
            f"pupil_{side}",
            (0.20 * sign, -1.14, 1.13),
            (0.038, 0.022, 0.052),
            PUPIL,
            "head",
            10,
            6,
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"ear_{side}",
                (0.24 * sign, -0.76, 1.22),
                (0.36 * sign, -0.69, 1.48),
                0.16,
                0.018,
                HIDE_DARK,
                material,
                "head",
                14,
            )
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"tusk_{side}",
                (0.20 * sign, -1.27, 0.84),
                (0.28 * sign, -1.43, 0.72),
                0.065,
                0.006,
                TUSK,
                material,
                "snout",
                12,
            )
        )

    for index, y_position in enumerate(
        (-0.55, -0.38, -0.20, -0.02, 0.16, 0.34, 0.50)
    ):
        height = 1.38 - abs(y_position) * 0.18
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"mane_spike_{index}",
                (0.0, y_position, 1.10),
                (0.0, y_position + 0.015, height),
                0.105,
                0.012,
                MANE if index % 2 == 0 else ACCENT,
                material,
                "chest" if y_position < -0.10 else "spine",
                12,
            )
        )

    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_base",
            (0.0, 0.56, 0.82),
            (0.0, 0.88, 0.86),
            0.12,
            0.075,
            HIDE_DARK,
            material,
            "tail",
            14,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_tip",
            (0.0, 0.86, 0.86),
            (0.0, 1.08, 1.02),
            0.08,
            0.018,
            ACCENT,
            material,
            "tail.001",
            14,
        )
    )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        for label, y_position, upper_bone, lower_bone in (
            (
                "front",
                -0.38,
                f"leg_front.{side}",
                f"shin_front.{side}",
            ),
            (
                "back",
                0.36,
                f"leg_back.{side}",
                f"shin_back.{side}",
            ),
        ):
            hip = (0.30 * sign, y_position, 0.75)
            knee = (
                (0.32 if label == "front" else 0.36) * sign,
                y_position + (0.04 if label == "back" else -0.03),
                0.40,
            )
            ankle = (
                0.30 * sign,
                y_position + (-0.10 if label == "front" else -0.02),
                0.11,
            )
            hoof = (
                0.30 * sign,
                ankle[1] - 0.10,
                0.065,
            )
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"upper_{label}_{side}",
                    hip,
                    knee,
                    0.12,
                    HIDE_DARK,
                    material,
                    upper_bone,
                    16,
                )
            )
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"lower_{label}_{side}",
                    knee,
                    ankle,
                    0.095,
                    HIDE_LIGHT,
                    material,
                    lower_bone,
                    16,
                )
            )
            sphere(
                f"knee_{label}_{side}",
                knee,
                (0.145, 0.13, 0.13),
                ACCENT,
                lower_bone,
                16,
                8,
            )
            sphere(
                f"hoof_{label}_{side}",
                hoof,
                (0.15, 0.20, 0.085),
                HOOF,
                lower_bone,
                18,
                8,
            )
            parts.append(
                add_rounded_box(
                    ASSET_KEY,
                    f"hoof_split_{label}_{side}",
                    (hoof[0], hoof[1] - 0.16, hoof[2] + 0.01),
                    (0.025, 0.09, 0.055),
                    TUSK,
                    material,
                    lower_bone,
                    bevel=0.008,
                )
            )
    return parts


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, IDLE, 33)
    key_pose(rig, 1)
    key_pose(
        rig,
        9,
        {
            "spine": (1.5, 0.0, 2.0),
            "neck": (-3.0, 0.0, -2.0),
            "head": (3.0, 0.0, 4.0),
            "snout": (2.0, 0.0, 0.0),
            "tail": (0.0, 0.0, 16.0),
            "tail.001": (0.0, 0.0, -22.0),
        },
        {"root": (0.0, 0.0, 0.018)},
    )
    key_pose(
        rig,
        17,
        {
            "spine": (-1.5, 0.0, -2.0),
            "neck": (3.0, 0.0, 2.0),
            "head": (-3.0, 0.0, -4.0),
            "snout": (-2.0, 0.0, 0.0),
            "tail": (0.0, 0.0, -16.0),
            "tail.001": (0.0, 0.0, 22.0),
        },
        {"root": (0.0, 0.0, 0.03)},
    )
    key_pose(
        rig,
        25,
        {
            "neck": (-2.0, 0.0, 1.0),
            "head": (2.0, 0.0, -2.0),
            "tail": (0.0, 0.0, 9.0),
            "tail.001": (0.0, 0.0, -12.0),
        },
        {"root": (0.0, 0.0, 0.01)},
    )
    key_pose(rig, 33)
    return finish_action(action, "idle", True)


def create_run(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, RUN, 17)
    for frame in (1, 5, 9, 13, 17):
        phase = math.tau * (frame - 1) / 16.0
        stride = math.sin(phase)
        suspension = math.cos(phase)
        key_pose(
            rig,
            frame,
            {
                "spine": (4.0 * suspension, 0.0, 3.0 * stride),
                "chest": (-3.0 * suspension, 0.0, -2.0 * stride),
                "neck": (-6.0 * suspension, 0.0, 3.0 * stride),
                "head": (4.0 * suspension, 0.0, -3.0 * stride),
                "tail": (0.0, 0.0, -20.0 * stride),
                "tail.001": (0.0, 0.0, 28.0 * stride),
                "leg_front.L": (38.0 * stride, 0.0, 0.0),
                "leg_front.R": (34.0 * stride, 0.0, 0.0),
                "leg_back.L": (-38.0 * stride, 0.0, 0.0),
                "leg_back.R": (-34.0 * stride, 0.0, 0.0),
                "shin_front.L": (-34.0 * stride, 0.0, 0.0),
                "shin_front.R": (-30.0 * stride, 0.0, 0.0),
                "shin_back.L": (38.0 * stride, 0.0, 0.0),
                "shin_back.R": (34.0 * stride, 0.0, 0.0),
            },
            {"root": (0.0, 0.0, 0.065 * abs(suspension))},
        )
    return finish_action(action, "locomotion", True)


def create_jump(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, JUMP, 17)
    key_pose(rig, 1)
    key_pose(
        rig,
        4,
        {
            "spine": (13.0, 0.0, 0.0),
            "neck": (-12.0, 0.0, 0.0),
            "leg_front.L": (-20.0, 0.0, 0.0),
            "leg_front.R": (-20.0, 0.0, 0.0),
            "leg_back.L": (22.0, 0.0, 0.0),
            "leg_back.R": (22.0, 0.0, 0.0),
            "shin_front.L": (34.0, 0.0, 0.0),
            "shin_front.R": (34.0, 0.0, 0.0),
            "shin_back.L": (-36.0, 0.0, 0.0),
            "shin_back.R": (-36.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.07, -0.08)},
    )
    key_pose(
        rig,
        9,
        {
            "spine": (-9.0, 0.0, 0.0),
            "neck": (13.0, 0.0, 0.0),
            "head": (-8.0, 0.0, 0.0),
            "leg_front.L": (28.0, 0.0, 0.0),
            "leg_front.R": (28.0, 0.0, 0.0),
            "leg_back.L": (-32.0, 0.0, 0.0),
            "leg_back.R": (-32.0, 0.0, 0.0),
            "shin_front.L": (-40.0, 0.0, 0.0),
            "shin_front.R": (-40.0, 0.0, 0.0),
            "shin_back.L": (44.0, 0.0, 0.0),
            "shin_back.R": (44.0, 0.0, 0.0),
            "tail": (0.0, 0.0, -28.0),
            "tail.001": (0.0, 0.0, 34.0),
        },
        {"root": (0.0, -0.13, 0.26)},
    )
    key_pose(
        rig,
        13,
        {
            "spine": (5.0, 0.0, 0.0),
            "leg_front.L": (-14.0, 0.0, 0.0),
            "leg_front.R": (-14.0, 0.0, 0.0),
            "leg_back.L": (16.0, 0.0, 0.0),
            "leg_back.R": (16.0, 0.0, 0.0),
        },
        {"root": (0.0, -0.03, 0.11)},
    )
    key_pose(rig, 17)
    return finish_action(action, "jump", False)


def create_land(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, LAND, 13)
    key_pose(rig, 1)
    key_pose(
        rig,
        4,
        {
            "spine": (16.0, 0.0, 0.0),
            "neck": (-15.0, 0.0, 0.0),
            "head": (8.0, 0.0, 0.0),
            "leg_front.L": (-24.0, 0.0, 0.0),
            "leg_front.R": (-24.0, 0.0, 0.0),
            "leg_back.L": (26.0, 0.0, 0.0),
            "leg_back.R": (26.0, 0.0, 0.0),
            "shin_front.L": (30.0, 0.0, 0.0),
            "shin_front.R": (30.0, 0.0, 0.0),
            "shin_back.L": (-32.0, 0.0, 0.0),
            "shin_back.R": (-32.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.05, -0.11)},
    )
    key_pose(
        rig,
        8,
        {
            "spine": (-6.0, 0.0, 0.0),
            "neck": (7.0, 0.0, 0.0),
            "tail": (0.0, 0.0, 18.0),
        },
        {"root": (0.0, -0.02, 0.03)},
    )
    key_pose(rig, 13)
    return finish_action(action, "landing", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        RUN: create_run(rig),
        JUMP: create_jump(rig),
        LAND: create_land(rig),
    }


def main() -> None:
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.81)
    rig = build_rig()
    character = join_and_skin(
        ASSET_NAME,
        ASSET_KEY,
        "rideable",
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
            "spine",
            "neck",
            "head",
            "leg_front.L",
            "leg_front.R",
            "leg_back.L",
            "leg_back.R",
            "shin_front.L",
            "shin_back.R",
        ),
        minimum_triangles=6000,
        maximum_triangles=10000,
        minimum_colors=8,
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
        target=(0.0, -0.10, 0.78),
        camera_location=(2.25, -3.65, 1.75),
        floor_size=6.0,
        poses=(
            (RUN, 5, "A_hog_run_pose.png"),
            (JUMP, 9, "A_hog_jump_pose.png"),
            (LAND, 4, "A_hog_land_pose.png"),
            (IDLE, 17, "A_hog_idle_pose.png"),
        ),
        key_color=(1.0, 0.60, 0.28),
    )
    print(
        "HOG_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_hog "
        f"animations={len(actions)}"
    )
    print(f"HOG_SOURCE={SOURCE_PATH}")
    print(f"HOG_GLB={EXPORT_PATH}")
    print(f"HOG_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
