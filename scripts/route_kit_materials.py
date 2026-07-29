#!/usr/bin/env python3
"""Attach the animated kit materials to every instance of a routed piece.

The island's scenery arrives from two producers that know nothing about each
other: ``dress_island_cut.py`` generates the verges of Boulders, Hog Wild and
Papu's arena, while the seven beach segments were hand-authored to the beach's
own 96 m rhythm. A palm is a palm in both, so the sway has to reach both or the
level is half alive -- and nothing in the engine complains about the half that
is not, which is exactly the kind of silent gap this repo tests for.

This walks every scene, finds MeshInstance3D nodes whose mesh is a routed piece,
and sets ``material_override`` to the matching material from
``kit_material_routing.py``. It is idempotent: running it twice is a no-op, and
running it after a re-dress re-attaches whatever the dresser regenerated.

Usage:
    python3 scripts/route_kit_materials.py [--repo-root PATH] [--check]

``--check`` reports drift without writing, for use as a lint.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Sequence

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from scripts.kit_material_routing import (  # noqa: E402  (path set up above)
    material_for,
    material_path,
)

SCENE_DIR = Path("scenes")

MESH_EXT_RESOURCE = re.compile(
    r'\[ext_resource type="Mesh" path="[^"]*/mesh/([a-z0-9_]+)\.res" id="([^"]+)"\]'
)
MATERIAL_EXT_RESOURCE = re.compile(
    r'\[ext_resource type="Material" path="res://assets/materials/([A-Za-z0-9_]+)\.tres" '
    r'id="([^"]+)"\]'
)
NODE_HEADER = re.compile(r'^\[node .*\]$', re.MULTILINE)
MESH_ASSIGNMENT = re.compile(r'^mesh = ExtResource\("([^"]+)"\)$', re.MULTILINE)


class RoutingError(Exception):
    """Raised when a scene cannot be routed without guessing."""


def mesh_ids(text: str) -> dict[str, str]:
    """ext_resource id -> piece stem, for every kit mesh in the scene."""
    return {match.group(2): match.group(1) for match in MESH_EXT_RESOURCE.finditer(text)}


def material_ids(text: str) -> dict[str, str]:
    """material resource name -> ext_resource id, for materials already present."""
    return {match.group(1): match.group(2) for match in MATERIAL_EXT_RESOURCE.finditer(text)}


def _next_free_index(text: str) -> int:
    used = [
        int(match)
        for match in re.findall(r'\[ext_resource [^\]]*id="(\d+)_', text)
    ]
    return (max(used) + 1) if used else 1


def ensure_material_resource(text: str, resource_name: str) -> tuple[str, str, int]:
    """Return (text, ext_resource id, number added) for a material, reusing any present."""
    present = material_ids(text)
    if resource_name in present:
        return text, present[resource_name], 0

    new_id = f"{_next_free_index(text)}_{resource_name.lower()}"
    line = (
        f'[ext_resource type="Material" path="{material_path(resource_name)}" '
        f'id="{new_id}"]'
    )
    existing = list(re.finditer(r'^\[ext_resource [^\]]*\]$', text, flags=re.MULTILINE))
    if not existing:
        raise RoutingError("scene has no ext_resource block to anchor onto")
    insert_at = existing[-1].end()
    return text[:insert_at] + "\n" + line + text[insert_at:], new_id, 1


def _node_spans(text: str) -> list[tuple[int, int]]:
    """(start, end) character spans of each node block."""
    headers = list(NODE_HEADER.finditer(text))
    spans: list[tuple[int, int]] = []
    for index, header in enumerate(headers):
        end = headers[index + 1].start() if index + 1 < len(headers) else len(text)
        spans.append((header.start(), end))
    return spans


def bump_load_steps(text: str, added: int) -> str:
    if added == 0:
        return text

    def replace(match: re.Match) -> str:
        return f"load_steps={int(match.group(1)) + added}"

    return re.sub(r"load_steps=(\d+)", replace, text, count=1)


def route_scene_text(text: str) -> tuple[str, int]:
    """Apply routing to one scene's text. Returns (text, overrides added)."""
    ids = mesh_ids(text)
    if not ids:
        return text, 0

    added_overrides = 0
    added_resources = 0
    changed = True
    # Re-scan after each edit: inserting an ext_resource shifts every later span.
    while changed:
        changed = False
        for start, end in _node_spans(text):
            block = text[start:end]
            if 'type="MeshInstance3D"' not in block:
                continue
            if "material_override" in block:
                continue
            mesh_match = MESH_ASSIGNMENT.search(block)
            if mesh_match is None:
                continue
            piece = ids.get(mesh_match.group(1))
            if piece is None:
                continue
            resource_name = material_for(piece)
            if resource_name is None:
                continue

            text, material_id, added = ensure_material_resource(text, resource_name)
            added_resources += added
            if added:
                # Offsets moved; recompute this node's span from scratch.
                ids = mesh_ids(text)
                changed = True
                break

            insert_line = f'material_override = ExtResource("{material_id}")'
            block_end = start + len(block)
            new_block = block.rstrip("\n") + "\n" + insert_line + "\n\n"
            text = text[:start] + new_block + text[block_end:]
            added_overrides += 1
            changed = True
            break

    return bump_load_steps(text, added_resources), added_overrides


def scene_paths(repo_root: Path) -> list[Path]:
    return sorted((repo_root / SCENE_DIR).rglob("*.tscn"))


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=_REPO_ROOT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report scenes that would change, without writing",
    )
    arguments = parser.parse_args(argv)

    drifted: list[str] = []
    total = 0
    for path in scene_paths(arguments.repo_root):
        original = path.read_text(encoding="utf-8")
        routed, added = route_scene_text(original)
        if added:
            total += added
            drifted.append(f"{path.name} ({added})")
            if not arguments.check:
                path.write_text(routed, encoding="utf-8")
                print(f"ROUTED {path.name} {added}")

    if arguments.check:
        if drifted:
            print("Kit material routing is stale in:")
            for entry in drifted:
                print(f"  {entry}")
            print("Run: python3 scripts/route_kit_materials.py")
            return 1
        print("Kit material routing lint passed.")
        return 0

    print(f"Attached {total} animated material override(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
