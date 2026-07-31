"""Build the original stand-in kart mesh and export it for Godot.

CTR R6 Task 3. Mirrors ``create_standard_crate.py``'s own shape (a static,
un-rigged prop assembled from primitive ops, one vertex-coloured material,
one draw call) rather than ``character_asset_common.py``'s skinned-rig
pipeline -- this is a stand-in tier vehicle chassis, not a character, and it
needs no skeleton or animation of its own for R6 (the rider supplies the
animation; see kart_controller.gd's own mount_character() doc).

Run from the repository root:

    blender --background --factory-startup \\
        --python scripts/blender/build_kart.py

The editable Blender source and preview render are build artifacts. The
shipping GLB is written to assets/models/karts/SM_kart.glb -- a NEW budget
category ("kart"), deliberately separate from assets/models/rideables/'s
6,000-10,000 tri creature-mount band (SK_hog): this is a low-poly graybox-
tier vehicle shell, not a creature, and belongs nowhere near that band. See
docs/art/import-export-contract.md and src/tuning/art_budget_tuning.gd for
the category this build's own measured triangle count justifies.

PALETTE. Exactly three vertex-painted colour cells, matching the task
brief's own "body/wheels/seat" language:
  - BODY  -- the visible shell (floor, nose, tail, spoiler, pontoons,
    headlight housing). Painted a light, near-neutral grey so it reads
    clearly under a runtime tint multiply.
  - WHEELS -- near-black rubber. Multiplying near-zero RGB by any tint
    colour stays near-zero, so a runtime AI-slot body tint (see
    kart_controller.gd's apply_body_tint()) recolours the shell without the
    wheels visibly shifting hue.
  - SEAT -- muted interior/trim grey, covering the seat cushion, seat back,
    dash, steering-wheel plate, roll bar and exhaust. Also dark enough to
    resist an obvious tint shift, so a runtime recolour reads as "the car
    changed colour", not "everything on it changed colour".
This is a deliberate substitute for the environment kit's shared UV-atlas
palette (env_kit_palette.py/env_kit_common.py): that machinery exists so
MANY pieces can share ONE draw call's worth of texture, which is not this
asset's problem (it is a single, standalone mesh). The character/prop
precedent (vertex colour, one material, one slot) is the correct fit here,
and the post-import script (scripts/godot/enable_vertex_color_albedo.gd,
already wired to every character/rideable/prop .glb.import in this repo)
is what turns the vertex colour on at runtime.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATH = REPO_ROOT / "build/art-source/SM_kart.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/karts/SM_kart.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SM_kart.png"

ASSET_NAME = "SM_kart"
MATERIAL_NAME = "M_kart_body"
COLOR_ATTRIBUTE = "Color"

# --- palette (see module docstring) -------------------------------------
BODY = (0.80, 0.80, 0.83, 1.0)
WHEEL = (0.045, 0.040, 0.042, 1.0)
SEAT = (0.16, 0.15, 0.17, 1.0)

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
    shader.inputs["Roughness"].default_value = 0.82
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
) -> bpy.types.Object:
    global _part_index
    _part_index += 1
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    part = bpy.context.active_object
    part.name = f"_kart_part_{_part_index:02d}_{name}"
    part.dimensions = dimensions
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    part.data.materials.append(material)
    paint_mesh(part.data, color)
    return part


WHEEL_SIDES = 10


def add_wheel(
    name: str,
    x: float,
    y: float,
    ground_z: float,
    radius: float,
    width: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    """A wheel: a cylinder built along Blender's default +Z axis, then laid
    on its side (rotated 90 degrees about Y) so its rolling axis runs along
    world X -- the kart's lateral axis, matching a real axle.

    ``primitive_cylinder_add`` starts its first side vertex at a half-segment
    offset from the axis (not at angle 0), so the polygon's true lowest point
    is the cylinder's APOTHEM (radius * cos(pi/sides)), not its radius. The
    vertical centre is placed at ground_z + that apothem, not ground_z +
    radius, so the wheel's actual lowest vertex -- not just its nominal
    radius -- touches ground_z exactly (proven by validate_kart()'s own
    ground-contact assertion).
    """
    global _part_index
    _part_index += 1
    apothem = radius * math.cos(math.pi / WHEEL_SIDES)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=WHEEL_SIDES,
        radius=radius,
        depth=width,
        location=(x, y, ground_z + apothem),
        rotation=(0.0, math.radians(90.0), 0.0),
    )
    part = bpy.context.active_object
    part.name = f"_kart_part_{_part_index:02d}_{name}"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    part.data.materials.append(material)
    paint_mesh(part.data, WHEEL)
    return part


def add_post(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    height: float,
    material: bpy.types.Material,
    color: tuple[float, float, float, float] = SEAT,
) -> bpy.types.Object:
    """A short vertical post (roll-bar upright, exhaust stub): a plain
    Z-axis cylinder, no rotation needed."""
    global _part_index
    _part_index += 1
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=6,
        radius=radius,
        depth=height,
        location=(location[0], location[1], location[2] + height / 2.0),
    )
    part = bpy.context.active_object
    part.name = f"_kart_part_{_part_index:02d}_{name}"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    part.data.materials.append(material)
    paint_mesh(part.data, color)
    return part


def build_kart(material: bpy.types.Material) -> bpy.types.Object:
    parts: list[bpy.types.Object] = []

    # --- body shell (tintable) -------------------------------------
    parts.append(add_box("floor", (0.0, 0.05, 0.20), (1.00, 1.55, 0.28), BODY, material))
    parts.append(add_box("nose_mid", (0.0, -0.68, 0.22), (0.85, 0.35, 0.26), BODY, material))
    parts.append(add_box("nose_tip", (0.0, -0.92, 0.20), (0.55, 0.22, 0.20), BODY, material))
    parts.append(add_box("headlight", (0.0, -0.95, 0.26), (0.50, 0.08, 0.10), BODY, material))
    parts.append(add_box("tail", (0.0, 0.78, 0.22), (0.85, 0.35, 0.26), BODY, material))
    parts.append(add_box("spoiler", (0.0, 0.92, 0.42), (0.90, 0.08, 0.16), BODY, material))
    parts.append(add_box("pontoon_l", (-0.58, 0.05, 0.22), (0.22, 1.30, 0.24), BODY, material))
    parts.append(add_box("pontoon_r", (0.58, 0.05, 0.22), (0.22, 1.30, 0.24), BODY, material))

    # --- seat / interior / trim (kept dark -- see module docstring) ------
    parts.append(add_box("seat_cushion", (0.0, 0.05, 0.34), (0.50, 0.42, 0.10), SEAT, material))
    parts.append(add_box("seat_back", (0.0, 0.30, 0.46), (0.50, 0.14, 0.36), SEAT, material))
    parts.append(add_box("dash", (0.0, -0.42, 0.42), (0.14, 0.10, 0.30), SEAT, material))
    parts.append(
        add_box(
            "wheel_plate",
            (0.0, -0.48, 0.56),
            (0.26, 0.05, 0.22),
            SEAT,
            material,
            rotation=(math.radians(-18.0), 0.0, 0.0),
        )
    )
    parts.append(add_post("rollbar_l", (-0.24, 0.34, 0.46), 0.035, 0.30, material))
    parts.append(add_post("rollbar_r", (0.24, 0.34, 0.46), 0.035, 0.30, material))
    parts.append(add_box("rollbar_bar", (0.0, 0.34, 0.76), (0.50, 0.06, 0.06), SEAT, material))
    # Kept well clear of the rear-right wheel (centre (0.60, 0.62), radius
    # 0.27) -- an earlier placement close to the wheel's own footprint
    # visibly z-fought with it in the preview render.
    parts.append(add_post("exhaust", (0.50, 0.98, 0.16), 0.05, 0.22, material))

    # --- wheels (fixed, never tintable) -----------------------------
    # wheel_x's inner face (wheel_x - wheel_width/2) is kept clear of the
    # pontoons' own outer face (0.58 + 0.22/2 = 0.69) -- an earlier, narrower
    # wheel_x sat the wheel INSIDE the pontoon box instead of outside it,
    # which z-fought visibly in the preview render.
    wheel_radius = 0.27
    wheel_width = 0.18
    wheel_x = 0.80
    front_y = -0.62
    rear_y = 0.62
    for name, x, y in (
        ("wheel_fl", -wheel_x, front_y),
        ("wheel_fr", wheel_x, front_y),
        ("wheel_rl", -wheel_x, rear_y),
        ("wheel_rr", wheel_x, rear_y),
    ):
        parts.append(
            add_wheel(name, x, y, 0.0, wheel_radius, wheel_width, material)
        )

    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    kart = bpy.context.active_object
    kart.name = ASSET_NAME
    kart.data.name = f"{ASSET_NAME}_mesh"
    kart.location = (0.0, 0.0, 0.0)
    kart.rotation_euler = (0.0, 0.0, 0.0)
    kart.scale = (1.0, 1.0, 1.0)
    kart["asset_role"] = "rideable_vehicle"
    kart["forward_axis"] = "-Y"
    kart["unit_m"] = 1.0
    kart["original_asset"] = True

    bpy.context.view_layer.objects.active = kart
    kart.select_set(True)
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

    kart.data.validate(verbose=True)
    kart.data.update()
    return kart


def validate_kart(kart: bpy.types.Object) -> tuple[int, int, int]:
    assert kart.name == ASSET_NAME
    assert tuple(kart.location) == (0.0, 0.0, 0.0)
    assert tuple(kart.rotation_euler) == (0.0, 0.0, 0.0)
    assert tuple(kart.scale) == (1.0, 1.0, 1.0)
    assert len(kart.data.materials) == 1
    assert kart.data.materials[0].name == MATERIAL_NAME
    assert COLOR_ATTRIBUTE in kart.data.color_attributes
    assert len(kart.data.uv_layers) == 1

    coordinates = [vertex.co for vertex in kart.data.vertices]
    minimum = Vector(
        (
            min(coordinate.x for coordinate in coordinates),
            min(coordinate.y for coordinate in coordinates),
            min(coordinate.z for coordinate in coordinates),
        )
    )
    # Ground contact: the wheels' own lowest point must sit at Z=0 (the
    # import/export contract's "origin at the prop's resting contact
    # point"), so this asset needs no vertical offset when instanced under
    # kart.tscn's Kart body (whose own collision floor is already Z=0).
    tolerance = 0.0005
    assert abs(minimum.z) < tolerance, minimum

    kart.data.calc_loop_triangles()
    return (
        len(kart.data.vertices),
        len(kart.data.polygons),
        len(kart.data.loop_triangles),
    )


def save_source_and_export(kart: bpy.types.Object) -> None:
    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH), check_existing=False)

    bpy.ops.object.select_all(action="DESELECT")
    kart.select_set(True)
    bpy.context.view_layer.objects.active = kart
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


def create_preview(kart: bpy.types.Object) -> None:
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, -0.005))
    floor = bpy.context.active_object
    floor.name = "_preview_floor"
    floor_material = bpy.data.materials.new("_preview_floor_material")
    floor_material.diffuse_color = (0.035, 0.055, 0.080, 1.0)
    floor.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("_preview_camera")
    camera = bpy.data.objects.new("_preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.35, -3.10, 1.55)
    camera_data.lens = 58.0
    point_at(camera, Vector((0.0, 0.0, 0.32)))
    bpy.context.scene.camera = camera

    for name, light_type, energy, size, location, color in (
        ("_preview_key", "AREA", 650.0, 4.0, (-2.2, -3.0, 4.0), (1.0, 0.74, 0.50)),
        ("_preview_fill", "AREA", 420.0, 3.0, (3.0, -0.8, 2.4), (0.45, 0.68, 1.0)),
        ("_preview_rim", "AREA", 500.0, 2.5, (-1.0, 3.0, 2.8), (0.55, 0.78, 1.0)),
    ):
        light_data = bpy.data.lights.new(name, light_type)
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 0.30)))

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.022, 0.040, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.30

    scene = bpy.context.scene
    render_engines = {
        item.identifier
        for item in scene.bl_rna.properties["render"].fixed_type.properties["engine"].enum_items
    }
    scene.render.engine = (
        "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in render_engines else "BLENDER_EEVEE"
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
    bpy.context.view_layer.objects.active = kart
    bpy.ops.render.render(write_still=True)


def main() -> None:
    reset_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    material = create_material()
    kart = build_kart(material)
    vertices, faces, triangles = validate_kart(kart)
    save_source_and_export(kart)
    create_preview(kart)

    print(
        "KART_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 uv_maps=1"
    )
    print(f"KART_SOURCE={SOURCE_PATH}")
    print(f"KART_GLB={EXPORT_PATH}")
    print(f"KART_PREVIEW={PREVIEW_PATH}")


if __name__ == "__main__":
    main()
