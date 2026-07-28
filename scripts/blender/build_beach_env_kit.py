"""Generate the N. Sanity Beach environment kit as glTF pieces.

Environment art only -- terrain, cliffs, rocks, vegetation, water and
dressing. Nothing here builds, touches or depends on characters, crates,
enemies or any gameplay object.

Every mesh is generated from primitives by this script, so the kit is
original by construction and reproducible: each piece seeds its own RNG, so
re-running writes byte-identical files.

Run it with::

    blender --background --factory-startup \\
        --python scripts/blender/build_beach_env_kit.py
    godot --headless --path . --import

Output lands in ``assets/models/kits/``, and the extracted meshes the scenes
actually reference land in ``assets/models/kits/mesh/``.

*Why meshes are extracted.* The beach segments reference each prop as a
``Mesh`` on a plain ``MeshInstance3D``, not by instancing the ``.glb`` as a
PackedScene. ``scripts/lint_level_authoring.py`` walks every instanced
PackedScene it finds and parses it as text, so instancing a binary glTF
crashes the lint. Referencing the extracted mesh keeps the scenes free of
nested instances, which is both lint-safe and one less node per prop.

Extraction is driven by ``_subresources`` in each ``.glb.import`` sidecar;
this script rewrites those sidecars after exporting, so the pipeline stays
reproducible. A brand-new piece has no sidecar until Godot has seen it once,
so after *adding* a piece run the blender/godot pair twice -- the script says
so when it notices a missing sidecar.

Modelling conventions, both load-bearing:

* Build Z-up in Blender. The exporter's Y-up conversion means Blender +X is
  Godot +X, Blender +Z is Godot +Y, and Blender +Y is Godot **-Z** -- which
  is the direction the level runs, so "along the level" is Blender +Y.
* Ground pieces meet the play surface at Z = 0 and tuck a few centimetres
  under it, because the graybox floors' top face is exactly Godot Y = 0.
"""

from __future__ import annotations

import math
import os
import random
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from env_kit_common import (  # noqa: E402  (path set up above)
    Piece,
    add_blade,
    add_box,
    add_cylinder,
    add_height_grid,
    add_rock,
    export_glb,
    reset_scene,
)


# Ground pieces sit this far below the play surface so their inner edge
# cannot z-fight with the graybox floor it butts against.
FLOOR_TUCK = -0.06

# Width of the flat lip on the inner edge of every ground tile, in metres.
# Height grids are single-sided, so any sliver of ground the floor slab does
# not overlap can be seen straight through from the camera's angle. The apron
# lets a tile be pushed well under the floor (x = +-3.6) while its slope still
# starts outside the widest floor edge, which covers both the 12 m runs and
# the 10 m ones without poking through either.
APRON_M = 2.5

# Ground and water tiles span a whole segment, so one node per side dresses
# a segment instead of three. Segments are 96 m end to end.
TILE_LENGTH = 96.0

# Cells along a tile's length. ~3 m quads: coarse enough to stay cheap on a
# phone, fine enough that dune and swell shapes survive.
TILE_CELLS = 32


# --- terrain ------------------------------------------------------------


def build_beach_shelf() -> None:
    """Sand shelf beside the corridor that falls away toward the sea.

    Used on the *open* side only. Because it descends, whatever lies beyond
    it stays visible -- so it is always paired with water and a headland.
    """
    rng = random.Random(1101)
    piece = Piece("terrain_beach_shelf")
    dunes = [(rng.uniform(0.15, 0.85), rng.uniform(0.05, 0.95), rng.uniform(0.35, 1.1)) for _ in range(14)]

    apron = APRON_M / 14.0

    def height(u: float, v: float) -> float:
        # Flat where it meets the floor, then a slow fall to the waterline.
        beyond = max(0.0, (u - apron) / (1.0 - apron))
        fall = -2.4 * (beyond ** 1.7)
        roll = 0.22 * math.sin(v * math.pi * 7.0 + 0.6) * min(1.0, beyond * 2.2)
        bumps = 0.0
        for du, dv, amp in dunes:
            dist = math.hypot((beyond - du) * 1.4, (v - dv) * 6.0)
            bumps += amp * math.exp(-(dist * 3.4) ** 2)
        # Fade dunes out across the apron too. Scaling only their amplitude
        # is not enough -- a bump centred near the inner edge still lifts the
        # apron above the floor it is supposed to hide under.
        return FLOOR_TUCK + fall + roll + bumps * (0.35 + beyond * 0.8) * min(1.0, beyond * 4.0)

    def palette(u: float, v: float) -> str:
        z = height(u, v)
        if z < -1.5:
            return "sand_wet"
        if z > 0.2:
            return "sand_light"
        return "sand_mid"

    add_height_grid(piece, (0.0, 0.0, 0.0), 14.0, TILE_LENGTH, 12, TILE_CELLS, height, palette)
    piece.finish()


def _hash01(first: int, second: int, salt: int) -> float:
    """Deterministic 0..1 noise for a grid cell.

    Ground tone keyed straight off ``int(u * n) + int(v * m)`` produces a
    visible checkerboard; mixing in this hash breaks the regularity while
    staying reproducible run to run.
    """
    mixed = (first * 73856093) ^ (second * 19349663) ^ (salt * 83492791)
    mixed &= 0xFFFFFFFF
    return ((mixed * 2654435761) & 0xFFFFFFFF) / float(0xFFFFFFFF)


def _rising_bank(name: str, seed: int, width: float, climb: float, palette_fn) -> None:
    """A bank that climbs away from the corridor.

    Rising ground is the workhorse of the closed side: it hides everything
    behind it, so a segment's horizon can be shut without modelling any of
    the world past the bank.
    """
    rng = random.Random(seed)
    piece = Piece(name)
    lumps = [(rng.uniform(0.2, 1.0), rng.uniform(0.02, 0.98), rng.uniform(0.5, 1.8)) for _ in range(18)]
    apron = APRON_M / width

    def height(u: float, v: float) -> float:
        beyond = max(0.0, (u - apron) / (1.0 - apron))
        rise = climb * (beyond ** 1.3)
        lump = 0.0
        for du, dv, amp in lumps:
            dist = math.hypot((beyond - du) * 1.2, (v - dv) * 5.5)
            lump += amp * math.exp(-(dist * 3.0) ** 2)
        return FLOOR_TUCK + rise + lump * (0.3 + beyond) * min(1.0, beyond * 4.0)

    add_height_grid(
        piece,
        (0.0, 0.0, 0.0),
        width,
        TILE_LENGTH,
        11,
        TILE_CELLS,
        height,
        lambda u, v: palette_fn(u, v, height(u, v)),
    )
    piece.finish()


def build_beach_bank() -> None:
    """Sand bank climbing inland: the closed side of the beach segments."""

    def palette(u: float, v: float, z: float) -> str:
        score = z / 4.0 + _hash01(int(u * 22), int(v * 150), 3) * 0.4
        if score > 0.55:
            return "sand_light"
        return "sand_mid" if score > 0.16 else "sand_wet"

    _rising_bank("terrain_beach_bank", 3303, 12.0, 4.0, palette)


def build_jungle_bank() -> None:
    """Earth bank climbing into the jungle: the closed side inland.

    Tone follows elevation -- sunlit growth on the crests, deep shade in the
    hollows -- with a strip of bare earth where the bank meets the corridor.
    """

    def palette(u: float, v: float, z: float) -> str:
        if u < 0.11 and z < 0.2:
            return "rock_warm"
        score = z / 4.6 + _hash01(int(u * 22), int(v * 150), 9) * 0.38
        if score > 0.6:
            return "leaf_light"
        return "leaf_mid" if score > 0.26 else "leaf_dark"

    _rising_bank("terrain_jungle_bank", 2202, 12.0, 4.6, palette)


# --- cliffs -------------------------------------------------------------


def _stratified_cliff(piece: Piece, length: float, depth: float, height: float, rng: random.Random, layers: int) -> None:
    """Stack offset slabs into a stratified rock wall.

    The slabs deliberately overrun their own spacing in all three axes: a
    tidy grid of touching boxes reads as brickwork, whereas heavily
    interpenetrating ones read as bedding planes in stone. Embedded
    boulders then break up whatever regularity survives.
    """
    band = height / layers
    for layer in range(layers):
        base_z = layer * band
        shrink = 1.0 - 0.38 * (layer / max(1, layers - 1))
        run = 0.0
        while run < length:
            step = rng.uniform(2.2, 4.2)
            step = min(step, length - run)
            if step < 0.8:
                break
            # Slabs are wide along the wall and shallow through it. Boxes as
            # deep as they are long read as a heap of crates, not a rock face.
            wide = depth * shrink * rng.uniform(0.34, 0.72)
            if layer < layers // 3:
                tone = "rock_dark"
            elif layer < layers - 1:
                tone = rng.choice(("rock_mid", "rock_mid", "rock_warm"))
            else:
                tone = "rock_warm"
            add_box(
                piece,
                (
                    wide * 0.5 + rng.uniform(-1.1, 0.9),
                    run + step * 0.5,
                    base_z + band * 0.5 + rng.uniform(-0.22, 0.22) * band,
                ),
                (wide, step * rng.uniform(1.7, 2.3), band * rng.uniform(1.25, 1.6)),
                tone,
                rotation_z=rng.uniform(-0.16, 0.16),
                taper=rng.uniform(0.72, 0.98),
            )
            run += step
    # Outcrops welded onto the face, killing the last of the grid read.
    for _ in range(max(12, int(length * 1.1))):
        along = rng.uniform(0.0, length)
        up = rng.uniform(0.0, height)
        add_rock(
            piece,
            (rng.uniform(0.1, depth * 0.6), along, up),
            rng.uniform(0.6, 1.7),
            rng.choice(("rock_mid", "rock_light", "rock_dark", "rock_warm")),
            rng,
            subdivisions=1,
            jitter=0.4,
            squash=0.55,
            sink=0.0,
        )


def _canopy_cap(piece: Piece, length: float, depth: float, height: float, rng: random.Random) -> None:
    """Overgrow a cliff top with canopy blobs.

    From the corridor, only the part of a cliff standing above the bank in
    front of it is visible. Left bare, that reads as a pale grey block on the
    skyline; capping it means what shows is a jungle ridge instead, which is
    what this island is supposed to be covered in.
    """
    along = 0.0
    while along < length:
        add_rock(
            piece,
            (
                rng.uniform(-0.4, depth * 0.9),
                along,
                height - rng.uniform(0.2, 1.4),
            ),
            rng.uniform(1.8, 3.4),
            rng.choice(("leaf_dark", "leaf_mid", "leaf_mid", "leaf_light")),
            rng,
            subdivisions=1,
            jitter=0.32,
            squash=0.5,
            sink=0.0,
        )
        along += rng.uniform(1.6, 3.0)


def build_cliff_low() -> None:
    rng = random.Random(4404)
    piece = Piece("cliff_low_a")
    _stratified_cliff(piece, 24.0, 4.6, 6.2, rng, layers=4)
    for _ in range(6):
        add_rock(
            piece,
            (rng.uniform(0.4, 3.6), rng.uniform(0.5, 23.5), rng.uniform(0.0, 0.7)),
            rng.uniform(0.5, 1.1),
            "rock_mid",
            rng,
        )
    _canopy_cap(piece, 24.0, 4.6, 6.2, rng)
    piece.finish()


def build_cliff_tall() -> None:
    rng = random.Random(5505)
    piece = Piece("cliff_tall_a")
    _stratified_cliff(piece, 24.0, 6.4, 14.0, rng, layers=7)
    _canopy_cap(piece, 24.0, 6.4, 14.0, rng)
    piece.finish()


def build_headland() -> None:
    """Distant island silhouette for the sea horizon."""
    rng = random.Random(6606)
    piece = Piece("headland_far")
    # One ridge, not a row of pillars: the masses are far wider than their
    # spacing so they fuse into a single silhouette at distance.
    for index in range(8):
        along = index * 8.5
        tall = 13.0 + 13.0 * math.sin(index * 0.8 + 0.4) ** 2 + rng.uniform(-2.0, 2.0)
        add_box(
            piece,
            (rng.uniform(-2.0, 2.0), along, tall * 0.5),
            (rng.uniform(19.0, 27.0), rng.uniform(17.0, 24.0), tall),
            "rock_haze" if index % 2 else "rock_haze_dark",
            rotation_z=rng.uniform(-0.22, 0.22),
            taper=rng.uniform(0.58, 0.8),
        )
    # Vegetation cap, sunk into the rock so it merges instead of perching.
    for index in range(8):
        along = index * 8.5 + rng.uniform(-2.5, 2.5)
        tall = 13.0 + 13.0 * math.sin(index * 0.8 + 0.4) ** 2
        add_rock(
            piece,
            (rng.uniform(-3.0, 3.0), along, tall - 1.6),
            rng.uniform(7.0, 11.0),
            "leaf_haze",
            rng,
            subdivisions=1,
            jitter=0.3,
            squash=0.34,
            sink=0.0,
        )
    piece.finish()


# --- rocks --------------------------------------------------------------


def build_boulder(name: str, seed: int, radius: float, tone: str) -> None:
    rng = random.Random(seed)
    # Pure rock, so it can take the strata trim sheet rather than a flat atlas
    # cell. The cliffs cannot: their canopy cap is foliage, and the trim sheet
    # carries the rock family only.
    piece = Piece(name, uses_trim=True)
    add_rock(piece, (0.0, 0.0, 0.0), radius, tone, rng, subdivisions=2, jitter=0.3)
    for _ in range(3):
        add_rock(
            piece,
            (rng.uniform(-radius, radius), rng.uniform(-radius, radius), 0.0),
            radius * rng.uniform(0.22, 0.4),
            "rock_dark",
            rng,
        )
    piece.finish()


def build_rock_cluster() -> None:
    rng = random.Random(7707)
    piece = Piece("rock_cluster_a", uses_trim=True)
    for _ in range(4):
        add_rock(
            piece,
            (rng.uniform(-2.2, 2.2), rng.uniform(-2.2, 2.2), rng.uniform(-0.1, 0.4)),
            rng.uniform(0.7, 1.5),
            rng.choice(("rock_mid", "rock_light", "rock_warm")),
            rng,
            subdivisions=1,
        )
    for _ in range(9):
        add_rock(
            piece,
            (rng.uniform(-3.4, 3.4), rng.uniform(-3.4, 3.4), 0.0),
            rng.uniform(0.16, 0.36),
            "rock_dark",
            rng,
            subdivisions=1,
        )
    piece.finish()


# --- vegetation ---------------------------------------------------------


def _palm(name: str, seed: int, trunk_height: float, lean_x: float, fronds: int) -> None:
    rng = random.Random(seed)
    piece = Piece(name)
    tip = add_cylinder(
        piece,
        (0.0, 0.0, 0.0),
        trunk_height,
        0.42,
        0.24,
        "trunk",
        sides=7,
        lean=(lean_x, rng.uniform(-0.3, 0.3)),
        bend=lean_x * 0.55,
        rings=6,
    )
    # Ring scars: small collars up the trunk, the cheapest read of "palm".
    # They must trace the same lean+bend curve add_cylinder used, or they
    # float off the trunk they are supposed to be wrapped around.
    bend_x = lean_x * 0.55
    for step in range(5):
        along = 0.2 + step * 0.16
        add_box(
            piece,
            (
                lean_x * along + bend_x * along * along,
                0.0,
                trunk_height * along,
            ),
            (0.84, 0.84, 0.15),
            "trunk_dark",
            rotation_z=rng.uniform(0.0, 0.8),
            taper=0.9,
        )
    for index in range(fronds):
        angle = 2.0 * math.pi * index / fronds + rng.uniform(-0.16, 0.16)
        add_blade(
            piece,
            tip,
            angle,
            rng.uniform(3.4, 4.4),
            rng.uniform(0.95, 1.35),
            "frond" if index % 2 else "leaf_mid",
            segments=5,
            rise=rng.uniform(0.32, 0.5),
            droop=rng.uniform(0.85, 1.15),
            tilt=rng.uniform(0.2, 0.6),
        )
    for index in range(3):
        angle = 2.0 * math.pi * index / 3
        add_rock(
            piece,
            (
                tip[0] + math.cos(angle) * 0.42,
                tip[1] + math.sin(angle) * 0.42,
                tip[2] - 0.3,
            ),
            0.26,
            "coconut",
            rng,
            squash=1.0,
            sink=0.0,
            jitter=0.12,
        )
    piece.finish()


def build_palms() -> None:
    _palm("palm_tall_a", 8808, 7.4, 0.9, 8)
    _palm("palm_lean_a", 9909, 5.6, 2.4, 7)


def _jungle_tree(name: str, seed: int, trunk_height: float, canopy_radius: float, blobs: int) -> None:
    rng = random.Random(seed)
    piece = Piece(name)
    tip = add_cylinder(
        piece,
        (0.0, 0.0, 0.0),
        trunk_height,
        0.62,
        0.34,
        "trunk",
        sides=6,
        lean=(rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4)),
        bend=rng.uniform(-0.3, 0.3),
        rings=5,
    )
    # Buttress roots -- reads as rainforest rather than generic tree.
    for index in range(4):
        angle = 2.0 * math.pi * index / 4 + 0.4
        add_box(
            piece,
            (math.cos(angle) * 0.5, math.sin(angle) * 0.5, 0.45),
            (0.5, 0.5, 1.5),
            "trunk_dark",
            rotation_z=angle,
            taper=0.25,
        )
    for _ in range(blobs):
        offset_angle = rng.uniform(0.0, 2.0 * math.pi)
        offset_dist = rng.uniform(0.0, canopy_radius * 0.75)
        add_rock(
            piece,
            (
                tip[0] + math.cos(offset_angle) * offset_dist,
                tip[1] + math.sin(offset_angle) * offset_dist,
                tip[2] + rng.uniform(-0.4, 1.5),
            ),
            rng.uniform(canopy_radius * 0.45, canopy_radius * 0.8),
            rng.choice(("leaf_mid", "leaf_dark", "leaf_light")),
            rng,
            subdivisions=1,
            jitter=0.26,
            squash=0.62,
            sink=0.0,
        )
    for index in range(6):
        angle = 2.0 * math.pi * index / 6 + rng.uniform(-0.2, 0.2)
        add_blade(
            piece,
            (tip[0], tip[1], tip[2] - rng.uniform(0.2, 0.9)),
            angle,
            rng.uniform(2.0, 3.0),
            rng.uniform(0.7, 1.1),
            "leaf_mid",
            segments=4,
            rise=0.2,
            droop=1.05,
            tilt=0.4,
        )
    piece.finish()


def build_jungle_trees() -> None:
    _jungle_tree("jungle_tree_a", 1210, 8.2, 3.2, 7)
    _jungle_tree("jungle_tree_b", 1311, 5.4, 3.8, 6)


def build_fern_cluster() -> None:
    rng = random.Random(1412)
    piece = Piece("fern_cluster_a")
    for _ in range(6):
        base = (rng.uniform(-1.9, 1.9), rng.uniform(-1.9, 1.9), 0.0)
        for blade in range(rng.randint(6, 9)):
            angle = 2.0 * math.pi * blade / 7 + rng.uniform(-0.3, 0.3)
            add_blade(
                piece,
                base,
                angle,
                rng.uniform(1.2, 2.0),
                rng.uniform(0.3, 0.5),
                rng.choice(("leaf_light", "leaf_mid", "frond")),
                segments=4,
                rise=rng.uniform(0.75, 1.05),
                droop=rng.uniform(0.9, 1.25),
                tilt=rng.uniform(0.1, 0.4),
            )
    piece.finish()


def build_bush_cluster() -> None:
    """Leafy shrubs.

    Mass comes from many overlapping blades rather than big green spheres:
    a squashed icosphere at bush scale reads as a mossy boulder, not foliage.
    A couple of small dark blobs stay at the base purely to stop light
    showing through the middle.
    """
    rng = random.Random(1513)
    piece = Piece("bush_cluster_a")
    for _ in range(4):
        centre = (rng.uniform(-1.8, 1.8), rng.uniform(-1.8, 1.8), 0.0)
        for _ in range(2):
            add_rock(
                piece,
                (
                    centre[0] + rng.uniform(-0.3, 0.3),
                    centre[1] + rng.uniform(-0.3, 0.3),
                    rng.uniform(0.1, 0.3),
                ),
                rng.uniform(0.3, 0.46),
                "leaf_dark",
                rng,
                subdivisions=1,
                jitter=0.3,
                squash=0.7,
                sink=0.2,
            )
        for blade in range(16):
            add_blade(
                piece,
                (
                    centre[0] + rng.uniform(-0.3, 0.3),
                    centre[1] + rng.uniform(-0.3, 0.3),
                    rng.uniform(0.0, 0.35),
                ),
                2.0 * math.pi * blade / 16 + rng.uniform(-0.3, 0.3),
                rng.uniform(0.8, 1.35),
                rng.uniform(0.26, 0.42),
                rng.choice(("leaf_light", "leaf_mid", "leaf_mid", "frond")),
                segments=3,
                rise=rng.uniform(0.85, 1.3),
                droop=rng.uniform(1.0, 1.35),
                tilt=rng.uniform(0.1, 0.4),
            )
    piece.finish()


def build_grass_patch() -> None:
    rng = random.Random(1614)
    piece = Piece("grass_patch_a")
    for _ in range(46):
        angle = rng.uniform(0.0, 2.0 * math.pi)
        dist = math.sqrt(rng.uniform(0.0, 1.0)) * 2.6
        base = (math.cos(angle) * dist, math.sin(angle) * dist, 0.0)
        for blade in range(rng.randint(2, 4)):
            add_blade(
                piece,
                base,
                rng.uniform(0.0, 2.0 * math.pi),
                rng.uniform(0.5, 0.95),
                rng.uniform(0.1, 0.18),
                rng.choice(("leaf_light", "frond", "leaf_mid")),
                segments=2,
                rise=1.5,
                droop=1.1,
            )
            _ = blade
    piece.finish()


def _fringe(name: str, seed: int, tones: tuple[str, ...], stone: str, density: float, blade_len: tuple[float, float]) -> None:
    """A narrow planting strip that runs the length of a segment's edge.

    This is a readability piece as much as a dressing one. Where the corridor
    floor and the ground beside it are near the same colour, the player loses
    the edge of the play surface; a continuous low fringe puts a hard line
    exactly on the boundary without occluding anything or narrowing the
    corridor. It is deliberately narrow so it can sit clear of the floor.
    """
    rng = random.Random(seed)
    piece = Piece(name)
    step = 1.0 / density
    along = 0.0
    while along < TILE_LENGTH:
        # Tufts keep clear of the strip's inner edge so that, once placed
        # against the floor, no blade or its width reaches back onto it.
        base = (rng.uniform(0.5, 1.5), along, 0.0)
        for _ in range(rng.randint(2, 4)):
            add_blade(
                piece,
                (base[0] + rng.uniform(-0.12, 0.12), base[1] + rng.uniform(-0.3, 0.3), 0.0),
                # Blades fan outward, never back across the corridor: the
                # strip is placed hard against the floor edge, so an
                # inward-pointing blade would lie over the play surface.
                rng.uniform(-1.15, 1.15),
                rng.uniform(*blade_len),
                rng.uniform(0.11, 0.2),
                rng.choice(tones),
                segments=2,
                rise=1.45,
                droop=1.1,
            )
        if rng.random() < 0.22:
            add_rock(
                piece,
                (rng.uniform(0.1, 1.5), along + rng.uniform(-0.4, 0.4), 0.0),
                rng.uniform(0.14, 0.3),
                stone,
                rng,
                subdivisions=1,
                jitter=0.4,
                squash=0.55,
                sink=0.25,
            )
        along += step * rng.uniform(0.75, 1.25)
    piece.finish()


def build_fringes() -> None:
    _fringe(
        "fringe_grass_a",
        2626,
        ("leaf_light", "leaf_mid", "frond"),
        "rock_mid",
        1.0,
        (0.45, 0.85),
    )
    _fringe(
        "fringe_beach_a",
        2727,
        ("leaf_light", "frond", "sand_light"),
        "rock_light",
        0.62,
        (0.35, 0.7),
    )


def build_canopy_arch() -> None:
    """Overhead fronds, hung above the corridor to frame the top of the screen."""
    rng = random.Random(1715)
    piece = Piece("canopy_frond_arch")
    add_cylinder(
        piece,
        (0.0, 0.0, 0.0),
        0.5,
        0.5,
        0.42,
        "trunk_dark",
        sides=6,
        rings=1,
    )
    for index in range(11):
        angle = rng.uniform(-0.9, 0.9) + (math.pi if index % 2 else 0.0)
        add_blade(
            piece,
            (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(-0.2, 0.3)),
            angle,
            rng.uniform(3.0, 4.6),
            rng.uniform(0.8, 1.3),
            rng.choice(("leaf_dark", "leaf_mid", "frond")),
            segments=5,
            rise=rng.uniform(-0.1, 0.2),
            droop=rng.uniform(1.1, 1.5),
            tilt=rng.uniform(0.2, 0.7),
        )
    piece.finish()


# --- water --------------------------------------------------------------


def build_sea_tile() -> None:
    """Stylised sea surface: long swells with a shallow band nearest the shore."""
    piece = Piece("water_sea_tile")

    def height(u: float, v: float) -> float:
        swell = 0.18 * math.sin(v * math.pi * 6.0 + u * 1.6)
        chop = 0.07 * math.sin(v * math.pi * 19.0 + u * 4.0)
        return swell + chop

    def palette(u: float, v: float) -> str:
        return "water_shallow" if u < 0.1 else "water_deep"

    add_height_grid(piece, (0.0, 0.0, 0.0), 90.0, TILE_LENGTH, 15, TILE_CELLS, height, palette)
    piece.finish()


def build_surf_foam() -> None:
    """Scalloped foam strip for the waterline."""
    rng = random.Random(1816)
    piece = Piece("surf_foam_edge")
    wobble = [rng.uniform(0.5, 1.5) for _ in range(TILE_CELLS + 1)]

    def height(u: float, v: float) -> float:
        return 0.05 * math.sin(v * math.pi * 16.0)

    def palette(u: float, v: float) -> str:
        index = min(len(wobble) - 1, int(v * (len(wobble) - 1)))
        return "foam" if u < 0.45 * wobble[index] else "water_shallow"

    add_height_grid(piece, (0.0, 0.0, 0.0), 5.0, TILE_LENGTH, 8, TILE_CELLS, height, palette)
    piece.finish()


# --- dressing -----------------------------------------------------------


def build_driftwood() -> None:
    rng = random.Random(1917)
    piece = Piece("driftwood_a")
    # Modelled standing, then laid down -- a beached log, not a post.
    add_cylinder(
        piece,
        (0.0, 0.0, 0.0),
        4.4,
        0.34,
        0.22,
        "driftwood",
        sides=6,
        lean=(0.35, 0.0),
        bend=0.28,
        rings=4,
    )
    for _ in range(2):
        add_cylinder(
            piece,
            (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(1.4, 3.2)),
            rng.uniform(0.7, 1.1),
            0.17,
            0.09,
            "driftwood",
            sides=5,
            lean=(rng.uniform(-1.1, 1.1), rng.uniform(0.2, 0.7)),
            rings=2,
        )
    piece.rotate_x(math.pi * 0.5)
    piece.translate(0.0, 2.2, 0.32)
    piece.finish()


def build_shell_scatter() -> None:
    rng = random.Random(2018)
    piece = Piece("shell_scatter_a")
    for _ in range(14):
        add_rock(
            piece,
            (rng.uniform(-2.6, 2.6), rng.uniform(-2.6, 2.6), 0.0),
            rng.uniform(0.13, 0.26),
            rng.choice(("shell", "sand_light", "flower")),
            rng,
            subdivisions=1,
            jitter=0.4,
            squash=0.4,
            sink=0.2,
        )
    piece.finish()


def build_coconut_cluster() -> None:
    rng = random.Random(2119)
    piece = Piece("coconut_cluster_a")
    for _ in range(6):
        add_rock(
            piece,
            (rng.uniform(-1.1, 1.1), rng.uniform(-1.1, 1.1), 0.0),
            rng.uniform(0.22, 0.3),
            "coconut",
            rng,
            subdivisions=1,
            jitter=0.14,
            squash=0.95,
            sink=0.3,
        )
    piece.finish()


def build_stone_cairn() -> None:
    rng = random.Random(2220)
    piece = Piece("stone_cairn_a")
    height = 0.0
    for index in range(5):
        radius = 0.72 - index * 0.11
        add_rock(
            piece,
            (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), height + radius * 0.42),
            radius,
            "rock_light" if index % 2 else "rock_mid",
            rng,
            subdivisions=1,
            jitter=0.22,
            squash=0.5,
            sink=0.0,
        )
        height += radius * 0.62
    piece.finish()


# --- driver -------------------------------------------------------------

BUILDERS = (
    ("terrain_beach_shelf", build_beach_shelf),
    ("terrain_beach_bank", build_beach_bank),
    ("terrain_jungle_bank", build_jungle_bank),
    ("cliff_low_a", build_cliff_low),
    ("cliff_tall_a", build_cliff_tall),
    ("headland_far", build_headland),
    ("rock_boulder_a", lambda: build_boulder("rock_boulder_a", 2321, 1.5, "rock_mid")),
    ("rock_boulder_b", lambda: build_boulder("rock_boulder_b", 2422, 2.3, "rock_warm")),
    ("rock_cluster_a", build_rock_cluster),
    ("palms", build_palms),
    ("jungle_trees", build_jungle_trees),
    ("fern_cluster_a", build_fern_cluster),
    ("bush_cluster_a", build_bush_cluster),
    ("grass_patch_a", build_grass_patch),
    ("fringes", build_fringes),
    ("canopy_frond_arch", build_canopy_arch),
    ("water_sea_tile", build_sea_tile),
    ("surf_foam_edge", build_surf_foam),
    ("driftwood_a", build_driftwood),
    ("shell_scatter_a", build_shell_scatter),
    ("coconut_cluster_a", build_coconut_cluster),
    ("stone_cairn_a", build_stone_cairn),
)

# Builders that emit more than one piece, so the driver knows to export each
# object to its own file instead of one file named after the builder.
MULTI = {"palms", "jungle_trees", "fringes"}


MATERIAL_DIR = "res://assets/materials"


def _brace_span(text: str, start: int) -> int:
    """Index of the closing brace matching the first ``{`` at or after ``start``."""
    index = text.index("{", start)
    depth = 0
    while index < len(text):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise ValueError("unbalanced braces in .import sidecar")


def _with_external_material(text: str, material_name: str) -> str:
    """Point a ``.glb.import`` at the committed material carrying the texture.

    The kit's .glb files carry a white, untextured material on purpose --
    embedding a 2 MB atlas in each of twenty-five meshes would put twenty-five
    copies of it in a public repo's history forever. The texture lives once in
    ``assets/materials/``, and this block is what makes the *extracted* mesh
    reference it.

    A post-import script cannot do this job. It runs on the imported scene,
    while ``save_to_file`` writes the mesh from the pre-script material, so the
    texture never reaches ``kits/mesh/*.res`` -- which is exactly the failure
    ``tests/integration/test_kit_materials.gd`` was written to catch.
    """
    # Whatever wrote this before, the import script is not what wires materials.
    text = re.sub(
        r'^import_script/path=.*$',
        'import_script/path=""',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    block = (
        '"materials": {\n'
        f'"{material_name}": {{\n'
        '"use_external/enabled": true,\n'
        f'"use_external/path": "{MATERIAL_DIR}/{material_name}.tres"\n'
        "}\n"
        "}"
    )
    marker = '"materials": {'
    start = text.find(marker)
    if start >= 0:
        end = _brace_span(text, start + len(marker) - 1)
        # Godot rewrites the inner keys on import; replace the whole object so a
        # renamed material cannot leave a stale entry behind.
        return text[:start] + block + text[end + 1 :]
    anchor = "_subresources={\n"
    index = text.find(anchor)
    if index < 0:
        return text
    insert_at = index + len(anchor)
    return text[:insert_at] + block + ",\n" + text[insert_at:]


def _patch_import_sidecar(out_dir: str, piece: str, material_name: str) -> bool:
    """Point a ``.glb.import`` at an extracted mesh under ``kits/mesh/``.

    Returns False when the sidecar does not exist yet, which just means Godot
    has not imported this piece before.
    """
    sidecar = os.path.join(out_dir, f"{piece}.glb.import")
    if not os.path.exists(sidecar):
        return False
    original = open(sidecar, encoding="utf-8").read()
    text = _with_external_material(original, material_name)
    if "save_to_file/enabled" in text:
        if text != original:
            with open(sidecar, "w", encoding="utf-8") as handle:
                handle.write(text)
        # Already wired. Godot rewrites this block on import (it swaps the
        # path for a uid and adds its own keys), so leave its version alone
        # rather than fighting it every build.
        return True
    # Godot names an imported glTF mesh "<node>_<mesh>"; this script gives an
    # object and its mesh datablock the same name, so the key doubles up.
    block = (
        "_subresources={\n"
        '"meshes": {\n'
        f'"{piece}_{piece}": {{\n'
        '"save_to_file/enabled": true,\n'
        f'"save_to_file/path": "res://assets/models/kits/mesh/{piece}.res"\n'
        "}\n"
        "}\n"
        "}"
    )
    start = text.find("_subresources={")
    if start < 0:
        return False
    # Brace-match to the end of the existing value. A regex cannot do this:
    # once Godot has nested its own keys inside, the first "\n}" is the inner
    # dict's, and replacing up to there silently corrupts the sidecar.
    index = text.index("{", start)
    depth = 0
    while index < len(text):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                break
        index += 1
    with open(sidecar, "w", encoding="utf-8") as handle:
        handle.write(text[:start] + block + text[index + 1:])
    return True


def _invalidate(out_dir: str, piece: str) -> None:
    """Force Godot to re-extract ``piece``'s mesh on the next import.

    A stale ``.res`` is the worst failure this pipeline can have: the scenes
    keep rendering last build's geometry while the source says otherwise --
    exactly the dead-wire shape this project exists to avoid. Deleting the
    extracted mesh alone is not enough, because Godot skips reimport when the
    source's hash is unchanged and so never rewrites it. The cached import
    entry has to go with it.
    """
    stale = os.path.join(out_dir, "mesh", f"{piece}.res")
    if os.path.exists(stale):
        os.remove(stale)
    cache = os.path.abspath(os.path.join(out_dir, "..", "..", "..", ".godot", "imported"))
    if not os.path.isdir(cache):
        return
    for entry in os.listdir(cache):
        if entry.startswith(f"{piece}.glb-"):
            os.remove(os.path.join(cache, entry))


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.abspath(os.path.join(here, "..", "..", "assets", "models", "kits"))
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(os.path.join(out_dir, "mesh"), exist_ok=True)
    # (path, material name). The material decides which texture the extracted
    # mesh ends up referencing, so it has to travel with the piece.
    written: list[tuple[str, str]] = []
    for label, builder in BUILDERS:
        reset_scene()
        builder()
        if label in MULTI:
            objects = list(bpy.context.collection.objects)
            for obj in objects:
                for other in objects:
                    other.hide_set(False)
                    other.select_set(other is obj)
                path = os.path.join(out_dir, f"{obj.name}.glb")
                _export_single(obj, path)
                written.append((path, _material_name(obj)))
        else:
            path = os.path.join(out_dir, f"{label}.glb")
            export_glb(path)
            written.append((path, _material_name(bpy.context.collection.objects[0])))
    pending: list[str] = []
    for path, material_name in written:
        piece = os.path.basename(path)[: -len(".glb")]
        _invalidate(out_dir, piece)
        if not _patch_import_sidecar(out_dir, piece, material_name):
            pending.append(piece)
        print(f"KIT_WROTE {os.path.basename(path)} {material_name} {os.path.getsize(path)}")
    print(f"KIT_TOTAL {len(written)}")
    if pending:
        print(
            "KIT_NOTE no .import sidecar yet for: "
            + ", ".join(pending)
            + " -- run godot --headless --path . --import, then this script "
            "again, so their meshes get extracted."
        )


def _material_name(obj: "bpy.types.Object") -> str:
    """The single material a finished piece carries.

    Pieces have exactly one slot by design -- that is the whole point of moving
    colour into the atlas UVs -- so anything else means a builder regressed and
    the sidecar would be wired to the wrong texture.
    """
    materials = [slot for slot in obj.data.materials if slot is not None]
    if len(materials) != 1:
        raise RuntimeError(
            f"{obj.name} has {len(materials)} materials; kit pieces must have "
            "exactly one so the atlas can be wired to it"
        )
    return materials[0].name


def _export_single(obj: bpy.types.Object, path: str) -> None:
    """Export exactly one object by temporarily unlinking its siblings."""
    collection = bpy.context.collection
    siblings = [other for other in list(collection.objects) if other is not obj]
    for other in siblings:
        collection.objects.unlink(other)
    export_glb(path)
    for other in siblings:
        collection.objects.link(other)


if __name__ == "__main__":
    main()
