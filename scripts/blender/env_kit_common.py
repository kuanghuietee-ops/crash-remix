"""Shared Blender helpers for the environment kit generators.

Environment art only. This module knows nothing about characters, gameplay
objects or rigging -- it builds static, hand-authored props out of primitive
operations so every byte of the kit is original to this project.

Two conventions matter and are easy to get wrong:

*Colour space.* Blender's Principled base colour is **linear**; Godot's
``StandardMaterial3D.albedo_color`` is displayed and authored in **sRGB**.
The palette below is written in sRGB so it can be read against the sRGB
colours already authored into ``scenes/segments/beach_*.tscn``, and is
converted on the way into Blender. Skipping that conversion is the classic
"why is my sand washed out" bug.

*Up axis.* Build with Blender's Z-up convention. The glTF exporter's default
``export_yup`` rotates into Godot's Y-up on the way out, so a prop modelled
standing on the Blender XY plane arrives standing on Godot's XZ plane.
"""

from __future__ import annotations

import math
import random
from typing import Iterable, Sequence

import bmesh
import bpy
import mathutils


# --- palette -----------------------------------------------------------
# sRGB, deliberately keyed to the graybox floor colours already authored in
# the beach segments so the dressing and the play surface read as one place.

PALETTE: dict[str, tuple[float, float, float]] = {
    "sand_light": (0.87, 0.78, 0.57),
    "sand_mid": (0.76, 0.63, 0.40),
    "sand_wet": (0.58, 0.48, 0.33),
    "rock_light": (0.63, 0.61, 0.56),
    "rock_mid": (0.47, 0.45, 0.43),
    "rock_dark": (0.32, 0.31, 0.30),
    "rock_warm": (0.56, 0.46, 0.34),
    "leaf_light": (0.52, 0.70, 0.29),
    "leaf_mid": (0.30, 0.52, 0.24),
    "leaf_dark": (0.17, 0.34, 0.18),
    "frond": (0.37, 0.59, 0.26),
    "trunk": (0.45, 0.33, 0.22),
    "trunk_dark": (0.31, 0.23, 0.16),
    "driftwood": (0.66, 0.60, 0.52),
    # Distance tones. There is no fog on this level -- the level scene owns
    # the WorldEnvironment -- so aerial perspective is faked by desaturating
    # far-away pieces toward the sky colour instead.
    "rock_haze": (0.44, 0.54, 0.63),
    "rock_haze_dark": (0.34, 0.45, 0.56),
    "leaf_haze": (0.35, 0.50, 0.50),
    "water_shallow": (0.30, 0.67, 0.70),
    "water_deep": (0.13, 0.42, 0.58),
    "foam": (0.88, 0.94, 0.95),
    "coconut": (0.38, 0.26, 0.17),
    "shell": (0.92, 0.86, 0.78),
    "flower": (0.92, 0.44, 0.31),
}


def srgb_to_linear(channel: float) -> float:
    """Convert one sRGB channel to the linear value Blender expects."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def reset_scene() -> None:
    """Start from a guaranteed-empty file so pieces cannot leak into each other."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str) -> bpy.types.Material:
    """Fetch or create the palette material called ``name``."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    if name not in PALETTE:
        raise KeyError(f"{name!r} is not in the environment palette")
    red, green, blue = PALETTE[name]
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    shader = made.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (
        srgb_to_linear(red),
        srgb_to_linear(green),
        srgb_to_linear(blue),
        1.0,
    )
    shader.inputs["Roughness"].default_value = 0.92
    shader.inputs["Metallic"].default_value = 0.0
    made.diffuse_color = (
        srgb_to_linear(red),
        srgb_to_linear(green),
        srgb_to_linear(blue),
        1.0,
    )
    return made


class Piece:
    """A single kit mesh under construction.

    Wraps a bmesh plus the ordered material slot list, and hands out slot
    indices by palette name so builders never juggle raw integers.
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self.bm = bmesh.new()
        self._slots: list[str] = []

    def slot(self, palette_name: str) -> int:
        """Index of ``palette_name`` in this piece's material slots."""
        if palette_name not in self._slots:
            self._slots.append(palette_name)
        return self._slots.index(palette_name)

    def paint(self, faces: Iterable[bmesh.types.BMFace], palette_name: str) -> None:
        index = self.slot(palette_name)
        for face in faces:
            face.material_index = index
            face.smooth = False

    def new_faces(self, before: set[bmesh.types.BMFace]) -> list[bmesh.types.BMFace]:
        self.bm.faces.ensure_lookup_table()
        return [face for face in self.bm.faces if face not in before]

    def snapshot(self) -> set[bmesh.types.BMFace]:
        self.bm.faces.ensure_lookup_table()
        return set(self.bm.faces)

    def rotate_x(self, angle: float) -> None:
        """Spin the whole piece about the X axis, in place.

        Lets builders model along the convenient axis (columns grow up Z)
        and then lay the result down, e.g. a driftwood log.
        """
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for vert in self.bm.verts:
            y, z = vert.co.y, vert.co.z
            vert.co.y = y * cos_a - z * sin_a
            vert.co.z = y * sin_a + z * cos_a

    def translate(self, dx: float, dy: float, dz: float) -> None:
        """Shift the whole piece, in place."""
        for vert in self.bm.verts:
            vert.co.x += dx
            vert.co.y += dy
            vert.co.z += dz

    def finish(self) -> bpy.types.Object:
        """Bake the bmesh into a real object with its material slots attached."""
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for palette_name in self._slots:
            mesh.materials.append(material(palette_name))
        for polygon in mesh.polygons:
            polygon.use_smooth = False
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


# --- geometry primitives ------------------------------------------------


def add_box(
    piece: Piece,
    center: Sequence[float],
    size: Sequence[float],
    palette_name: str,
    *,
    rotation_z: float = 0.0,
    taper: float = 1.0,
) -> None:
    """Axis-aligned box, optionally tapered toward its top and spun about Z."""
    half_x, half_y, half_z = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    lower = [
        (-half_x, -half_y, -half_z),
        (half_x, -half_y, -half_z),
        (half_x, half_y, -half_z),
        (-half_x, half_y, -half_z),
    ]
    upper = [
        (x * taper, y * taper, half_z)
        for x, y, _ in lower
    ]
    before = piece.snapshot()
    cos_z, sin_z = math.cos(rotation_z), math.sin(rotation_z)
    verts = []
    for x, y, z in lower + upper:
        spun_x = x * cos_z - y * sin_z
        spun_y = x * sin_z + y * cos_z
        verts.append(
            piece.bm.verts.new(
                (center[0] + spun_x, center[1] + spun_y, center[2] + z)
            )
        )
    piece.bm.verts.ensure_lookup_table()
    quads = (
        (0, 1, 2, 3),
        (7, 6, 5, 4),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    )
    for a, b, c, d in quads:
        piece.bm.faces.new((verts[a], verts[b], verts[c], verts[d]))
    piece.paint(piece.new_faces(before), palette_name)


def add_cylinder(
    piece: Piece,
    base: Sequence[float],
    height: float,
    radius_base: float,
    radius_top: float,
    palette_name: str,
    *,
    sides: int = 7,
    lean: Sequence[float] = (0.0, 0.0),
    bend: float = 0.0,
    rings: int = 4,
) -> tuple[float, float, float]:
    """A tapered, optionally curved column. Returns the centre of its top cap.

    ``lean`` is the total XY offset accumulated from base to tip; ``bend``
    adds a quadratic droop on top of that so trunks curve instead of shearing.
    """
    before = piece.snapshot()
    rows: list[list[bmesh.types.BMVert]] = []
    for ring in range(rings + 1):
        along = ring / rings
        radius = radius_base + (radius_top - radius_base) * along
        curve = along * along
        offset_x = lean[0] * along + bend * curve
        offset_y = lean[1] * along
        row = []
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            row.append(
                piece.bm.verts.new(
                    (
                        base[0] + offset_x + math.cos(angle) * radius,
                        base[1] + offset_y + math.sin(angle) * radius,
                        base[2] + height * along,
                    )
                )
            )
        rows.append(row)
    piece.bm.verts.ensure_lookup_table()
    for ring in range(rings):
        low, high = rows[ring], rows[ring + 1]
        for side in range(sides):
            nxt = (side + 1) % sides
            piece.bm.faces.new((low[side], low[nxt], high[nxt], high[side]))
    piece.bm.faces.new(tuple(reversed(rows[0])))
    piece.bm.faces.new(tuple(rows[-1]))
    piece.paint(piece.new_faces(before), palette_name)
    tip_x = base[0] + lean[0] + bend
    tip_y = base[1] + lean[1]
    return (tip_x, tip_y, base[2] + height)


def add_rock(
    piece: Piece,
    center: Sequence[float],
    radius: float,
    palette_name: str,
    rng: random.Random,
    *,
    subdivisions: int = 1,
    jitter: float = 0.34,
    squash: float = 0.72,
    sink: float = 0.35,
) -> None:
    """A faceted boulder: an icosphere pushed around per-vertex, then squashed.

    ``sink`` drops the ball so its lower cap sits under y=0 and the piece
    reads as embedded in the ground rather than resting on it.
    """
    before_verts = set(piece.bm.verts)
    before = piece.snapshot()
    bmesh.ops.create_icosphere(
        piece.bm,
        subdivisions=subdivisions,
        radius=radius,
        matrix=mathutils.Matrix.Identity(4),
    )
    piece.bm.verts.ensure_lookup_table()
    for vert in piece.bm.verts:
        if vert in before_verts:
            continue
        scale = 1.0 + rng.uniform(-jitter, jitter)
        vert.co.x = center[0] + vert.co.x * scale
        vert.co.y = center[1] + vert.co.y * scale
        vert.co.z = center[2] + vert.co.z * scale * squash - radius * sink
    piece.paint(piece.new_faces(before), palette_name)


def add_blade(
    piece: Piece,
    base: Sequence[float],
    direction: float,
    length: float,
    width: float,
    palette_name: str,
    *,
    segments: int = 4,
    rise: float = 0.55,
    droop: float = 0.9,
    tilt: float = 0.0,
) -> None:
    """An arching leaf/frond blade: a tapering ribbon that lifts then falls.

    Used for palm fronds, ferns and grass alike -- the difference between
    them is entirely in the length/width/droop numbers the callers pass.
    """
    before = piece.snapshot()
    cos_d, sin_d = math.cos(direction), math.sin(direction)
    left: list[bmesh.types.BMVert] = []
    right: list[bmesh.types.BMVert] = []
    for step in range(segments + 1):
        along = step / segments
        reach = length * along
        height = rise * length * along - droop * length * along * along
        half = width * 0.5 * (1.0 - along * along * 0.85)
        if step == 0:
            half *= 0.45
        spine_x = base[0] + cos_d * reach
        spine_y = base[1] + sin_d * reach
        spine_z = base[2] + height
        fold = tilt * along * length * 0.25
        left.append(
            piece.bm.verts.new(
                (spine_x - sin_d * half, spine_y + cos_d * half, spine_z - fold)
            )
        )
        right.append(
            piece.bm.verts.new(
                (spine_x + sin_d * half, spine_y - cos_d * half, spine_z - fold)
            )
        )
    piece.bm.verts.ensure_lookup_table()
    for step in range(segments):
        piece.bm.faces.new(
            (left[step], right[step], right[step + 1], left[step + 1])
        )
    piece.paint(piece.new_faces(before), palette_name)


def add_height_grid(
    piece: Piece,
    origin: Sequence[float],
    span_x: float,
    span_y: float,
    cells_x: int,
    cells_y: int,
    height_fn,
    palette_fn,
) -> None:
    """A quad grid whose corner heights and per-quad palette come from callbacks.

    ``height_fn(u, v)`` and ``palette_fn(u, v)`` both take normalised 0..1
    coordinates; this is how terrain shelves, dune ridges and the sea tile are
    all built from one routine.
    """
    before = piece.snapshot()
    grid: list[list[bmesh.types.BMVert]] = []
    for ix in range(cells_x + 1):
        u = ix / cells_x
        column = []
        for iy in range(cells_y + 1):
            v = iy / cells_y
            column.append(
                piece.bm.verts.new(
                    (
                        origin[0] + span_x * u,
                        origin[1] + span_y * v,
                        origin[2] + height_fn(u, v),
                    )
                )
            )
        grid.append(column)
    piece.bm.verts.ensure_lookup_table()
    for ix in range(cells_x):
        for iy in range(cells_y):
            face = piece.bm.faces.new(
                (
                    grid[ix][iy],
                    grid[ix + 1][iy],
                    grid[ix + 1][iy + 1],
                    grid[ix][iy + 1],
                )
            )
            face.smooth = False
            face.material_index = piece.slot(
                palette_fn((ix + 0.5) / cells_x, (iy + 0.5) / cells_y)
            )
    _ = before


def export_glb(path: str) -> None:
    """Write every object in the current scene out as one binary glTF."""
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_yup=True,
    )
