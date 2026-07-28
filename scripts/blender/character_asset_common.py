"""Shared primitives for original scripted character assets.

This module is intentionally Blender-only.  It keeps the five-asset Phase 1
batch consistent without coupling any shipped runtime code to Blender.
Every generated character remains one vertex-coloured mesh, one compact
skeleton, and a set of named actions exported in a self-contained GLB.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable, Sequence

import bpy
from mathutils import Vector

COLOR_ATTRIBUTE = "COLOR_0"
FPS = 24

Color = tuple[float, float, float, float]
Point = tuple[float, float, float]
BoneSpec = tuple[str, Point, Point, str | None]


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


def configure_metric_scene() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def create_vertex_material(
    name: str,
    roughness: float = 0.8,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    vertex_color = nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = COLOR_ATTRIBUTE
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Roughness"].default_value = roughness
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
    asset_key: str,
    name: str,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    smooth: bool = True,
) -> bpy.types.Object:
    part.name = f"_{asset_key}_part_{name}"
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
    asset_key: str,
    name: str,
    location: Point,
    scale: Point,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    segments: int = 20,
    rings: int = 12,
    rotation: Point = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
        rotation=rotation,
    )
    part = bpy.context.active_object
    part.scale = scale
    return finish_part(part, asset_key, name, color, material, bone)


def add_cylinder_between(
    asset_key: str,
    name: str,
    start: Point,
    end: Point,
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
    return finish_part(part, asset_key, name, color, material, bone)


def add_cone_between(
    asset_key: str,
    name: str,
    start: Point,
    end: Point,
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
    return finish_part(part, asset_key, name, color, material, bone)


def add_rounded_box(
    asset_key: str,
    name: str,
    location: Point,
    dimensions: Point,
    color: Color,
    material: bpy.types.Material,
    bone: str,
    rotation: Point = (0.0, 0.0, 0.0),
    bevel: float = 0.015,
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
    return finish_part(
        part,
        asset_key,
        name,
        color,
        material,
        bone,
        False,
    )


def create_rig(
    rig_name: str,
    bones: Sequence[BoneSpec],
    role: str,
) -> bpy.types.Object:
    armature = bpy.data.armatures.new(f"{rig_name}_skeleton")
    rig = bpy.data.objects.new(rig_name, armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bones:
        edit_bone = armature.edit_bones.new(name)
        edit_bone.head = head
        edit_bone.tail = tail
        edit_bone.use_deform = True
        if parent is not None:
            edit_bone.parent = armature.edit_bones[parent]
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig["original_asset"] = True
    rig["asset_role"] = role
    rig["forward_axis"] = "-Y"
    rig["unit_m"] = 1.0
    return rig


def join_and_skin(
    asset_name: str,
    asset_key: str,
    role: str,
    parts: Sequence[bpy.types.Object],
    material: bpy.types.Material,
    rig: bpy.types.Object,
    action_names: Sequence[str],
) -> bpy.types.Object:
    if not parts:
        raise RuntimeError(f"{asset_name} has no mesh parts")
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    character = bpy.context.active_object
    character.name = asset_name
    character.data.name = f"{asset_name}_mesh"
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

    modifier = character.modifiers.new(
        name=f"{asset_key.title()}Deform",
        type="ARMATURE",
    )
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    character.parent = rig
    character.matrix_parent_inverse = rig.matrix_world.inverted()
    character["asset_role"] = role
    character["original_asset"] = True
    character["material_slots"] = 1
    character["actions"] = list(action_names)
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
    rotations: dict[str, Point] | None = None,
    locations: dict[str, Point] | None = None,
    scales: dict[str, Point] | None = None,
) -> None:
    rotations = rotations or {}
    locations = locations or {}
    scales = scales or {}
    for pose_bone in rig.pose.bones:
        degrees = rotations.get(pose_bone.name, (0.0, 0.0, 0.0))
        pose_bone.rotation_euler = tuple(
            math.radians(value) for value in degrees
        )
        pose_bone.location = locations.get(
            pose_bone.name,
            (0.0, 0.0, 0.0),
        )
        pose_bone.scale = scales.get(
            pose_bone.name,
            (1.0, 1.0, 1.0),
        )
        pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame)
        pose_bone.keyframe_insert(data_path="location", frame=frame)
        pose_bone.keyframe_insert(data_path="scale", frame=frame)


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


def triangle_count(character: bpy.types.Object) -> int:
    return sum(
        max(len(polygon.vertices) - 2, 0)
        for polygon in character.data.polygons
    )


def validate_asset(
    *,
    asset_name: str,
    character: bpy.types.Object,
    rig: bpy.types.Object,
    actions: dict[str, bpy.types.Action],
    action_names: Iterable[str],
    required_bones: Iterable[str],
    minimum_triangles: int,
    maximum_triangles: int,
    minimum_colors: int = 2,
) -> tuple[int, int, int]:
    vertices = len(character.data.vertices)
    faces = len(character.data.polygons)
    triangles = triangle_count(character)
    if not minimum_triangles <= triangles <= maximum_triangles:
        raise RuntimeError(
            f"{asset_name} has {triangles} triangles; "
            f"required band is {minimum_triangles}-{maximum_triangles}"
        )
    if len(character.data.materials) != 1:
        raise RuntimeError(f"{asset_name} must export one material slot")
    color_attribute = character.data.color_attributes.get(COLOR_ATTRIBUTE)
    if color_attribute is None:
        raise RuntimeError(f"{asset_name} has no authored vertex colors")
    unique_colors = {
        tuple(round(channel, 4) for channel in value.color)
        for value in color_attribute.data
    }
    if len(unique_colors) < minimum_colors:
        raise RuntimeError(
            f"{asset_name} has only {len(unique_colors)} authored colors"
        )
    if not character.data.uv_layers:
        raise RuntimeError(f"{asset_name} has no UV map")
    if not character.vertex_groups:
        raise RuntimeError(f"{asset_name} has no deform weights")
    missing_actions = sorted(set(action_names) - set(actions))
    if missing_actions:
        raise RuntimeError(
            f"{asset_name} animation set is missing {missing_actions}"
        )
    missing_bones = set(required_bones) - {
        bone.name for bone in rig.data.bones
    }
    if missing_bones:
        raise RuntimeError(
            f"{asset_name} rig is missing {sorted(missing_bones)}"
        )
    return vertices, faces, triangles


def save_source_and_export(
    *,
    source_path: Path,
    export_path: Path,
    character: bpy.types.Object,
    rig: bpy.types.Object,
) -> None:
    source_path.parent.mkdir(parents=True, exist_ok=True)
    export_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(
        filepath=str(source_path),
        check_existing=False,
    )

    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.hide_viewport = False
    rig.select_set(True)
    character.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.context.scene.frame_set(1)
    bpy.ops.export_scene.gltf(
        filepath=str(export_path),
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
    *,
    preview_path: Path,
    character: bpy.types.Object,
    rig: bpy.types.Object,
    target: Point,
    camera_location: Point,
    floor_size: float,
    poses: Sequence[tuple[str, int, str]],
    key_color: tuple[float, float, float] = (1.0, 0.68, 0.38),
) -> None:
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    rig.hide_render = False

    bpy.ops.mesh.primitive_plane_add(
        size=floor_size,
        location=(0.0, 0.0, -0.012),
    )
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.025, 0.045, 0.070, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = camera_location
    camera_data.lens = 62.0
    point_at(camera, Vector(target))
    bpy.context.scene.camera = camera

    for name, energy, size, location, color in (
        ("_preview_key", 720.0, 3.2, (-2.6, -3.0, 4.0), key_color),
        ("_preview_fill", 460.0, 2.8, (2.8, -1.2, 2.7), (0.35, 0.68, 1.0)),
        ("_preview_rim", 560.0, 2.4, (-1.4, 2.8, 3.0), (0.55, 0.88, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector(target))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.009,
        0.018,
        0.034,
        1.0,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28
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
        # These are review thumbnails, not final frames. A compact sample
        # count keeps deterministic headless asset regeneration fast enough
        # for the full character batch.
        scene.eevee.taa_render_samples = 24
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
    for action_name, frame, filename in poses:
        rig.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(preview_path.with_name(filename))
        bpy.ops.render.render(write_still=True)
    if poses:
        action_name, frame, _filename = poses[0]
        rig.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
    scene.render.filepath = str(preview_path)
    bpy.ops.render.render(write_still=True)
