"""Build the deliberately unshipped Phase 1 practice quadruped.

This is a rigging exercise, not game content.  Its editable source, GLB, and
previews all stay under build/ so the practice animal can never enter an APK.
The lessons are then applied to the separate production hog generator.
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
ASSET_NAME = "SK_practice_quadruped"
ASSET_KEY = "practice_quadruped"
RIG_NAME = "RIG_practice_quadruped"
MATERIAL_NAME = "M_practice_quadruped"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_practice_quadruped.blend"
EXPORT_PATH = REPO_ROOT / "build/art-practice/SK_practice_quadruped.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_practice_quadruped.png"

IDLE = "A_practice_quadruped_idle"
WALK = "A_practice_quadruped_walk"
RUN = "A_practice_quadruped_run"
JUMP = "A_practice_quadruped_jump"
LAND = "A_practice_quadruped_land"
ACTION_NAMES = (IDLE, WALK, RUN, JUMP, LAND)

BODY = (0.16, 0.30, 0.62, 1.0)
BODY_LIGHT = (0.30, 0.52, 0.88, 1.0)
BODY_DARK = (0.075, 0.12, 0.30, 1.0)
CHEST = (0.46, 0.25, 0.76, 1.0)
JOINT = (0.94, 0.47, 0.12, 1.0)
PAW = (0.98, 0.73, 0.26, 1.0)
EYE = (0.92, 0.96, 1.0, 1.0)
PUPIL = (0.01, 0.012, 0.025, 1.0)
NOSE = (0.08, 0.025, 0.05, 1.0)


def build_rig() -> bpy.types.Object:
    bones = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.15), None),
        ("spine", (0.0, 0.35, 0.72), (0.0, -0.22, 0.77), "root"),
        ("chest", (0.0, -0.15, 0.77), (0.0, -0.52, 0.82), "spine"),
        ("neck", (0.0, -0.45, 0.82), (0.0, -0.72, 1.04), "chest"),
        ("head", (0.0, -0.67, 1.04), (0.0, -0.98, 1.02), "neck"),
        ("tail", (0.0, 0.50, 0.76), (0.0, 0.84, 0.82), "spine"),
        ("tail.001", (0.0, 0.82, 0.82), (0.0, 1.12, 0.70), "tail"),
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bones.extend(
            [
                (
                    f"leg_front.{side}",
                    (0.24 * sign, -0.36, 0.70),
                    (0.27 * sign, -0.40, 0.37),
                    "chest",
                ),
                (
                    f"shin_front.{side}",
                    (0.27 * sign, -0.40, 0.37),
                    (0.25 * sign, -0.46, 0.08),
                    f"leg_front.{side}",
                ),
                (
                    f"leg_back.{side}",
                    (0.24 * sign, 0.35, 0.68),
                    (0.30 * sign, 0.43, 0.38),
                    "spine",
                ),
                (
                    f"shin_back.{side}",
                    (0.30 * sign, 0.43, 0.38),
                    (0.26 * sign, 0.35, 0.08),
                    f"leg_back.{side}",
                ),
            ]
        )
    return create_rig(RIG_NAME, bones, "practice")


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

    sphere("body", (0.0, 0.10, 0.76), (0.39, 0.62, 0.34), BODY, "spine", 28, 14)
    sphere("chest", (0.0, -0.38, 0.79), (0.43, 0.38, 0.39), CHEST, "chest", 24, 12)
    sphere("belly", (0.0, 0.08, 0.59), (0.30, 0.48, 0.16), BODY_LIGHT, "spine", 20, 10)
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "neck",
            (0.0, -0.43, 0.82),
            (0.0, -0.72, 1.03),
            0.24,
            BODY_DARK,
            material,
            "neck",
            16,
        )
    )
    sphere("head", (0.0, -0.78, 1.04), (0.31, 0.35, 0.30), BODY_LIGHT, "head", 24, 12)
    sphere("muzzle", (0.0, -1.04, 0.98), (0.25, 0.20, 0.17), CHEST, "head", 18, 10)
    sphere("nose", (0.0, -1.22, 1.00), (0.13, 0.075, 0.085), NOSE, "head", 14, 8)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        sphere(
            f"eye_{side}",
            (0.15 * sign, -1.02, 1.12),
            (0.09, 0.06, 0.10),
            EYE,
            "head",
            14,
            8,
        )
        sphere(
            f"pupil_{side}",
            (0.15 * sign, -1.075, 1.12),
            (0.035, 0.02, 0.050),
            PUPIL,
            "head",
            10,
            6,
        )
        parts.append(
            add_cone_between(
                ASSET_KEY,
                f"ear_{side}",
                (0.19 * sign, -0.77, 1.20),
                (0.30 * sign, -0.67, 1.44),
                0.13,
                0.015,
                JOINT,
                material,
                "head",
                12,
            )
        )

    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_base",
            (0.0, 0.50, 0.77),
            (0.0, 0.86, 0.83),
            0.13,
            0.09,
            BODY_DARK,
            material,
            "tail",
            14,
        )
    )
    parts.append(
        add_cone_between(
            ASSET_KEY,
            "tail_tip",
            (0.0, 0.83, 0.82),
            (0.0, 1.17, 0.68),
            0.095,
            0.02,
            PAW,
            material,
            "tail.001",
            14,
        )
    )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        for label, y_position, upper_bone, lower_bone in (
            (
                "front",
                -0.37,
                f"leg_front.{side}",
                f"shin_front.{side}",
            ),
            (
                "back",
                0.35,
                f"leg_back.{side}",
                f"shin_back.{side}",
            ),
        ):
            hip = (0.24 * sign, y_position, 0.69)
            knee = (
                (0.28 if label == "front" else 0.31) * sign,
                y_position + (0.02 if label == "back" else -0.03),
                0.37,
            )
            ankle = (
                0.26 * sign,
                y_position + (-0.09 if label == "front" else 0.0),
                0.09,
            )
            toe = (
                0.26 * sign,
                ankle[1] - 0.10,
                0.055,
            )
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"upper_{label}_{side}",
                    hip,
                    knee,
                    0.095,
                    BODY_DARK,
                    material,
                    upper_bone,
                    14,
                )
            )
            parts.append(
                add_cylinder_between(
                    ASSET_KEY,
                    f"lower_{label}_{side}",
                    knee,
                    ankle,
                    0.075,
                    BODY_LIGHT,
                    material,
                    lower_bone,
                    14,
                )
            )
            sphere(
                f"knee_{label}_{side}",
                knee,
                (0.12, 0.11, 0.11),
                JOINT,
                lower_bone,
                14,
                8,
            )
            sphere(
                f"paw_{label}_{side}",
                toe,
                (0.13, 0.18, 0.075),
                PAW,
                lower_bone,
                16,
                8,
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
            "head": (2.0, 0.0, 3.0),
            "tail": (0.0, 0.0, 12.0),
            "tail.001": (0.0, 0.0, -16.0),
        },
        {"root": (0.0, 0.0, 0.018)},
    )
    key_pose(
        rig,
        17,
        {
            "spine": (-1.5, 0.0, -2.0),
            "neck": (3.0, 0.0, 2.0),
            "head": (-2.0, 0.0, -3.0),
            "tail": (0.0, 0.0, -12.0),
            "tail.001": (0.0, 0.0, 16.0),
        },
        {"root": (0.0, 0.0, 0.028)},
    )
    key_pose(
        rig,
        25,
        {
            "neck": (-2.0, 0.0, 1.0),
            "head": (1.0, 0.0, -2.0),
            "tail": (0.0, 0.0, 7.0),
            "tail.001": (0.0, 0.0, -9.0),
        },
        {"root": (0.0, 0.0, 0.01)},
    )
    key_pose(rig, 33)
    return finish_action(action, "idle", True)


def gait_pose(
    rig: bpy.types.Object,
    frame: int,
    cycle_frames: int,
    stride_degrees: float,
    lift_m: float,
    run: bool,
) -> None:
    phase = math.tau * (frame - 1) / cycle_frames
    stride = math.sin(phase)
    secondary = math.cos(phase)
    fore = stride
    hind = -stride if not run else stride
    key_pose(
        rig,
        frame,
        {
            "spine": (3.0 * secondary if run else 1.5 * secondary, 0.0, 2.0 * stride),
            "chest": (-2.0 * secondary, 0.0, -2.0 * stride),
            "neck": (-4.0 * secondary, 0.0, 2.0 * stride),
            "head": (3.0 * secondary, 0.0, -2.0 * stride),
            "tail": (0.0, 0.0, -16.0 * stride),
            "tail.001": (0.0, 0.0, 22.0 * stride),
            "leg_front.L": (stride_degrees * fore, 0.0, 0.0),
            "leg_front.R": (-stride_degrees * fore, 0.0, 0.0),
            "leg_back.L": (stride_degrees * hind, 0.0, 0.0),
            "leg_back.R": (-stride_degrees * hind, 0.0, 0.0),
            "shin_front.L": (-22.0 * fore, 0.0, 0.0),
            "shin_front.R": (22.0 * fore, 0.0, 0.0),
            "shin_back.L": (-24.0 * hind, 0.0, 0.0),
            "shin_back.R": (24.0 * hind, 0.0, 0.0),
        },
        {"root": (0.0, 0.0, lift_m * abs(secondary))},
    )


def create_walk(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, WALK, 25)
    for frame in (1, 7, 13, 19, 25):
        gait_pose(rig, frame, 24, 24.0, 0.025, False)
    return finish_action(action, "locomotion", True)


def create_run(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, RUN, 17)
    for frame in (1, 5, 9, 13, 17):
        gait_pose(rig, frame, 16, 38.0, 0.055, True)
    return finish_action(action, "locomotion", True)


def create_jump(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, JUMP, 17)
    key_pose(rig, 1)
    key_pose(
        rig,
        4,
        {
            "spine": (12.0, 0.0, 0.0),
            "neck": (-10.0, 0.0, 0.0),
            "leg_front.L": (-18.0, 0.0, 0.0),
            "leg_front.R": (-18.0, 0.0, 0.0),
            "leg_back.L": (20.0, 0.0, 0.0),
            "leg_back.R": (20.0, 0.0, 0.0),
            "shin_front.L": (32.0, 0.0, 0.0),
            "shin_front.R": (32.0, 0.0, 0.0),
            "shin_back.L": (-34.0, 0.0, 0.0),
            "shin_back.R": (-34.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.05, -0.06)},
    )
    key_pose(
        rig,
        9,
        {
            "spine": (-8.0, 0.0, 0.0),
            "neck": (12.0, 0.0, 0.0),
            "head": (-8.0, 0.0, 0.0),
            "leg_front.L": (26.0, 0.0, 0.0),
            "leg_front.R": (26.0, 0.0, 0.0),
            "leg_back.L": (-30.0, 0.0, 0.0),
            "leg_back.R": (-30.0, 0.0, 0.0),
            "shin_front.L": (-38.0, 0.0, 0.0),
            "shin_front.R": (-38.0, 0.0, 0.0),
            "shin_back.L": (42.0, 0.0, 0.0),
            "shin_back.R": (42.0, 0.0, 0.0),
            "tail": (0.0, 0.0, -24.0),
        },
        {"root": (0.0, -0.10, 0.24)},
    )
    key_pose(
        rig,
        13,
        {
            "spine": (4.0, 0.0, 0.0),
            "leg_front.L": (-12.0, 0.0, 0.0),
            "leg_front.R": (-12.0, 0.0, 0.0),
            "leg_back.L": (14.0, 0.0, 0.0),
            "leg_back.R": (14.0, 0.0, 0.0),
        },
        {"root": (0.0, -0.02, 0.10)},
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
            "spine": (14.0, 0.0, 0.0),
            "neck": (-14.0, 0.0, 0.0),
            "leg_front.L": (-22.0, 0.0, 0.0),
            "leg_front.R": (-22.0, 0.0, 0.0),
            "leg_back.L": (24.0, 0.0, 0.0),
            "leg_back.R": (24.0, 0.0, 0.0),
            "shin_front.L": (28.0, 0.0, 0.0),
            "shin_front.R": (28.0, 0.0, 0.0),
            "shin_back.L": (-30.0, 0.0, 0.0),
            "shin_back.R": (-30.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.04, -0.10)},
    )
    key_pose(
        rig,
        8,
        {
            "spine": (-5.0, 0.0, 0.0),
            "neck": (6.0, 0.0, 0.0),
        },
        {"root": (0.0, -0.015, 0.025)},
    )
    key_pose(rig, 13)
    return finish_action(action, "landing", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        WALK: create_walk(rig),
        RUN: create_run(rig),
        JUMP: create_jump(rig),
        LAND: create_land(rig),
    }


def main() -> None:
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.78)
    rig = build_rig()
    character = join_and_skin(
        ASSET_NAME,
        ASSET_KEY,
        "practice",
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
            "leg_front.L",
            "leg_front.R",
            "leg_back.L",
            "leg_back.R",
            "shin_front.L",
            "shin_back.R",
        ),
        minimum_triangles=3500,
        maximum_triangles=7500,
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
        target=(0.0, -0.05, 0.72),
        camera_location=(2.05, -3.35, 1.65),
        floor_size=6.0,
        poses=(
            (WALK, 7, "A_practice_quadruped_walk_pose.png"),
            (RUN, 5, "A_practice_quadruped_run_pose.png"),
            (JUMP, 9, "A_practice_quadruped_jump_pose.png"),
            (LAND, 4, "A_practice_quadruped_land_pose.png"),
        ),
        key_color=(0.78, 0.68, 1.0),
    )
    print(
        "PRACTICE_QUADRUPED_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_quadruped "
        f"animations={len(actions)} shipped=false"
    )
    print(f"PRACTICE_SOURCE={SOURCE_PATH}")
    print(f"PRACTICE_GLB={EXPORT_PATH}")
    print(f"PRACTICE_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
