"""Shared Blender helpers for the environment kit generators.

Environment art only. This module knows nothing about characters, gameplay
objects or rigging -- it builds static, hand-authored props out of primitive
operations so every byte of the kit is original to this project.

Two conventions matter and are easy to get wrong:

*Colour comes from UVs, not slots.* Each piece carries exactly one material and
one UV layer. ``paint()`` still takes a palette name, but instead of adding a
material slot it maps the face into that colour's cell of the shared atlas
(``env_kit_palette``). One slot per piece is what design doc 9.4's 120-draw-call
budget needs, and it is why the kit can carry hand-painted grain at all.

*Colour space.* Blender's Principled base colour is **linear**; Godot's
``StandardMaterial3D.albedo_color`` is displayed and authored in **sRGB**. The
palette is written in sRGB so it can be read against the sRGB colours already
authored into ``scenes/segments/beach_*.tscn``. The kit material itself is
white, because the atlas -- not the material -- now carries the colour; tinting
it would multiply the palette in twice.

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

from env_kit_palette import (  # noqa: F401  (PALETTE re-exported for builders)
    PALETTE,
    atlas_uv_rect,
    face_window,
    projection_axes,
    srgb_to_linear,
    trim_uv_rect,
)

# The two shipping materials. Which one a piece gets decides which texture the
# Godot import script hangs on it, so these names are load-bearing and are
# asserted by tests/integration/test_kit_materials.gd.
ATLAS_MATERIAL = "M_beach_kit_atlas"
TRIM_MATERIAL = "M_beach_kit_trim"


def reset_scene() -> None:
    """Start from a guaranteed-empty file so pieces cannot leak into each other."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str) -> bpy.types.Material:
    """Fetch or create one of the kit's two shipping materials.

    Deliberately white and untextured on the Blender side. The atlas is not
    embedded in the ``.glb`` -- twenty-five copies of a 2 MB texture in a public
    repo's history is not a trade worth making -- so the texture is attached at
    import time by ``scripts/godot/apply_kit_atlas_material.gd``, keyed on the
    material name below.
    """
    if name not in (ATLAS_MATERIAL, TRIM_MATERIAL):
        raise KeyError(
            f"{name!r} is not a kit material; expected one of "
            f"{ATLAS_MATERIAL!r} or {TRIM_MATERIAL!r}"
        )
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    shader = made.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    shader.inputs["Roughness"].default_value = 0.92
    shader.inputs["Metallic"].default_value = 0.0
    made.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    return made


class Piece:
    """A single kit mesh under construction.

    Wraps a bmesh and a UV layer. Builders still say "paint these faces sand" and
    never touch UVs or slots; the piece turns that into a rectangle of the shared
    atlas, so the finished mesh has exactly one material.

    Set ``uses_trim`` before painting to route a piece onto the strata trim sheet
    instead. Only the rock family has bands, and asking for anything else raises
    rather than quietly falling back.
    """

    def __init__(self, name: str, uses_trim: bool = False) -> None:
        self.name = name
        self.bm = bmesh.new()
        self.uses_trim = uses_trim
        self.uv_layer = self.bm.loops.layers.uv.verify()
        # Advances once per painted face so two faces of the same colour land on
        # different patches of grain. Deterministic, so re-running the build
        # still writes byte-identical files.
        self._face_serial = 0

    @property
    def material_name(self) -> str:
        return TRIM_MATERIAL if self.uses_trim else ATLAS_MATERIAL

    def uv_rect(self, palette_name: str) -> tuple[float, float, float, float]:
        if self.uses_trim:
            return trim_uv_rect(palette_name)
        return atlas_uv_rect(palette_name)

    def paint(self, faces: Iterable[bmesh.types.BMFace], palette_name: str) -> None:
        rect = self.uv_rect(palette_name)
        for face in faces:
            face.material_index = 0
            face.smooth = False
            self._map_face(face, rect)

    def _map_face(
        self, face: bmesh.types.BMFace, rect: tuple[float, float, float, float]
    ) -> None:
        """Flatten one face onto its dominant plane and fit it into ``rect``."""
        u0, v0, u1, v1 = rect
        first, second = projection_axes(face.normal)
        coords = [(vert.co[first], vert.co[second]) for vert in face.verts]
        min_a = min(coord[0] for coord in coords)
        max_a = max(coord[0] for coord in coords)
        min_b = min(coord[1] for coord in coords)
        max_b = max(coord[1] for coord in coords)
        span_a = max_a - min_a
        span_b = max_b - min_b

        if self.uses_trim:
            # Strata have to run the full height of the band or the layering the
            # trim sheet exists for is lost, so trim faces fill their rectangle.
            window_u0, window_v0, window_u1, window_v1 = u0, v0, u1, v1
        else:
            window_u0, window_v0, window_u1, window_v1 = face_window(
                rect, self._face_serial
            )
        self._face_serial += 1

        for loop, (a, b) in zip(face.loops, coords):
            fraction_a = 0.5 if span_a <= 0.0 else (a - min_a) / span_a
            fraction_b = 0.5 if span_b <= 0.0 else (b - min_b) / span_b
            loop[self.uv_layer].uv = (
                window_u0 + fraction_a * (window_u1 - window_u0),
                window_v0 + fraction_b * (window_v1 - window_v0),
            )

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
        """Bake the bmesh into a real object with its single material attached."""
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.materials.append(material(self.material_name))
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
            # Route through paint() rather than setting the slot directly, so
            # grid faces get UVs like every other face. This was the one place
            # that bypassed it, and a bypass here would ship untextured terrain.
            piece.paint([face], palette_fn((ix + 0.5) / cells_x, (iy + 0.5) / cells_y))
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
