"""Generate the village and interior props for Papu's arena and the warp room.

Environment art only -- totems, huts, fences, braziers, pillars and banners.
Nothing here builds, touches or depends on characters, crates, enemies or any
gameplay object. Papu himself is rung 7 of the art ladder and is not in scope;
this script builds the place he stands in, not him.

Shares the kit's atlas, palette and single-material rule with
``build_beach_env_kit.py``, so a warp room pillar and a beach palm cost one
draw call between them rather than two.

Run it with::

    blender --background --factory-startup \\
        --python scripts/blender/build_island_props.py
    godot --headless --path . --import

Output lands in ``assets/models/kits/`` alongside the beach pieces, and the
extracted meshes the scenes reference land in ``assets/models/kits/mesh/``.

Same Z-up convention as the beach kit: Blender +Z is Godot +Y, Blender +Y is
Godot -Z. Props rest on Z = 0 so they sit on the floor they are placed on.
"""

from __future__ import annotations

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_beach_env_kit import (  # noqa: E402  (path set up above)
    _invalidate,
    _material_name,
    _patch_import_sidecar,
)
from env_kit_common import (  # noqa: E402
    Piece,
    add_blade,
    add_box,
    add_cylinder,
    export_glb,
    reset_scene,
)


# --- village props: Papu's arena ---------------------------------------


def build_totem() -> None:
    """A stacked carved totem. Reads as "someone lives here" from far off."""
    rng = random.Random(6101)
    piece = Piece("totem_tall_a")
    add_cylinder(piece, (0.0, 0.0, 0.0), 0.5, 0.85, 0.8, "stone_shadow", sides=8)
    height = 0.5
    for index in range(4):
        block = 1.15 - index * 0.07
        tone = "wood_post" if index % 2 == 0 else "wood_dark"
        add_box(
            piece,
            (0.0, 0.0, height + block / 2.0),
            (1.3 - index * 0.09, 1.15 - index * 0.08, block),
            tone,
            rotation_z=rng.uniform(-0.12, 0.12),
        )
        # Carved brow: a slab that juts out, which is what actually reads as a
        # face at phone size rather than any amount of surface detail.
        add_box(
            piece,
            (0.0, -0.62 + index * 0.02, height + block * 0.72),
            (1.05 - index * 0.08, 0.22, 0.2),
            "cloth_ochre" if index % 2 else "cloth_red",
        )
        height += block
    add_box(piece, (0.0, 0.0, height + 0.18), (1.5, 1.3, 0.36), "wood_dark", taper=0.55)
    piece.finish()


def build_hut() -> None:
    """Thatched round hut. Conical roof over a stubby drum."""
    piece = Piece("hut_thatch_a")
    add_cylinder(piece, (0.0, 0.0, 0.0), 2.2, 2.5, 2.35, "wood_post", sides=9, rings=2)
    # Roof: a wide cone that overhangs the wall so the silhouette has a lip.
    add_cylinder(piece, (0.0, 0.0, 2.15), 1.9, 3.05, 0.12, "thatch", sides=9, rings=3)
    add_cylinder(piece, (0.0, 0.0, 4.0), 0.35, 0.16, 0.05, "wood_dark", sides=5, rings=1)
    # Doorway, as a recessed dark panel rather than real geometry.
    add_box(piece, (0.0, -2.42, 0.85), (1.15, 0.2, 1.7), "wood_dark")
    piece.finish()


def build_torch_post() -> None:
    """A post with a burning bowl. The arena's only warm light source."""
    piece = Piece("torch_post_a")
    add_cylinder(piece, (0.0, 0.0, 0.0), 2.5, 0.16, 0.13, "wood_post", sides=6)
    add_cylinder(piece, (0.0, 0.0, 2.4), 0.35, 0.5, 0.42, "stone_shadow", sides=8, rings=1)
    add_cylinder(piece, (0.0, 0.0, 2.7), 0.42, 0.38, 0.1, "ember", sides=7, rings=2)
    piece.finish()


def build_log_fence() -> None:
    """A run of lashed stakes, 6 m long, for ringing the arena terraces."""
    rng = random.Random(6202)
    piece = Piece("log_fence_a")
    for index in range(9):
        y = -3.0 + index * 0.75
        add_cylinder(
            piece,
            (rng.uniform(-0.05, 0.05), y, 0.0),
            rng.uniform(1.5, 1.95),
            0.12,
            0.09,
            "wood_post" if index % 3 else "wood_dark",
            sides=5,
            lean=(rng.uniform(-0.1, 0.1), 0.0),
        )
    # Two rails, which is what stops it reading as a row of unrelated sticks.
    for height in (0.75, 1.35):
        add_box(piece, (0.0, 0.0, height), (0.1, 6.2, 0.1), "wood_dark")
    piece.finish()


def build_standing_stone() -> None:
    """A leaning carved monolith. Arena furniture with a strong silhouette."""
    rng = random.Random(6303)
    piece = Piece("standing_stone_a", uses_trim=False)
    add_box(piece, (0.0, 0.0, 1.6), (1.1, 0.75, 3.2), "stone_carved", rotation_z=0.16, taper=0.7)
    add_box(piece, (0.0, 0.0, 0.22), (1.7, 1.3, 0.45), "stone_shadow")
    # Carved notches down the face. A monolith that is one tapered box has no
    # scale cue on it at all, so these are what make it read as worked stone.
    for index in range(4):
        add_box(
            piece,
            (0.42 - index * 0.02, 0.0, 0.75 + index * 0.62),
            (0.16, 0.5, 0.14),
            "stone_shadow",
            rotation_z=rng.uniform(-0.08, 0.08),
        )
    for index in range(3):
        add_box(
            piece,
            (0.0, -0.4, 0.9 + index * 0.75),
            (0.62, 0.16, 0.16),
            "cloth_ochre" if index % 2 else "cloth_red",
            rotation_z=rng.uniform(-0.1, 0.1),
        )
    piece.finish()


# --- interior props: the warp room -------------------------------------


def build_pillar() -> None:
    """A carved chamber pillar, floor to ceiling at the warp room's 4 m."""
    piece = Piece("pillar_carved_a")
    add_box(piece, (0.0, 0.0, 0.3), (1.5, 1.5, 0.6), "stone_shadow")
    add_box(piece, (0.0, 0.0, 2.1), (1.05, 1.05, 3.0), "stone_carved", taper=0.9)
    for index in range(4):
        add_box(
            piece,
            (0.0, 0.0, 1.0 + index * 0.7),
            (1.16, 1.16, 0.12),
            "stone_shadow",
        )
    # Fluting on all four faces. Vertical breaks are what give a pillar its
    # height read under the warp room's single overhead light.
    for index in range(4):
        angle = index * math.tau / 4.0
        add_box(
            piece,
            (math.cos(angle) * 0.52, math.sin(angle) * 0.52, 2.1),
            (0.14, 0.14, 2.7),
            "stone_shadow",
            rotation_z=angle,
        )
    add_box(piece, (0.0, 0.0, 3.75), (1.45, 1.45, 0.5), "stone_carved")
    piece.finish()


def build_banner() -> None:
    """A hanging cloth banner for the chamber walls."""
    piece = Piece("wall_banner_a")
    rng = random.Random(6404)
    add_box(piece, (0.0, 0.0, 2.85), (1.9, 0.14, 0.16), "wood_dark")
    # Cloth as three vertical folds rather than one slab: at 4 m the fold edges
    # are the only thing that keeps it from reading as a painted-on decal.
    for index in range(3):
        add_box(
            piece,
            (-0.52 + index * 0.52, 0.02 + (index % 2) * 0.035, 1.55),
            (0.5, 0.06, 2.5),
            "cloth_red",
        )
    add_box(piece, (0.0, 0.06, 1.55), (0.7, 0.05, 1.7), "cloth_ochre")
    # Weighted hem, so it does not read as a flat decal stuck to the wall.
    add_box(piece, (0.0, 0.02, 0.28), (1.66, 0.1, 0.18), "wood_post")
    for index in range(5):
        add_box(
            piece,
            (-0.66 + index * 0.33, 0.02, 0.09),
            (0.07, 0.07, 0.26),
            "cloth_ochre",
            rotation_z=rng.uniform(-0.2, 0.2),
        )
    piece.finish()


def build_brazier() -> None:
    """A standing fire bowl. The warp room's warm accent."""
    piece = Piece("brazier_bowl_a")
    for index in range(3):
        angle = index * math.tau / 3.0
        add_cylinder(
            piece,
            (math.cos(angle) * 0.34, math.sin(angle) * 0.34, 0.0),
            0.95,
            0.1,
            0.08,
            "wood_dark",
            sides=5,
            lean=(-math.cos(angle) * 0.22, -math.sin(angle) * 0.22),
        )
    add_cylinder(piece, (0.0, 0.0, 0.9), 0.42, 0.68, 0.6, "stone_shadow", sides=9, rings=2)
    add_cylinder(piece, (0.0, 0.0, 1.18), 0.3, 0.55, 0.12, "ember", sides=8, rings=2)
    for index in range(5):
        angle = index * math.tau / 5.0
        add_blade(
            piece,
            (math.cos(angle) * 0.2, math.sin(angle) * 0.2, 1.3),
            angle,
            0.55,
            0.16,
            "ember",
            segments=3,
            rise=0.9,
            droop=0.2,
        )
    piece.finish()


BUILDERS = [
    ("totem_tall_a", build_totem),
    ("hut_thatch_a", build_hut),
    ("torch_post_a", build_torch_post),
    ("log_fence_a", build_log_fence),
    ("standing_stone_a", build_standing_stone),
    ("pillar_carved_a", build_pillar),
    ("wall_banner_a", build_banner),
    ("brazier_bowl_a", build_brazier),
]


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.abspath(os.path.join(here, "..", "..", "assets", "models", "kits"))
    os.makedirs(os.path.join(out_dir, "mesh"), exist_ok=True)
    pending: list[str] = []
    for label, builder in BUILDERS:
        reset_scene()
        builder()
        path = os.path.join(out_dir, f"{label}.glb")
        export_glb(path)
        material_name = _material_name(bpy.context.collection.objects[0])
        _invalidate(out_dir, label)
        if not _patch_import_sidecar(out_dir, label, material_name):
            pending.append(label)
        print(f"PROP_WROTE {label}.glb {material_name} {os.path.getsize(path)}")
    print(f"PROP_TOTAL {len(BUILDERS)}")
    if pending:
        print(
            "PROP_NOTE no .import sidecar yet for: "
            + ", ".join(pending)
            + " -- run godot --headless --path . --import, then this script again."
        )


if __name__ == "__main__":
    main()
