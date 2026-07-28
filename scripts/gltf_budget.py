#!/usr/bin/env python3
"""Read triangle counts out of glTF 2.0 binary (.glb) assets.

Pure parsing, no Godot and no third-party dependencies, so the budget lint
runs in the same pre-commit hook as the rest of the lint family.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

GLB_MAGIC = 0x46546C67  # 'glTF'
JSON_CHUNK_TYPE = 0x4E4F534A  # 'JSON'
GLB_HEADER_SIZE = 12
CHUNK_HEADER_SIZE = 8

# glTF 2.0 primitive modes. 0-3 are points and lines and carry no triangles.
MODE_TRIANGLES = 4
MODE_TRIANGLE_STRIP = 5
MODE_TRIANGLE_FAN = 6
DEFAULT_MODE = MODE_TRIANGLES

VERTICES_PER_TRIANGLE = 3
STRIP_FAN_OVERHEAD = 2


class MalformedGlbError(Exception):
    """Raised when a .glb cannot be parsed well enough to prove a count."""


def read_glb_json(data: bytes) -> dict:
    """Return the JSON chunk of a .glb as a dict."""
    if len(data) < GLB_HEADER_SIZE:
        raise MalformedGlbError("file is shorter than a glTF header")
    magic, version, total_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise MalformedGlbError("not a glTF binary file (bad magic)")
    if version != 2:
        raise MalformedGlbError(f"unsupported glTF binary version {version}")
    if total_length > len(data):
        raise MalformedGlbError(
            f"header declares {total_length} bytes but the file holds {len(data)}"
        )
    offset = GLB_HEADER_SIZE
    if offset + CHUNK_HEADER_SIZE > len(data):
        raise MalformedGlbError("file ends before its first chunk header")
    chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
    offset += CHUNK_HEADER_SIZE
    if chunk_type != JSON_CHUNK_TYPE:
        raise MalformedGlbError("first chunk is not the JSON chunk")
    if offset + chunk_length > len(data):
        raise MalformedGlbError("JSON chunk runs past the end of the file")
    try:
        return json.loads(data[offset : offset + chunk_length].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MalformedGlbError(f"JSON chunk is not readable: {error}") from error


def triangle_count(document: dict) -> int:
    """Return the total triangles across every mesh primitive in a glTF document."""
    accessors = document.get("accessors", [])
    total = 0
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            total += _primitive_triangles(
                primitive, accessors, f"meshes[{mesh_index}].primitives[{primitive_index}]"
            )
    return total


def triangle_count_of_file(path: Path) -> int:
    """Return the triangle count of a .glb on disk."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise MalformedGlbError(f"{path}: cannot be read: {error}") from error
    return triangle_count(read_glb_json(data))


def _primitive_triangles(primitive: dict, accessors: list, where: str) -> int:
    mode = primitive.get("mode", DEFAULT_MODE)
    if mode not in (MODE_TRIANGLES, MODE_TRIANGLE_STRIP, MODE_TRIANGLE_FAN):
        return 0
    if "indices" in primitive:
        vertex_count = _accessor_count(accessors, primitive["indices"], where)
    else:
        attributes = primitive.get("attributes", {})
        if "POSITION" not in attributes:
            raise MalformedGlbError(
                f"{where}: has neither an index accessor nor a POSITION attribute, "
                "so its triangle count cannot be proven"
            )
        vertex_count = _accessor_count(accessors, attributes["POSITION"], where)
    if mode == MODE_TRIANGLES:
        return vertex_count // VERTICES_PER_TRIANGLE
    return max(vertex_count - STRIP_FAN_OVERHEAD, 0)


def _accessor_count(accessors: list, index: int, where: str) -> int:
    if not isinstance(index, int) or index < 0 or index >= len(accessors):
        raise MalformedGlbError(f"{where}: accessor index {index!r} does not exist")
    count = accessors[index].get("count")
    if not isinstance(count, int) or count < 0:
        raise MalformedGlbError(f"{where}: accessor {index} has no usable count")
    return count
