"""Palette and texture layout for the N. Sanity Beach environment kit.

Deliberately free of ``bpy`` so the same numbers drive three things that must
never disagree: the Blender build that writes UVs, the generator that paints
the atlas, and the tests that check both. If this module ever imports Blender,
the tests stop being able to prove the UVs land on the colours they claim to.

*Colour space.* Every entry below is **sRGB**, matching how
``StandardMaterial3D.albedo_color`` is authored in the beach segments. Blender's
Principled base colour is linear, so the build converts on the way in; the atlas
generator writes sRGB bytes straight out, because that is what a PNG holds.

*Why an atlas at all.* The first version of the kit gave every palette colour its
own material slot, so a rock cluster cost four draw calls and the whole kit cost
far more than its geometry deserved. Encoding the colour in UVs instead collapses
each piece to a single slot, which is what design doc 9.4's 120-draw-call budget
actually needs, and it buys room for hand-painted grain that flat albedo cannot
carry.
"""

from __future__ import annotations

from typing import Sequence

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

# --- atlas layout ------------------------------------------------------
# 8x8 cells of 256px in a 2048 square. The palette occupies the leading cells in
# sorted order; the spare cells repeat the palette cyclically, so a UV that
# escapes its cell samples a real kit colour instead of void.

ATLAS_SIZE = 2048
ATLAS_CELLS_PER_SIDE = 8
ATLAS_CELL_PX = ATLAS_SIZE // ATLAS_CELLS_PER_SIDE

# The guard band each cell keeps between its painted content and its UV
# rectangle. Mipmapping averages neighbouring texels, and by the fifth mip a
# 256px cell is 8px wide, so without a margin one cell's colour bleeds into the
# next. The whole cell -- margin included -- is painted its own colour, so what
# bleeds in is the same hue rather than the neighbour's.
ATLAS_CELL_MARGIN_PX = 16

# Grain is zero-mean on purpose: every mip level averages back to the exact
# palette colour, so a piece seen from across the level reads as the flat colour
# the segments were authored against.
GRAIN_STRENGTH = 0.055

ATLAS_ORDER: tuple[str, ...] = tuple(sorted(PALETTE))

# --- trim sheet layout -------------------------------------------------
# Horizontal strata bands for the rock family. Cliffs, boulders and the rock
# cluster map across a band instead of into a flat cell, which is the one thing
# an atlas cell cannot give them: layering that runs up the face.

TRIM_WIDTH = 2048
TRIM_HEIGHT = 512
TRIM_BANDS: tuple[str, ...] = ("rock_light", "rock_mid", "rock_dark", "rock_warm")
TRIM_BAND_PX = TRIM_HEIGHT // len(TRIM_BANDS)
TRIM_BAND_MARGIN_PX = 8
TRIM_STRATA_PER_BAND = 5
TRIM_STRATA_STRENGTH = 0.12


class UnknownPaletteError(KeyError):
    """Raised when a piece asks for a colour the layout cannot place.

    Fails closed rather than falling back to cell zero: a silent fallback would
    paint sand onto a leaf and nothing downstream would notice.
    """


def atlas_cell_index(name: str) -> int:
    """Position of ``name`` in the atlas, in reading order from the top left."""
    try:
        return ATLAS_ORDER.index(name)
    except ValueError:
        raise UnknownPaletteError(
            f"{name!r} is not in the environment palette, so it has no atlas cell"
        ) from None


def atlas_cell_pixels(name: str) -> tuple[int, int, int, int]:
    """Pixel bounds ``(left, top, right, bottom)`` of a cell, margin included."""
    index = atlas_cell_index(name)
    column = index % ATLAS_CELLS_PER_SIDE
    row = index // ATLAS_CELLS_PER_SIDE
    left = column * ATLAS_CELL_PX
    top = row * ATLAS_CELL_PX
    return left, top, left + ATLAS_CELL_PX, top + ATLAS_CELL_PX


def atlas_uv_rect(name: str) -> tuple[float, float, float, float]:
    """UV rectangle ``(u0, v0, u1, v1)`` a face of ``name`` may occupy.

    Inset by the guard band, and returned in Godot's UV convention where v
    counts down from the top of the image -- the same direction the pixel rows
    are written, so cell 0 is the top-left in both.
    """
    left, top, right, bottom = atlas_cell_pixels(name)
    margin = ATLAS_CELL_MARGIN_PX
    return (
        (left + margin) / ATLAS_SIZE,
        (top + margin) / ATLAS_SIZE,
        (right - margin) / ATLAS_SIZE,
        (bottom - margin) / ATLAS_SIZE,
    )


def trim_band_index(name: str) -> int:
    try:
        return TRIM_BANDS.index(name)
    except ValueError:
        raise UnknownPaletteError(
            f"{name!r} has no trim band. The trim sheet carries the rock family "
            f"only ({', '.join(TRIM_BANDS)}); a piece painted with anything else "
            "must use the atlas."
        ) from None


def trim_band_pixels(name: str) -> tuple[int, int, int, int]:
    """Pixel bounds ``(left, top, right, bottom)`` of a band, margin included."""
    index = trim_band_index(name)
    top = index * TRIM_BAND_PX
    return 0, top, TRIM_WIDTH, top + TRIM_BAND_PX


def trim_uv_rect(name: str) -> tuple[float, float, float, float]:
    """UV rectangle a face mapped onto the ``name`` strata band may occupy."""
    left, top, right, bottom = trim_band_pixels(name)
    margin = TRIM_BAND_MARGIN_PX
    return (
        (left + margin) / TRIM_WIDTH,
        (top + margin) / TRIM_HEIGHT,
        (right - margin) / TRIM_WIDTH,
        (bottom - margin) / TRIM_HEIGHT,
    )


def srgb_to_linear(channel: float) -> float:
    """Convert one sRGB channel to the linear value Blender expects."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


# --- UV placement ------------------------------------------------------
# Kept here, free of Blender, because these two functions decide where every
# texel of the kit comes from and they are worth being able to test directly.

# How much of its rectangle one face may occupy, leaving room to be scattered.
FACE_WINDOW = 0.62


def projection_axes(normal: Sequence[float]) -> tuple[int, int]:
    """Pick the two axes to flatten a face onto, given its normal.

    Drops the axis the face faces along, so a wall is measured across its wall
    plane rather than across its thickness. Ties fall to the earlier axis, which
    only matters for perfectly diagonal faces where either answer is as good.

    Returns indices into a Blender-space ``(x, y, z)`` vector. Note the second
    axis is Z whenever the face is at all vertical -- that is what puts world
    "up" on the trim sheet's V axis, so strata run horizontally across a cliff.
    """
    x, y, z = (abs(float(component)) for component in normal)
    if z >= x and z >= y:
        return 0, 1
    if y >= x:
        return 0, 2
    return 1, 2


def face_window(
    rect: tuple[float, float, float, float], serial: int, scale: float = FACE_WINDOW
) -> tuple[float, float, float, float]:
    """A smaller rectangle inside ``rect``, positioned by ``serial``.

    Two faces painted the same colour would otherwise show the identical patch of
    grain, which reads as tiling across a hillside of rocks. The offset is a
    plain integer hash rather than ``random`` so the kit stays reproducible and
    so inserting a face cannot reshuffle every face after it in a different run.
    """
    u0, v0, u1, v1 = rect
    width = (u1 - u0) * scale
    height = (v1 - v0) * scale
    first = (serial * 2654435761 + 1013904223) & 0xFFFFFFFF
    second = (serial * 1597334677 + 12345) & 0xFFFFFFFF
    fraction_u = ((first >> 16) & 0xFFFF) / 65535.0
    fraction_v = ((second >> 16) & 0xFFFF) / 65535.0
    start_u = u0 + fraction_u * ((u1 - u0) - width)
    start_v = v0 + fraction_v * ((v1 - v0) - height)
    return start_u, start_v, start_u + width, start_v + height
