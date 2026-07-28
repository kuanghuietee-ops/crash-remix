"""Build the original untextured Crash likeness candidate for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_crash_likeness.py

This is the deliberately color-blind rung-three gate candidate: original
geometry, a uniform clay vertex color, one material, a proportion-matched
Rigify basic-human skeleton, and one subtle looping idle.  The editable
Blender source and inspection renders stay under build/; the shipping GLB is
written to the hero-character budget directory.
"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
HELPERS_PATH = REPO_ROOT / "scripts/blender/create_lab_assistant.py"
ASSET_NAME = "SK_crash"
RIG_NAME = "RIG_crash"
MATERIAL_NAME = "M_crash_clay"
IDLE_ACTION_NAME = "A_crash_idle"
COLOR_ATTRIBUTE = "COLOR_0"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_crash_likeness.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/characters/SK_crash.glb"
PREVIEW_ROOT = REPO_ROOT / "build/art-previews"

IDLE_FIRST_FRAME = 1
IDLE_LAST_FRAME = 49
IDLE_FPS = 24
CLAY = (0.55, 0.60, 0.67, 1.0)


def load_geometry_helpers():
    spec = importlib.util.spec_from_file_location(
        "crash_geometry_helpers",
        HELPERS_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load geometry helpers from {HELPERS_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


geometry = load_geometry_helpers()


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
    shader.inputs["Roughness"].default_value = 0.88
    shader.inputs["Metallic"].default_value = 0.0
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(vertex_color.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def add_polyhedron(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material: bpy.types.Material,
    deform_bone: str,
    smooth: bool = False,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"_{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    part = bpy.data.objects.new(f"_{name}", mesh)
    bpy.context.collection.objects.link(part)
    return geometry.finish_part(
        part,
        name,
        CLAY,
        material,
        deform_bone,
        smooth,
    )


def add_ear(
    side: str,
    sign: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    # A flattened, swept diamond reads as the tall triangular bandicoot ear
    # from both the front and side without relying on an inner-ear color.
    x_inner = 0.205 * sign
    x_outer = 0.315 * sign
    x_mid = 0.268 * sign
    vertices = [
        (x_inner, -0.015, 0.875),
        (x_outer, -0.002, 1.035),
        (x_mid, -0.018, 0.845),
        (x_inner, 0.055, 0.875),
        (x_outer, 0.045, 1.035),
        (x_mid, 0.060, 0.845),
    ]
    faces = [
        (0, 1, 2),
        (5, 4, 3),
        (0, 3, 4, 1),
        (1, 4, 5, 2),
        (2, 5, 3, 0),
    ]
    return add_polyhedron(
        f"ear_{side}",
        vertices,
        faces,
        material,
        "DEF-spine.006",
    )


def add_brow(
    side: str,
    sign: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    outer = 0.145 * sign
    inner = 0.018 * sign
    z_outer = 0.895
    z_inner = 0.915
    depth_front = -0.288
    depth_back = -0.258
    thickness = 0.024
    vertices = [
        (outer, depth_front, z_outer - thickness),
        (outer, depth_front, z_outer + thickness),
        (inner, depth_front, z_inner + thickness),
        (inner, depth_front, z_inner - thickness),
        (outer, depth_back, z_outer - thickness),
        (outer, depth_back, z_outer + thickness),
        (inner, depth_back, z_inner + thickness),
        (inner, depth_back, z_inner - thickness),
    ]
    faces = [
        (0, 1, 2, 3),
        (7, 6, 5, 4),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    return add_polyhedron(
        f"brow_{side}",
        vertices,
        faces,
        material,
        "DEF-spine.006",
    )


def build_character_parts(
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    # Split, oversized shoes anchor the 1.10 m silhouette exactly at z=0.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        x = 0.105 * sign
        parts.append(
            geometry.add_rounded_box(
                f"shoe_sole_{side}",
                (x, -0.075, 0.0225),
                (0.245, 0.335, 0.045),
                CLAY,
                material,
                f"DEF-foot.{side}",
                bevel=0.014,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"shoe_{side}",
                (x, -0.075, 0.082),
                (0.135, 0.205, 0.078),
                CLAY,
                material,
                f"DEF-foot.{side}",
                segments=28,
                rings=16,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"ankle_cuff_{side}",
                (0.080 * sign, 0.005, 0.145),
                (0.090, 0.085, 0.055),
                CLAY,
                material,
                f"DEF-shin.{side}",
                segments=18,
                rings=10,
            )
        )
        parts.append(
            geometry.add_cylinder_between(
                f"lower_leg_{side}",
                (0.078 * sign, 0.012, 0.105),
                (0.078 * sign, 0.008, 0.205),
                0.053,
                CLAY,
                material,
                f"DEF-shin.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"knee_{side}",
                (0.078 * sign, 0.005, 0.205),
                (0.058, 0.057, 0.055),
                CLAY,
                material,
                f"DEF-shin.{side}",
                segments=16,
                rings=9,
            )
        )
        parts.append(
            geometry.add_cylinder_between(
                f"upper_leg_{side}",
                (0.078 * sign, 0.005, 0.205),
                (0.078 * sign, 0.006, 0.330),
                0.057,
                CLAY,
                material,
                f"DEF-thigh.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"shorts_leg_{side}",
                (0.073 * sign, 0.000, 0.335),
                (0.094, 0.090, 0.075),
                CLAY,
                material,
                "DEF-spine",
                segments=18,
                rings=10,
            )
        )

    parts.append(
        geometry.add_sphere(
            "shorts_waist",
            (0.0, 0.012, 0.380),
            (0.158, 0.108, 0.105),
            CLAY,
            material,
            "DEF-spine",
            segments=18,
            rings=10,
        )
    )
    parts.append(
        geometry.add_cone_between(
            "tiny_torso",
            (0.0, 0.018, 0.385),
            (0.0, 0.008, 0.565),
            0.118,
            0.145,
            CLAY,
            material,
            "DEF-spine.003",
            vertices=22,
        )
    )
    parts.append(
        geometry.add_cylinder_between(
            "neck",
            (0.0, 0.005, 0.545),
            (0.0, 0.005, 0.655),
            0.068,
            CLAY,
            material,
            "DEF-spine.005",
            vertices=20,
        )
    )

    # Elbow-low A-pose, long forearms, and fist-sized hands are stronger cold
    # identifiers than costume surface details.
    arm_points = {
        "L": (
            (0.125, 0.015, 0.545),
            (0.305, 0.018, 0.430),
            (0.430, -0.005, 0.315),
        ),
        "R": (
            (-0.125, 0.015, 0.545),
            (-0.305, 0.018, 0.430),
            (-0.430, -0.005, 0.315),
        ),
    }
    for side, (shoulder, elbow, wrist) in arm_points.items():
        sign = 1.0 if side == "L" else -1.0
        parts.append(
            geometry.add_sphere(
                f"shoulder_{side}",
                shoulder,
                (0.083, 0.080, 0.083),
                CLAY,
                material,
                f"DEF-upper_arm.{side}",
                segments=16,
                rings=9,
            )
        )
        parts.append(
            geometry.add_cylinder_between(
                f"upper_arm_{side}",
                shoulder,
                elbow,
                0.060,
                CLAY,
                material,
                f"DEF-upper_arm.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"elbow_{side}",
                elbow,
                (0.066, 0.063, 0.066),
                CLAY,
                material,
                f"DEF-forearm.{side}",
                segments=16,
                rings=9,
            )
        )
        parts.append(
            geometry.add_cylinder_between(
                f"forearm_{side}",
                elbow,
                wrist,
                0.057,
                CLAY,
                material,
                f"DEF-forearm.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"fist_{side}",
                (0.495 * sign, -0.015, 0.275),
                (0.104, 0.092, 0.105),
                CLAY,
                material,
                f"DEF-hand.{side}",
                segments=22,
                rings=13,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"thumb_{side}",
                (0.448 * sign, -0.083, 0.283),
                (0.055, 0.052, 0.058),
                CLAY,
                material,
                f"DEF-hand.{side}",
                segments=12,
                rings=7,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"knuckles_{side}",
                (0.535 * sign, -0.068, 0.283),
                (0.071, 0.052, 0.060),
                CLAY,
                material,
                f"DEF-hand.{side}",
                segments=12,
                rings=7,
            )
        )

    # One huge cranium, deep double-lobed muzzle, large nose, and raised eye
    # masses.  Every part remains the same clay so lighting alone must describe
    # the face.
    parts.append(
        geometry.add_sphere(
            "head",
            (0.0, 0.018, 0.810),
            (0.270, 0.205, 0.245),
            CLAY,
            material,
            "DEF-spine.006",
            segments=30,
            rings=18,
        )
    )
    parts.append(
        geometry.add_sphere(
            "muzzle",
            (0.0, -0.165, 0.725),
            (0.255, 0.150, 0.145),
            CLAY,
            material,
            "DEF-spine.006",
            segments=28,
            rings=16,
        )
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            geometry.add_sphere(
                f"cheek_{side}",
                (0.112 * sign, -0.218, 0.725),
                (0.150, 0.105, 0.112),
                CLAY,
                material,
                "DEF-spine.006",
                segments=18,
                rings=10,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"eye_mass_{side}",
                (0.068 * sign, -0.215, 0.862),
                (0.066, 0.058, 0.125),
                CLAY,
                material,
                "DEF-spine.006",
                segments=18,
                rings=10,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"pupil_relief_{side}",
                (0.068 * sign, -0.282, 0.878),
                (0.025, 0.018, 0.050),
                CLAY,
                material,
                "DEF-spine.006",
                segments=12,
                rings=7,
            )
        )
        parts.append(add_brow(side, sign, material))
        parts.append(add_ear(side, sign, material))

    parts.append(
        geometry.add_sphere(
            "nose",
            (0.0, -0.310, 0.758),
            (0.100, 0.082, 0.078),
            CLAY,
            material,
            "DEF-spine.006",
            segments=22,
            rings=13,
        )
    )
    parts.append(
        geometry.add_rounded_box(
            "lower_mouth_plane",
            (0.0, -0.323, 0.667),
            (0.178, 0.020, 0.026),
            CLAY,
            material,
            "DEF-spine.006",
            bevel=0.010,
        )
    )

    # Five independent swept crest points preserve the characteristic crown in
    # front, profile, and three-quarter inspection.
    crest_points = (
        ((-0.205, 0.025, 0.940), (-0.315, 0.015, 1.055), 0.072),
        ((-0.118, 0.025, 1.000), (-0.178, 0.010, 1.090), 0.070),
        ((0.000, 0.020, 1.025), (0.000, 0.005, 1.100), 0.073),
        ((0.118, 0.025, 1.000), (0.178, 0.010, 1.090), 0.070),
        ((0.205, 0.025, 0.940), (0.315, 0.015, 1.055), 0.072),
    )
    for index, (start, end, radius) in enumerate(crest_points):
        parts.append(
            geometry.add_cone_between(
                f"crest_{index}",
                start,
                end,
                radius,
                0.006,
                CLAY,
                material,
                "DEF-spine.006",
                vertices=16,
            )
        )
    return parts


def set_edit_bone(
    metarig: bpy.types.Object,
    name: str,
    head: tuple[float, float, float],
    tail: tuple[float, float, float],
) -> None:
    bone = metarig.data.edit_bones[name]
    bone.head = head
    bone.tail = tail


def create_rigify_rig() -> bpy.types.Object:
    bpy.ops.preferences.addon_enable(module="rigify")
    bpy.ops.object.armature_basic_human_metarig_add()
    metarig = bpy.context.object
    metarig.name = "META_crash"
    metarig["rig_ui_type"] = "Rigify basic human"
    bpy.context.view_layer.objects.active = metarig
    bpy.ops.object.mode_set(mode="EDIT")

    spine_points = (
        (0.0, 0.018, 0.330),
        (0.0, 0.014, 0.385),
        (0.0, 0.010, 0.435),
        (0.0, 0.008, 0.490),
        (0.0, 0.006, 0.550),
        (0.0, 0.004, 0.595),
        (0.0, 0.002, 0.640),
        (0.0, 0.002, 0.930),
    )
    for index in range(7):
        name = "spine" if index == 0 else f"spine.{index:03d}"
        set_edit_bone(metarig, name, spine_points[index], spine_points[index + 1])

    for side, sign in (("L", 1.0), ("R", -1.0)):
        set_edit_bone(
            metarig,
            f"shoulder.{side}",
            (0.012 * sign, 0.000, 0.535),
            (0.128 * sign, 0.010, 0.545),
        )
        set_edit_bone(
            metarig,
            f"upper_arm.{side}",
            (0.135 * sign, 0.012, 0.545),
            (0.305 * sign, 0.018, 0.430),
        )
        set_edit_bone(
            metarig,
            f"forearm.{side}",
            (0.305 * sign, 0.018, 0.430),
            (0.430 * sign, -0.005, 0.315),
        )
        set_edit_bone(
            metarig,
            f"hand.{side}",
            (0.430 * sign, -0.005, 0.315),
            (0.510 * sign, -0.015, 0.275),
        )
        set_edit_bone(
            metarig,
            f"breast.{side}",
            (0.090 * sign, 0.035, 0.485),
            (0.090 * sign, -0.070, 0.485),
        )
        set_edit_bone(
            metarig,
            f"pelvis.{side}",
            (0.0, 0.018, 0.330),
            (0.080 * sign, -0.015, 0.395),
        )
        set_edit_bone(
            metarig,
            f"thigh.{side}",
            (0.078 * sign, 0.006, 0.340),
            (0.078 * sign, 0.005, 0.205),
        )
        set_edit_bone(
            metarig,
            f"shin.{side}",
            (0.078 * sign, 0.005, 0.205),
            (0.078 * sign, 0.012, 0.082),
        )
        set_edit_bone(
            metarig,
            f"foot.{side}",
            (0.078 * sign, 0.012, 0.082),
            (0.090 * sign, -0.105, 0.032),
        )
        set_edit_bone(
            metarig,
            f"toe.{side}",
            (0.090 * sign, -0.105, 0.032),
            (0.105 * sign, -0.205, 0.032),
        )
        set_edit_bone(
            metarig,
            f"heel.02.{side}",
            (0.035 * sign, 0.055, 0.000),
            (0.130 * sign, 0.055, 0.000),
        )

    bpy.ops.object.mode_set(mode="OBJECT")
    metarig.select_set(True)
    bpy.context.view_layer.objects.active = metarig
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
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(66.0),
        island_margin=0.008,
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
    character["asset_role"] = "hero"
    character["original_asset"] = True
    character["material_slots"] = 1
    character["likeness_stage"] = "uniform_clay_candidate"
    character["idle_action"] = IDLE_ACTION_NAME
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


def create_idle(rig: bpy.types.Object) -> bpy.types.Action:
    scene = bpy.context.scene
    scene.frame_start = IDLE_FIRST_FRAME
    scene.frame_end = IDLE_LAST_FRAME
    scene.render.fps = IDLE_FPS
    action = bpy.data.actions.new(IDLE_ACTION_NAME)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action

    for side in ("L", "R"):
        rig.pose.bones[f"upper_arm_parent.{side}"]["IK_FK"] = 0.0
        rig.pose.bones[f"thigh_parent.{side}"]["IK_FK"] = 0.0

    for frame in (IDLE_FIRST_FRAME, 13, 25, 37, IDLE_LAST_FRAME):
        phase = math.tau * (
            (frame - IDLE_FIRST_FRAME)
            / (IDLE_LAST_FRAME - IDLE_FIRST_FRAME)
        )
        breath = math.sin(phase)
        settle = math.cos(phase)
        key_rotation(
            rig.pose.bones["torso"],
            frame,
            (
                math.radians(1.5) * breath,
                0.0,
                math.radians(0.8) * settle,
            ),
        )
        key_rotation(
            rig.pose.bones["head"],
            frame,
            (
                -math.radians(1.2) * breath,
                math.radians(0.7) * settle,
                -math.radians(0.8) * settle,
            ),
        )
        key_rotation(
            rig.pose.bones["upper_arm_fk.L"],
            frame,
            (0.0, math.radians(0.8) * breath, math.radians(0.6) * settle),
        )
        key_rotation(
            rig.pose.bones["upper_arm_fk.R"],
            frame,
            (0.0, -math.radians(0.8) * breath, -math.radians(0.6) * settle),
        )
        hips = rig.pose.bones["hips"]
        hips.location = (0.0, 0.0, 0.004 * (1.0 - settle))
        hips.keyframe_insert(data_path="location", frame=frame)

    for curve in action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "BEZIER"
            keyframe.handle_left_type = "AUTO_CLAMPED"
            keyframe.handle_right_type = "AUTO_CLAMPED"
    action["looping"] = True
    action["clip_role"] = "idle"
    scene.frame_set(IDLE_FIRST_FRAME)
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
    if not 10000 <= triangles <= 12000:
        raise RuntimeError(
            f"{ASSET_NAME} has {triangles} triangles; hero band is 10000-12000"
        )
    if len(character.data.materials) != 1:
        raise RuntimeError("Crash likeness candidate must export one material")
    color_attribute = character.data.color_attributes.get(COLOR_ATTRIBUTE)
    if color_attribute is None:
        raise RuntimeError("Crash likeness candidate has no vertex colors")
    unique_colors = {
        tuple(round(channel, 6) for channel in value.color)
        for value in color_attribute.data
    }
    if len(unique_colors) != 1:
        raise RuntimeError("cold likeness gate must remain one uniform clay color")
    if not character.data.uv_layers:
        raise RuntimeError("Crash likeness candidate has no UV map")
    if not character.vertex_groups:
        raise RuntimeError("Crash likeness candidate has no deform weights")
    if action.name != IDLE_ACTION_NAME:
        raise RuntimeError("idle action lost its authored name")
    required_bones = {
        "DEF-spine",
        "DEF-upper_arm.L",
        "DEF-upper_arm.R",
        "DEF-thigh.L",
        "DEF-thigh.R",
        "DEF-foot.L",
        "DEF-foot.R",
    }
    rig_bones = {bone.name for bone in rig.data.bones}
    missing_bones = sorted(required_bones - rig_bones)
    if missing_bones:
        raise RuntimeError(f"generated Rigify rig is missing {missing_bones}")
    min_z = min(vertex.co.z for vertex in character.data.vertices)
    max_z = max(vertex.co.z for vertex in character.data.vertices)
    if abs(min_z) > 0.001 or not 1.05 <= max_z - min_z <= 1.15:
        raise RuntimeError(
            f"hero height/origin invalid: min_z={min_z:.4f} "
            f"height={max_z - min_z:.4f}"
        )
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
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
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


def create_inspection_previews(
    character: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.frame_set(13)
    rig.hide_render = False

    bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.035, 0.050, 0.072, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.30
    bpy.context.scene.camera = camera

    for name, energy, size, location, color in (
        (
            "_preview_key",
            650.0,
            3.0,
            (-2.0, -2.6, 3.0),
            (1.0, 0.82, 0.68),
        ),
        (
            "_preview_fill",
            420.0,
            2.5,
            (2.4, -1.1, 1.9),
            (0.55, 0.72, 1.0),
        ),
        (
            "_preview_rim",
            520.0,
            2.0,
            (-1.2, 2.4, 2.3),
            (0.62, 0.82, 1.0),
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
        point_at(light, Vector((0.0, 0.0, 0.55)))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.012,
        0.020,
        0.035,
        1.0,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.26

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

    views = {
        "front": (0.0, -3.0, 0.58),
        "side": (3.0, 0.0, 0.58),
        "back": (0.0, 3.0, 0.58),
    }
    for view_name, position in views.items():
        camera.location = position
        point_at(camera, Vector((0.0, 0.0, 0.55)))
        scene.render.filepath = str(
            PREVIEW_ROOT / f"SK_crash_likeness_{view_name}.png"
        )
        bpy.ops.render.render(write_still=True)

    bpy.context.view_layer.objects.active = character


def main() -> None:
    geometry.reset_scene()
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
    action = create_idle(rig)
    vertices, faces, triangles = validate_asset(character, rig, action)
    save_source_and_export(character, rig)
    create_inspection_previews(character, rig)
    print(
        "CRASH_LIKENESS_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 "
        f"rig=rigify_basic_human idle={IDLE_ACTION_NAME}"
    )
    print(f"CRASH_LIKENESS_SOURCE={SOURCE_PATH}")
    print(f"CRASH_LIKENESS_GLB={EXPORT_PATH}")
    print(f"CRASH_LIKENESS_PREVIEWS={PREVIEW_ROOT}")


if __name__ == "__main__":
    main()
