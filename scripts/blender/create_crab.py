"""Build the original low-poly Beach crab enemy for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_crab.py

The generated asset is original geometry authored entirely by this script.
It exports one vertex-painted skinned mesh, one compact custom skeleton and
five gameplay clips. Editable source and previews stay under build/.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_NAME = "SK_crab"
RIG_NAME = "RIG_crab"
MATERIAL_NAME = "M_crab_body"
COLOR_ATTRIBUTE = "COLOR_0"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_crab.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/enemies/SK_crab.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_crab.png"

IDLE = "A_crab_idle"
WALK = "A_crab_walk"
ATTACK = "A_crab_attack"
HIT = "A_crab_hit"
DEFEAT = "A_crab_defeat"
ACTION_NAMES = (IDLE, WALK, ATTACK, HIT, DEFEAT)
FPS = 24

Color = tuple[float, float, float, float]

SHELL: Color = (0.73, 0.075, 0.025, 1.0)
SHELL_LIGHT: Color = (1.0, 0.24, 0.045, 1.0)
SHELL_DARK: Color = (0.32, 0.025, 0.018, 1.0)
BELLY: Color = (1.0, 0.48, 0.12, 1.0)
CLAW: Color = (0.93, 0.11, 0.025, 1.0)
PINCER: Color = (1.0, 0.34, 0.055, 1.0)
LEG: Color = (0.46, 0.04, 0.025, 1.0)
LEG_TIP: Color = (0.93, 0.17, 0.035, 1.0)
EYE: Color = (1.0, 0.94, 0.62, 1.0)
PUPIL: Color = (0.018, 0.012, 0.01, 1.0)
MOUTH: Color = (0.18, 0.012, 0.012, 1.0)
TOOTH: Color = (1.0, 0.86, 0.55, 1.0)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
        bpy.data.actions,
    ):
        for datablock in list(datablocks):
            datablocks.remove(datablock)


def create_material() -> bpy.types.Material:
    material = bpy.data.materials.new(MATERIAL_NAME)
    material.use_nodes = True
    material.use_backface_culling = True
    material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    vertex_color = nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = COLOR_ATTRIBUTE
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Roughness"].default_value = 0.82
    shader.inputs["Metallic"].default_value = 0.0
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(vertex_color.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def paint_mesh(mesh: bpy.types.Mesh, color: Color) -> None:
    attribute = mesh.color_attributes.get(COLOR_ATTRIBUTE)
    if attribute is None:
        attribute = mesh.color_attributes.new(
            name=COLOR_ATTRIBUTE,
            type="BYTE_COLOR",
            domain="CORNER",
        )
    for value in attribute.data:
        value.color = color


def finish_part(
    part: bpy.types.Object,
    name: str,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    smooth: bool = True,
) -> bpy.types.Object:
    part.name = f"_crab_part_{name}"
    bpy.context.view_layer.objects.active = part
    part.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    part.data.materials.append(material)
    paint_mesh(part.data, color)
    for polygon in part.data.polygons:
        polygon.use_smooth = smooth
    group = part.vertex_groups.new(name=bone)
    group.add(list(range(len(part.data.vertices))), 1.0, "REPLACE")
    return part


def add_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    color: Color,
    material: bpy.types.Material,
    bone: str,
    segments: int,
    rings: int,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
    )
    part = bpy.context.active_object
    part.scale = scale
    return finish_part(part, name, color, material, bone)


def add_cylinder_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    vertices: int = 12,
) -> bpy.types.Object:
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        end_fill_type="NGON",
        location=(start_vector + end_vector) * 0.5,
    )
    part = bpy.context.active_object
    part.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return finish_part(part, name, color, material, bone)


def add_cone_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    base_radius: float,
    tip_radius: float,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    vertices: int = 12,
) -> bpy.types.Object:
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=base_radius,
        radius2=tip_radius,
        depth=direction.length,
        end_fill_type="NGON",
        location=(start_vector + end_vector) * 0.5,
    )
    part = bpy.context.active_object
    part.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return finish_part(part, name, color, material, bone)


def add_rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    color: Color,
    material: bpy.types.Material,
    bone: str,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=location,
        rotation=rotation,
    )
    part = bpy.context.active_object
    part.dimensions = dimensions
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bevel > 0.0:
        modifier = part.modifiers.new(name="_soft_edges", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = part
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish_part(part, name, color, material, bone, False)


def create_rig() -> bpy.types.Object:
    armature = bpy.data.armatures.new(f"{RIG_NAME}_skeleton")
    rig = bpy.data.objects.new(RIG_NAME, armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(
        name: str,
        head: tuple[float, float, float],
        tail: tuple[float, float, float],
        parent: str | None = None,
    ) -> None:
        edit_bone = armature.edit_bones.new(name)
        edit_bone.head = head
        edit_bone.tail = tail
        edit_bone.use_deform = True
        if parent is not None:
            edit_bone.parent = armature.edit_bones[parent]

    bone("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.12))
    bone("body", (0.0, 0.0, 0.12), (0.0, 0.0, 0.63), "root")
    bone("eye.L", (0.16, -0.08, 0.56), (0.16, -0.12, 0.82), "body")
    bone("eye.R", (-0.16, -0.08, 0.56), (-0.16, -0.12, 0.82), "body")
    bone("claw.L", (0.31, -0.02, 0.48), (0.58, -0.08, 0.55), "body")
    bone("claw.R", (-0.31, -0.02, 0.48), (-0.58, -0.08, 0.55), "body")
    bone(
        "pincer_upper.L",
        (0.58, -0.08, 0.55),
        (0.73, -0.12, 0.66),
        "claw.L",
    )
    bone(
        "pincer_lower.L",
        (0.58, -0.08, 0.53),
        (0.73, -0.12, 0.43),
        "claw.L",
    )
    bone(
        "pincer_upper.R",
        (-0.58, -0.08, 0.55),
        (-0.73, -0.12, 0.66),
        "claw.R",
    )
    bone(
        "pincer_lower.R",
        (-0.58, -0.08, 0.53),
        (-0.73, -0.12, 0.43),
        "claw.R",
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        for label, y_position in (
            ("front", -0.22),
            ("mid", 0.0),
            ("back", 0.22),
        ):
            bone(
                f"leg_{label}.{side}",
                (0.28 * sign, y_position, 0.37),
                (0.59 * sign, y_position, 0.08),
                "body",
            )

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig["original_asset"] = True
    rig["forward_axis"] = "-Y"
    rig["unit_m"] = 1.0
    return rig


def build_parts(material: bpy.types.Material) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    parts.append(
        add_sphere(
            "shell",
            (0.0, 0.04, 0.43),
            (0.46, 0.31, 0.27),
            SHELL,
            material,
            "body",
            32,
            16,
        )
    )
    parts.append(
        add_sphere(
            "belly",
            (0.0, -0.225, 0.40),
            (0.34, 0.105, 0.19),
            BELLY,
            material,
            "body",
            24,
            12,
        )
    )
    parts.append(
        add_sphere(
            "brow",
            (0.0, -0.235, 0.58),
            (0.31, 0.07, 0.10),
            SHELL_LIGHT,
            material,
            "body",
            18,
            8,
        )
    )
    for index, (x_position, z_position, scale) in enumerate(
        (
            (-0.27, 0.55, (0.075, 0.03, 0.045)),
            (0.27, 0.55, (0.075, 0.03, 0.045)),
            (-0.19, 0.67, (0.055, 0.025, 0.035)),
            (0.19, 0.67, (0.055, 0.025, 0.035)),
        )
    ):
        parts.append(
            add_sphere(
                f"shell_mark_{index}",
                (x_position, -0.225, z_position),
                scale,
                SHELL_DARK,
                material,
                "body",
                10,
                6,
            )
        )
    parts.append(
        add_rounded_box(
            "mouth",
            (0.0, -0.335, 0.36),
            (0.23, 0.025, 0.055),
            MOUTH,
            material,
            "body",
            bevel=0.015,
        )
    )
    for tooth_index, x_position in enumerate((-0.07, 0.0, 0.07)):
        parts.append(
            add_cone_between(
                f"tooth_{tooth_index}",
                (x_position, -0.355, 0.39),
                (x_position, -0.36, 0.35),
                0.022,
                0.006,
                TOOTH,
                material,
                "body",
                8,
            )
        )

    for side, sign in (("L", 1.0), ("R", -1.0)):
        eye_bone = f"eye.{side}"
        parts.append(
            add_cylinder_between(
                f"eye_stalk_{side}",
                (0.16 * sign, -0.08, 0.57),
                (0.16 * sign, -0.11, 0.73),
                0.055,
                SHELL_LIGHT,
                material,
                eye_bone,
                12,
            )
        )
        parts.append(
            add_sphere(
                f"eye_{side}",
                (0.16 * sign, -0.13, 0.76),
                (0.105, 0.09, 0.125),
                EYE,
                material,
                eye_bone,
                16,
                10,
            )
        )
        parts.append(
            add_sphere(
                f"pupil_{side}",
                (0.16 * sign, -0.21, 0.76),
                (0.042, 0.025, 0.066),
                PUPIL,
                material,
                eye_bone,
                12,
                8,
            )
        )

        claw_bone = f"claw.{side}"
        parts.append(
            add_cylinder_between(
                f"claw_arm_{side}",
                (0.31 * sign, -0.02, 0.46),
                (0.51 * sign, -0.07, 0.52),
                0.065,
                LEG,
                material,
                claw_bone,
                12,
            )
        )
        parts.append(
            add_sphere(
                f"claw_palm_{side}",
                (0.57 * sign, -0.09, 0.54),
                (0.16, 0.13, 0.15),
                CLAW,
                material,
                claw_bone,
                18,
                10,
            )
        )
        parts.append(
            add_cone_between(
                f"pincer_upper_{side}",
                (0.60 * sign, -0.11, 0.57),
                (0.74 * sign, -0.14, 0.68),
                0.09,
                0.018,
                PINCER,
                material,
                f"pincer_upper.{side}",
                12,
            )
        )
        parts.append(
            add_cone_between(
                f"pincer_lower_{side}",
                (0.60 * sign, -0.11, 0.51),
                (0.74 * sign, -0.14, 0.42),
                0.085,
                0.018,
                SHELL_LIGHT,
                material,
                f"pincer_lower.{side}",
                12,
            )
        )

        for leg_index, (label, y_position) in enumerate(
            (
                ("front", -0.22),
                ("mid", 0.0),
                ("back", 0.22),
            )
        ):
            leg_bone = f"leg_{label}.{side}"
            hip = (0.28 * sign, y_position, 0.35)
            knee = (
                (0.45 + leg_index * 0.018) * sign,
                y_position - 0.015,
                0.20,
            )
            foot = (
                (0.61 + leg_index * 0.012) * sign,
                y_position - 0.035,
                0.075,
            )
            parts.append(
                add_cylinder_between(
                    f"leg_upper_{label}_{side}",
                    hip,
                    knee,
                    0.045,
                    LEG,
                    material,
                    leg_bone,
                    12,
                )
            )
            parts.append(
                add_cylinder_between(
                    f"leg_lower_{label}_{side}",
                    knee,
                    foot,
                    0.038,
                    LEG_TIP,
                    material,
                    leg_bone,
                    12,
                )
            )
            parts.append(
                add_sphere(
                    f"leg_joint_{label}_{side}",
                    knee,
                    (0.062, 0.055, 0.062),
                    SHELL_LIGHT,
                    material,
                    leg_bone,
                    10,
                    6,
                )
            )
            parts.append(
                add_sphere(
                    f"foot_{label}_{side}",
                    foot,
                    (0.085, 0.07, 0.042),
                    LEG_TIP,
                    material,
                    leg_bone,
                    10,
                    6,
                )
            )
    return parts


def join_and_skin(
    parts: list[bpy.types.Object],
    material: bpy.types.Material,
    rig: bpy.types.Object,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    character = bpy.context.active_object
    character.name = ASSET_NAME
    character.data.name = f"{ASSET_NAME}_mesh"
    for polygon in character.data.polygons:
        polygon.material_index = 0
    character.data.materials.clear()
    character.data.materials.append(material)

    bpy.context.view_layer.objects.active = character
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(66.0),
        island_margin=0.012,
        area_weight=0.0,
        correct_aspect=True,
        scale_to_bounds=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    modifier = character.modifiers.new(name="CrabDeform", type="ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    character.parent = rig
    character.matrix_parent_inverse = rig.matrix_world.inverted()
    character["asset_role"] = "enemy"
    character["original_asset"] = True
    character["material_slots"] = 1
    character["actions"] = list(ACTION_NAMES)
    character.data.validate(verbose=True)
    character.data.update()
    return character


def begin_action(
    rig: bpy.types.Object,
    name: str,
    last_frame: int,
) -> bpy.types.Action:
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = last_frame
    scene.render.fps = FPS
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    return action


def key_pose(
    rig: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]] | None = None,
    locations: dict[str, tuple[float, float, float]] | None = None,
) -> None:
    rotations = rotations or {}
    locations = locations or {}
    for pose_bone in rig.pose.bones:
        degrees = rotations.get(pose_bone.name, (0.0, 0.0, 0.0))
        pose_bone.rotation_euler = tuple(
            math.radians(value) for value in degrees
        )
        pose_bone.location = locations.get(
            pose_bone.name,
            (0.0, 0.0, 0.0),
        )
        pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame)
        pose_bone.keyframe_insert(data_path="location", frame=frame)


def finish_action(
    action: bpy.types.Action,
    role: str,
    looping: bool,
) -> bpy.types.Action:
    for curve in action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "BEZIER"
            keyframe.handle_left_type = "AUTO_CLAMPED"
            keyframe.handle_right_type = "AUTO_CLAMPED"
    action["looping"] = looping
    action["clip_role"] = role
    return action


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, IDLE, 25)
    key_pose(rig, 1)
    key_pose(
        rig,
        7,
        {
            "body": (0.0, 0.0, 2.0),
            "eye.L": (2.0, 0.0, -2.0),
            "eye.R": (-2.0, 0.0, -2.0),
            "claw.L": (0.0, 0.0, -4.0),
            "claw.R": (0.0, 0.0, 4.0),
        },
        {"root": (0.0, 0.0, 0.012)},
    )
    key_pose(
        rig,
        13,
        {
            "body": (0.0, 0.0, -2.0),
            "eye.L": (-2.0, 0.0, 2.0),
            "eye.R": (2.0, 0.0, 2.0),
            "claw.L": (0.0, 0.0, 3.0),
            "claw.R": (0.0, 0.0, -3.0),
        },
        {"root": (0.0, 0.0, 0.024)},
    )
    key_pose(
        rig,
        19,
        {
            "body": (0.0, 0.0, 1.0),
            "claw.L": (0.0, 0.0, -2.0),
            "claw.R": (0.0, 0.0, 2.0),
        },
        {"root": (0.0, 0.0, 0.010)},
    )
    key_pose(rig, 25)
    return finish_action(action, "idle", True)


def create_walk(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, WALK, 25)
    leg_names = (
        "leg_front.L",
        "leg_mid.L",
        "leg_back.L",
        "leg_front.R",
        "leg_mid.R",
        "leg_back.R",
    )
    for frame in (1, 7, 13, 19, 25):
        phase = math.tau * (frame - 1) / 24.0
        stride = math.sin(phase)
        double_step = math.cos(phase * 2.0)
        rotations: dict[str, tuple[float, float, float]] = {
            "body": (0.0, 0.0, 4.0 * stride),
            "eye.L": (2.5 * stride, 0.0, -2.0 * stride),
            "eye.R": (-2.5 * stride, 0.0, -2.0 * stride),
            "claw.L": (0.0, 0.0, -6.0 - 3.0 * stride),
            "claw.R": (0.0, 0.0, 6.0 - 3.0 * stride),
        }
        for index, bone_name in enumerate(leg_names):
            leg_phase = stride if index % 2 == 0 else -stride
            side_sign = 1.0 if bone_name.endswith(".L") else -1.0
            rotations[bone_name] = (
                9.0 * leg_phase,
                0.0,
                13.0 * leg_phase * side_sign,
            )
        key_pose(
            rig,
            frame,
            rotations,
            {"root": (0.0, 0.0, 0.016 * (1.0 - double_step))},
        )
    return finish_action(action, "locomotion", True)


def create_attack(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, ATTACK, 15)
    key_pose(rig, 1)
    key_pose(
        rig,
        4,
        {
            "body": (8.0, 0.0, 0.0),
            "claw.L": (0.0, 0.0, 24.0),
            "claw.R": (0.0, 0.0, -24.0),
            "pincer_upper.L": (0.0, 0.0, 18.0),
            "pincer_lower.L": (0.0, 0.0, -18.0),
            "pincer_upper.R": (0.0, 0.0, -18.0),
            "pincer_lower.R": (0.0, 0.0, 18.0),
        },
        {"root": (0.0, 0.025, 0.02)},
    )
    key_pose(
        rig,
        8,
        {
            "body": (-13.0, 0.0, 0.0),
            "eye.L": (-10.0, 0.0, 0.0),
            "eye.R": (-10.0, 0.0, 0.0),
            "claw.L": (0.0, 0.0, -38.0),
            "claw.R": (0.0, 0.0, 38.0),
            "pincer_upper.L": (0.0, 0.0, -20.0),
            "pincer_lower.L": (0.0, 0.0, 20.0),
            "pincer_upper.R": (0.0, 0.0, 20.0),
            "pincer_lower.R": (0.0, 0.0, -20.0),
        },
        {"root": (0.0, -0.045, 0.045)},
    )
    key_pose(
        rig,
        11,
        {
            "body": (-5.0, 0.0, 0.0),
            "claw.L": (0.0, 0.0, -16.0),
            "claw.R": (0.0, 0.0, 16.0),
        },
        {"root": (0.0, -0.018, 0.015)},
    )
    key_pose(rig, 15)
    return finish_action(action, "attack", False)


def create_hit(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, HIT, 10)
    key_pose(rig, 1)
    key_pose(
        rig,
        3,
        {
            "body": (0.0, 0.0, -22.0),
            "eye.L": (16.0, 0.0, -8.0),
            "eye.R": (-16.0, 0.0, -8.0),
            "claw.L": (0.0, 0.0, 34.0),
            "claw.R": (0.0, 0.0, -34.0),
        },
        {"root": (0.075, 0.0, 0.055)},
    )
    key_pose(
        rig,
        6,
        {
            "body": (0.0, 0.0, 10.0),
            "claw.L": (0.0, 0.0, -18.0),
            "claw.R": (0.0, 0.0, 18.0),
        },
        {"root": (-0.025, 0.0, 0.018)},
    )
    key_pose(rig, 10)
    return finish_action(action, "reaction", False)


def create_defeat(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, DEFEAT, 19)
    key_pose(rig, 1)
    key_pose(
        rig,
        5,
        {
            "body": (36.0, 0.0, 20.0),
            "eye.L": (24.0, 0.0, -12.0),
            "eye.R": (-24.0, 0.0, 12.0),
            "claw.L": (0.0, 0.0, 46.0),
            "claw.R": (0.0, 0.0, -46.0),
        },
        {"root": (0.0, 0.0, 0.18)},
    )
    key_pose(
        rig,
        11,
        {
            "body": (88.0, 0.0, -14.0),
            "eye.L": (30.0, 0.0, 10.0),
            "eye.R": (-30.0, 0.0, -10.0),
            "claw.L": (0.0, 0.0, 58.0),
            "claw.R": (0.0, 0.0, -58.0),
            "leg_front.L": (24.0, 0.0, 22.0),
            "leg_mid.L": (-20.0, 0.0, -18.0),
            "leg_back.L": (18.0, 0.0, 24.0),
            "leg_front.R": (-24.0, 0.0, -22.0),
            "leg_mid.R": (20.0, 0.0, 18.0),
            "leg_back.R": (-18.0, 0.0, -24.0),
        },
        {"root": (0.0, 0.03, 0.07)},
    )
    final_pose = {
        "body": (94.0, 0.0, -6.0),
        "eye.L": (35.0, 0.0, 15.0),
        "eye.R": (-35.0, 0.0, -15.0),
        "claw.L": (0.0, 0.0, 64.0),
        "claw.R": (0.0, 0.0, -64.0),
        "leg_front.L": (28.0, 0.0, 28.0),
        "leg_mid.L": (-24.0, 0.0, -22.0),
        "leg_back.L": (22.0, 0.0, 26.0),
        "leg_front.R": (-28.0, 0.0, -28.0),
        "leg_mid.R": (24.0, 0.0, 22.0),
        "leg_back.R": (-22.0, 0.0, -26.0),
    }
    key_pose(rig, 16, final_pose, {"root": (0.0, 0.05, -0.015)})
    key_pose(rig, 19, final_pose, {"root": (0.0, 0.05, -0.015)})
    return finish_action(action, "defeat", False)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {
        IDLE: create_idle(rig),
        WALK: create_walk(rig),
        ATTACK: create_attack(rig),
        HIT: create_hit(rig),
        DEFEAT: create_defeat(rig),
    }


def triangle_count(character: bpy.types.Object) -> int:
    return sum(
        max(len(polygon.vertices) - 2, 0)
        for polygon in character.data.polygons
    )


def validate_asset(
    character: bpy.types.Object,
    rig: bpy.types.Object,
    actions: dict[str, bpy.types.Action],
) -> tuple[int, int, int]:
    vertices = len(character.data.vertices)
    faces = len(character.data.polygons)
    triangles = triangle_count(character)
    if not 3000 <= triangles <= 6000:
        raise RuntimeError(
            f"{ASSET_NAME} has {triangles} triangles; enemy band is 3000-6000"
        )
    if len(character.data.materials) != 1:
        raise RuntimeError("crab must export one material slot")
    if character.data.color_attributes.get(COLOR_ATTRIBUTE) is None:
        raise RuntimeError("crab has no authored vertex colors")
    if not character.data.uv_layers:
        raise RuntimeError("crab has no UV map")
    if not character.vertex_groups:
        raise RuntimeError("crab has no deform weights")
    missing = sorted(set(ACTION_NAMES) - set(actions))
    if missing:
        raise RuntimeError(f"crab animation set is missing {missing}")
    required_bones = {
        "body",
        "eye.L",
        "eye.R",
        "claw.L",
        "claw.R",
        "leg_front.L",
        "leg_front.R",
    }
    missing_bones = required_bones - {bone.name for bone in rig.data.bones}
    if missing_bones:
        raise RuntimeError(f"crab rig is missing {sorted(missing_bones)}")
    return vertices, faces, triangles


def save_source_and_export(
    character: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)

    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.hide_viewport = False
    rig.select_set(True)
    character.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.context.scene.frame_set(1)
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_PATH),
        check_existing=False,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_materials="EXPORT",
        export_colors=True,
        export_attributes=True,
        export_normals=True,
        export_texcoords=True,
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_frame_range=True,
        export_frame_step=1,
        export_force_sampling=True,
        export_animation_mode="ACTIONS",
        export_def_bones=True,
        export_hierarchy_flatten_bones=False,
        export_optimize_animation_size=False,
        export_reset_pose_bones=True,
        export_skins=True,
        export_influence_nb=4,
        export_all_influences=False,
        export_nla_strips=False,
        export_extras=True,
    )


def point_at(subject: bpy.types.Object, target: Vector) -> None:
    subject.rotation_euler = (
        target - subject.location
    ).to_track_quat("-Z", "Y").to_euler()


def create_preview(
    character: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    rig.hide_render = False

    bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.035, 0.055, 0.080, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (1.65, -2.55, 1.2)
    camera_data.lens = 64.0
    point_at(camera, Vector((0.0, 0.0, 0.42)))
    bpy.context.scene.camera = camera

    for name, energy, size, location, color in (
        ("_preview_key", 650.0, 3.0, (-2.0, -2.5, 3.0), (1.0, 0.65, 0.35)),
        ("_preview_fill", 420.0, 2.5, (2.2, -1.0, 2.0), (0.4, 0.7, 1.0)),
        ("_preview_rim", 500.0, 2.0, (-1.0, 2.2, 2.2), (0.5, 0.85, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 0.42)))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.012,
        0.022,
        0.040,
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
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    bpy.context.view_layer.objects.active = character
    for action_name, frame, filename in (
        (WALK, 7, "A_crab_walk_pose.png"),
        (ATTACK, 8, "A_crab_attack_pose.png"),
        (HIT, 3, "A_crab_hit_pose.png"),
        (DEFEAT, 16, "A_crab_defeat_pose.png"),
    ):
        rig.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(PREVIEW_PATH.with_name(filename))
        bpy.ops.render.render(write_still=True)
    rig.animation_data.action = bpy.data.actions[ATTACK]
    scene.frame_set(8)
    scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    material = create_material()
    rig = create_rig()
    character = join_and_skin(build_parts(material), material, rig)
    actions = create_actions(rig)
    vertices, faces, triangles = validate_asset(character, rig, actions)
    save_source_and_export(character, rig)
    create_preview(character, rig)
    print(
        "CRAB_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_crab "
        f"animations={len(actions)}"
    )
    print(f"CRAB_SOURCE={SOURCE_PATH}")
    print(f"CRAB_GLB={EXPORT_PATH}")
    print(f"CRAB_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
