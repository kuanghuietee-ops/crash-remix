"""Build the original low-poly carnivorous Beach plant for Godot.

The generated asset is original scripted geometry.  It exports one
vertex-painted mesh, a compact bending stem/jaw rig, and six clips matching
the existing safe-closed / lethal-open gameplay cycle.
"""

from __future__ import annotations

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
ASSET_NAME = "SK_plant"
ASSET_KEY = "plant"
RIG_NAME = "RIG_plant"
MATERIAL_NAME = "M_plant_body"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_plant.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/enemies/SK_plant.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_plant.png"

IDLE = "A_plant_idle"
TELEGRAPH = "A_plant_telegraph"
CHOMP = "A_plant_chomp"
RECOVER = "A_plant_recover"
HIT = "A_plant_hit"
DEFEAT = "A_plant_defeat"
ACTION_NAMES = (IDLE, TELEGRAPH, CHOMP, RECOVER, HIT, DEFEAT)

STEM = (0.035, 0.43, 0.095, 1.0)
STEM_LIGHT = (0.11, 0.72, 0.18, 1.0)
LEAF = (0.035, 0.58, 0.12, 1.0)
LEAF_LIGHT = (0.22, 0.86, 0.20, 1.0)
HEAD = (0.72, 0.045, 0.14, 1.0)
HEAD_LIGHT = (0.96, 0.10, 0.20, 1.0)
LIP = (1.0, 0.30, 0.15, 1.0)
MOUTH = (0.075, 0.008, 0.025, 1.0)
TOOTH = (1.0, 0.91, 0.56, 1.0)
EYE = (1.0, 0.94, 0.66, 1.0)
PUPIL = (0.008, 0.006, 0.008, 1.0)
SPOT = (1.0, 0.65, 0.04, 1.0)


def build_rig() -> bpy.types.Object:
    return create_rig(
        RIG_NAME,
        [
            ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.12), None),
            ("stem", (0.0, 0.0, 0.12), (0.0, 0.02, 0.60), "root"),
            (
                "stem.001",
                (0.0, 0.02, 0.58),
                (0.0, -0.06, 0.98),
                "stem",
            ),
            (
                "head",
                (0.0, -0.05, 0.94),
                (0.0, -0.22, 1.16),
                "stem.001",
            ),
            (
                "jaw_upper",
                (0.0, -0.18, 1.13),
                (0.0, -0.54, 1.27),
                "head",
            ),
            (
                "jaw_lower",
                (0.0, -0.18, 1.04),
                (0.0, -0.52, 0.94),
                "head",
            ),
            (
                "leaf.L",
                (0.08, 0.0, 0.18),
                (0.62, 0.06, 0.10),
                "root",
            ),
            (
                "leaf.R",
                (-0.08, 0.0, 0.18),
                (-0.62, 0.06, 0.10),
                "root",
            ),
            (
                "leaf_front",
                (0.0, -0.05, 0.16),
                (0.0, -0.68, 0.08),
                "root",
            ),
            (
                "leaf_back",
                (0.0, 0.05, 0.16),
                (0.0, 0.64, 0.08),
                "root",
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
        segments: int = 18,
        rings: int = 10,
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

    sphere("root_bulb", (0.0, 0.0, 0.19), (0.34, 0.31, 0.20), STEM, "root", 24, 12)
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "stem_lower",
            (0.0, 0.0, 0.18),
            (0.0, 0.02, 0.62),
            0.13,
            STEM,
            material,
            "stem",
            16,
        )
    )
    parts.append(
        add_cylinder_between(
            ASSET_KEY,
            "stem_upper",
            (0.0, 0.02, 0.56),
            (0.0, -0.08, 1.01),
            0.115,
            STEM_LIGHT,
            material,
            "stem.001",
            16,
        )
    )
    for index, (z_position, radius) in enumerate(
        ((0.38, 0.145), (0.60, 0.13), (0.82, 0.12))
    ):
        sphere(
            f"stem_node_{index}",
            (0.0, -0.02 * index, z_position),
            (radius, radius, radius * 0.72),
            LEAF_LIGHT if index % 2 == 0 else STEM,
            "stem" if index == 0 else "stem.001",
            12,
            8,
        )

    leaf_specs = (
        ("left", (0.38, 0.03, 0.12), (0.46, 0.18, 0.055), "leaf.L", 0.10),
        ("right", (-0.38, 0.03, 0.12), (0.46, 0.18, 0.055), "leaf.R", -0.10),
        ("front", (0.0, -0.40, 0.10), (0.20, 0.48, 0.052), "leaf_front", 0.0),
        ("back", (0.0, 0.38, 0.10), (0.20, 0.44, 0.052), "leaf_back", 0.0),
    )
    for index, (name, location, scale, bone, yaw) in enumerate(leaf_specs):
        sphere(
            f"leaf_{name}",
            location,
            scale,
            LEAF_LIGHT if index % 2 == 0 else LEAF,
            bone,
            18,
            8,
            (0.0, 0.0, yaw),
        )
        sphere(
            f"leaf_mark_{name}",
            (
                location[0],
                location[1] - 0.015,
                location[2] + 0.045,
            ),
            (scale[0] * 0.55, scale[1] * 0.55, 0.018),
            STEM,
            bone,
            12,
            6,
            (0.0, 0.0, yaw),
        )

    sphere(
        "upper_head",
        (0.0, -0.24, 1.17),
        (0.48, 0.41, 0.31),
        HEAD_LIGHT,
        "jaw_upper",
        24,
        12,
    )
    sphere(
        "lower_head",
        (0.0, -0.27, 0.99),
        (0.44, 0.37, 0.25),
        HEAD,
        "jaw_lower",
        22,
        11,
    )
    sphere(
        "upper_mouth",
        (0.0, -0.575, 1.075),
        (0.35, 0.075, 0.13),
        MOUTH,
        "jaw_upper",
        18,
        8,
    )
    sphere(
        "lower_mouth",
        (0.0, -0.575, 1.00),
        (0.33, 0.072, 0.10),
        MOUTH,
        "jaw_lower",
        18,
        8,
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "upper_lip",
            (0.0, -0.645, 1.13),
            (0.70, 0.055, 0.085),
            LIP,
            material,
            "jaw_upper",
            bevel=0.025,
        )
    )
    parts.append(
        add_rounded_box(
            ASSET_KEY,
            "lower_lip",
            (0.0, -0.645, 1.00),
            (0.64, 0.055, 0.075),
            LIP,
            material,
            "jaw_lower",
            bevel=0.025,
        )
    )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        sphere(
            f"eye_{side}",
            (0.20 * sign, -0.555, 1.30),
            (0.11, 0.075, 0.12),
            EYE,
            "jaw_upper",
            14,
            8,
        )
        sphere(
            f"pupil_{side}",
            (0.20 * sign, -0.62, 1.30),
            (0.045, 0.025, 0.064),
            PUPIL,
            "jaw_upper",
            10,
            6,
        )

    for index, (x_position, z_position) in enumerate(
        (
            (-0.30, 1.25),
            (0.0, 1.41),
            (0.30, 1.23),
            (-0.25, 0.94),
            (0.23, 0.91),
        )
    ):
        sphere(
            f"head_spot_{index}",
            (x_position, -0.535, z_position),
            (0.075, 0.035, 0.055),
            SPOT,
            "jaw_upper" if z_position > 1.1 else "jaw_lower",
            12,
            6,
        )

    for row, (bone, z_start, z_end, direction) in enumerate(
        (
            ("jaw_upper", 1.105, 1.015, -1.0),
            ("jaw_lower", 1.025, 1.115, 1.0),
        )
    ):
        for tooth_index, x_position in enumerate(
            (-0.27, -0.135, 0.0, 0.135, 0.27)
        ):
            y_position = -0.675 + abs(x_position) * 0.025
            parts.append(
                add_cone_between(
                    ASSET_KEY,
                    f"tooth_{row}_{tooth_index}",
                    (x_position, y_position, z_start),
                    (
                        x_position,
                        y_position - 0.012,
                        z_end + direction * abs(x_position) * 0.025,
                    ),
                    0.033,
                    0.006,
                    TOOTH,
                    material,
                    bone,
                    9,
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
            "stem": (0.0, 4.0, 3.0),
            "stem.001": (0.0, -7.0, -4.0),
            "head": (2.0, 0.0, 2.0),
            "leaf.L": (0.0, 0.0, 8.0),
            "leaf.R": (0.0, 0.0, -8.0),
            "leaf_front": (5.0, 0.0, 0.0),
            "leaf_back": (-5.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.0, 0.012)},
    )
    key_pose(
        rig,
        17,
        {
            "stem": (0.0, -4.0, -3.0),
            "stem.001": (0.0, 7.0, 4.0),
            "head": (-2.0, 0.0, -2.0),
            "jaw_upper": (-2.0, 0.0, 0.0),
            "jaw_lower": (3.0, 0.0, 0.0),
            "leaf.L": (0.0, 0.0, -8.0),
            "leaf.R": (0.0, 0.0, 8.0),
        },
        {"root": (0.0, 0.0, 0.022)},
    )
    key_pose(
        rig,
        25,
        {
            "stem": (0.0, 3.0, 2.0),
            "stem.001": (0.0, -5.0, -3.0),
            "head": (1.0, 0.0, 1.0),
            "leaf_front": (-4.0, 0.0, 0.0),
            "leaf_back": (4.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.0, 0.008)},
    )
    key_pose(rig, 33)
    return finish_action(action, "idle", True)


def create_telegraph(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, TELEGRAPH, 13)
    key_pose(rig, 1)
    key_pose(
        rig,
        5,
        {
            "stem": (12.0, 0.0, 0.0),
            "stem.001": (-18.0, 0.0, 0.0),
            "head": (14.0, 0.0, 0.0),
            "jaw_upper": (-16.0, 0.0, 0.0),
            "jaw_lower": (22.0, 0.0, 0.0),
            "leaf.L": (0.0, 0.0, 16.0),
            "leaf.R": (0.0, 0.0, -16.0),
        },
        {"root": (0.0, 0.05, -0.04)},
    )
    key_pose(
        rig,
        9,
        {
            "stem": (8.0, 0.0, 4.0),
            "stem.001": (-14.0, 0.0, -6.0),
            "head": (10.0, 0.0, 5.0),
            "jaw_upper": (-23.0, 0.0, 0.0),
            "jaw_lower": (30.0, 0.0, 0.0),
            "leaf_front": (12.0, 0.0, 0.0),
            "leaf_back": (-12.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.04, -0.025)},
    )
    key_pose(
        rig,
        13,
        {
            "stem": (10.0, 0.0, 0.0),
            "stem.001": (-16.0, 0.0, 0.0),
            "head": (12.0, 0.0, 0.0),
            "jaw_upper": (-18.0, 0.0, 0.0),
            "jaw_lower": (25.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.05, -0.035)},
    )
    return finish_action(action, "telegraph", False)


def create_chomp(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, CHOMP, 15)
    key_pose(
        rig,
        1,
        {
            "stem": (10.0, 0.0, 0.0),
            "stem.001": (-16.0, 0.0, 0.0),
            "jaw_upper": (-18.0, 0.0, 0.0),
            "jaw_lower": (25.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.05, -0.035)},
    )
    key_pose(
        rig,
        4,
        {
            "stem": (-6.0, 0.0, 0.0),
            "stem.001": (16.0, 0.0, 0.0),
            "head": (-12.0, 0.0, 0.0),
            "jaw_upper": (-34.0, 0.0, 0.0),
            "jaw_lower": (46.0, 0.0, 0.0),
            "leaf.L": (0.0, 0.0, -18.0),
            "leaf.R": (0.0, 0.0, 18.0),
        },
        {"root": (0.0, -0.08, 0.07)},
    )
    key_pose(
        rig,
        7,
        {
            "stem": (-10.0, 0.0, 0.0),
            "stem.001": (22.0, 0.0, 0.0),
            "head": (-18.0, 0.0, 0.0),
            "jaw_upper": (4.0, 0.0, 0.0),
            "jaw_lower": (-5.0, 0.0, 0.0),
            "leaf_front": (-14.0, 0.0, 0.0),
            "leaf_back": (14.0, 0.0, 0.0),
        },
        {"root": (0.0, -0.14, 0.09)},
    )
    key_pose(
        rig,
        11,
        {
            "stem": (5.0, 0.0, 0.0),
            "stem.001": (-9.0, 0.0, 0.0),
            "head": (7.0, 0.0, 0.0),
            "jaw_upper": (-13.0, 0.0, 0.0),
            "jaw_lower": (18.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.025, 0.01)},
    )
    key_pose(rig, 15)
    return finish_action(action, "attack", False)


def create_recover(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, RECOVER, 17)
    key_pose(
        rig,
        1,
        {
            "stem": (-8.0, 0.0, 0.0),
            "stem.001": (12.0, 0.0, 0.0),
            "head": (-8.0, 0.0, 0.0),
        },
    )
    key_pose(
        rig,
        6,
        {
            "stem": (8.0, 0.0, 4.0),
            "stem.001": (-12.0, 0.0, -7.0),
            "head": (8.0, 0.0, 5.0),
            "jaw_upper": (-8.0, 0.0, 0.0),
            "jaw_lower": (10.0, 0.0, 0.0),
        },
        {"root": (0.0, 0.02, 0.015)},
    )
    key_pose(
        rig,
        11,
        {
            "stem": (-4.0, 0.0, -3.0),
            "stem.001": (7.0, 0.0, 5.0),
            "head": (-4.0, 0.0, -4.0),
        },
    )
    key_pose(rig, 17)
    return finish_action(action, "recovery", False)


def create_hit(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, HIT, 9)
    key_pose(rig, 1)
    key_pose(
        rig,
        3,
        {
            "stem": (0.0, 0.0, 24.0),
            "stem.001": (0.0, 0.0, 32.0),
            "head": (-16.0, 0.0, 20.0),
            "jaw_upper": (-20.0, 0.0, 0.0),
            "jaw_lower": (28.0, 0.0, 0.0),
            "leaf.L": (0.0, 0.0, 28.0),
            "leaf.R": (0.0, 0.0, -28.0),
        },
        {"root": (0.07, 0.0, 0.04)},
    )
    key_pose(
        rig,
        6,
        {
            "stem": (0.0, 0.0, -10.0),
            "stem.001": (0.0, 0.0, -14.0),
            "head": (8.0, 0.0, -8.0),
        },
        {"root": (-0.02, 0.0, 0.01)},
    )
    key_pose(rig, 9)
    return finish_action(action, "reaction", False)


def create_defeat(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, DEFEAT, 21)
    key_pose(rig, 1)
    key_pose(
        rig,
        7,
        {
            "stem": (0.0, 0.0, 32.0),
            "stem.001": (0.0, 0.0, 48.0),
            "head": (18.0, 0.0, 30.0),
            "jaw_upper": (-24.0, 0.0, 0.0),
            "jaw_lower": (34.0, 0.0, 0.0),
            "leaf.L": (0.0, 0.0, 38.0),
            "leaf.R": (0.0, 0.0, -38.0),
        },
        {"root": (0.08, 0.0, 0.12)},
    )
    final_pose = {
        "stem": (0.0, 0.0, 62.0),
        "stem.001": (0.0, 0.0, 82.0),
        "head": (38.0, 0.0, 28.0),
        "jaw_upper": (-32.0, 0.0, 0.0),
        "jaw_lower": (46.0, 0.0, 0.0),
        "leaf.L": (0.0, 0.0, 54.0),
        "leaf.R": (0.0, 0.0, -54.0),
        "leaf_front": (38.0, 0.0, 0.0),
        "leaf_back": (-38.0, 0.0, 0.0),
    }
    key_pose(rig, 15, final_pose, {"root": (0.12, 0.03, -0.02)})
    key_pose(rig, 21, final_pose, {"root": (0.12, 0.03, -0.03)})
    return finish_action(action, "defeat", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        TELEGRAPH: create_telegraph(rig),
        CHOMP: create_chomp(rig),
        RECOVER: create_recover(rig),
        HIT: create_hit(rig),
        DEFEAT: create_defeat(rig),
    }


def main() -> None:
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(MATERIAL_NAME, 0.76)
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
            "stem",
            "stem.001",
            "head",
            "jaw_upper",
            "jaw_lower",
            "leaf.L",
            "leaf.R",
        ),
        minimum_triangles=3000,
        maximum_triangles=6000,
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
        target=(0.0, -0.08, 0.72),
        camera_location=(1.85, -3.15, 1.65),
        floor_size=5.0,
        poses=(
            (CHOMP, 4, "A_plant_chomp_pose.png"),
            (TELEGRAPH, 9, "A_plant_telegraph_pose.png"),
            (HIT, 3, "A_plant_hit_pose.png"),
            (DEFEAT, 18, "A_plant_defeat_pose.png"),
        ),
        key_color=(1.0, 0.42, 0.24),
    )
    print(
        "PLANT_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_plant "
        f"animations={len(actions)}"
    )
    print(f"PLANT_SOURCE={SOURCE_PATH}")
    print(f"PLANT_GLB={EXPORT_PATH}")
    print(f"PLANT_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
