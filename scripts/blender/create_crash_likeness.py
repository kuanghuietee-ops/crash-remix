"""Build the original vertex-painted Crash character candidate for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_crash_likeness.py

The silhouette was reviewed in uniform clay before this color pass.  This
stage preserves that geometry while adding a self-contained, matte palette
through vertex colors: one draw-call material, no copied textures, a
proportion-matched Rigify basic-human skeleton, and twelve authored gameplay
and personality actions plus idle.  The editable Blender source and
inspection renders stay under build/; the shipping GLB is written to the
hero-character budget directory.
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
MATERIAL_NAME = "M_crash_body"
IDLE_ACTION_NAME = "A_crash_idle"
BORED_IDLE_ACTION_NAME = "A_crash_bored_idle"
RUN_ACTION_NAME = "A_crash_run"
CROUCH_ACTION_NAME = "A_crash_crouch"
CRAWL_ACTION_NAME = "A_crash_crawl"
JUMP_ACTION_NAME = "A_crash_jump"
DOUBLE_JUMP_ACTION_NAME = "A_crash_double_jump"
SPIN_ACTION_NAME = "A_crash_spin"
SLIDE_ACTION_NAME = "A_crash_slide"
SLAM_ACTION_NAME = "A_crash_slam"
WALL_RUN_ACTION_NAME = "A_crash_wall_run"
GRIND_ACTION_NAME = "A_crash_grind"
SWING_ACTION_NAME = "A_crash_swing"
CORE_ACTION_NAMES = (
    BORED_IDLE_ACTION_NAME,
    RUN_ACTION_NAME,
    CROUCH_ACTION_NAME,
    CRAWL_ACTION_NAME,
    JUMP_ACTION_NAME,
    DOUBLE_JUMP_ACTION_NAME,
    SPIN_ACTION_NAME,
    SLIDE_ACTION_NAME,
    SLAM_ACTION_NAME,
    WALL_RUN_ACTION_NAME,
    GRIND_ACTION_NAME,
    SWING_ACTION_NAME,
)
COLOR_ATTRIBUTE = "COLOR_0"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_crash_color.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/characters/SK_crash.glb"
PREVIEW_ROOT = REPO_ROOT / "build/art-previews"

IDLE_FIRST_FRAME = 1
IDLE_LAST_FRAME = 49
IDLE_FPS = 24
BORED_IDLE_LAST_FRAME = 73
RUN_LAST_FRAME = 17
CROUCH_LAST_FRAME = 13
CRAWL_LAST_FRAME = 25
JUMP_LAST_FRAME = 21
DOUBLE_JUMP_LAST_FRAME = 19
SPIN_LAST_FRAME = 13
SLIDE_LAST_FRAME = 17
SLAM_LAST_FRAME = 15
WALL_RUN_LAST_FRAME = 17
GRIND_LAST_FRAME = 25
SWING_LAST_FRAME = 25
Color = tuple[float, float, float, float]

FUR_ORANGE: Color = (0.88, 0.225, 0.035, 1.0)
FUR_DARK: Color = (0.155, 0.030, 0.012, 1.0)
MUZZLE_TAN: Color = (0.94, 0.545, 0.205, 1.0)
SHORTS_BLUE: Color = (0.025, 0.145, 0.525, 1.0)
SHOE_RED: Color = (0.72, 0.035, 0.018, 1.0)
SHOE_SOLE: Color = (0.105, 0.020, 0.014, 1.0)
SHOE_WHITE: Color = (0.94, 0.90, 0.72, 1.0)
EYE_WHITE: Color = (0.96, 0.94, 0.72, 1.0)
PUPIL: Color = (0.018, 0.010, 0.008, 1.0)
NOSE: Color = (0.012, 0.008, 0.010, 1.0)
MOUTH: Color = (0.16, 0.010, 0.018, 1.0)
TEETH: Color = (1.0, 0.88, 0.56, 1.0)


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
    color: Color,
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
        color,
        material,
        deform_bone,
        smooth,
    )


def add_ear(
    side: str,
    sign: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    # Keep the ear broad, outward-swept, and lower than the central crest.  The
    # first candidate's tall equal-sided triangles read as cat ears on phone.
    x_inner = 0.175 * sign
    x_outer = 0.325 * sign
    x_mid = 0.255 * sign
    vertices = [
        (x_inner, -0.020, 0.905),
        (x_outer, -0.005, 1.055),
        (x_mid, -0.025, 0.805),
        (x_inner, 0.070, 0.905),
        (x_outer, 0.055, 1.055),
        (x_mid, 0.080, 0.805),
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
        FUR_ORANGE,
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
        FUR_DARK,
        material,
        "DEF-spine.006",
    )


def carve_smile(
    muzzle: bpy.types.Object,
    deform_bone: str,
) -> None:
    """Cut a broad recessed grin into the muzzle."""
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=18,
        ring_count=10,
        radius=1.0,
        location=(0.0, -0.286, 0.675),
    )
    cutter = bpy.context.active_object
    cutter.name = "_smile_cutter"
    cutter.scale = (0.135, 0.082, 0.050)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    modifier = muzzle.modifiers.new(name="_recessed_grin", type="BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.context.view_layer.objects.active = muzzle
    muzzle.select_set(True)
    cutter.select_set(False)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

    geometry.paint_mesh(muzzle.data, MUZZLE_TAN)
    group = muzzle.vertex_groups.get(deform_bone)
    if group is None:
        group = muzzle.vertex_groups.new(name=deform_bone)
    group.add(list(range(len(muzzle.data.vertices))), 1.0, "REPLACE")
    for polygon in muzzle.data.polygons:
        polygon.use_smooth = True


def add_tapered_head(
    material: bpy.types.Material,
) -> bpy.types.Object:
    """Create the upper-heavy wedge that the round first pass lacked."""
    center_z = 0.810
    half_height = 0.245
    head = geometry.add_sphere(
        "head",
        (0.0, 0.020, center_z),
        (0.255, 0.190, half_height),
        FUR_ORANGE,
        material,
        "DEF-spine.006",
        segments=28,
        rings=16,
    )
    for vertex in head.data.vertices:
        normalized_z = max(
            -1.0,
            min(1.0, (vertex.co.z - center_z) / half_height),
        )
        height_ratio = (normalized_z + 1.0) * 0.5
        vertex.co.x *= 0.58 + 0.52 * height_ratio
        vertex.co.y = (
            0.020
            + (vertex.co.y - 0.020) * (0.88 + 0.12 * height_ratio)
        )
    head.data.update()
    return head


def add_nose_wedge(
    material: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [
        (-0.065, -0.285, 0.795),
        (0.065, -0.285, 0.795),
        (0.060, -0.285, 0.725),
        (-0.060, -0.285, 0.725),
        (-0.078, -0.430, 0.782),
        (0.078, -0.430, 0.782),
        (0.062, -0.430, 0.735),
        (-0.062, -0.430, 0.735),
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
        "nose_wedge",
        vertices,
        faces,
        NOSE,
        material,
        "DEF-spine.006",
    )


def build_character_parts(
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []

    # Split, oversized shoes anchor the 1.10 m silhouette exactly at z=0.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        x = 0.112 * sign
        parts.append(
            geometry.add_rounded_box(
                f"shoe_sole_{side}",
                (x, -0.075, 0.0225),
                (0.205, 0.335, 0.045),
                SHOE_SOLE,
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
                SHOE_RED,
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
                SHOE_WHITE,
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
                FUR_ORANGE,
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
                FUR_ORANGE,
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
                FUR_ORANGE,
                material,
                f"DEF-thigh.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"shorts_leg_{side}",
                (0.065 * sign, 0.000, 0.325),
                (0.082, 0.088, 0.075),
                SHORTS_BLUE,
                material,
                "DEF-spine",
                segments=18,
                rings=10,
            )
        )

    parts.append(
        geometry.add_sphere(
            "shorts_waist",
            (0.0, 0.012, 0.355),
            (0.138, 0.103, 0.090),
            SHORTS_BLUE,
            material,
            "DEF-spine",
            segments=18,
            rings=10,
        )
    )
    parts.append(
        geometry.add_cone_between(
            "tiny_torso",
            (0.0, 0.018, 0.350),
            (0.0, 0.008, 0.610),
            0.108,
            0.160,
            FUR_ORANGE,
            material,
            "DEF-spine.003",
            vertices=22,
        )
    )
    parts.append(
        geometry.add_cylinder_between(
            "neck",
            (0.0, 0.005, 0.590),
            (0.0, 0.005, 0.660),
            0.060,
            FUR_ORANGE,
            material,
            "DEF-spine.005",
            vertices=20,
        )
    )
    parts.append(
        geometry.add_sphere(
            "chest_patch",
            (0.0, -0.105, 0.490),
            (0.095, 0.026, 0.135),
            MUZZLE_TAN,
            material,
            "DEF-spine.003",
            segments=18,
            rings=10,
        )
    )

    # Elbow-low A-pose, long forearms, and open four-finger hands are stronger
    # cold identifiers than costume surface details.
    arm_points = {
        "L": (
            (0.145, 0.015, 0.595),
            (0.220, 0.018, 0.430),
            (0.250, -0.005, 0.285),
        ),
        "R": (
            (-0.145, 0.015, 0.595),
            (-0.220, 0.018, 0.430),
            (-0.250, -0.005, 0.285),
        ),
    }
    for side, (shoulder, elbow, wrist) in arm_points.items():
        sign = 1.0 if side == "L" else -1.0
        parts.append(
            geometry.add_sphere(
                f"shoulder_{side}",
                shoulder,
                (0.083, 0.080, 0.083),
                FUR_ORANGE,
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
                FUR_ORANGE,
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
                FUR_ORANGE,
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
                FUR_ORANGE,
                material,
                f"DEF-forearm.{side}",
                vertices=18,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"palm_{side}",
                (0.272 * sign, -0.010, 0.235),
                (0.072, 0.065, 0.088),
                FUR_ORANGE,
                material,
                f"DEF-hand.{side}",
                segments=18,
                rings=10,
            )
        )
        finger_positions = (
            (0.235, -0.055, 0.176, 0.028, 0.037, 0.065),
            (0.275, -0.060, 0.165, 0.029, 0.038, 0.070),
            (0.315, -0.055, 0.180, 0.028, 0.037, 0.063),
            (0.330, -0.070, 0.238, 0.050, 0.040, 0.043),
        )
        for finger_index, (
            finger_x,
            finger_y,
            finger_z,
            scale_x,
            scale_y,
            scale_z,
        ) in enumerate(finger_positions):
            parts.append(
                geometry.add_sphere(
                    f"finger_{side}_{finger_index}",
                    (finger_x * sign, finger_y, finger_z),
                    (scale_x, scale_y, scale_z),
                    FUR_ORANGE,
                    material,
                    f"DEF-hand.{side}",
                    segments=10,
                    rings=6,
                )
            )

    # The first phone candidate read as a round cat.  Narrow the cranium, keep
    # the eyes tall and joined, project one angular muzzle, and cut a real
    # shadowed grin so the face must read without orange fur or a black nose.
    parts.append(add_tapered_head(material))
    muzzle = geometry.add_sphere(
        "muzzle",
        (0.0, -0.190, 0.730),
        (0.198, 0.160, 0.112),
        MUZZLE_TAN,
        material,
        "DEF-spine.006",
        segments=26,
        rings=15,
    )
    carve_smile(muzzle, "DEF-spine.006")
    parts.append(muzzle)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            geometry.add_sphere(
                f"eye_mass_{side}",
                (0.058 * sign, -0.220, 0.865),
                (0.063, 0.060, 0.135),
                EYE_WHITE,
                material,
                "DEF-spine.006",
                segments=18,
                rings=10,
            )
        )
        parts.append(
            geometry.add_sphere(
                f"pupil_relief_{side}",
                (0.058 * sign, -0.292, 0.885),
                (0.024, 0.018, 0.053),
                PUPIL,
                material,
                "DEF-spine.006",
                segments=12,
                rings=7,
            )
        )
        parts.append(add_brow(side, sign, material))
        parts.append(add_ear(side, sign, material))

    parts.append(add_nose_wedge(material))
    parts.append(
        geometry.add_sphere(
            "lower_jaw",
            (0.0, -0.205, 0.635),
            (0.148, 0.095, 0.052),
            MUZZLE_TAN,
            material,
            "DEF-spine.006",
            segments=18,
            rings=10,
        )
    )
    parts.append(
        geometry.add_rounded_box(
            "mouth_cavity",
            (0.0, -0.315, 0.675),
            (0.145, 0.014, 0.055),
            MOUTH,
            material,
            "DEF-spine.006",
            bevel=0.012,
        )
    )
    for tooth_index, tooth_x in enumerate((-0.045, -0.015, 0.015, 0.045)):
        parts.append(
            geometry.add_rounded_box(
                f"tooth_{tooth_index}",
                (tooth_x, -0.326, 0.697),
                (0.027, 0.018, 0.036),
                TEETH,
                material,
                "DEF-spine.006",
                bevel=0.006,
            )
        )

    # Five points now sweep front-to-back as one narrow central tuft.  Spreading
    # them sideways made the failed candidate read as a Sonic-like crown.
    crest_points = (
        ((0.000, -0.090, 0.970), (0.000, -0.180, 1.085), 0.066),
        ((-0.020, -0.045, 1.005), (-0.035, -0.095, 1.135), 0.068),
        ((0.015, 0.000, 1.020), (0.020, -0.020, 1.115), 0.068),
        ((-0.012, 0.038, 1.010), (-0.022, 0.065, 1.085), 0.056),
        ((0.015, 0.070, 0.990), (0.025, 0.110, 1.055), 0.050),
    )
    for index, (start, end, radius) in enumerate(crest_points):
        parts.append(
            geometry.add_cone_between(
                f"crest_{index}",
                start,
                end,
                radius,
                0.006,
                FUR_DARK,
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
            (0.012 * sign, 0.000, 0.580),
            (0.140 * sign, 0.010, 0.595),
        )
        set_edit_bone(
            metarig,
            f"upper_arm.{side}",
            (0.145 * sign, 0.012, 0.595),
            (0.220 * sign, 0.018, 0.430),
        )
        set_edit_bone(
            metarig,
            f"forearm.{side}",
            (0.220 * sign, 0.018, 0.430),
            (0.250 * sign, -0.005, 0.285),
        )
        set_edit_bone(
            metarig,
            f"hand.{side}",
            (0.250 * sign, -0.005, 0.285),
            (0.275 * sign, -0.015, 0.205),
        )
        set_edit_bone(
            metarig,
            f"breast.{side}",
            (0.095 * sign, 0.035, 0.535),
            (0.095 * sign, -0.070, 0.535),
        )
        set_edit_bone(
            metarig,
            f"pelvis.{side}",
            (0.0, 0.018, 0.330),
            (0.070 * sign, -0.015, 0.380),
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
    character["likeness_stage"] = "vertex_color_candidate"
    character["idle_action"] = IDLE_ACTION_NAME
    character["core_actions"] = list(CORE_ACTION_NAMES)
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


def key_location(
    bone: bpy.types.PoseBone,
    frame: int,
    location: tuple[float, float, float],
) -> None:
    bone.location = location
    bone.keyframe_insert(data_path="location", frame=frame)


def begin_action(
    rig: bpy.types.Object,
    name: str,
    last_frame: int,
) -> bpy.types.Action:
    scene = bpy.context.scene
    scene.frame_start = IDLE_FIRST_FRAME
    scene.frame_end = last_frame
    scene.render.fps = IDLE_FPS
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action

    control_names = (
        "root",
        "torso",
        "head",
        "hips",
        "upper_arm_fk.L",
        "upper_arm_fk.R",
        "forearm_fk.L",
        "forearm_fk.R",
        "thigh_fk.L",
        "thigh_fk.R",
        "shin_fk.L",
        "shin_fk.R",
        "foot_fk.L",
        "foot_fk.R",
    )
    for control_name in control_names:
        bone = rig.pose.bones[control_name]
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)
        # Give every action a deterministic neutral value for controls that
        # the pose does not otherwise touch.  Without these bookend keys,
        # Blender keeps the previous action's unkeyed limb values during
        # validation and inspection renders.
        for frame in (IDLE_FIRST_FRAME, last_frame):
            bone.keyframe_insert(data_path="rotation_euler", frame=frame)
            bone.keyframe_insert(data_path="location", frame=frame)
    for side in ("L", "R"):
        # These actions key the FK controls.  Rigify uses 1.0 for FK; leaving
        # this at 0.0 silently keeps the limbs on their unkeyed IK controls.
        rig.pose.bones[f"upper_arm_parent.{side}"]["IK_FK"] = 1.0
        rig.pose.bones[f"thigh_parent.{side}"]["IK_FK"] = 1.0
    scene.frame_set(IDLE_FIRST_FRAME)
    return action


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
    action = begin_action(rig, IDLE_ACTION_NAME, IDLE_LAST_FRAME)

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
        key_location(
            rig.pose.bones["root"],
            frame,
            (0.0, 0.0, 0.004 * (1.0 - settle)),
        )

    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "idle", True)


def create_bored_idle(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(
        rig,
        BORED_IDLE_ACTION_NAME,
        BORED_IDLE_LAST_FRAME,
    )
    relaxed_pose = {
        "torso": (2.0, 0.0, 0.0),
        "head": (-1.0, 0.0, 0.0),
        "hips": (0.0, 0.0, 0.0),
        "thigh_fk.L": (-2.0, 0.0, -2.0),
        "thigh_fk.R": (-2.0, 0.0, 2.0),
        "shin_fk.L": (4.0, 0.0, 0.0),
        "shin_fk.R": (4.0, 0.0, 0.0),
        "foot_fk.L": (-2.0, 0.0, 0.0),
        "foot_fk.R": (-2.0, 0.0, 0.0),
        "upper_arm_fk.L": (5.0, -8.0, -2.0),
        "upper_arm_fk.R": (5.0, 8.0, 2.0),
        "forearm_fk.L": (8.0, 0.0, -3.0),
        "forearm_fk.R": (8.0, 0.0, 3.0),
    }
    poses = {
        IDLE_FIRST_FRAME: relaxed_pose,
        13: {
            "torso": (5.0, 1.0, -6.0),
            "head": (-4.0, -12.0, 8.0),
            "hips": (0.0, 0.0, 5.0),
            "thigh_fk.L": (-5.0, 0.0, -3.0),
            "thigh_fk.R": (-1.0, 0.0, 4.0),
            "shin_fk.L": (8.0, 0.0, 0.0),
            "shin_fk.R": (3.0, 0.0, 0.0),
            "foot_fk.L": (-4.0, 0.0, 0.0),
            "foot_fk.R": (-10.0, 0.0, 0.0),
            "upper_arm_fk.L": (9.0, -12.0, -5.0),
            "upper_arm_fk.R": (16.0, 12.0, 6.0),
            "forearm_fk.L": (12.0, 0.0, -4.0),
            "forearm_fk.R": (18.0, 0.0, 5.0),
        },
        25: {
            "torso": (7.0, 2.0, -8.0),
            "head": (-7.0, -15.0, 10.0),
            "hips": (0.0, 0.0, 6.0),
            "thigh_fk.L": (-6.0, 0.0, -4.0),
            "thigh_fk.R": (1.0, 0.0, 5.0),
            "shin_fk.L": (9.0, 0.0, 0.0),
            "shin_fk.R": (2.0, 0.0, 0.0),
            "foot_fk.L": (-5.0, 0.0, 0.0),
            "foot_fk.R": (8.0, 0.0, 0.0),
            "upper_arm_fk.L": (12.0, -18.0, -8.0),
            "upper_arm_fk.R": (108.0, 22.0, 20.0),
            "forearm_fk.L": (18.0, 0.0, -5.0),
            "forearm_fk.R": (92.0, 0.0, 10.0),
        },
        37: {
            "torso": (8.0, -2.0, 8.0),
            "head": (-8.0, 14.0, -10.0),
            "hips": (0.0, 0.0, -6.0),
            "thigh_fk.L": (1.0, 0.0, -5.0),
            "thigh_fk.R": (-6.0, 0.0, 4.0),
            "shin_fk.L": (2.0, 0.0, 0.0),
            "shin_fk.R": (9.0, 0.0, 0.0),
            "foot_fk.L": (7.0, 0.0, 0.0),
            "foot_fk.R": (-5.0, 0.0, 0.0),
            "upper_arm_fk.L": (15.0, -16.0, -7.0),
            "upper_arm_fk.R": (118.0, 28.0, 23.0),
            "forearm_fk.L": (20.0, 0.0, -5.0),
            "forearm_fk.R": (104.0, 0.0, 11.0),
        },
        49: {
            "torso": (4.0, -1.0, 6.0),
            "head": (-4.0, 12.0, -8.0),
            "hips": (0.0, 0.0, -4.0),
            "thigh_fk.L": (0.0, 0.0, -4.0),
            "thigh_fk.R": (-5.0, 0.0, 3.0),
            "shin_fk.L": (3.0, 0.0, 0.0),
            "shin_fk.R": (8.0, 0.0, 0.0),
            "foot_fk.L": (-2.0, 0.0, 0.0),
            "foot_fk.R": (-4.0, 0.0, 0.0),
            "upper_arm_fk.L": (38.0, -38.0, -32.0),
            "upper_arm_fk.R": (38.0, 38.0, 32.0),
            "forearm_fk.L": (48.0, 0.0, -8.0),
            "forearm_fk.R": (48.0, 0.0, 8.0),
        },
        61: {
            "torso": (3.0, 0.0, 2.0),
            "head": (-2.0, 4.0, -3.0),
            "hips": (0.0, 0.0, -2.0),
            "thigh_fk.L": (-1.0, 0.0, -3.0),
            "thigh_fk.R": (-3.0, 0.0, 3.0),
            "shin_fk.L": (3.0, 0.0, 0.0),
            "shin_fk.R": (6.0, 0.0, 0.0),
            "foot_fk.L": (-2.0, 0.0, 0.0),
            "foot_fk.R": (-3.0, 0.0, 0.0),
            "upper_arm_fk.L": (12.0, -14.0, -6.0),
            "upper_arm_fk.R": (18.0, 16.0, 7.0),
            "forearm_fk.L": (16.0, 0.0, -4.0),
            "forearm_fk.R": (20.0, 0.0, 5.0),
        },
        BORED_IDLE_LAST_FRAME: relaxed_pose,
    }
    root_locations = {
        IDLE_FIRST_FRAME: (0.0, 0.0, 0.0),
        13: (-0.012, 0.0, 0.0),
        25: (-0.018, 0.0, 0.003),
        37: (0.018, 0.0, 0.003),
        49: (0.012, 0.0, 0.0),
        61: (0.004, 0.0, 0.0),
        BORED_IDLE_LAST_FRAME: (0.0, 0.0, 0.0),
    }
    for frame, rotations in poses.items():
        key_action_pose(rig, frame, rotations, root_locations[frame])
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "personality", True)


def create_run(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, RUN_ACTION_NAME, RUN_LAST_FRAME)
    for frame in (IDLE_FIRST_FRAME, 5, 9, 13, RUN_LAST_FRAME):
        phase = math.tau * (
            (frame - IDLE_FIRST_FRAME)
            / (RUN_LAST_FRAME - IDLE_FIRST_FRAME)
        )
        stride = math.sin(phase)
        double_step = math.cos(phase * 2.0)
        for side, direction in (("L", 1.0), ("R", -1.0)):
            leg_stride = stride * direction
            key_rotation(
                rig.pose.bones[f"thigh_fk.{side}"],
                frame,
                (math.radians(44.0) * leg_stride, 0.0, 0.0),
            )
            key_rotation(
                rig.pose.bones[f"shin_fk.{side}"],
                frame,
                (
                    math.radians(14.0)
                    + math.radians(54.0) * max(-leg_stride, 0.0),
                    0.0,
                    0.0,
                ),
            )
            key_rotation(
                rig.pose.bones[f"foot_fk.{side}"],
                frame,
                (-math.radians(18.0) * leg_stride, 0.0, 0.0),
            )
            key_rotation(
                rig.pose.bones[f"upper_arm_fk.{side}"],
                frame,
                (
                    -math.radians(56.0) * leg_stride,
                    math.radians(7.0) * direction,
                    0.0,
                ),
            )
            key_rotation(
                rig.pose.bones[f"forearm_fk.{side}"],
                frame,
                (
                    math.radians(30.0)
                    + math.radians(20.0) * max(leg_stride, 0.0),
                    0.0,
                    -math.radians(12.0) * direction,
                ),
            )
        key_rotation(
            rig.pose.bones["torso"],
            frame,
            (
                math.radians(12.0)
                + math.radians(4.0) * double_step,
                0.0,
                -math.radians(10.0) * stride,
            ),
        )
        key_rotation(
            rig.pose.bones["head"],
            frame,
            (
                -math.radians(7.0) * double_step,
                0.0,
                math.radians(7.0) * stride,
            ),
        )
        key_location(
            rig.pose.bones["root"],
            frame,
            (0.0, 0.0, 0.010 * (1.0 - double_step)),
        )
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "locomotion", True)


def key_action_pose(
    rig: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
    root_location: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    for bone_name, degrees in rotations.items():
        key_rotation(
            rig.pose.bones[bone_name],
            frame,
            tuple(math.radians(value) for value in degrees),
        )
    # Translating Rigify's hips independently compresses its very short lower
    # spine B-Bones.  The resulting volume-preserving scale baked into glTF
    # stretched Crash's head by nearly 9x.  Visual offsets belong on the
    # root so every deform bone remains rigidly scaled.
    key_location(rig.pose.bones["root"], frame, root_location)


def create_crouch(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, CROUCH_ACTION_NAME, CROUCH_LAST_FRAME)
    poses = {
        1: {
            "torso": (4.0, 0.0, 0.0),
            "head": (-3.0, 0.0, 0.0),
            "thigh_fk.L": (-12.0, 0.0, -3.0),
            "thigh_fk.R": (-12.0, 0.0, 3.0),
            "shin_fk.L": (24.0, 0.0, 0.0),
            "shin_fk.R": (24.0, 0.0, 0.0),
            "foot_fk.L": (-12.0, 0.0, 0.0),
            "foot_fk.R": (-12.0, 0.0, 0.0),
            "upper_arm_fk.L": (22.0, -18.0, -2.0),
            "upper_arm_fk.R": (18.0, 18.0, 2.0),
            "forearm_fk.L": (16.0, 0.0, -5.0),
            "forearm_fk.R": (14.0, 0.0, 5.0),
        },
        7: {
            "torso": (50.0, 0.0, 0.0),
            "head": (-14.0, 0.0, 0.0),
            "thigh_fk.L": (-68.0, 0.0, -5.0),
            "thigh_fk.R": (-68.0, 0.0, 5.0),
            "shin_fk.L": (122.0, 0.0, 0.0),
            "shin_fk.R": (122.0, 0.0, 0.0),
            "foot_fk.L": (-54.0, 0.0, 0.0),
            "foot_fk.R": (-54.0, 0.0, 0.0),
            "upper_arm_fk.L": (40.0, -45.0, -3.0),
            "upper_arm_fk.R": (45.0, 40.0, 3.0),
            "forearm_fk.L": (30.0, 0.0, -6.0),
            "forearm_fk.R": (35.0, 0.0, 6.0),
        },
        CROUCH_LAST_FRAME: {
            "torso": (50.0, 0.0, 0.0),
            "head": (-14.0, 0.0, 0.0),
            "thigh_fk.L": (-68.0, 0.0, -5.0),
            "thigh_fk.R": (-68.0, 0.0, 5.0),
            "shin_fk.L": (122.0, 0.0, 0.0),
            "shin_fk.R": (122.0, 0.0, 0.0),
            "foot_fk.L": (-54.0, 0.0, 0.0),
            "foot_fk.R": (-54.0, 0.0, 0.0),
            "upper_arm_fk.L": (40.0, -45.0, -3.0),
            "upper_arm_fk.R": (45.0, 40.0, 3.0),
            "forearm_fk.L": (30.0, 0.0, -6.0),
            "forearm_fk.R": (35.0, 0.0, 6.0),
        },
    }
    for frame, rotations in poses.items():
        root_drop = -0.025 if frame != 1 else -0.015
        key_action_pose(rig, frame, rotations, (0.0, 0.0, root_drop))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "movement", False)


def create_crawl(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, CRAWL_ACTION_NAME, CRAWL_LAST_FRAME)
    low_pose = {
        "torso": (58.0, 0.0, 0.0),
        "head": (-20.0, 0.0, 0.0),
        "thigh_fk.L": (-72.0, 0.0, -6.0),
        "thigh_fk.R": (-72.0, 0.0, 6.0),
        "shin_fk.L": (120.0, 0.0, 0.0),
        "shin_fk.R": (120.0, 0.0, 0.0),
        "foot_fk.L": (-48.0, 0.0, 0.0),
        "foot_fk.R": (-48.0, 0.0, 0.0),
        "upper_arm_fk.L": (55.0, -35.0, -5.0),
        "upper_arm_fk.R": (55.0, 35.0, 5.0),
        "forearm_fk.L": (38.0, 0.0, -6.0),
        "forearm_fk.R": (38.0, 0.0, 6.0),
    }
    poses = {
        IDLE_FIRST_FRAME: low_pose,
        7: {
            "torso": (62.0, 0.0, -7.0),
            "head": (-22.0, 0.0, 6.0),
            "thigh_fk.L": (-88.0, 0.0, -12.0),
            "thigh_fk.R": (-54.0, 0.0, 10.0),
            "shin_fk.L": (98.0, 0.0, 0.0),
            "shin_fk.R": (132.0, 0.0, 0.0),
            "foot_fk.L": (-28.0, 0.0, 0.0),
            "foot_fk.R": (-58.0, 0.0, 0.0),
            "upper_arm_fk.L": (38.0, -46.0, -7.0),
            "upper_arm_fk.R": (80.0, 28.0, 7.0),
            "forearm_fk.L": (28.0, 0.0, -7.0),
            "forearm_fk.R": (52.0, 0.0, 7.0),
        },
        13: low_pose,
        19: {
            "torso": (62.0, 0.0, 7.0),
            "head": (-22.0, 0.0, -6.0),
            "thigh_fk.L": (-54.0, 0.0, -10.0),
            "thigh_fk.R": (-88.0, 0.0, 12.0),
            "shin_fk.L": (132.0, 0.0, 0.0),
            "shin_fk.R": (98.0, 0.0, 0.0),
            "foot_fk.L": (-58.0, 0.0, 0.0),
            "foot_fk.R": (-28.0, 0.0, 0.0),
            "upper_arm_fk.L": (80.0, -28.0, -7.0),
            "upper_arm_fk.R": (38.0, 46.0, 7.0),
            "forearm_fk.L": (52.0, 0.0, -7.0),
            "forearm_fk.R": (28.0, 0.0, 7.0),
        },
        CRAWL_LAST_FRAME: low_pose,
    }
    for frame, rotations in poses.items():
        root_height = 0.045 if frame in (7, 19) else -0.026
        key_action_pose(rig, frame, rotations, (0.0, 0.0, root_height))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "locomotion", True)


def create_jump(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, JUMP_ACTION_NAME, JUMP_LAST_FRAME)
    poses = {
        1: {
            "torso": (14.0, 0.0, 0.0),
            "head": (-10.0, 0.0, 0.0),
            "thigh_fk.L": (26.0, 0.0, 0.0),
            "thigh_fk.R": (26.0, 0.0, 0.0),
            "shin_fk.L": (38.0, 0.0, 0.0),
            "shin_fk.R": (38.0, 0.0, 0.0),
            "upper_arm_fk.L": (42.0, 0.0, -20.0),
            "upper_arm_fk.R": (42.0, 0.0, 20.0),
            "forearm_fk.L": (20.0, 0.0, -8.0),
            "forearm_fk.R": (20.0, 0.0, 8.0),
        },
        5: {
            "torso": (-8.0, 0.0, 0.0),
            "head": (8.0, 0.0, 0.0),
            "thigh_fk.L": (-12.0, 0.0, 0.0),
            "thigh_fk.R": (-12.0, 0.0, 0.0),
            "shin_fk.L": (5.0, 0.0, 0.0),
            "shin_fk.R": (5.0, 0.0, 0.0),
            "upper_arm_fk.L": (55.0, 0.0, -16.0),
            "upper_arm_fk.R": (55.0, 0.0, 16.0),
            "forearm_fk.L": (35.0, 0.0, -8.0),
            "forearm_fk.R": (35.0, 0.0, 8.0),
        },
        11: {
            "torso": (2.0, 0.0, -4.0),
            "head": (-4.0, 0.0, 4.0),
            "thigh_fk.L": (32.0, 0.0, -8.0),
            "thigh_fk.R": (20.0, 0.0, 8.0),
            "shin_fk.L": (42.0, 0.0, 0.0),
            "shin_fk.R": (34.0, 0.0, 0.0),
            "upper_arm_fk.L": (65.0, 0.0, -10.0),
            "upper_arm_fk.R": (65.0, 0.0, 10.0),
            "forearm_fk.L": (45.0, 0.0, -6.0),
            "forearm_fk.R": (45.0, 0.0, 6.0),
        },
        16: {
            "torso": (8.0, 0.0, 3.0),
            "head": (-6.0, 0.0, -3.0),
            "thigh_fk.L": (12.0, 0.0, 0.0),
            "thigh_fk.R": (18.0, 0.0, 0.0),
            "shin_fk.L": (20.0, 0.0, 0.0),
            "shin_fk.R": (26.0, 0.0, 0.0),
            "upper_arm_fk.L": (55.0, 0.0, -16.0),
            "upper_arm_fk.R": (55.0, 0.0, 16.0),
            "forearm_fk.L": (35.0, 0.0, -8.0),
            "forearm_fk.R": (35.0, 0.0, 8.0),
        },
        JUMP_LAST_FRAME: {
            "torso": (14.0, 0.0, 0.0),
            "head": (-10.0, 0.0, 0.0),
            "thigh_fk.L": (26.0, 0.0, 0.0),
            "thigh_fk.R": (26.0, 0.0, 0.0),
            "shin_fk.L": (38.0, 0.0, 0.0),
            "shin_fk.R": (38.0, 0.0, 0.0),
            "upper_arm_fk.L": (42.0, 0.0, -20.0),
            "upper_arm_fk.R": (42.0, 0.0, 20.0),
            "forearm_fk.L": (20.0, 0.0, -8.0),
            "forearm_fk.R": (20.0, 0.0, 8.0),
        },
    }
    for frame, rotations in poses.items():
        lift = 0.018 if frame in (5, 11) else 0.0
        key_action_pose(rig, frame, rotations, (0.0, 0.0, lift))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "airborne", False)


def create_double_jump(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(
        rig,
        DOUBLE_JUMP_ACTION_NAME,
        DOUBLE_JUMP_LAST_FRAME,
    )
    poses = {
        1: {
            "torso": (6.0, 0.0, -8.0),
            "head": (-4.0, 0.0, 6.0),
            "thigh_fk.L": (28.0, 0.0, -12.0),
            "thigh_fk.R": (18.0, 0.0, 12.0),
            "shin_fk.L": (36.0, 0.0, 0.0),
            "shin_fk.R": (30.0, 0.0, 0.0),
            "upper_arm_fk.L": (44.0, -42.0, -4.0),
            "upper_arm_fk.R": (52.0, 40.0, 4.0),
            "forearm_fk.L": (30.0, 0.0, -7.0),
            "forearm_fk.R": (36.0, 0.0, 7.0),
        },
        6: {
            "torso": (-4.0, 0.0, 10.0),
            "head": (4.0, 0.0, -8.0),
            "thigh_fk.L": (-18.0, 0.0, -24.0),
            "thigh_fk.R": (12.0, 0.0, 24.0),
            "shin_fk.L": (14.0, 0.0, 0.0),
            "shin_fk.R": (24.0, 0.0, 0.0),
            "upper_arm_fk.L": (60.0, -50.0, -4.0),
            "upper_arm_fk.R": (48.0, 48.0, 5.0),
            "forearm_fk.L": (40.0, 0.0, -7.0),
            "forearm_fk.R": (30.0, 0.0, 7.0),
        },
        12: {
            "torso": (3.0, 0.0, -9.0),
            "head": (-3.0, 0.0, 7.0),
            "thigh_fk.L": (18.0, 0.0, -18.0),
            "thigh_fk.R": (-14.0, 0.0, 18.0),
            "shin_fk.L": (26.0, 0.0, 0.0),
            "shin_fk.R": (12.0, 0.0, 0.0),
            "upper_arm_fk.L": (45.0, -46.0, -3.0),
            "upper_arm_fk.R": (60.0, 52.0, 3.0),
            "forearm_fk.L": (30.0, 0.0, -6.0),
            "forearm_fk.R": (42.0, 0.0, 6.0),
        },
        DOUBLE_JUMP_LAST_FRAME: {
            "torso": (5.0, 0.0, 0.0),
            "head": (-4.0, 0.0, 0.0),
            "thigh_fk.L": (20.0, 0.0, -5.0),
            "thigh_fk.R": (20.0, 0.0, 5.0),
            "shin_fk.L": (28.0, 0.0, 0.0),
            "shin_fk.R": (28.0, 0.0, 0.0),
            "upper_arm_fk.L": (46.0, -40.0, -3.0),
            "upper_arm_fk.R": (48.0, 40.0, 3.0),
            "forearm_fk.L": (30.0, 0.0, -6.0),
            "forearm_fk.R": (32.0, 0.0, 6.0),
        },
    }
    for frame, rotations in poses.items():
        key_action_pose(rig, frame, rotations, (0.0, 0.0, 0.016))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "airborne", False)


def create_spin(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SPIN_ACTION_NAME, SPIN_LAST_FRAME)
    for frame, sweep in ((1, -1.0), (4, 0.0), (7, 1.0), (10, 0.0), (13, -1.0)):
        key_action_pose(
            rig,
            frame,
            {
                "torso": (15.0, 8.0 * sweep, 10.0 * sweep),
                "head": (-10.0, -6.0 * sweep, -8.0 * sweep),
                "thigh_fk.L": (18.0, 0.0, -12.0),
                "thigh_fk.R": (18.0, 0.0, 12.0),
                "shin_fk.L": (28.0, 0.0, 0.0),
                "shin_fk.R": (28.0, 0.0, 0.0),
                "upper_arm_fk.L": (
                    43.0 + 11.0 * sweep,
                    -56.0 - 8.0 * sweep,
                    12.0 * sweep,
                ),
                "upper_arm_fk.R": (
                    43.0 - 11.0 * sweep,
                    56.0 - 8.0 * sweep,
                    -12.0 * sweep,
                ),
                "forearm_fk.L": (
                    27.0 + 7.0 * sweep,
                    0.0,
                    -6.0,
                ),
                "forearm_fk.R": (
                    27.0 - 7.0 * sweep,
                    0.0,
                    6.0,
                ),
            },
            (0.0, 0.0, 0.009 * (1.0 + sweep)),
        )
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "attack", True)


def create_slide(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SLIDE_ACTION_NAME, SLIDE_LAST_FRAME)
    poses = {
        1: {
            "torso": (18.0, 0.0, 0.0),
            "head": (-10.0, 0.0, 0.0),
            "thigh_fk.L": (-48.0, 0.0, -10.0),
            "thigh_fk.R": (-18.0, 0.0, 8.0),
            "shin_fk.L": (18.0, 0.0, 0.0),
            "shin_fk.R": (62.0, 0.0, 0.0),
            "foot_fk.L": (-4.0, 0.0, 0.0),
            "foot_fk.R": (-30.0, 0.0, 0.0),
            "upper_arm_fk.L": (32.0, -30.0, -3.0),
            "upper_arm_fk.R": (38.0, 26.0, 4.0),
            "forearm_fk.L": (24.0, 0.0, -6.0),
            "forearm_fk.R": (30.0, 0.0, 6.0),
        },
        5: {
            "torso": (64.0, 0.0, -6.0),
            "head": (-22.0, 0.0, 8.0),
            "thigh_fk.L": (-90.0, 0.0, -20.0),
            "thigh_fk.R": (-24.0, 0.0, 12.0),
            "shin_fk.L": (6.0, 0.0, 0.0),
            "shin_fk.R": (112.0, 0.0, 0.0),
            "foot_fk.L": (-4.0, 0.0, 0.0),
            "foot_fk.R": (-54.0, 0.0, 0.0),
            "upper_arm_fk.L": (45.0, -35.0, -3.0),
            "upper_arm_fk.R": (55.0, 35.0, 4.0),
            "forearm_fk.L": (30.0, 0.0, -7.0),
            "forearm_fk.R": (40.0, 0.0, 7.0),
        },
        12: {
            "torso": (64.0, 0.0, 5.0),
            "head": (-22.0, 0.0, -6.0),
            "thigh_fk.L": (-96.0, 0.0, -24.0),
            "thigh_fk.R": (-28.0, 0.0, 14.0),
            "shin_fk.L": (4.0, 0.0, 0.0),
            "shin_fk.R": (108.0, 0.0, 0.0),
            "foot_fk.L": (-2.0, 0.0, 0.0),
            "foot_fk.R": (-50.0, 0.0, 0.0),
            "upper_arm_fk.L": (48.0, -44.0, -2.0),
            "upper_arm_fk.R": (58.0, 32.0, 5.0),
            "forearm_fk.L": (34.0, 0.0, -7.0),
            "forearm_fk.R": (42.0, 0.0, 7.0),
        },
        SLIDE_LAST_FRAME: {
            "torso": (64.0, 0.0, 0.0),
            "head": (-22.0, 0.0, 0.0),
            "thigh_fk.L": (-88.0, 0.0, -18.0),
            "thigh_fk.R": (-30.0, 0.0, 12.0),
            "shin_fk.L": (8.0, 0.0, 0.0),
            "shin_fk.R": (104.0, 0.0, 0.0),
            "foot_fk.L": (-6.0, 0.0, 0.0),
            "foot_fk.R": (-48.0, 0.0, 0.0),
            "upper_arm_fk.L": (46.0, -40.0, -3.0),
            "upper_arm_fk.R": (54.0, 38.0, 4.0),
            "forearm_fk.L": (32.0, 0.0, -6.0),
            "forearm_fk.R": (38.0, 0.0, 6.0),
        },
    }
    for frame, rotations in poses.items():
        # Lower the root as the straight leading leg swings forward so its
        # heel skims the floor while the trailing leg stays folded underneath.
        root_drop = 0.015 if frame != 1 else -0.015
        key_action_pose(rig, frame, rotations, (0.0, 0.0, root_drop))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "movement", False)


def create_slam(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SLAM_ACTION_NAME, SLAM_LAST_FRAME)
    poses = {
        1: {
            "torso": (-12.0, 0.0, 0.0),
            "head": (10.0, 0.0, 0.0),
            "thigh_fk.L": (34.0, 0.0, -8.0),
            "thigh_fk.R": (34.0, 0.0, 8.0),
            "shin_fk.L": (42.0, 0.0, 0.0),
            "shin_fk.R": (42.0, 0.0, 0.0),
            "upper_arm_fk.L": (46.0, 0.0, -30.0),
            "upper_arm_fk.R": (46.0, 0.0, 30.0),
        },
        5: {
            "torso": (34.0, 0.0, 0.0),
            "head": (-24.0, 0.0, 0.0),
            "thigh_fk.L": (-14.0, 0.0, -6.0),
            "thigh_fk.R": (-14.0, 0.0, 6.0),
            "shin_fk.L": (8.0, 0.0, 0.0),
            "shin_fk.R": (8.0, 0.0, 0.0),
            "upper_arm_fk.L": (-64.0, 0.0, -20.0),
            "upper_arm_fk.R": (-64.0, 0.0, 20.0),
        },
        10: {
            "torso": (48.0, 0.0, -4.0),
            "head": (-34.0, 0.0, 5.0),
            "thigh_fk.L": (-20.0, 0.0, -5.0),
            "thigh_fk.R": (-20.0, 0.0, 5.0),
            "shin_fk.L": (4.0, 0.0, 0.0),
            "shin_fk.R": (4.0, 0.0, 0.0),
            "upper_arm_fk.L": (-78.0, 0.0, -14.0),
            "upper_arm_fk.R": (-78.0, 0.0, 14.0),
        },
        SLAM_LAST_FRAME: {
            "torso": (52.0, 0.0, 0.0),
            "head": (-38.0, 0.0, 0.0),
            "thigh_fk.L": (-24.0, 0.0, -4.0),
            "thigh_fk.R": (-24.0, 0.0, 4.0),
            "shin_fk.L": (2.0, 0.0, 0.0),
            "shin_fk.R": (2.0, 0.0, 0.0),
            "upper_arm_fk.L": (-84.0, 0.0, -10.0),
            "upper_arm_fk.R": (-84.0, 0.0, 10.0),
        },
    }
    for frame, rotations in poses.items():
        key_action_pose(rig, frame, rotations, (0.0, 0.0, -0.012))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "attack", False)


def create_wall_run(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, WALL_RUN_ACTION_NAME, WALL_RUN_LAST_FRAME)
    for frame in (IDLE_FIRST_FRAME, 5, 9, 13, WALL_RUN_LAST_FRAME):
        phase = math.tau * (
            (frame - IDLE_FIRST_FRAME)
            / (WALL_RUN_LAST_FRAME - IDLE_FIRST_FRAME)
        )
        stride = math.sin(phase)
        double_step = math.cos(phase * 2.0)
        for side, direction in (("L", 1.0), ("R", -1.0)):
            leg_stride = stride * direction
            key_rotation(
                rig.pose.bones[f"thigh_fk.{side}"],
                frame,
                (
                    math.radians(40.0) * leg_stride,
                    0.0,
                    math.radians(5.0) * direction,
                ),
            )
            key_rotation(
                rig.pose.bones[f"shin_fk.{side}"],
                frame,
                (
                    math.radians(20.0)
                    + math.radians(58.0) * max(-leg_stride, 0.0),
                    0.0,
                    0.0,
                ),
            )
            key_rotation(
                rig.pose.bones[f"foot_fk.{side}"],
                frame,
                (-math.radians(20.0) * leg_stride, 0.0, 0.0),
            )
            key_rotation(
                rig.pose.bones[f"upper_arm_fk.{side}"],
                frame,
                (
                    -math.radians(60.0) * leg_stride,
                    math.radians(20.0) * direction,
                    math.radians(5.0) * direction,
                ),
            )
            key_rotation(
                rig.pose.bones[f"forearm_fk.{side}"],
                frame,
                (
                    math.radians(34.0)
                    + math.radians(22.0) * max(leg_stride, 0.0),
                    0.0,
                    -math.radians(10.0) * direction,
                ),
            )
        key_rotation(
            rig.pose.bones["torso"],
            frame,
            (
                math.radians(22.0)
                + math.radians(3.0) * double_step,
                math.radians(3.0) * stride,
                -math.radians(9.0) * stride,
            ),
        )
        key_rotation(
            rig.pose.bones["head"],
            frame,
            (
                -math.radians(10.0)
                - math.radians(3.0) * double_step,
                -math.radians(2.0) * stride,
                math.radians(7.0) * stride,
            ),
        )
        key_location(
            rig.pose.bones["root"],
            frame,
            (0.0, 0.0, 0.008 * (1.0 - double_step)),
        )
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "traversal", True)


def create_grind(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, GRIND_ACTION_NAME, GRIND_LAST_FRAME)
    neutral_pose = {
        "torso": (26.0, 0.0, 0.0),
        "head": (-14.0, 0.0, 0.0),
        "thigh_fk.L": (-28.0, 0.0, -10.0),
        "thigh_fk.R": (-22.0, 0.0, 10.0),
        "shin_fk.L": (72.0, 0.0, 0.0),
        "shin_fk.R": (66.0, 0.0, 0.0),
        "foot_fk.L": (-36.0, 0.0, 0.0),
        "foot_fk.R": (-32.0, 0.0, 0.0),
        "upper_arm_fk.L": (-45.0, -20.0, 60.0),
        "upper_arm_fk.R": (-45.0, 20.0, -60.0),
        "forearm_fk.L": (20.0, 0.0, 0.0),
        "forearm_fk.R": (20.0, 0.0, 0.0),
    }
    poses = {
        1: neutral_pose,
        7: {
            "torso": (29.0, 0.0, -16.0),
            "head": (-15.0, 0.0, 12.0),
            "thigh_fk.L": (-38.0, 0.0, -17.0),
            "thigh_fk.R": (-16.0, 0.0, 8.0),
            "shin_fk.L": (84.0, 0.0, 0.0),
            "shin_fk.R": (58.0, 0.0, 0.0),
            "foot_fk.L": (-42.0, 0.0, 0.0),
            "foot_fk.R": (-28.0, 0.0, 0.0),
            "upper_arm_fk.L": (-60.0, -20.0, 75.0),
            "upper_arm_fk.R": (-30.0, 20.0, -45.0),
            "forearm_fk.L": (20.0, 0.0, 0.0),
            "forearm_fk.R": (24.0, 0.0, 0.0),
        },
        13: neutral_pose,
        19: {
            "torso": (29.0, 0.0, 16.0),
            "head": (-15.0, 0.0, -12.0),
            "thigh_fk.L": (-16.0, 0.0, -8.0),
            "thigh_fk.R": (-38.0, 0.0, 17.0),
            "shin_fk.L": (58.0, 0.0, 0.0),
            "shin_fk.R": (84.0, 0.0, 0.0),
            "foot_fk.L": (-28.0, 0.0, 0.0),
            "foot_fk.R": (-42.0, 0.0, 0.0),
            "upper_arm_fk.L": (-30.0, -20.0, 45.0),
            "upper_arm_fk.R": (-60.0, 20.0, -75.0),
            "forearm_fk.L": (24.0, 0.0, 0.0),
            "forearm_fk.R": (20.0, 0.0, 0.0),
        },
        GRIND_LAST_FRAME: neutral_pose,
    }
    for frame, rotations in poses.items():
        root_drop = -0.018 if frame in (7, 19) else -0.012
        key_action_pose(rig, frame, rotations, (0.0, 0.0, root_drop))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "traversal", True)


def create_swing(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SWING_ACTION_NAME, SWING_LAST_FRAME)
    neutral_pose = {
        "torso": (-2.0, 0.0, 0.0),
        "head": (4.0, 0.0, 0.0),
        "thigh_fk.L": (18.0, 0.0, -7.0),
        "thigh_fk.R": (18.0, 0.0, 7.0),
        "shin_fk.L": (36.0, 0.0, 0.0),
        "shin_fk.R": (36.0, 0.0, 0.0),
        "foot_fk.L": (-16.0, 0.0, 0.0),
        "foot_fk.R": (-16.0, 0.0, 0.0),
        "upper_arm_fk.L": (150.0, -20.0, -25.0),
        "upper_arm_fk.R": (150.0, 20.0, 25.0),
        "forearm_fk.L": (50.0, 0.0, 0.0),
        "forearm_fk.R": (50.0, 0.0, 0.0),
    }
    poses = {
        1: neutral_pose,
        7: {
            "torso": (-17.0, 0.0, -4.0),
            "head": (11.0, 0.0, 4.0),
            "thigh_fk.L": (-42.0, 0.0, -9.0),
            "thigh_fk.R": (-32.0, 0.0, 9.0),
            "shin_fk.L": (22.0, 0.0, 0.0),
            "shin_fk.R": (30.0, 0.0, 0.0),
            "foot_fk.L": (10.0, 0.0, 0.0),
            "foot_fk.R": (6.0, 0.0, 0.0),
            "upper_arm_fk.L": (148.0, -22.0, -25.0),
            "upper_arm_fk.R": (152.0, 18.0, 25.0),
            "forearm_fk.L": (48.0, 0.0, 0.0),
            "forearm_fk.R": (52.0, 0.0, 0.0),
        },
        13: neutral_pose,
        19: {
            "torso": (17.0, 0.0, 4.0),
            "head": (-11.0, 0.0, -4.0),
            "thigh_fk.L": (52.0, 0.0, -9.0),
            "thigh_fk.R": (42.0, 0.0, 9.0),
            "shin_fk.L": (62.0, 0.0, 0.0),
            "shin_fk.R": (54.0, 0.0, 0.0),
            "foot_fk.L": (-28.0, 0.0, 0.0),
            "foot_fk.R": (-24.0, 0.0, 0.0),
            "upper_arm_fk.L": (152.0, -18.0, -25.0),
            "upper_arm_fk.R": (148.0, 22.0, 25.0),
            "forearm_fk.L": (52.0, 0.0, 0.0),
            "forearm_fk.R": (48.0, 0.0, 0.0),
        },
        SWING_LAST_FRAME: neutral_pose,
    }
    for frame, rotations in poses.items():
        root_lift = 0.010 if frame in (7, 19) else 0.0
        key_action_pose(rig, frame, rotations, (0.0, 0.0, root_lift))
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return finish_action(action, "traversal", True)


def create_animation_set(
    rig: bpy.types.Object,
) -> dict[str, bpy.types.Action]:
    actions = {
        IDLE_ACTION_NAME: create_idle(rig),
        BORED_IDLE_ACTION_NAME: create_bored_idle(rig),
        RUN_ACTION_NAME: create_run(rig),
        CROUCH_ACTION_NAME: create_crouch(rig),
        CRAWL_ACTION_NAME: create_crawl(rig),
        JUMP_ACTION_NAME: create_jump(rig),
        DOUBLE_JUMP_ACTION_NAME: create_double_jump(rig),
        SPIN_ACTION_NAME: create_spin(rig),
        SLIDE_ACTION_NAME: create_slide(rig),
        SLAM_ACTION_NAME: create_slam(rig),
        WALL_RUN_ACTION_NAME: create_wall_run(rig),
        GRIND_ACTION_NAME: create_grind(rig),
        SWING_ACTION_NAME: create_swing(rig),
    }
    rig.animation_data.action = actions[IDLE_ACTION_NAME]
    bpy.context.scene.frame_start = IDLE_FIRST_FRAME
    bpy.context.scene.frame_end = IDLE_LAST_FRAME
    bpy.context.scene.frame_set(IDLE_FIRST_FRAME)
    return actions


def triangle_count(character: bpy.types.Object) -> int:
    return sum(
        max(len(polygon.vertices) - 2, 0)
        for polygon in character.data.polygons
    )


def evaluated_z_bounds(
    character: bpy.types.Object,
) -> tuple[float, float]:
    bpy.context.view_layer.update()
    dependency_graph = bpy.context.evaluated_depsgraph_get()
    evaluated_character = character.evaluated_get(dependency_graph)
    world_vertices = (
        evaluated_character.matrix_world @ vertex.co
        for vertex in evaluated_character.data.vertices
    )
    z_values = [vertex.z for vertex in world_vertices]
    return min(z_values), max(z_values)


def validate_action_poses(
    character: bpy.types.Object,
    rig: bpy.types.Object,
    actions: dict[str, bpy.types.Action],
) -> None:
    scene = bpy.context.scene
    hand_clearances = {
        DOUBLE_JUMP_ACTION_NAME: 0.050,
        SPIN_ACTION_NAME: 0.040,
        SLIDE_ACTION_NAME: 0.035,
        CRAWL_ACTION_NAME: 0.020,
    }
    for action_name, minimum_clearance in hand_clearances.items():
        action = actions[action_name]
        rig.animation_data.action = action
        first_frame, last_frame = (round(value) for value in action.frame_range)
        for frame in range(first_frame, last_frame + 1):
            scene.frame_set(frame)
            chest_y = rig.pose.bones["DEF-spine.003"].head.y
            for side in ("L", "R"):
                hand_y = rig.pose.bones[f"DEF-hand.{side}"].head.y
                clearance = chest_y - hand_y
                if clearance < minimum_clearance:
                    raise RuntimeError(
                        f"{action_name} frame {frame} hand {side} trails "
                        f"the chest: clearance={clearance:.4f}"
                    )

    rig.animation_data.action = actions[SWING_ACTION_NAME]
    first_frame, last_frame = (
        round(value)
        for value in actions[SWING_ACTION_NAME].frame_range
    )
    for frame in range(first_frame, last_frame + 1):
        scene.frame_set(frame)
        chest_z = rig.pose.bones["DEF-spine.003"].head.z
        for side in ("L", "R"):
            hand_z = rig.pose.bones[f"DEF-hand.{side}"].head.z
            if hand_z - chest_z < 0.100:
                raise RuntimeError(
                    f"{SWING_ACTION_NAME} frame {frame} hand {side} is "
                    f"not overhead: rise={hand_z - chest_z:.4f}"
                )

    # Scaling a short Rigify spine control previously produced an 8.7x head
    # stretch in the exported run clip.  Every authored pose must instead
    # preserve the deform skeleton's rigid unit scale.
    for action_name, action in actions.items():
        rig.animation_data.action = action
        first_frame, last_frame = (round(value) for value in action.frame_range)
        for frame in range(first_frame, last_frame + 1):
            scene.frame_set(frame)
            for bone in rig.pose.bones:
                if not bone.name.startswith("DEF-"):
                    continue
                for scale in bone.matrix.to_scale():
                    if abs(scale - 1.0) > 0.001:
                        raise RuntimeError(
                            f"{action_name} frame {frame} scales "
                            f"{bone.name} to {scale:.4f}"
                        )

    rig.animation_data.action = actions[IDLE_ACTION_NAME]
    scene.frame_set(IDLE_FIRST_FRAME)
    idle_min_z, idle_max_z = evaluated_z_bounds(character)
    low_pose_checks = (
        (CROUCH_ACTION_NAME, CROUCH_LAST_FRAME, 0.150),
        (CRAWL_ACTION_NAME, 7, 0.140),
        (CRAWL_ACTION_NAME, 19, 0.140),
        (CRAWL_ACTION_NAME, CRAWL_LAST_FRAME, 0.140),
        (SLIDE_ACTION_NAME, 5, 0.140),
        (SLIDE_ACTION_NAME, 12, 0.140),
        (SLIDE_ACTION_NAME, SLIDE_LAST_FRAME, 0.140),
    )
    for action_name, frame, required_top_drop in low_pose_checks:
        rig.animation_data.action = actions[action_name]
        scene.frame_set(frame)
        pose_min_z, pose_max_z = evaluated_z_bounds(character)
        if abs(pose_min_z - idle_min_z) > 0.035:
            raise RuntimeError(
                f"{action_name} frame {frame} sinks through the floor: "
                f"idle_min={idle_min_z:.4f} pose_min={pose_min_z:.4f} "
                f"idle_max={idle_max_z:.4f} pose_max={pose_max_z:.4f}"
            )
        if idle_max_z - pose_max_z < required_top_drop:
            raise RuntimeError(
                f"{action_name} frame {frame} is not visibly low enough: "
                f"top_drop={idle_max_z - pose_max_z:.4f}"
            )

    rig.animation_data.action = actions[IDLE_ACTION_NAME]
    scene.frame_set(IDLE_FIRST_FRAME)


def validate_asset(
    character: bpy.types.Object,
    rig: bpy.types.Object,
    actions: dict[str, bpy.types.Action],
) -> tuple[int, int, int]:
    vertices = len(character.data.vertices)
    faces = len(character.data.polygons)
    triangles = triangle_count(character)
    if not 10000 <= triangles <= 12000:
        raise RuntimeError(
            f"{ASSET_NAME} has {triangles} triangles; hero band is 10000-12000"
        )
    if len(character.data.materials) != 1:
        raise RuntimeError("Crash color pass must export one material")
    if character.data.materials[0].name != MATERIAL_NAME:
        raise RuntimeError(
            f"Crash color pass material must be named {MATERIAL_NAME}"
        )
    color_attribute = character.data.color_attributes.get(COLOR_ATTRIBUTE)
    if color_attribute is None:
        raise RuntimeError("Crash color pass has no vertex colors")
    unique_colors = {
        tuple(round(channel, 6) for channel in value.color)
        for value in color_attribute.data
    }
    if len(unique_colors) < 9:
        raise RuntimeError(
            "Crash color pass must retain at least nine readable color regions"
        )
    if not character.data.uv_layers:
        raise RuntimeError("Crash color pass has no UV map")
    if not character.vertex_groups:
        raise RuntimeError("Crash color pass has no deform weights")
    required_actions = {IDLE_ACTION_NAME, *CORE_ACTION_NAMES}
    missing_actions = sorted(required_actions - set(actions))
    if missing_actions:
        raise RuntimeError(f"Crash animation set is missing {missing_actions}")
    for action_name in required_actions:
        action = actions[action_name]
        if action.name != action_name or not action.fcurves:
            raise RuntimeError(f"{action_name} has no keyed animation data")
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
    validate_action_poses(character, rig, actions)
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
    rig.animation_data.action = bpy.data.actions[IDLE_ACTION_NAME]
    bpy.context.scene.frame_start = IDLE_FIRST_FRAME
    bpy.context.scene.frame_end = IDLE_LAST_FRAME
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
    rig.animation_data.action = bpy.data.actions[IDLE_ACTION_NAME]
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
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 16
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
            PREVIEW_ROOT / f"SK_crash_color_{view_name}.png"
        )
        bpy.ops.render.render(write_still=True)

    camera.location = views["front"]
    point_at(camera, Vector((0.0, 0.0, 0.55)))
    preview_frames = {
        BORED_IDLE_ACTION_NAME: 37,
        RUN_ACTION_NAME: 5,
        CROUCH_ACTION_NAME: 13,
        CRAWL_ACTION_NAME: 7,
        JUMP_ACTION_NAME: 11,
        DOUBLE_JUMP_ACTION_NAME: 6,
        SPIN_ACTION_NAME: 7,
        SLIDE_ACTION_NAME: 12,
        SLAM_ACTION_NAME: 10,
        WALL_RUN_ACTION_NAME: 5,
        GRIND_ACTION_NAME: 7,
        SWING_ACTION_NAME: 7,
    }
    for action_name, frame in preview_frames.items():
        rig.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(
            PREVIEW_ROOT / f"{action_name}_pose.png"
        )
        bpy.ops.render.render(write_still=True)

    # The forward leg and hanging silhouette are most legible in profile, so
    # keep dedicated checks alongside the standard front-facing action sheets.
    camera.location = views["side"]
    point_at(camera, Vector((0.0, 0.0, 0.55)))
    rig.animation_data.action = bpy.data.actions[SLIDE_ACTION_NAME]
    scene.frame_set(12)
    scene.render.filepath = str(
        PREVIEW_ROOT / f"{SLIDE_ACTION_NAME}_pose_side.png"
    )
    bpy.ops.render.render(write_still=True)

    rig.animation_data.action = bpy.data.actions[CRAWL_ACTION_NAME]
    scene.frame_set(7)
    scene.render.filepath = str(
        PREVIEW_ROOT / f"{CRAWL_ACTION_NAME}_pose_side.png"
    )
    bpy.ops.render.render(write_still=True)

    rig.animation_data.action = bpy.data.actions[SWING_ACTION_NAME]
    scene.frame_set(7)
    scene.render.filepath = str(
        PREVIEW_ROOT / f"{SWING_ACTION_NAME}_pose_side.png"
    )
    bpy.ops.render.render(write_still=True)

    rig.animation_data.action = bpy.data.actions[IDLE_ACTION_NAME]
    scene.frame_set(IDLE_FIRST_FRAME)
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
    actions = create_animation_set(rig)
    vertices, faces, triangles = validate_asset(character, rig, actions)
    save_source_and_export(character, rig)
    create_inspection_previews(character, rig)
    print(
        "CRASH_COLOR_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 "
        f"rig=rigify_basic_human animations={len(actions)}"
    )
    print(f"CRASH_COLOR_SOURCE={SOURCE_PATH}")
    print(f"CRASH_COLOR_GLB={EXPORT_PATH}")
    print(f"CRASH_COLOR_PREVIEWS={PREVIEW_ROOT}")


if __name__ == "__main__":
    main()
