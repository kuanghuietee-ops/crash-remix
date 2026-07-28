"""Build the original standard-crate model and export it for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_standard_crate.py

The editable Blender source and preview render are build artifacts. The shipping
GLB is written to assets/models/props/SM_crate_standard.glb.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = REPO_ROOT / "build/art-source/SM_crate_standard.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/props/SM_crate_standard.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SM_crate_standard.png"

ASSET_NAME = "SM_crate_standard"
MATERIAL_NAME = "M_crate_standard"
COLOR_ATTRIBUTE = "Color"

WOOD_DARK = (0.16, 0.045, 0.012, 1.0)
WOOD_PLANKS = (
    (0.52, 0.20, 0.045, 1.0),
    (0.61, 0.27, 0.060, 1.0),
    (0.47, 0.15, 0.028, 1.0),
    (0.68, 0.31, 0.075, 1.0),
)
WOOD_FRAME = (0.72, 0.34, 0.080, 1.0)
WOOD_BRACE = (0.58, 0.22, 0.038, 1.0)
IRON_DARK = (0.075, 0.050, 0.030, 1.0)

_part_index = 0


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
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
    shader.inputs["Roughness"].default_value = 0.84
    shader.inputs["Metallic"].default_value = 0.0
    output = nodes.new("ShaderNodeOutputMaterial")

    links.new(vertex_color.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def paint_mesh(mesh: bpy.types.Mesh, color: tuple[float, float, float, float]) -> None:
    attribute = mesh.color_attributes.get(COLOR_ATTRIBUTE)
    if attribute is None:
        attribute = mesh.color_attributes.new(
            name=COLOR_ATTRIBUTE,
            type="BYTE_COLOR",
            domain="CORNER",
        )
    for value in attribute.data:
        value.color = color


def add_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    color: tuple[float, float, float, float],
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel_width: float = 0.0,
) -> bpy.types.Object:
    global _part_index
    _part_index += 1
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=location,
        rotation=rotation,
    )
    part = bpy.context.active_object
    part.name = f"_crate_part_{_part_index:02d}_{name}"
    part.dimensions = dimensions
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if bevel_width > 0.0:
        bevel = part.modifiers.new(name="_edge_soften", type="BEVEL")
        bevel.width = bevel_width
        bevel.segments = 1
        bevel.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = part
        bpy.ops.object.modifier_apply(modifier=bevel.name)

    part.data.materials.append(material)
    paint_mesh(part.data, color)
    return part


def add_rivet(
    name: str,
    location: tuple[float, float, float],
    material: bpy.types.Material,
) -> bpy.types.Object:
    global _part_index
    _part_index += 1
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8,
        radius=0.024,
        depth=0.018,
        end_fill_type="NGON",
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    rivet = bpy.context.active_object
    rivet.name = f"_crate_part_{_part_index:02d}_{name}"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rivet.data.materials.append(material)
    paint_mesh(rivet.data, IRON_DARK)
    return rivet


def build_crate(material: bpy.types.Material) -> bpy.types.Object:
    parts: list[bpy.types.Object] = []

    # A dark inset core shows through the narrow plank gaps without requiring a
    # second material slot or a texture lookup.
    parts.append(
        add_box(
            "shadow_core",
            (0.0, 0.0, 0.50),
            (0.82, 0.82, 0.82),
            WOOD_DARK,
            material,
        )
    )

    plank_heights = (0.17, 0.39, 0.61, 0.83)
    front_back_tilts = (-1.2, 0.8, -0.6, 1.0)
    side_tilts = (0.7, -1.1, 0.9, -0.5)

    for face_index, y_position in enumerate((-0.443, 0.443)):
        for index, z_position in enumerate(plank_heights):
            parts.append(
                add_box(
                    f"face_{face_index}_plank_{index}",
                    ((-0.006, 0.006, -0.004, 0.004)[index], y_position, z_position),
                    (0.76, 0.045, 0.185),
                    WOOD_PLANKS[(index + face_index) % len(WOOD_PLANKS)],
                    material,
                    rotation=(0.0, math.radians(front_back_tilts[index]), 0.0),
                    bevel_width=0.004,
                )
            )

    for face_index, x_position in enumerate((-0.443, 0.443)):
        for index, z_position in enumerate(plank_heights):
            parts.append(
                add_box(
                    f"side_{face_index}_plank_{index}",
                    (x_position, (0.004, -0.005, 0.006, -0.003)[index], z_position),
                    (0.045, 0.76, 0.185),
                    WOOD_PLANKS[(index + face_index + 1) % len(WOOD_PLANKS)],
                    material,
                    rotation=(math.radians(side_tilts[index]), 0.0, 0.0),
                    bevel_width=0.004,
                )
            )

    for index, y_position in enumerate((-0.30, -0.10, 0.10, 0.30)):
        parts.append(
            add_box(
                f"lid_plank_{index}",
                (0.0, y_position, 0.963),
                (0.80, 0.18, 0.050),
                WOOD_PLANKS[(index + 2) % len(WOOD_PLANKS)],
                material,
                rotation=(0.0, 0.0, math.radians((-0.7, 0.4, -0.3, 0.6)[index])),
                bevel_width=0.004,
            )
        )

    for x_position in (-0.45, 0.45):
        for y_position in (-0.45, 0.45):
            parts.append(
                add_box(
                    "corner_post",
                    (x_position, y_position, 0.50),
                    (0.10, 0.10, 1.00),
                    WOOD_FRAME,
                    material,
                    bevel_width=0.010,
                )
            )

    for y_position in (-0.465, 0.465):
        for z_position in (0.08, 0.92):
            parts.append(
                add_box(
                    "face_frame",
                    (0.0, y_position, z_position),
                    (0.90, 0.050, 0.12),
                    WOOD_FRAME,
                    material,
                    bevel_width=0.009,
                )
            )

    for x_position in (-0.465, 0.465):
        for z_position in (0.08, 0.92):
            parts.append(
                add_box(
                    "side_frame",
                    (x_position, 0.0, z_position),
                    (0.050, 0.90, 0.12),
                    WOOD_FRAME,
                    material,
                    bevel_width=0.009,
                )
            )

    # X braces on every vertical face keep the silhouette readable as the
    # gameplay camera and look-dev turntable rotate around the crate.
    for y_position in (-0.4925, 0.4925):
        for angle in (-45.0, 45.0):
            parts.append(
                add_box(
                    "face_cross_brace",
                    (0.0, y_position, 0.50),
                    (0.94, 0.015, 0.065),
                    WOOD_BRACE,
                    material,
                    rotation=(0.0, math.radians(angle), 0.0),
                    bevel_width=0.006,
                )
            )

    for x_position in (-0.4925, 0.4925):
        for angle in (-45.0, 45.0):
            parts.append(
                add_box(
                    "side_cross_brace",
                    (x_position, 0.0, 0.50),
                    (0.015, 0.94, 0.065),
                    WOOD_BRACE,
                    material,
                    rotation=(math.radians(angle), 0.0, 0.0),
                    bevel_width=0.006,
                )
            )

    for y_position in (-0.491, 0.491):
        for x_position in (-0.39, 0.39):
            for z_position in (0.105, 0.895):
                parts.append(
                    add_rivet(
                        "frame_rivet",
                        (x_position, y_position, z_position),
                        material,
                    )
                )

    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    crate = bpy.context.active_object
    crate.name = ASSET_NAME
    crate.data.name = f"{ASSET_NAME}_mesh"
    crate.location = (0.0, 0.0, 0.0)
    crate.rotation_euler = (0.0, 0.0, 0.0)
    crate.scale = (1.0, 1.0, 1.0)
    crate["asset_role"] = "prop"
    crate["forward_axis"] = "-Y"
    crate["unit_m"] = 1.0
    crate["original_asset"] = True

    bpy.context.view_layer.objects.active = crate
    crate.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(66.0),
        island_margin=0.015,
        area_weight=0.0,
        correct_aspect=True,
        scale_to_bounds=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    crate.data.validate(verbose=True)
    crate.data.update()
    return crate


def validate_crate(crate: bpy.types.Object) -> tuple[int, int, int]:
    assert crate.name == ASSET_NAME
    assert tuple(crate.location) == (0.0, 0.0, 0.0)
    assert tuple(crate.rotation_euler) == (0.0, 0.0, 0.0)
    assert tuple(crate.scale) == (1.0, 1.0, 1.0)
    assert len(crate.data.materials) == 1
    assert crate.data.materials[0].name == MATERIAL_NAME
    assert COLOR_ATTRIBUTE in crate.data.color_attributes
    assert len(crate.data.uv_layers) == 1

    coordinates = [vertex.co for vertex in crate.data.vertices]
    minimum = Vector(
        (
            min(coordinate.x for coordinate in coordinates),
            min(coordinate.y for coordinate in coordinates),
            min(coordinate.z for coordinate in coordinates),
        )
    )
    maximum = Vector(
        (
            max(coordinate.x for coordinate in coordinates),
            max(coordinate.y for coordinate in coordinates),
            max(coordinate.z for coordinate in coordinates),
        )
    )
    tolerance = 0.0001
    assert (minimum - Vector((-0.5, -0.5, 0.0))).length < tolerance, minimum
    assert (maximum - Vector((0.5, 0.5, 1.0))).length < tolerance, maximum

    crate.data.calc_loop_triangles()
    return (
        len(crate.data.vertices),
        len(crate.data.polygons),
        len(crate.data.loop_triangles),
    )


def save_source_and_export(crate: bpy.types.Object) -> None:
    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)

    bpy.ops.object.select_all(action="DESELECT")
    crate.select_set(True)
    bpy.context.view_layer.objects.active = crate
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_PATH),
        check_existing=False,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_colors=True,
        export_attributes=True,
        export_normals=True,
        export_texcoords=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=True,
    )


def point_at(subject: bpy.types.Object, target: Vector) -> None:
    subject.rotation_euler = (target - subject.location).to_track_quat("-Z", "Y").to_euler()


def create_preview(crate: bpy.types.Object) -> None:
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.012))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.035, 0.055, 0.080, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.35, -3.10, 1.95)
    camera_data.lens = 58.0
    point_at(camera, Vector((0.0, 0.0, 0.48)))
    bpy.context.scene.camera = camera

    for name, light_type, energy, size, location, color in (
        (
            "_preview_key",
            "AREA",
            650.0,
            4.0,
            (-2.2, -3.0, 4.0),
            (1.0, 0.74, 0.50),
        ),
        (
            "_preview_fill",
            "AREA",
            420.0,
            3.0,
            (3.0, -0.8, 2.4),
            (0.45, 0.68, 1.0),
        ),
        (
            "_preview_rim",
            "AREA",
            500.0,
            2.5,
            (-1.0, 3.0, 2.8),
            (0.55, 0.78, 1.0),
        ),
    ):
        light_data = bpy.data.lights.new(name, light_type)
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 0.45)))

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
    bpy.context.view_layer.objects.active = crate
    bpy.ops.render.render(write_still=True)


def main() -> None:
    reset_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    material = create_material()
    crate = build_crate(material)
    vertices, faces, triangles = validate_crate(crate)
    save_source_and_export(crate)
    create_preview(crate)

    print(
        "CRATE_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} bounds=1.0x1.0x1.0m "
        f"materials=1 uv_maps=1"
    )
    print(f"CRATE_SOURCE={SOURCE_PATH}")
    print(f"CRATE_GLB={EXPORT_PATH}")
    print(f"CRATE_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
