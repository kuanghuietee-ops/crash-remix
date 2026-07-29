#!/usr/bin/env python3
"""Which kit pieces get an animated material, and which one.

One table, imported by everything that writes scenes, because the routing is
split across two very different producers: the generated dressing in
``dress_island_cut.py`` and the hand-authored beach segments. When those two
disagree, half the ferns on the island move and half do not, and nothing errors.

Routing is by **piece name**, deliberately. The current kit is a placeholder
that the operator's own models replace at rung 4 of the art ladder, and the
import/export contract already routes materials by name -- so a hand-made
``palm_tall_a`` inherits the sway for free, without this file changing.
"""

from __future__ import annotations

MATERIAL_DIR = "res://assets/materials"

SEA_MATERIAL = "M_beach_kit_sea"
FOAM_MATERIAL = "M_beach_kit_foam"
FOLIAGE_MATERIAL = "M_beach_kit_foliage"

# Piece stem -> material resource name.
#
# The plant family is everything that would move in wind. Trunk-only pieces
# (driftwood, coconut clusters lying on sand) are excluded: they are dead wood
# and swaying them reads as an error, not as life.
ANIMATED_PIECES: dict[str, str] = {
    "water_sea_tile": SEA_MATERIAL,
    "surf_foam_edge": FOAM_MATERIAL,
    "palm_tall_a": FOLIAGE_MATERIAL,
    "palm_lean_a": FOLIAGE_MATERIAL,
    "fern_cluster_a": FOLIAGE_MATERIAL,
    "bush_cluster_a": FOLIAGE_MATERIAL,
    "grass_patch_a": FOLIAGE_MATERIAL,
    "fringe_grass_a": FOLIAGE_MATERIAL,
    "canopy_frond_arch": FOLIAGE_MATERIAL,
    "jungle_tree_a": FOLIAGE_MATERIAL,
    "jungle_tree_b": FOLIAGE_MATERIAL,
}

# Pieces that share the plant palette but must NOT move, recorded so the
# omission reads as a decision rather than an oversight.
STATIC_BY_DESIGN: dict[str, str] = {
    "driftwood_a": "beached dead wood; swaying it reads as a physics bug",
    "coconut_cluster_a": "fallen fruit resting on sand",
    "shell_scatter_a": "shells on sand",
    "hut_thatch_a": "a building; thatch roofs do not sway as one body",
}


def material_path(resource_name: str) -> str:
    return f"{MATERIAL_DIR}/{resource_name}.tres"


def material_for(piece: str) -> str | None:
    """The animated material a piece should carry, or None if it stays static."""
    return ANIMATED_PIECES.get(piece)


def animated_piece_names() -> tuple[str, ...]:
    return tuple(sorted(ANIMATED_PIECES))


def material_names() -> tuple[str, ...]:
    return tuple(sorted(set(ANIMATED_PIECES.values())))
