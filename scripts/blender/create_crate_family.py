"""Build the six remaining original crate-family models for Godot.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_crate_family.py

The script deliberately reuses the standard crate's mesh helpers and preview
lighting so every variant shares one visual language. Editable Blender sources
and preview renders stay under build/; shipping GLBs are written to
assets/models/props/.
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy

SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))
import create_standard_crate as base


Color = tuple[float, float, float, float]


@dataclass(frozen=True)
class VariantSpec:
    slug: str
    core: Color
    planks: tuple[Color, Color, Color]
    frame: Color
    accent: Color
    rivet: Color
    metallic: float = 0.0
    roughness: float = 0.78

    @property
    def asset_name(self) -> str:
        return f"SM_crate_{self.slug}"


VARIANTS = (
    VariantSpec(
        slug="bounce",
        core=(0.018, 0.055, 0.105, 1.0),
        planks=(
            (0.060, 0.300, 0.620, 1.0),
            (0.080, 0.420, 0.780, 1.0),
            (0.120, 0.520, 0.880, 1.0),
        ),
        frame=(0.700, 0.820, 0.900, 1.0),
        accent=(0.970, 0.700, 0.080, 1.0),
        rivet=(0.025, 0.080, 0.150, 1.0),
    ),
    VariantSpec(
        slug="tnt",
        core=(0.105, 0.010, 0.006, 1.0),
        planks=(
            (0.500, 0.025, 0.018, 1.0),
            (0.700, 0.045, 0.025, 1.0),
            (0.850, 0.080, 0.035, 1.0),
        ),
        frame=(0.900, 0.580, 0.180, 1.0),
        accent=(0.990, 0.850, 0.170, 1.0),
        rivet=(0.120, 0.018, 0.010, 1.0),
    ),
    VariantSpec(
        slug="checkpoint",
        core=(0.018, 0.090, 0.035, 1.0),
        planks=(
            (0.035, 0.330, 0.120, 1.0),
            (0.055, 0.500, 0.180, 1.0),
            (0.090, 0.650, 0.250, 1.0),
        ),
        frame=(0.620, 0.850, 0.600, 1.0),
        accent=(0.940, 0.950, 0.620, 1.0),
        rivet=(0.020, 0.110, 0.045, 1.0),
    ),
    VariantSpec(
        slug="iron",
        core=(0.050, 0.060, 0.080, 1.0),
        planks=(
            (0.220, 0.250, 0.300, 1.0),
            (0.300, 0.340, 0.400, 1.0),
            (0.390, 0.430, 0.500, 1.0),
        ),
        frame=(0.570, 0.620, 0.690, 1.0),
        accent=(0.760, 0.810, 0.870, 1.0),
        rivet=(0.035, 0.040, 0.055, 1.0),
        metallic=0.72,
        roughness=0.40,
    ),
    VariantSpec(
        slug="aku",
        core=(0.110, 0.025, 0.030, 1.0),
        planks=(
            (0.610, 0.180, 0.025, 1.0),
            (0.790, 0.300, 0.035, 1.0),
            (0.910, 0.460, 0.055, 1.0),
        ),
        frame=(0.890, 0.650, 0.170, 1.0),
        accent=(0.650, 0.900, 0.910, 1.0),
        rivet=(0.160, 0.035, 0.025, 1.0),
    ),
    VariantSpec(
        slug="time",
        core=(0.010, 0.060, 0.110, 1.0),
        planks=(
            (0.025, 0.350, 0.500, 1.0),
            (0.045, 0.520, 0.700, 1.0),
            (0.090, 0.700, 0.860, 1.0),
        ),
        frame=(0.690, 0.880, 0.930, 1.0),
        accent=(0.990, 0.900, 0.300, 1.0),
        rivet=(0.020, 0.110, 0.160, 1.0),
    ),
)


def add_mark_box(
    parts: list[bpy.types.Object],
    name: str,
    u: float,
    z: float,
    width: float,
    height: float,
    angle_degrees: float,
    color: Color,
    material: bpy.types.Material,
) -> None:
    """Add the same raised mark to all four vertical faces."""
    angle = math.radians(angle_degrees)
    for face_index, face_sign in enumerate((-1.0, 1.0)):
        parts.append(
            base.add_box(
                f"{name}_front_{face_index}",
                (-face_sign * u, face_sign * 0.493, z),
                (width, 0.012, height),
                color,
                material,
                rotation=(0.0, face_sign * angle, 0.0),
            )
        )
        parts.append(
            base.add_box(
                f"{name}_side_{face_index}",
                (face_sign * 0.493, face_sign * u, z),
                (0.012, width, height),
                color,
                material,
                rotation=(face_sign * angle, 0.0, 0.0),
            )
        )


def add_face_disc(
    parts: list[bpy.types.Object],
    name: str,
    u: float,
    z: float,
    radius: float,
    color: Color,
    material: bpy.types.Material,
) -> None:
    """Add a low-poly disc to all four vertical faces."""
    for face_index, face_sign in enumerate((-1.0, 1.0)):
        base._part_index += 1
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=12,
            radius=radius,
            depth=0.012,
            end_fill_type="NGON",
            location=(u, face_sign * 0.493, z),
            rotation=(math.radians(90.0), 0.0, 0.0),
        )
        front_disc = bpy.context.active_object
        front_disc.name = (
            f"_crate_part_{base._part_index:02d}_{name}_front_{face_index}"
        )
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        front_disc.data.materials.append(material)
        base.paint_mesh(front_disc.data, color)
        parts.append(front_disc)

        base._part_index += 1
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=12,
            radius=radius,
            depth=0.012,
            end_fill_type="NGON",
            location=(face_sign * 0.493, u, z),
            rotation=(0.0, math.radians(90.0), 0.0),
        )
        side_disc = bpy.context.active_object
        side_disc.name = (
            f"_crate_part_{base._part_index:02d}_{name}_side_{face_index}"
        )
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        side_disc.data.materials.append(material)
        base.paint_mesh(side_disc.data, color)
        parts.append(side_disc)


def build_shell(
    spec: VariantSpec,
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = [
        base.add_box(
            "shadow_core",
            (0.0, 0.0, 0.50),
            (0.82, 0.82, 0.82),
            spec.core,
            material,
        )
    ]

    plank_heights = (0.24, 0.50, 0.76)
    plank_offsets = (-0.004, 0.005, -0.003)
    for face_index, face_sign in enumerate((-1.0, 1.0)):
        for plank_index, z_position in enumerate(plank_heights):
            parts.append(
                base.add_box(
                    f"face_{face_index}_plank_{plank_index}",
                    (
                        plank_offsets[plank_index],
                        face_sign * 0.444,
                        z_position,
                    ),
                    (0.78, 0.042, 0.245),
                    spec.planks[(plank_index + face_index) % len(spec.planks)],
                    material,
                    bevel_width=0.004,
                )
            )
            parts.append(
                base.add_box(
                    f"side_{face_index}_plank_{plank_index}",
                    (
                        face_sign * 0.444,
                        -plank_offsets[plank_index],
                        z_position,
                    ),
                    (0.042, 0.78, 0.245),
                    spec.planks[(plank_index + face_index + 1) % len(spec.planks)],
                    material,
                    bevel_width=0.004,
                )
            )

    for plank_index, y_position in enumerate((-0.27, 0.0, 0.27)):
        parts.append(
            base.add_box(
                f"lid_plank_{plank_index}",
                (0.0, y_position, 0.965),
                (0.80, 0.25, 0.050),
                spec.planks[(plank_index + 1) % len(spec.planks)],
                material,
                bevel_width=0.004,
            )
        )

    for x_position in (-0.45, 0.45):
        for y_position in (-0.45, 0.45):
            parts.append(
                base.add_box(
                    "corner_post",
                    (x_position, y_position, 0.50),
                    (0.10, 0.10, 1.00),
                    spec.frame,
                    material,
                    bevel_width=0.010,
                )
            )

    for face_sign in (-1.0, 1.0):
        for z_position in (0.08, 0.92):
            parts.append(
                base.add_box(
                    "face_frame",
                    (0.0, face_sign * 0.465, z_position),
                    (0.90, 0.050, 0.12),
                    spec.frame,
                    material,
                    bevel_width=0.008,
                )
            )
            parts.append(
                base.add_box(
                    "side_frame",
                    (face_sign * 0.465, 0.0, z_position),
                    (0.050, 0.90, 0.12),
                    spec.frame,
                    material,
                    bevel_width=0.008,
                )
            )

    for face_sign in (-1.0, 1.0):
        for u_position in (-0.38, 0.38):
            parts.append(
                base.add_rivet(
                    "frame_rivet",
                    (u_position, face_sign * 0.491, 0.105),
                    material,
                )
            )
            parts.append(
                base.add_rivet(
                    "frame_rivet",
                    (u_position, face_sign * 0.491, 0.895),
                    material,
                )
            )
    return parts


def decorate_bounce(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    add_mark_box(parts, "arrow_stem", 0.0, 0.43, 0.085, 0.30, 0.0, spec.accent, material)
    add_mark_box(parts, "arrow_left", -0.105, 0.66, 0.29, 0.070, -43.0, spec.accent, material)
    add_mark_box(parts, "arrow_right", 0.105, 0.66, 0.29, 0.070, 43.0, spec.accent, material)


def decorate_tnt(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    segments = (
        ("left_t_top", -0.25, 0.68, 0.18, 0.055, 0.0),
        ("left_t_stem", -0.25, 0.52, 0.052, 0.28, 0.0),
        ("n_left", -0.085, 0.52, 0.050, 0.32, 0.0),
        ("n_diagonal", 0.0, 0.52, 0.28, 0.050, -48.0),
        ("n_right", 0.085, 0.52, 0.050, 0.32, 0.0),
        ("right_t_top", 0.25, 0.68, 0.18, 0.055, 0.0),
        ("right_t_stem", 0.25, 0.52, 0.052, 0.28, 0.0),
    )
    for name, u, z, width, height, angle in segments:
        add_mark_box(
            parts,
            name,
            u,
            z,
            width,
            height,
            angle,
            spec.accent,
            material,
        )


def decorate_checkpoint(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    add_mark_box(parts, "c_top", 0.0, 0.70, 0.40, 0.070, 0.0, spec.accent, material)
    add_mark_box(parts, "c_left", -0.17, 0.52, 0.070, 0.42, 0.0, spec.accent, material)
    add_mark_box(parts, "c_bottom", 0.0, 0.34, 0.40, 0.070, 0.0, spec.accent, material)


def decorate_iron(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    add_mark_box(parts, "center_plate", 0.0, 0.52, 0.46, 0.42, 0.0, spec.accent, material)
    for u in (-0.15, 0.15):
        for z in (0.40, 0.64):
            add_face_disc(
                parts,
                "plate_bolt",
                u,
                z,
                0.038,
                spec.rivet,
                material,
            )


def decorate_aku(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    segments = (
        ("left_brow", -0.14, 0.69, 0.20, 0.050, -10.0),
        ("right_brow", 0.14, 0.69, 0.20, 0.050, 10.0),
        ("left_eye", -0.14, 0.58, 0.070, 0.120, 0.0),
        ("right_eye", 0.14, 0.58, 0.070, 0.120, 0.0),
        ("nose", 0.0, 0.47, 0.050, 0.135, 0.0),
        ("mouth", 0.0, 0.34, 0.28, 0.050, 0.0),
    )
    for name, u, z, width, height, angle in segments:
        add_mark_box(
            parts,
            name,
            u,
            z,
            width,
            height,
            angle,
            spec.accent,
            material,
        )


def decorate_time(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
    material: bpy.types.Material,
) -> None:
    add_face_disc(parts, "clock_face", 0.0, 0.52, 0.25, spec.core, material)
    add_mark_box(parts, "clock_hour", -0.045, 0.57, 0.055, 0.18, -25.0, spec.accent, material)
    add_mark_box(parts, "clock_minute", 0.075, 0.47, 0.24, 0.050, 18.0, spec.accent, material)


DECORATORS = {
    "bounce": decorate_bounce,
    "tnt": decorate_tnt,
    "checkpoint": decorate_checkpoint,
    "iron": decorate_iron,
    "aku": decorate_aku,
    "time": decorate_time,
}


def join_parts(
    parts: list[bpy.types.Object],
    spec: VariantSpec,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    crate = bpy.context.active_object
    crate.name = spec.asset_name
    crate.data.name = f"{spec.asset_name}_mesh"
    crate.location = (0.0, 0.0, 0.0)
    crate.rotation_euler = (0.0, 0.0, 0.0)
    crate.scale = (1.0, 1.0, 1.0)
    crate["asset_role"] = "prop"
    crate["crate_variant"] = spec.slug
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


def configure_base(spec: VariantSpec) -> None:
    base.ASSET_NAME = spec.asset_name
    base.MATERIAL_NAME = f"M_crate_{spec.slug}"
    base.SOURCE_PATH = base.REPO_ROOT / f"build/art-source/{spec.asset_name}.blend"
    base.EXPORT_PATH = (
        base.REPO_ROOT / f"assets/models/props/{spec.asset_name}.glb"
    )
    base.PREVIEW_PATH = base.REPO_ROOT / f"build/art-previews/{spec.asset_name}.png"
    base.IRON_DARK = spec.rivet
    base._part_index = 0


def build_variant(spec: VariantSpec) -> tuple[int, int, int]:
    base.reset_scene()
    configure_base(spec)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    material = base.create_material()
    shader = next(
        node
        for node in material.node_tree.nodes
        if node.bl_idname == "ShaderNodeBsdfPrincipled"
    )
    shader.inputs["Metallic"].default_value = spec.metallic
    shader.inputs["Roughness"].default_value = spec.roughness

    parts = build_shell(spec, material)
    DECORATORS[spec.slug](parts, spec, material)
    crate = join_parts(parts, spec)
    counts = base.validate_crate(crate)
    base.save_source_and_export(crate)
    base.create_preview(crate)
    return counts


def main() -> None:
    summaries: list[str] = []
    for spec in VARIANTS:
        vertices, faces, triangles = build_variant(spec)
        summaries.append(
            f"{spec.asset_name}:vertices={vertices},faces={faces},triangles={triangles}"
        )
        print(
            "CRATE_VARIANT_BUILD_OK "
            f"name={spec.asset_name} vertices={vertices} faces={faces} "
            f"triangles={triangles} bounds=1.0x1.0x1.0m materials=1 uv_maps=1"
        )
        print(f"CRATE_SOURCE={base.SOURCE_PATH}")
        print(f"CRATE_GLB={base.EXPORT_PATH}")
        print(f"CRATE_PREVIEW={base.PREVIEW_PATH}")
    print("CRATE_FAMILY_BUILD_OK " + " ".join(summaries))


if __name__ == "__main__":
    main()
