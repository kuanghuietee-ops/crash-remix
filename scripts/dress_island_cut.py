#!/usr/bin/env python3
"""Dress the Island Cut's graybox segments with the beach/jungle kit.

N. Sanity Beach was dressed by hand. Boulders and Hog Wild are nineteen segments
between them, so they are dressed from the geometry instead: this script reads
each segment's graybox platforms, works out where the play corridor is, and
places scenery outside it. Deterministic per segment, so re-running writes the
same scene, and idempotent, so it can be re-run after a segment is re-authored.

Run it with::

    python3 scripts/dress_island_cut.py

The rule every placement obeys: **nothing the script emits may sit inside the
volume the player can reach.** Scenery is pushed past the widest platform edge
plus a clearance margin, and the emitted nodes carry no collision shapes, no
scripts and no groups -- they are decoration and nothing else. A piece that
strayed into the corridor would be invisible to every lint and would simply make
the level unplayable, so the margin is checked rather than assumed, by
``tests/lint/test_island_dressing.py``.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from scripts.scene_transform_parsing import (  # noqa: E402  (path set up above)
    assignment_values,
    header_attributes,
    parse_vector,
)

# Clearance between the widest thing the player can stand on and the nearest
# vertex of any scenery. Generous on purpose: the camera swings wide on the
# chase levels, and a trunk clipping the lens is worse than a sparse verge.
CLEARANCE_M = 2.5

# How far past the corridor the dressing band extends. Beyond this the pieces
# stop earning their draw calls.
BAND_DEPTH_M = 26.0

# The physical length of the kit pieces this script tiles. These mirror the
# geometry built by scripts/blender/build_beach_env_kit.py -- TILE_LENGTH for the
# bank/ground tiles and the cliff pieces' own extent -- and exist because the
# dresser previously placed exactly one of each per side regardless of how long
# the segment was. The kit was built to the beach's 96 m rhythm, but Boulders
# segments are 64 m and Hog Wild's are 128 m, so a Hog Wild segment ran 32 m per
# side with no verge ground beneath its scatter and ~104 m per side with no back
# wall at all, showing raw background colour between the trees at speed.
BANK_TILE_LENGTH_M = 96.0
WALL_PIECE_LENGTH_M = 24.0
FRINGE_TILE_LENGTH_M = 96.0

# How far below the corridor floor the edge fringe sits, so its roots are buried
# rather than hovering on top of the play surface.
FRINGE_SINK_M = 0.05

# The only pieces allowed to sit inside the clearance band, because marking the
# play-surface boundary is their entire job. They are built for it: narrow, low,
# with blades that fan outward and never reach back across the corridor. Every
# other piece keeps CLEARANCE_M. Adding to this set widens the one rule that can
# make a level unplayable, so it stays short and explicit.
EDGE_PIECES = frozenset({"fringe_grass_a", "fringe_beach_a"})

# Overhead canopy arches, for the ride level only. Hog Wild is a forced run down
# a long straight corridor: the verge slides past in the periphery, but nothing
# crosses the top of the frame, so at speed the screen is static apart from the
# ground. Arches passing overhead at an even beat are what reads as speed --
# evenly, because randomly spaced ones read as clutter instead of rhythm.
CANOPY_ARCH_PIECE = "canopy_frond_arch"
CANOPY_ARCH_CADENCE_M = 40.0

# Measured off the built mesh, not guessed: the piece is a stub at its origin
# with fronds hanging to y -6.13, so the origin has to sit this far above the
# height the lowest frond should reach.
CANOPY_ARCH_DROOP_M = 6.15

# How much air stays under the lowest frond. The player rides at roughly two
# metres; this keeps the fronds in the top of the frame and out of the ride.
CANOPY_ARCH_CLEARANCE_M = 4.5

SEGMENT_DIR = Path("scenes/segments")
MESH_DIR = "res://assets/models/kits/mesh"

ENVIRONMENT_NODE = "EnvironmentArt"


@dataclass(frozen=True)
class Platform:
    """One graybox slab: what the player can actually stand on."""

    position: tuple[float, float, float]
    size: tuple[float, float, float]


@dataclass(frozen=True)
class Corridor:
    """The reachable volume of a segment, in its own local space."""

    half_width: float
    z_near: float
    z_far: float
    floor_y: float
    platforms: tuple[Platform, ...] = ()

    @property
    def length(self) -> float:
        return abs(self.z_far - self.z_near)

    def floor_at(self, z: float) -> float:
        """Ground height under a given point along the segment.

        Papu's arena climbs three terraces, so a single floor height would bury
        the far end's scenery four metres underground. Falls back to the
        segment's main floor where nothing covers that z.
        """
        covering = [
            plat
            for plat in self.platforms
            if plat.position[2] - plat.size[2] / 2.0
            <= z
            <= plat.position[2] + plat.size[2] / 2.0
        ]
        if not covering:
            return self.floor_y
        widest = max(covering, key=lambda plat: plat.size[0] * plat.size[2])
        return widest.position[1] + widest.size[1] / 2.0


@dataclass(frozen=True)
class Placement:
    node: str
    piece: str
    position: tuple[float, float, float]
    yaw: float
    cast_shadow: bool = True
    # Length along z that this piece's geometry occupies, for the long
    # origin-anchored strips (banks, walls, fringes). Zero for compact props
    # like rocks and trees, which are centred on their origin and so are
    # unaffected by yaw. Recorded because mirroring a strip onto the left verge
    # flips its span, and nothing could check that without knowing the length.
    span_m: float = 0.0


def mirrored_z(z_right: float, side: float, span_m: float) -> float:
    """Where to place a piece on ``side`` so it covers the same z as its twin.

    The kit's long pieces run from their origin toward -z. The left verge is
    dressed by rotating them 180 degrees, which flips that span to +z -- so a
    left piece placed at its twin's z covers the *previous* segment and leaves
    this one bare. Shifting the origin back by the span puts the two spans on
    top of each other, which is what "mirrored" was always supposed to mean.
    """
    if side > 0:
        return z_right
    return z_right - span_m


def parse_platforms(text: str) -> list[Platform]:
    """Every graybox platform instanced in a segment, with position and size."""
    platforms: list[Platform] = []
    for block in _node_blocks(text):
        header, body = block
        attributes = header_attributes(header)
        if "instance" not in attributes:
            continue
        values = assignment_values(body)
        size = parse_vector(values.get("size", ""))
        if size is None:
            continue
        # A node with no explicit position sits at its parent's origin.
        position = parse_vector(values.get("position", "")) or (0.0, 0.0, 0.0)
        platforms.append(Platform(position=tuple(position), size=tuple(size)))
    return platforms


def corridor_of(platforms: Sequence[Platform]) -> Corridor | None:
    """The bounding corridor of every platform in a segment.

    Uses the *widest* slab rather than an average: a segment whose entry apron
    is wider than its main run still has to be cleared by the wider one.
    """
    if not platforms:
        return None
    half_width = max(
        abs(plat.position[0]) + plat.size[0] / 2.0 for plat in platforms
    )
    z_near = max(plat.position[2] + plat.size[2] / 2.0 for plat in platforms)
    z_far = min(plat.position[2] - plat.size[2] / 2.0 for plat in platforms)
    # Ground level comes from the biggest slab, not the highest one. Hog Wild's
    # gate obstacles are platforms too, and taking the highest top surface would
    # float every tree on that segment 3.7 m into the air.
    ground = max(platforms, key=lambda plat: plat.size[0] * plat.size[2])
    floor_y = ground.position[1] + ground.size[1] / 2.0
    return Corridor(
        half_width=half_width,
        z_near=z_near,
        z_far=z_far,
        floor_y=floor_y,
        platforms=tuple(platforms),
    )


def _node_blocks(text: str) -> list[tuple[str, str]]:
    """Split a .tscn into (header line, body) pairs, one per node."""
    blocks: list[tuple[str, str]] = []
    current_header: str | None = None
    current_body: list[str] = []
    for line in text.splitlines():
        if line.startswith("[node "):
            if current_header is not None:
                blocks.append((current_header, "\n".join(current_body)))
            current_header = line
            current_body = []
        elif current_header is not None:
            if line.startswith("["):
                blocks.append((current_header, "\n".join(current_body)))
                current_header = None
                current_body = []
            else:
                current_body.append(line)
    if current_header is not None:
        blocks.append((current_header, "\n".join(current_body)))
    return blocks


def _hash01(seed: int, salt: int) -> float:
    """Deterministic 0..1 noise. Matches the kit builders' approach."""
    mixed = (seed * 73856093) ^ (salt * 19349663)
    mixed &= 0xFFFFFFFF
    return ((mixed * 2654435761) & 0xFFFFFFFF) / float(0xFFFFFFFF)


# --- the two dressing styles -------------------------------------------
# Boulders runs down a canyon, so it is walled with cliffs; Hog Wild is a
# flat-out jungle sprint, so it is banked and treed. Both draw on the same kit.

CANYON_STYLE = {
    "fringe": "fringe_grass_a",
    "walls": ["cliff_tall_a", "cliff_low_a"],
    "bank": "terrain_jungle_bank",
    "scatter": ["rock_boulder_a", "rock_boulder_b", "rock_cluster_a", "stone_cairn_a"],
    "canopy": ["jungle_tree_b", "fern_cluster_a"],
    "scatter_every_m": 11.0,
}

JUNGLE_STYLE = {
    "fringe": "fringe_grass_a",
    # The ride level, and the only one that gets overhead arches.
    "canopy_arch": True,
    "walls": ["cliff_low_a"],
    "bank": "terrain_jungle_bank",
    "scatter": ["bush_cluster_a", "fern_cluster_a", "grass_patch_a", "rock_cluster_a"],
    "canopy": ["jungle_tree_a", "jungle_tree_b", "palm_tall_a", "palm_lean_a"],
    "scatter_every_m": 13.0,
}

# Papu's arena is a tribal village terrace, so it is ringed with the village
# props rather than jungle: totems and standing stones read as "someone built
# this", which is what a boss arena needs that a corridor does not.
VILLAGE_STYLE = {
    "walls": ["cliff_low_a"],
    "bank": "terrain_jungle_bank",
    "scatter": ["totem_tall_a", "standing_stone_a", "log_fence_a", "torch_post_a"],
    "canopy": ["hut_thatch_a", "palm_tall_a"],
    "scatter_every_m": 12.0,
}

STYLE_BY_PREFIX = {
    "boulders_": CANYON_STYLE,
    "hog_": JUNGLE_STYLE,
    "papu_": VILLAGE_STYLE,
}


def placements_for(name: str, corridor: Corridor, style: dict) -> list[Placement]:
    """Every scenery node for one segment, on both verges."""
    placements: list[Placement] = []
    inner = corridor.half_width + CLEARANCE_M
    seed = sum(ord(character) for character in name)

    for side_index, side in enumerate((-1.0, 1.0)):
        # Bank tiles hide the horizon, so they have to reach the end of the
        # corridor. One tile only covers BANK_TILE_LENGTH_M of it.
        bank_tiles = max(1, math.ceil(corridor.length / BANK_TILE_LENGTH_M))
        for tile_index in range(bank_tiles):
            placements.append(
                Placement(
                    node=f"Bank{'Left' if side < 0 else 'Right'}{tile_index}",
                    piece=str(style["bank"]),
                    position=(
                        side * inner,
                        corridor.floor_y,
                        mirrored_z(
                            corridor.z_near - tile_index * BANK_TILE_LENGTH_M,
                            side,
                            BANK_TILE_LENGTH_M,
                        ),
                    ),
                    yaw=0.0 if side > 0 else 180.0,
                    span_m=BANK_TILE_LENGTH_M,
                )
            )

        # The corridor edge itself. The kit ships fringe strips built for this
        # exact job -- a narrow line of planting hard against the floor edge,
        # blades fanning outward so nothing reaches back over the play surface --
        # and until now only the hand-dressed beach used them, leaving the two
        # fast levels with raw box arrises where the floor meets the verge.
        fringe = style.get("fringe")
        if fringe:
            fringe_tiles = max(1, math.ceil(corridor.length / FRINGE_TILE_LENGTH_M))
            for tile_index in range(fringe_tiles):
                placements.append(
                    Placement(
                        node=f"Fringe{'L' if side < 0 else 'R'}{tile_index}",
                        piece=str(fringe),
                        position=(
                            side * corridor.half_width,
                            corridor.floor_y - FRINGE_SINK_M,
                            mirrored_z(
                                corridor.z_near - tile_index * FRINGE_TILE_LENGTH_M,
                                side,
                                FRINGE_TILE_LENGTH_M,
                            ),
                        ),
                        yaw=0.0 if side > 0 else 180.0,
                        cast_shadow=False,
                        span_m=FRINGE_TILE_LENGTH_M,
                    )
                )

        count = max(2, int(corridor.length / float(style["scatter_every_m"])))
        for index in range(count):
            along = corridor.z_near - (index + 0.5) * (corridor.length / count)
            jitter = _hash01(seed + index, side_index * 31 + 7)
            depth = inner + 1.5 + jitter * (BAND_DEPTH_M - inner - 1.5)
            ground = corridor.floor_at(along)

            scatter = list(style["scatter"])
            piece = scatter[(index + side_index) % len(scatter)]
            placements.append(
                Placement(
                    node=f"Scatter{'L' if side < 0 else 'R'}{index}",
                    piece=piece,
                    position=(side * depth, ground - 0.15, along),
                    yaw=_hash01(seed + index, side_index * 17 + 3) * 360.0,
                )
            )

            if index % 2 == 0:
                canopy = list(style["canopy"])
                tree = canopy[(index // 2 + side_index) % len(canopy)]
                placements.append(
                    Placement(
                        node=f"Canopy{'L' if side < 0 else 'R'}{index}",
                        piece=tree,
                        position=(
                            side * (depth + 3.0),
                            corridor.floor_at(along - 3.5) - 0.4,
                            along - 3.5,
                        ),
                        yaw=_hash01(seed + index, side_index * 11 + 5) * 360.0,
                    )
                )

        # Overhead arches, alternating sides so the eye gets a left-right beat
        # rather than a single file. Each side steps twice the cadence, offset
        # by one, which makes the combined rhythm land on the cadence itself.
        if style.get("canopy_arch"):
            stride = CANOPY_ARCH_CADENCE_M * 2.0
            offset = CANOPY_ARCH_CADENCE_M if side > 0 else 0.0
            along = offset + CANOPY_ARCH_CADENCE_M
            while along < corridor.length:
                z = corridor.z_near - along
                placements.append(
                    Placement(
                        node=f"CanopyArch{'L' if side < 0 else 'R'}{int(along)}",
                        piece=CANOPY_ARCH_PIECE,
                        position=(
                            side * inner,
                            corridor.floor_at(z)
                            + CANOPY_ARCH_CLEARANCE_M
                            + CANOPY_ARCH_DROOP_M,
                            z,
                        ),
                        yaw=_hash01(seed + int(along), side_index * 23 + 13) * 360.0,
                    )
                )
                along += stride

        # Each wall style entry forms its own depth layer; every layer has to
        # run the whole corridor or the background shows through the gaps.
        walls = list(style["walls"])
        wall_steps = max(1, math.ceil(corridor.length / WALL_PIECE_LENGTH_M))
        for index, wall in enumerate(walls):
            for step in range(wall_steps):
                placements.append(
                    Placement(
                        node=f"Wall{'L' if side < 0 else 'R'}{index}_{step}",
                        piece=wall,
                        position=(
                            side * (BAND_DEPTH_M - 2.0 - index * 5.0),
                            corridor.floor_y - 0.5,
                            mirrored_z(
                                corridor.z_near
                                - index * 6.0
                                - step * WALL_PIECE_LENGTH_M,
                                side,
                                WALL_PIECE_LENGTH_M,
                            ),
                        ),
                        yaw=0.0 if side > 0 else 180.0,
                        cast_shadow=False,
                        span_m=WALL_PIECE_LENGTH_M,
                    )
                )
    return placements


def render_environment_art(placements: Sequence[Placement], ids: dict[str, str]) -> str:
    """The EnvironmentArt subtree as .tscn text."""
    lines = [f'[node name="{ENVIRONMENT_NODE}" type="Node3D" parent="."]', ""]
    for placement in placements:
        lines.append(
            f'[node name="{placement.node}" type="MeshInstance3D" '
            f'parent="{ENVIRONMENT_NODE}"]'
        )
        x, y, z = placement.position
        lines.append(f"position = Vector3({_number(x)}, {_number(y)}, {_number(z)})")
        if abs(placement.yaw) > 1e-6:
            lines.append(f"rotation_degrees = Vector3(0, {_number(placement.yaw)}, 0)")
        lines.append(f'mesh = ExtResource("{ids[placement.piece]}")')
        if not placement.cast_shadow:
            lines.append("cast_shadow = 0")
        lines.append("")
    return "\n".join(lines)


def _number(value: float) -> str:
    rounded = round(value, 3)
    if math.isclose(rounded, int(rounded), abs_tol=1e-9):
        return str(int(rounded))
    return str(rounded)


def strip_existing(text: str) -> str:
    """Remove a previously generated EnvironmentArt subtree, if any."""
    marker = f'[node name="{ENVIRONMENT_NODE}" type="Node3D" parent="."]'
    start = text.find(marker)
    if start < 0:
        return text
    # Everything from the marker to the next node that is not one of its
    # children. Children are the only nodes parented to EnvironmentArt.
    remainder = text[start + len(marker) :]
    offset = 0
    for match in re.finditer(r"^\[node .*$", remainder, flags=re.MULTILINE):
        attributes = header_attributes(match.group(0))
        if attributes.get("parent") != ENVIRONMENT_NODE:
            offset = match.start()
            break
    else:
        offset = len(remainder)
    return text[:start] + remainder[offset:]


def ensure_ext_resources(text: str, pieces: Sequence[str]) -> tuple[str, dict[str, str]]:
    """Add a Mesh ext_resource per piece, reusing any already present."""
    ids: dict[str, str] = {}
    existing = dict(
        re.findall(
            r'\[ext_resource type="Mesh" path="[^"]*/mesh/([a-z0-9_]+)\.res" '
            r'id="([^"]+)"\]',
            text,
        )
    )
    additions: list[str] = []
    used = set(re.findall(r'id="([^"]+)"', text))
    for piece in pieces:
        if piece in existing:
            ids[piece] = existing[piece]
            continue
        identifier = f"env_{piece}"
        suffix = 0
        while identifier in used:
            suffix += 1
            identifier = f"env_{piece}_{suffix}"
        used.add(identifier)
        ids[piece] = identifier
        additions.append(
            f'[ext_resource type="Mesh" path="{MESH_DIR}/{piece}.res" '
            f'id="{identifier}"]'
        )
    if not additions:
        return text, ids
    lines = text.splitlines()
    last = max(
        index for index, line in enumerate(lines) if line.startswith("[ext_resource ")
    )
    lines[last + 1 : last + 1] = additions
    return "\n".join(lines) + ("\n" if text.endswith("\n") else ""), ids


def nested_segments(segment_dir: Path) -> set[str]:
    """Segment scenes that are instanced *inside* another segment.

    ``boulders_chase_obstacle`` is a reusable obstacle block, not a stretch of
    level. Dressing it would place scenery relative to wherever it is instanced
    -- which is inside the corridor -- and duplicate it at every use site.
    """
    nested: set[str] = set()
    for path in sorted(segment_dir.glob("*.tscn")):
        for match in re.finditer(
            r'\[ext_resource type="PackedScene" '
            r'path="res://scenes/segments/([a-z0-9_]+)\.tscn"',
            path.read_text(encoding="utf-8"),
        ):
            if match.group(1) != path.stem:
                nested.add(match.group(1))
    return nested


def undress(text: str) -> str:
    """Remove everything a previous run of this script added.

    Nodes alone are not enough: the ext_resource lines and the load_steps count
    would accumulate on every re-run, so the generator has to be able to put a
    scene back exactly as it found it.
    """
    text = strip_existing(text)
    lines = text.splitlines()
    kept = [
        line
        for line in lines
        if not (line.startswith("[ext_resource ") and 'id="env_' in line)
    ]
    removed = len(lines) - len(kept)
    # Trailing blank lines are what the stripped subtree left behind. Dropping
    # them is what makes a full undress byte-identical to the original file.
    while kept and not kept[-1].strip():
        kept.pop()
    text = "\n".join(kept) + ("\n" if text.endswith("\n") else "")
    return bump_load_steps(text, -removed)


def bump_load_steps(text: str, added: int) -> str:
    """Keep the gd_scene load_steps header honest about the resource count."""
    if added == 0:
        return text

    def replace(match: re.Match) -> str:
        return f"load_steps={int(match.group(1)) + added}"

    return re.sub(r"load_steps=(\d+)", replace, text, count=1)


# --- the warp room -----------------------------------------------------
# A 24 m square chamber rather than a corridor, so its dressing is authored
# rather than scattered: four corner pillars, banners on the wall spans between
# the portals, and braziers flanking the boss dais. Placement is by hand because
# there are eleven nodes and every one of them has a reason.

WARP_ROOM_PATH = Path("scenes/levels/warp_room_1.tscn")

# Chamber is 24x24 with walls at +-12 and portals at the cardinal points, so
# decor lives in the corners and on the wall spans the portals do not use.
WARP_ROOM_PLACEMENTS: tuple[Placement, ...] = (
    Placement("PillarNorthWest", "pillar_carved_a", (-9.6, 0.0, -9.6), 0.0),
    Placement("PillarNorthEast", "pillar_carved_a", (9.6, 0.0, -9.6), 0.0),
    Placement("PillarSouthWest", "pillar_carved_a", (-9.6, 0.0, 9.6), 0.0),
    Placement("PillarSouthEast", "pillar_carved_a", (9.6, 0.0, 9.6), 0.0),
    # Banners flank the beach portal on the north wall and face into the room.
    Placement("BannerNorthWest", "wall_banner_a", (-5.2, 0.0, -11.7), 0.0),
    Placement("BannerNorthEast", "wall_banner_a", (5.2, 0.0, -11.7), 0.0),
    Placement("BannerWest", "wall_banner_a", (-11.7, 0.0, 3.6), 90.0),
    Placement("BannerEast", "wall_banner_a", (11.7, 0.0, 3.6), -90.0),
    # Braziers flanking the boss dais: the room's only warm light, pointing the
    # player at the door that matters.
    Placement("BrazierDaisWest", "brazier_bowl_a", (-3.4, 0.0, 6.4), 0.0),
    Placement("BrazierDaisEast", "brazier_bowl_a", (3.4, 0.0, 6.4), 0.0),
    Placement("TotemGuardian", "totem_tall_a", (0.0, 0.0, 11.2), 180.0),
)

# Nothing may sit closer than this to the room's centre line through a portal,
# or it blocks the walk into a level.
PORTAL_KEEPOUT_M = 2.6
WARP_ROOM_PORTALS = ((0.0, -9.7), (-9.7, -3.4), (9.7, -3.4), (0.0, 8.4))


def dress_warp_room(path: Path) -> int:
    """Dress the warp room chamber. Returns the node count."""
    text = path.read_text(encoding="utf-8")
    text = undress(text)
    pieces = sorted({placement.piece for placement in WARP_ROOM_PLACEMENTS})
    before = len(re.findall(r"\[ext_resource ", text))
    text, ids = ensure_ext_resources(text, pieces)
    added = len(re.findall(r"\[ext_resource ", text)) - before
    text = bump_load_steps(text, added)
    body = render_environment_art(WARP_ROOM_PLACEMENTS, ids)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + "\n" + body, encoding="utf-8")
    return len(WARP_ROOM_PLACEMENTS)


def dress_segment(path: Path) -> int:
    """Rewrite one segment with generated scenery. Returns the node count."""
    style = next(
        (value for prefix, value in STYLE_BY_PREFIX.items() if path.name.startswith(prefix)),
        None,
    )
    if style is None:
        return 0
    text = path.read_text(encoding="utf-8")
    corridor = corridor_of(parse_platforms(text))
    if corridor is None:
        return 0

    placements = placements_for(path.stem, corridor, style)
    text = undress(text)
    pieces = sorted({placement.piece for placement in placements})
    before = len(re.findall(r"\[ext_resource ", text))
    text, ids = ensure_ext_resources(text, pieces)
    added = len(re.findall(r"\[ext_resource ", text)) - before
    text = bump_load_steps(text, added)

    body = render_environment_art(placements, ids)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + "\n" + body, encoding="utf-8")
    return len(placements)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=_REPO_ROOT)
    arguments = parser.parse_args(argv)

    segment_dir = arguments.repo_root / SEGMENT_DIR
    nested = nested_segments(segment_dir)
    total = 0
    dressed = 0
    for path in sorted(segment_dir.glob("*.tscn")):
        if path.stem in nested:
            # Reusable block, not a stretch of level. Undress it in case an
            # earlier run dressed it before this exclusion existed.
            original = path.read_text(encoding="utf-8")
            cleaned = undress(original)
            if cleaned != original:
                path.write_text(cleaned, encoding="utf-8")
                print(f"UNDRESSED {path.name} (instanced by another segment)")
            continue
        count = dress_segment(path)
        if count:
            dressed += 1
            total += count
            print(f"DRESSED {path.name} {count}")

    warp_room = arguments.repo_root / WARP_ROOM_PATH
    if warp_room.is_file():
        count = dress_warp_room(warp_room)
        dressed += 1
        total += count
        print(f"DRESSED {warp_room.name} {count}")
    print(f"DRESS_TOTAL {dressed} scene(s), {total} scenery node(s)")

    # Regenerating EnvironmentArt drops the animated material overrides with it,
    # so re-attach them here rather than trusting anyone to remember a second
    # command. Without this a re-dress silently freezes every palm and fern it
    # touches, and nothing in the engine or the lints would say so.
    from scripts.route_kit_materials import main as route_materials

    route_materials(["--repo-root", str(arguments.repo_root)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
