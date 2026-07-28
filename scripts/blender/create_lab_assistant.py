"""Build the original low-poly lab-assistant biped for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_lab_assistant.py

The generated character is original geometry built entirely by this script.
It uses Rigify's basic-human metarig, explicit deform-bone weights, one
vertex-painted material, and one looping walk action. The editable Blender
source and preview stay under build/; the shipping GLB is written to the
enemy budget directory.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_NAME = "SK_lab_assistant"
RIG_NAME = "RIG_lab_assistant"
MATERIAL_NAME = "M_lab_assistant"
WALK_ACTION_NAME = "A_lab_assistant_walk"
COLOR_ATTRIBUTE = "COLOR_0"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_lab_assistant.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/enemies/SK_lab_assistant.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_lab_assistant.png"

WALK_FIRST_FRAME = 1
WALK_LAST_FRAME = 25
WALK_FPS = 24

Color = tuple[float, float, float, float]

SKIN: Color = (0.78, 0.42, 0.25, 1.0)
SKIN_LIGHT: Color = (0.96, 0.66, 0.40, 1.0)
HAIR: Color = (0.025, 0.035, 0.060, 1.0)
HAIR_RIM: Color = (0.085, 0.120, 0.190, 1.0)
COAT: Color = (0.76, 0.88, 0.78, 1.0)
COAT_SHADOW: Color = (0.28, 0.52, 0.50, 1.0)
TROUSERS: Color = (0.10, 0.12, 0.22, 1.0)
GLOVES: Color = (0.44, 0.16, 0.62, 1.0)
SHOES: Color = (0.92, 0.24, 0.055, 1.0)
SHOE_SOLE: Color = (0.16, 0.045, 0.035, 1.0)
GOGGLE_FRAME: Color = (0.82, 0.95, 0.20, 1.0)
GOGGLE_LENS: Color = (0.12, 0.56, 0.67, 1.0)
MOUTH: Color = (0.15, 0.025, 0.035, 1.0)
TEETH: Color = (1.0, 0.88, 0.58, 1.0)
ACCENT: Color = (1.0, 0.58, 0.075, 1.0)


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
    deform_bone: str,
    smooth: bool = False,
) -> bpy.types.Object:
    part.name = f"_lab_part_{name}"
    bpy.context.view_layer.objects.active = part
    part.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    part.data.materials.append(material)
    paint_mesh(part.data, color)
    if smooth:
        for polygon in part.data.polygons:
            polygon.use_smooth = True
    group = part.vertex_groups.new(name=deform_bone)
    group.add(
        list(range(len(part.data.vertices))),
        1.0,
        "REPLACE",
    )
    return part


def add_rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    color: Color,
    material: bpy.types.Material,
    deform_bone: str,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.025,
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
    return finish_part(part, name, color, material, deform_bone)


def add_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    color: Color,
    material: bpy.types.Material,
    deform_bone: str,
    segments: int = 14,
    rings: int = 8,
    smooth: bool = True,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
    )
    part = bpy.context.active_object
    part.scale = scale
    return finish_part(
        part,
        name,
        color,
        material,
        deform_bone,
        smooth,
    )


def add_cylinder_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    color: Color,
    material: bpy.types.Material,
    deform_bone: str,
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
    return finish_part(
        part,
        name,
        color,
        material,
        deform_bone,
        True,
    )


def add_cone_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    base_radius: float,
    tip_radius: float,
    color: Color,
    material: bpy.types.Material,
    deform_bone: str,
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
    return finish_part(
        part,
        name,
        color,
        material,
        deform_bone,
        True,
    )


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    color: Color,
    material: bpy.types.Material,
    deform_bone: str,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=16,
        minor_segments=6,
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
        major_radius=major_radius,
        minor_radius=minor_radius,
    )
    return finish_part(
        bpy.context.active_object,
        name,
        color,
        material,
        deform_bone,
        True,
    )


def build_character_parts(
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    # Boots and legs follow the generated Rigify deform-bone rest positions.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        x = 0.098 * sign
        parts.append(
            add_cylinder_between(
                f"upper_leg_{side}",
                (x, 0.005, 1.05),
                (x, -0.028, 0.54),
                0.125,
                TROUSERS,
                material,
                f"DEF-thigh.{side}",
            )
        )
        parts.append(
            add_sphere(
                f"knee_{side}",
                (x, -0.026, 0.55),
                (0.135, 0.135, 0.14),
                TROUSERS,
                material,
                f"DEF-shin.{side}",
                segments=12,
                rings=8,
            )
        )
        parts.append(
            add_cylinder_between(
                f"lower_leg_{side}",
                (x, -0.026, 0.55),
                (x, 0.012, 0.12),
                0.105,
                COAT_SHADOW,
                material,
                f"DEF-shin.{side}",
            )
        )
        parts.append(
            add_sphere(
                f"shoe_{side}",
                (x, -0.105, 0.105),
                (0.19, 0.29, 0.12),
                SHOES,
                material,
                f"DEF-foot.{side}",
                segments=16,
                rings=10,
            )
        )
        parts.append(
            add_rounded_box(
                f"shoe_sole_{side}",
                (x, -0.12, 0.035),
                (0.31, 0.43, 0.055),
                SHOE_SOLE,
                material,
                f"DEF-foot.{side}",
                bevel=0.018,
            )
        )

    # Coat, pelvis, lapels, tie and small readable costume accents.
    parts.append(
        add_sphere(
            "pelvis",
            (0.0, 0.01, 1.075),
            (0.31, 0.22, 0.22),
            TROUSERS,
            material,
            "DEF-spine",
            segments=16,
            rings=10,
        )
    )
    parts.append(
        add_cone_between(
            "coat_body",
            (0.0, 0.0, 1.06),
            (0.0, 0.0, 1.62),
            0.34,
            0.25,
            COAT,
            material,
            "DEF-spine.003",
            vertices=16,
        )
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            add_rounded_box(
                f"coat_tail_{side}",
                (0.145 * sign, 0.035, 0.98),
                (0.255, 0.31, 0.40),
                COAT,
                material,
                "DEF-spine.001",
                rotation=(0.0, math.radians(-4.0 * sign), 0.0),
                bevel=0.035,
            )
        )
        parts.append(
            add_rounded_box(
                f"lapel_{side}",
                (0.105 * sign, -0.255, 1.48),
                (0.16, 0.035, 0.36),
                COAT_SHADOW,
                material,
                "DEF-spine.004",
                rotation=(0.0, math.radians(-23.0 * sign), 0.0),
                bevel=0.018,
            )
        )
    parts.append(
        add_rounded_box(
            "belt",
            (0.0, -0.22, 1.19),
            (0.48, 0.045, 0.085),
            TROUSERS,
            material,
            "DEF-spine.002",
            bevel=0.018,
        )
    )
    parts.append(
        add_cone_between(
            "tie",
            (0.0, -0.285, 1.52),
            (0.0, -0.285, 1.27),
            0.075,
            0.025,
            ACCENT,
            material,
            "DEF-spine.004",
            vertices=8,
        )
    )
    for index, z_position in enumerate((1.36, 1.22, 1.08)):
        parts.append(
            add_sphere(
                f"coat_button_{index}",
                (0.105, -0.305, z_position),
                (0.035, 0.022, 0.035),
                ACCENT,
                material,
                "DEF-spine.003",
                segments=8,
                rings=6,
            )
        )

    # Sleeves follow the basic-human metarig's relaxed A-pose.
    arm_points = {
        "L": (
            (0.195, 0.027, 1.585),
            (0.442, 0.089, 1.449),
            (0.659, 0.049, 1.306),
        ),
        "R": (
            (-0.195, 0.027, 1.585),
            (-0.442, 0.089, 1.449),
            (-0.659, 0.049, 1.306),
        ),
    }
    for side, (shoulder, elbow, wrist) in arm_points.items():
        parts.append(
            add_sphere(
                f"shoulder_{side}",
                shoulder,
                (0.145, 0.145, 0.145),
                COAT,
                material,
                f"DEF-upper_arm.{side}",
                segments=12,
                rings=8,
            )
        )
        parts.append(
            add_cylinder_between(
                f"upper_sleeve_{side}",
                shoulder,
                elbow,
                0.115,
                COAT,
                material,
                f"DEF-upper_arm.{side}",
            )
        )
        parts.append(
            add_sphere(
                f"elbow_{side}",
                elbow,
                (0.12, 0.12, 0.12),
                COAT_SHADOW,
                material,
                f"DEF-forearm.{side}",
                segments=12,
                rings=8,
            )
        )
        parts.append(
            add_cylinder_between(
                f"forearm_sleeve_{side}",
                elbow,
                wrist,
                0.095,
                COAT,
                material,
                f"DEF-forearm.{side}",
            )
        )
        hand_sign = 1.0 if side == "L" else -1.0
        parts.append(
            add_sphere(
                f"glove_{side}",
                (0.705 * hand_sign, 0.032, 1.275),
                (0.145, 0.125, 0.14),
                GLOVES,
                material,
                f"DEF-hand.{side}",
                segments=14,
                rings=8,
            )
        )
        for finger_index, finger_z in enumerate((1.255, 1.29)):
            parts.append(
                add_sphere(
                    f"glove_finger_{side}_{finger_index}",
                    (
                        (0.79 + finger_index * 0.018) * hand_sign,
                        -0.018,
                        finger_z,
                    ),
                    (0.075, 0.065, 0.052),
                    GLOVES,
                    material,
                    f"DEF-hand.{side}",
                    segments=8,
                    rings=6,
                )
            )

    # Head, readable face, glasses and an intentionally original swept silhouette.
    parts.append(
        add_cylinder_between(
            "neck",
            (0.0, 0.01, 1.56),
            (0.0, 0.005, 1.67),
            0.115,
            SKIN,
            material,
            "DEF-spine.005",
        )
    )
    parts.append(
        add_sphere(
            "head",
            (0.0, -0.015, 1.84),
            (0.34, 0.30, 0.34),
            SKIN,
            material,
            "DEF-spine.006",
            segments=20,
            rings=12,
        )
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            add_sphere(
                f"ear_{side}",
                (0.315 * sign, -0.015, 1.84),
                (0.075, 0.045, 0.095),
                SKIN_LIGHT,
                material,
                "DEF-spine.006",
                segments=10,
                rings=6,
            )
        )
        parts.append(
            add_torus(
                f"goggle_frame_{side}",
                (0.132 * sign, -0.295, 1.89),
                0.105,
                0.025,
                GOGGLE_FRAME,
                material,
                "DEF-spine.006",
            )
        )
        parts.append(
            add_cylinder_between(
                f"goggle_lens_{side}",
                (0.132 * sign, -0.289, 1.89),
                (0.132 * sign, -0.315, 1.89),
                0.084,
                GOGGLE_LENS,
                material,
                "DEF-spine.006",
                vertices=20,
            )
        )
    parts.append(
        add_rounded_box(
            "goggle_bridge",
            (0.0, -0.305, 1.89),
            (0.075, 0.025, 0.028),
            GOGGLE_FRAME,
            material,
            "DEF-spine.006",
            bevel=0.008,
        )
    )
    parts.append(
        add_sphere(
            "nose",
            (0.0, -0.305, 1.78),
            (0.078, 0.105, 0.088),
            SKIN_LIGHT,
            material,
            "DEF-spine.006",
            segments=12,
            rings=8,
        )
    )
    parts.append(
        add_rounded_box(
            "mouth",
            (0.0, -0.315, 1.69),
            (0.17, 0.025, 0.043),
            MOUTH,
            material,
            "DEF-spine.006",
            bevel=0.012,
        )
    )
    parts.append(
        add_rounded_box(
            "teeth",
            (0.0, -0.331, 1.706),
            (0.105, 0.015, 0.022),
            TEETH,
            material,
            "DEF-spine.006",
            bevel=0.005,
        )
    )
    parts.append(
        add_sphere(
            "hair_cap",
            (0.0, 0.015, 2.055),
            (0.35, 0.285, 0.24),
            HAIR,
            material,
            "DEF-spine.006",
            segments=16,
            rings=10,
        )
    )
    hair_spikes = (
        ((-0.25, 0.00, 2.10), (-0.39, 0.015, 2.31), 0.13),
        ((-0.12, 0.02, 2.16), (-0.19, 0.025, 2.42), 0.14),
        ((0.02, 0.03, 2.17), (0.05, 0.035, 2.45), 0.15),
        ((0.16, 0.02, 2.14), (0.25, 0.025, 2.38), 0.14),
        ((0.27, 0.00, 2.08), (0.42, 0.005, 2.27), 0.12),
    )
    for index, (start, end, radius) in enumerate(hair_spikes):
        parts.append(
            add_cone_between(
                f"hair_spike_{index}",
                start,
                end,
                radius,
                0.012,
                HAIR_RIM if index % 2 else HAIR,
                material,
                "DEF-spine.006",
                vertices=12,
            )
        )
    return parts


def create_rigify_rig() -> bpy.types.Object:
    bpy.ops.preferences.addon_enable(module="rigify")
    bpy.ops.object.armature_basic_human_metarig_add()
    metarig = bpy.context.object
    metarig.name = "META_lab_assistant"
    metarig["rig_ui_type"] = "Rigify basic human"
    bpy.context.view_layer.objects.active = metarig
    metarig.select_set(True)
    bpy.ops.pose.rigify_generate()
    rig = bpy.context.object
    rig.name = RIG_NAME
    rig.data.name = f"{RIG_NAME}_skeleton"
    rig["rigify_source"] = "basic_human"
    rig["original_asset"] = True
    rig["forward_axis"] = "-Y"
    rig["unit_m"] = 1.0
    bpy.data.objects.remove(metarig, do_unlink=True)
    return rig


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
    character.select_set(True)
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

    modifier = character.modifiers.new(name="RigifyDeform", type="ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    character.parent = rig
    character.matrix_parent_inverse = rig.matrix_world.inverted()
    character["asset_role"] = "enemy"
    character["original_asset"] = True
    character["material_slots"] = 1
    character["walk_action"] = WALK_ACTION_NAME
    character.data.validate(verbose=True)
    character.data.update()
    return character


def key_rotation(
    bone: bpy.types.PoseBone,
    frame: int,
    rotation: tuple[float, float, float],
) -> None:
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = rotation
    bone.keyframe_insert(data_path="rotation_euler", frame=frame)


def create_walk_cycle(rig: bpy.types.Object) -> bpy.types.Action:
    scene = bpy.context.scene
    scene.frame_start = WALK_FIRST_FRAME
    scene.frame_end = WALK_LAST_FRAME
    scene.render.fps = WALK_FPS
    action = bpy.data.actions.new(WALK_ACTION_NAME)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action

    for side in ("L", "R"):
        rig.pose.bones[f"upper_arm_parent.{side}"]["IK_FK"] = 0.0
        rig.pose.bones[f"thigh_parent.{side}"]["IK_FK"] = 0.0

    keyed_frames = (
        WALK_FIRST_FRAME,
        7,
        13,
        19,
        WALK_LAST_FRAME,
    )
    for frame in keyed_frames:
        phase = math.tau * (
            (frame - WALK_FIRST_FRAME)
            / (WALK_LAST_FRAME - WALK_FIRST_FRAME)
        )
        stride = math.sin(phase)
        double_step = math.cos(phase * 2.0)

        key_rotation(
            rig.pose.bones["thigh_fk.L"],
            frame,
            (math.radians(26.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["thigh_fk.R"],
            frame,
            (-math.radians(26.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["shin_fk.L"],
            frame,
            (
                math.radians(12.0)
                + math.radians(18.0) * max(-stride, 0.0),
                0.0,
                0.0,
            ),
        )
        key_rotation(
            rig.pose.bones["shin_fk.R"],
            frame,
            (
                math.radians(12.0)
                + math.radians(18.0) * max(stride, 0.0),
                0.0,
                0.0,
            ),
        )
        key_rotation(
            rig.pose.bones["foot_fk.L"],
            frame,
            (-math.radians(8.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["foot_fk.R"],
            frame,
            (math.radians(8.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["upper_arm_fk.L"],
            frame,
            (-math.radians(22.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["upper_arm_fk.R"],
            frame,
            (math.radians(22.0) * stride, 0.0, 0.0),
        )
        key_rotation(
            rig.pose.bones["forearm_fk.L"],
            frame,
            (math.radians(14.0), 0.0, -math.radians(8.0)),
        )
        key_rotation(
            rig.pose.bones["forearm_fk.R"],
            frame,
            (math.radians(14.0), 0.0, math.radians(8.0)),
        )
        key_rotation(
            rig.pose.bones["torso"],
            frame,
            (
                math.radians(2.0) * double_step,
                0.0,
                -math.radians(3.5) * stride,
            ),
        )
        key_rotation(
            rig.pose.bones["head"],
            frame,
            (
                -math.radians(2.0) * double_step,
                0.0,
                math.radians(2.5) * stride,
            ),
        )
        hips = rig.pose.bones["hips"]
        hips.location = (
            0.0,
            0.0,
            0.018 * (1.0 - double_step),
        )
        hips.keyframe_insert(data_path="location", frame=frame)

    for curve in action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "BEZIER"
            keyframe.handle_left_type = "AUTO_CLAMPED"
            keyframe.handle_right_type = "AUTO_CLAMPED"
    action["looping"] = True
    action["clip_role"] = "locomotion"
    scene.frame_set(WALK_FIRST_FRAME)
    return action


def triangle_count(character: bpy.types.Object) -> int:
    return sum(
        max(len(polygon.vertices) - 2, 0)
        for polygon in character.data.polygons
    )


def validate_asset(
    character: bpy.types.Object,
    rig: bpy.types.Object,
    action: bpy.types.Action,
) -> tuple[int, int, int]:
    vertices = len(character.data.vertices)
    faces = len(character.data.polygons)
    triangles = triangle_count(character)
    if not 3000 <= triangles <= 6000:
        raise RuntimeError(
            f"{ASSET_NAME} has {triangles} triangles; enemy band is 3000-6000"
        )
    if len(character.data.materials) != 1:
        raise RuntimeError("lab assistant must export one material slot")
    if character.data.color_attributes.get(COLOR_ATTRIBUTE) is None:
        raise RuntimeError("lab assistant has no authored vertex colors")
    if not character.data.uv_layers:
        raise RuntimeError("lab assistant has no UV map")
    if not character.vertex_groups:
        raise RuntimeError("lab assistant has no deform weights")
    if action.name != WALK_ACTION_NAME:
        raise RuntimeError("walk action lost its authored name")
    if not any(bone.name.startswith("DEF-") for bone in rig.data.bones):
        raise RuntimeError("generated Rigify rig has no deform bones")
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
    bpy.context.scene.frame_set(WALK_FIRST_FRAME)
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
    bpy.context.scene.frame_set(7)
    rig.hide_render = False

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.035, 0.055, 0.080, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.6, -4.4, 2.25)
    camera_data.lens = 64.0
    point_at(camera, Vector((0.0, 0.0, 1.2)))
    bpy.context.scene.camera = camera

    for name, energy, size, location, color in (
        (
            "_preview_key",
            720.0,
            4.0,
            (-2.5, -3.2, 4.2),
            (1.0, 0.72, 0.48),
        ),
        (
            "_preview_fill",
            470.0,
            3.0,
            (3.0, -1.2, 2.8),
            (0.42, 0.68, 1.0),
        ),
        (
            "_preview_rim",
            560.0,
            2.5,
            (-1.2, 3.2, 3.4),
            (0.50, 0.82, 1.0),
        ),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 1.1)))

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
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    bpy.context.view_layer.objects.active = character
    bpy.ops.render.render(write_still=True)


def main() -> None:
    reset_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    material = create_material()
    rig = create_rigify_rig()
    character = join_and_skin(
        build_character_parts(material),
        material,
        rig,
    )
    action = create_walk_cycle(rig)
    vertices, faces, triangles = validate_asset(character, rig, action)
    save_source_and_export(character, rig)
    create_preview(character, rig)
    print(
        "LAB_ASSISTANT_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 "
        f"rig=rigify_basic_human walk={WALK_ACTION_NAME}"
    )
    print(f"LAB_ASSISTANT_SOURCE={SOURCE_PATH}")
    print(f"LAB_ASSISTANT_GLB={EXPORT_PATH}")
    print(f"LAB_ASSISTANT_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
