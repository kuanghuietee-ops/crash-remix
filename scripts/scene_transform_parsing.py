"""Shared low-level ``.tscn`` parsing primitives for the authoring lints.

``lint_level_authoring.py`` and ``lint_traversal_authoring.py`` each parse
Godot's saved-scene text format independently: one walks a level's full,
possibly-instanced node tree with cycle detection and property-override
inheritance; the other scans each segment file directly without following
``instance=`` references, because wall-run/grind rules only ever need
geometry authored directly inside a single segment file. Those two
higher-level scene-graph models genuinely differ and are not shared here.

The low-level pieces below — how a ``Vector3``/``Basis``/``Transform3D``
literal is parsed, and what counts as a recognized ``.tscn`` section — are
*not* architecture-specific, and are not different between the two lints.
Letting each lint keep its own copy is exactly what let one of them
(``lint_traversal_authoring.py``) miss two fixes that had already landed
in the other: ``transform =`` parsing (P1-1) and loud-failure on an
unrecognized scene section instead of silently dropping it (G13/N3). Both
lints import these primitives from here so a future fix to either lands
for both automatically, instead of drifting again.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

Vector3 = tuple[float, float, float]
Basis3 = tuple[Vector3, Vector3, Vector3]
ZERO: Vector3 = (0.0, 0.0, 0.0)
ONE: Vector3 = (1.0, 1.0, 1.0)
UP: Vector3 = (0.0, 1.0, 0.0)
IDENTITY_BASIS: Basis3 = (
    (1.0, 0.0, 0.0),
    (0.0, 1.0, 0.0),
    (0.0, 0.0, 1.0),
)

VECTOR_PATTERN = re.compile(
    r"Vector3\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,"
    r"\s*([-+0-9.eE]+)\s*\)"
)
RESOURCE_CALL_PATTERN = re.compile(
    r'(?:ExtResource|SubResource)\("([^"]+)"\)'
)
HEADER_ATTRIBUTE_PATTERN = re.compile(
    r'([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|([^\s]+))'
)
PROPERTY_PATTERN = re.compile(r"^([A-Za-z_][A-Za-z0-9_/]*)\s*=\s*(.+)$")

# Section headers every authoring lint's line-oriented .tscn parser must
# either understand or explicitly treat as carrying no authoring-relevant
# data. A section that is neither must raise loudly instead of silently
# dropping whatever properties it holds (see G13/N3): a tripwire that
# cannot fire is worse than no tripwire.
KNOWN_SCENE_SECTIONS = {"ext_resource", "sub_resource", "node"}
INERT_SCENE_SECTIONS = {
    "gd_scene",
    "gd_resource",
    # "[editable path="..."]" only toggles whether the Godot editor shows
    # an instanced sub-scene's internal nodes as editable in the scene
    # tree dock (Node.set_editable_instance / is_editable_instance,
    # confirmed by reading Godot 4.7.1's own scene/main/node.cpp and
    # scene/resources/packed_scene.cpp). It carries no geometry, crate,
    # checkpoint, or camera data of its own — PackedScene instancing
    # applies every authored override line unconditionally regardless of
    # this flag — so it is genuinely inert for authoring purposes.
    # Confirmed deliberately, per N3, not left unclassified by default.
    "editable",
}


@dataclass(frozen=True)
class SpatialTransform:
    basis: Basis3
    origin: Vector3


IDENTITY_TRANSFORM = SpatialTransform(IDENTITY_BASIS, ZERO)


def raise_on_unrecognized_section(path, section_name: str) -> None:
    """Raise loudly if ``section_name`` is neither known nor inert.

    Shared so both lints' ``.tscn`` parsers fail the same way on syntax
    neither of them has a rule for, instead of one silently dropping a
    section (e.g. ``[connection]``) the other would have caught.
    """
    if (
        section_name not in KNOWN_SCENE_SECTIONS
        and section_name not in INERT_SCENE_SECTIONS
    ):
        raise ValueError(
            f"{path}: unrecognized scene section "
            f"[{section_name}] — the authoring lint has no rule for "
            "this syntax and cannot silently ignore it; teach the "
            "parser about it or confirm it carries no authoring-relevant "
            "data before adding it to INERT_SCENE_SECTIONS"
        )


def parse_vector(value: str) -> Vector3 | None:
    match = VECTOR_PATTERN.fullmatch(value.strip())
    if match is None:
        return None
    return tuple(
        float(match.group(index))
        for index in range(1, 4)
    )  # type: ignore[return-value]


def parse_constructor_components(
    value: str,
    constructor: str,
    count: int,
) -> tuple[float, ...] | None:
    stripped = value.strip()
    prefix = constructor + "("
    if not stripped.startswith(prefix) or not stripped.endswith(")"):
        return None
    raw_components = stripped[len(prefix) : -1].split(",")
    if len(raw_components) != count:
        return None
    try:
        components = tuple(
            float(component.strip())
            for component in raw_components
        )
    except ValueError:
        return None
    if not all(math.isfinite(component) for component in components):
        return None
    return components


def parse_basis(value: str) -> Basis3 | None:
    components = parse_constructor_components(value, "Basis", 9)
    if components is None:
        return None
    return (
        (components[0], components[3], components[6]),
        (components[1], components[4], components[7]),
        (components[2], components[5], components[8]),
    )


def parse_transform(value: str) -> SpatialTransform | None:
    components = parse_constructor_components(
        value,
        "Transform3D",
        12,
    )
    if components is None:
        return None
    return SpatialTransform(
        basis=(
            (components[0], components[3], components[6]),
            (components[1], components[4], components[7]),
            (components[2], components[5], components[8]),
        ),
        origin=(
            components[9],
            components[10],
            components[11],
        ),
    )


def header_attributes(header: str) -> dict[str, str]:
    attributes: dict[str, str] = {}
    for match in HEADER_ATTRIBUTE_PATTERN.finditer(header):
        attributes[match.group(1)] = (
            match.group(2)
            if match.group(2) is not None
            else match.group(3)
        )
    return attributes


def resource_id(value: str) -> str:
    match = RESOURCE_CALL_PATTERN.fullmatch(value.strip())
    return match.group(1) if match is not None else ""
