#!/usr/bin/env python3
"""Read texture dimensions and Godot import settings for the art budget lint."""

from __future__ import annotations

import struct
from pathlib import Path

try:
    from scene_transform_parsing import assignment_values
except ModuleNotFoundError:  # invoked as scripts.texture_budget
    from scripts.scene_transform_parsing import assignment_values

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
IHDR_OFFSET = 16  # 8-byte signature + 4-byte length + 4-byte "IHDR"
IHDR_END = 24
# Godot's texture importer: 0 = lossless, 1 = lossy, 2 = VRAM compressed,
# 3 = uncompressed. Only mode 2 yields the ASTC/ETC2 the mobile budget assumes.
VRAM_COMPRESSED_MODE = "2"


class MalformedTextureError(Exception):
    """Raised when a texture cannot be parsed well enough to prove its size."""


def png_dimensions(path: Path) -> tuple[int, int]:
    """Return (width, height) from a PNG's IHDR chunk."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise MalformedTextureError(f"{path}: cannot be read: {error}") from error
    if not data.startswith(PNG_SIGNATURE):
        raise MalformedTextureError(f"{path}: not a PNG (bad signature)")
    if len(data) < IHDR_END:
        raise MalformedTextureError(f"{path}: truncated before its IHDR chunk")
    width, height = struct.unpack_from(">II", data, IHDR_OFFSET)
    if width <= 0 or height <= 0:
        raise MalformedTextureError(f"{path}: IHDR reports a zero dimension")
    return width, height


def is_power_of_two(value: int) -> bool:
    return value > 0 and value & (value - 1) == 0


def import_uses_vram_compression(import_path: Path) -> bool:
    """Return whether a .import sidecar selects Godot's VRAM-compressed mode."""
    if not import_path.is_file():
        return False
    values = assignment_values(import_path.read_text(encoding="utf-8"))
    return values.get("compress/mode") == VRAM_COMPRESSED_MODE
