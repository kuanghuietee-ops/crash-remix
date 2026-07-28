#!/usr/bin/env python3
"""Paint the N. Sanity Beach kit's atlas and trim sheet.

Every texel is generated from the palette in ``env_kit_palette`` plus seeded
noise, so the textures are original by construction, reproducible byte for byte,
and impossible to accidentally source from a shipped game.

Run it with::

    python3 scripts/build_kit_textures.py

Output lands in ``assets/textures/``. Godot must then import the PNGs
(``godot --headless --path . --import``) before the ``.import`` sidecars exist
to be set to VRAM compression -- see docs/art/import-export-contract.md.

*Why the grain is zero-mean.* Mipmapping averages texels, so a cell whose noise
had a bias would drift off its palette colour at distance and stop matching the
graybox floor it was authored against. Every noise field here has its mean
subtracted before it is applied.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path
from typing import Sequence

import numpy as np

# The palette lives under scripts/blender/ because Blender needs it on a bare
# path, but it must resolve to one module object whether this file is run
# directly or imported as scripts.build_kit_textures -- two copies of the layout
# constants is exactly the drift this module exists to prevent.
_REPO_ROOT = Path(__file__).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from scripts.blender.env_kit_palette import (  # noqa: E402  (path set up above)
    ATLAS_CELL_MARGIN_PX,
    ATLAS_CELL_PX,
    ATLAS_CELLS_PER_SIDE,
    ATLAS_ORDER,
    ATLAS_SIZE,
    GRAIN_STRENGTH,
    PALETTE,
    TRIM_BAND_PX,
    TRIM_BANDS,
    TRIM_HEIGHT,
    TRIM_STRATA_PER_BAND,
    TRIM_STRATA_STRENGTH,
    TRIM_WIDTH,
    atlas_cell_pixels,
    trim_band_pixels,
)

ATLAS_NAME = "T_beach_kit_atlas.png"
TRIM_NAME = "T_beach_kit_trim.png"

# One seed per texture. Cells derive their own from this plus the cell index, so
# adding a palette entry cannot reshuffle the grain of the cells before it.
ATLAS_SEED = 20260728
TRIM_SEED = 20260729

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _family(name: str) -> str:
    """Which grain character a palette entry gets.

    Grouped by how the real material behaves rather than by colour: sand is fine
    and isotropic, rock mottles in patches, foliage and bark streak along one
    axis, water is smooth.
    """
    if name.startswith("sand") or name in ("shell", "driftwood"):
        return "fine"
    if name.startswith("rock") or name == "coconut":
        return "mottle"
    if name.startswith("leaf") or name in ("frond", "flower"):
        return "leaf"
    if name.startswith("trunk"):
        return "bark"
    if name.startswith("water") or name == "foam":
        return "smooth"
    return "fine"


def _upscale(field: np.ndarray, height: int, width: int) -> np.ndarray:
    """Nearest-neighbour upscale of a small noise field to full cell size."""
    rows = np.linspace(0, field.shape[0], height, endpoint=False).astype(int)
    columns = np.linspace(0, field.shape[1], width, endpoint=False).astype(int)
    return field[np.ix_(rows, columns)]


def _blur(field: np.ndarray, radius: int) -> np.ndarray:
    """Cheap separable box blur, so mottling reads as patches not static."""
    if radius < 1:
        return field
    window = 2 * radius + 1
    kernel = np.ones(window) / window
    blurred = np.apply_along_axis(
        lambda row: np.convolve(row, kernel, mode="same"), 1, field
    )
    return np.apply_along_axis(
        lambda column: np.convolve(column, kernel, mode="same"), 0, blurred
    )


def grain_field(family: str, height: int, width: int, seed: int) -> np.ndarray:
    """A zero-mean noise field with the character of ``family``."""
    rng = np.random.default_rng(seed)
    if family == "fine":
        field = rng.random((height, width))
    elif family == "mottle":
        field = _blur(_upscale(rng.random((16, 16)), height, width), 6)
    elif family == "leaf":
        field = _upscale(rng.random((24, 6)), height, width)
        field = _blur(field, 2)
    elif family == "bark":
        field = _upscale(rng.random((4, 40)), height, width)
        field = _blur(field, 2)
    elif family == "smooth":
        field = _blur(_upscale(rng.random((8, 8)), height, width), 10)
    else:  # pragma: no cover - _family never returns anything else
        raise ValueError(f"unknown grain family {family!r}")
    return field - field.mean()


def atlas_pixels() -> np.ndarray:
    """The full atlas as an ``(ATLAS_SIZE, ATLAS_SIZE, 3)`` uint8 array."""
    image = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 3), dtype=np.float64)
    cell_count = ATLAS_CELLS_PER_SIDE * ATLAS_CELLS_PER_SIDE
    for index in range(cell_count):
        # Spare cells repeat the palette so a stray UV samples a real colour.
        name = ATLAS_ORDER[index % len(ATLAS_ORDER)]
        column = index % ATLAS_CELLS_PER_SIDE
        row = index // ATLAS_CELLS_PER_SIDE
        left = column * ATLAS_CELL_PX
        top = row * ATLAS_CELL_PX
        grain = grain_field(
            _family(name), ATLAS_CELL_PX, ATLAS_CELL_PX, ATLAS_SEED + index
        )
        colour = np.array(PALETTE[name], dtype=np.float64)
        cell = colour[None, None, :] + grain[:, :, None] * GRAIN_STRENGTH
        image[top : top + ATLAS_CELL_PX, left : left + ATLAS_CELL_PX] = cell
    return _to_bytes(image)


def trim_pixels() -> np.ndarray:
    """The trim sheet as a ``(TRIM_HEIGHT, TRIM_WIDTH, 3)`` uint8 array."""
    image = np.zeros((TRIM_HEIGHT, TRIM_WIDTH, 3), dtype=np.float64)
    for index, name in enumerate(TRIM_BANDS):
        _, top, _, bottom = trim_band_pixels(name)
        height = bottom - top
        colour = np.array(PALETTE[name], dtype=np.float64)
        band = np.repeat(
            np.repeat(colour[None, None, :], height, axis=0), TRIM_WIDTH, axis=1
        )

        # Strata: horizontal seams of alternating lightness running the length of
        # the band. This is the whole reason the trim sheet exists -- a cliff
        # face mapped across a band gets layering an atlas cell cannot give it.
        rng = np.random.default_rng(TRIM_SEED + index)
        edges = np.sort(rng.choice(np.arange(4, height - 4), TRIM_STRATA_PER_BAND - 1, replace=False))
        starts = np.concatenate(([0], edges))
        ends = np.concatenate((edges, [height]))
        steps = rng.uniform(-1.0, 1.0, TRIM_STRATA_PER_BAND)
        # Weight by how many rows each stratum actually covers. Subtracting the
        # plain mean would only balance the step *values*, and the strata are
        # deliberately uneven heights, so the band would still drift off colour.
        steps -= float((steps * (ends - starts)).sum()) / height
        for start, end, step in zip(starts, ends, steps):
            band[start:end] += step * TRIM_STRATA_STRENGTH

        grain = grain_field("mottle", height, TRIM_WIDTH, TRIM_SEED + 100 + index)
        band += grain[:, :, None] * GRAIN_STRENGTH
        image[top:bottom] = band
    return _to_bytes(image)


def _to_bytes(image: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(image * 255.0), 0, 255).astype(np.uint8)


def _chunk(kind: bytes, body: bytes) -> bytes:
    return (
        struct.pack(">I", len(body))
        + kind
        + body
        + struct.pack(">I", zlib.crc32(kind + body))
    )


def encode_png(pixels: np.ndarray) -> bytes:
    """Encode an ``(h, w, 3)`` uint8 array as an 8-bit RGB PNG."""
    if pixels.ndim != 3 or pixels.shape[2] != 3:
        raise ValueError("expected an (h, w, 3) RGB array")
    height, width = pixels.shape[0], pixels.shape[1]
    # Filter byte 0 (None) in front of every row. The images are noise-heavy, so
    # a smarter filter buys little and costs reproducibility risk.
    raw = np.concatenate(
        [np.zeros((height, 1), dtype=np.uint8), pixels.reshape(height, width * 3)],
        axis=1,
    ).tobytes()
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def write_png(path: Path, pixels: np.ndarray) -> None:
    path.write_bytes(encode_png(pixels))


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "assets" / "textures",
        help="where the PNGs are written (default: assets/textures)",
    )
    arguments = parser.parse_args(argv)
    arguments.out_dir.mkdir(parents=True, exist_ok=True)

    atlas_path = arguments.out_dir / ATLAS_NAME
    trim_path = arguments.out_dir / TRIM_NAME
    write_png(atlas_path, atlas_pixels())
    write_png(trim_path, trim_pixels())

    print(f"KIT_TEXTURE {ATLAS_NAME} {ATLAS_SIZE}x{ATLAS_SIZE} {atlas_path.stat().st_size}")
    print(f"KIT_TEXTURE {TRIM_NAME} {TRIM_WIDTH}x{TRIM_HEIGHT} {trim_path.stat().st_size}")
    print(
        f"KIT_TEXTURE_CELLS {len(ATLAS_ORDER)} palette cells, "
        f"{len(TRIM_BANDS)} trim bands of {TRIM_BAND_PX}px, "
        f"{ATLAS_CELL_MARGIN_PX}px cell margin"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
