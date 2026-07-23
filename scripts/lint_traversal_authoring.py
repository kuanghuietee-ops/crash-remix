#!/usr/bin/env python3
"""Validate authored traversal segments without launching Godot."""

from __future__ import annotations

import argparse
import math
import posixpath
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


WALL_CAMERA_RULE = "wall_run_horizon_stable"
DETACH_VISIBILITY_RULE = "wall_run_detach_target_visible"
RAIL_READABILITY_RULE = "rail_readability"

WALL_STRIP_SCRIPT = "res://src/gameplay/traversal/wall_run_strip.gd"
TRAVERSAL_RAIL_SCRIPT = "res://src/gameplay/traversal/traversal_rail.gd"
CAMERA_REGION_SCRIPT = "res://src/gameplay/camera/camera_region.gd"
WALL_RUN_MODE = "wall_run"
GRIND_MODE = "grind"

Vector3 = tuple[float, float, float]
ZERO: Vector3 = (0.0, 0.0, 0.0)
UP: Vector3 = (0.0, 1.0, 0.0)
VECTOR_PATTERN = re.compile(
    r"Vector3\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,"
    r"\s*([-+0-9.eE]+)\s*\)"
)
RESOURCE_CALL_PATTERN = re.compile(
    r'(?:ExtResource|SubResource)\("([^"]+)"\)'
)
NODE_PATH_PATTERN = re.compile(r'NodePath\("([^"]*)"\)')
STRING_NAME_PATTERN = re.compile(r'&"([^"]*)"')
HEADER_ATTRIBUTE_PATTERN = re.compile(
    r'([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|([^\s]+))'
)
PROPERTY_PATTERN = re.compile(r"^([A-Za-z_][A-Za-z0-9_/]*)\s*=\s*(.+)$")
SCREEN_TOLERANCE = 0.02
MAXIMUM_COMFORT_ROLL_DEGREES = 10.0
VISIBILITY_SAMPLES = 9
VISIBILITY_MARGIN = 1.05


@dataclass(frozen=True)
class AuthoringViolation:
    scene_path: str
    rule: str
    detail: str


@dataclass
class SceneNode:
    name: str
    node_type: str
    parent: str
    path: str
    index: int
    properties: dict[str, str]


@dataclass
class SubResource:
    resource_type: str
    properties: dict[str, str]


@dataclass
class ParsedScene:
    path: Path
    ext_resources: dict[str, str]
    sub_resources: dict[str, SubResource]
    nodes: list[SceneNode]

    @property
    def nodes_by_path(self) -> dict[str, SceneNode]:
        return {node.path: node for node in self.nodes}


@dataclass(frozen=True)
class Bounds:
    center: Vector3
    half_size: Vector3

    def contains(self, point: Vector3) -> bool:
        return all(
            abs(point[axis] - self.center[axis])
            <= self.half_size[axis] + SCREEN_TOLERANCE
            for axis in range(3)
        )


@dataclass(frozen=True)
class CameraConfig:
    field_of_view_degrees: float
    look_ahead_m: float
    look_at_height_m: float
    wall_run_offset: Vector3
    aspect_ratio: float


def find_authoring_violations(root: Path) -> list[AuthoringViolation]:
    root = root.resolve()
    repo_root = _find_repo_root(root)
    camera = _load_camera_config(repo_root)
    findings: list[AuthoringViolation] = []
    for scene_path in _scene_files(root):
        scene = _parse_scene(scene_path)
        findings.extend(_wall_run_findings(scene, repo_root, camera))
        findings.extend(_rail_findings(scene, repo_root))
    return sorted(
        findings,
        key=lambda finding: (
            finding.scene_path,
            finding.rule,
            finding.detail,
        ),
    )


def _wall_run_findings(
    scene: ParsedScene,
    repo_root: Path,
    camera: CameraConfig,
) -> list[AuthoringViolation]:
    strips = _nodes_with_script(scene, WALL_STRIP_SCRIPT)
    if not strips:
        return []
    scene_path = _display_path(scene.path, repo_root)
    regions = _camera_regions(scene, WALL_RUN_MODE)
    targets = [
        node
        for node in scene.nodes
        if node.name.casefold() in {"landingpad", "detachtarget"}
    ]
    findings: list[AuthoringViolation] = []
    readable_strips: list[tuple[SceneNode, tuple[Vector3, Vector3], Vector3]] = []
    for strip in strips:
        endpoints = _path_endpoints(scene, strip)
        if endpoints is None:
            findings.append(
                AuthoringViolation(
                    scene_path,
                    WALL_CAMERA_RULE,
                    f"{strip.path} needs at least two direct Marker3D points",
                )
            )
            continue
        start, finish = endpoints
        tangent = _normalize(_subtract(finish, start))
        normal = _normalize(
            _parse_vector(strip.properties.get("surface_normal", ""))
            or (1.0, 0.0, 0.0)
        )
        matching_regions = [
            bounds
            for _, bounds in regions
            if bounds.contains(start) and bounds.contains(finish)
        ]
        if not matching_regions:
            findings.append(
                AuthoringViolation(
                    scene_path,
                    WALL_CAMERA_RULE,
                    f"{strip.path} is not enclosed by a wall_run camera region",
                )
            )
            continue
        frame = _wall_camera_frame(start, tangent, normal, camera)
        if frame is None:
            findings.append(
                AuthoringViolation(
                    scene_path,
                    WALL_CAMERA_RULE,
                    f"{strip.path} has degenerate tangent/normal camera geometry",
                )
            )
            continue
        _, _, screen_right, screen_up = frame
        if (
            abs(_dot(screen_right, UP))
            > math.sin(math.radians(MAXIMUM_COMFORT_ROLL_DEGREES))
            or _dot(screen_up, UP) <= 0.0
        ):
            findings.append(
                AuthoringViolation(
                    scene_path,
                    WALL_CAMERA_RULE,
                    f"{strip.path} wall camera exceeds the upright horizon band",
                )
            )
            continue
        readable_strips.append((strip, endpoints, normal))

    if not readable_strips:
        return findings
    if not targets:
        findings.append(
            AuthoringViolation(
                scene_path,
                DETACH_VISIBILITY_RULE,
                "wall-run scene needs a LandingPad or DetachTarget node",
            )
        )
        return findings
    target_points = [
        point
        for target in targets
        for point in _node_bounds_points(scene, target)
    ]
    for strip, (start, finish), normal in readable_strips:
        tangent = _normalize(_subtract(finish, start))
        if not _target_becomes_visible(
            start,
            finish,
            tangent,
            normal,
            target_points,
            camera,
        ):
            findings.append(
                AuthoringViolation(
                    scene_path,
                    DETACH_VISIBILITY_RULE,
                    f"{strip.path} detach target never enters the wall camera frustum",
                )
            )
    return findings


def _rail_findings(
    scene: ParsedScene,
    repo_root: Path,
) -> list[AuthoringViolation]:
    rails = _nodes_with_script(scene, TRAVERSAL_RAIL_SCRIPT)
    if not rails:
        return []
    scene_path = _display_path(scene.path, repo_root)
    rail_by_path = {rail.path: rail for rail in rails}
    regions = _camera_regions(scene, GRIND_MODE)
    findings: list[AuthoringViolation] = []
    for rail in rails:
        endpoints = _path_endpoints(scene, rail)
        if (
            endpoints is None
            or not any(
                bounds.contains(endpoints[0]) and bounds.contains(endpoints[1])
                for _, bounds in regions
            )
        ):
            findings.append(
                AuthoringViolation(
                    scene_path,
                    RAIL_READABILITY_RULE,
                    f"{rail.path} must sit inside a grind camera region",
                )
            )
        for property_name, reciprocal_name in (
            ("left_neighbor_path", "right_neighbor_path"),
            ("right_neighbor_path", "left_neighbor_path"),
        ):
            raw_path = rail.properties.get(property_name)
            if raw_path is None:
                continue
            neighbour_path = _resolve_node_path(rail.path, raw_path)
            neighbour = rail_by_path.get(neighbour_path)
            if neighbour is None:
                findings.append(
                    AuthoringViolation(
                        scene_path,
                        RAIL_READABILITY_RULE,
                        f"{rail.path} points to missing rail {neighbour_path}",
                    )
                )
                continue
            reciprocal = neighbour.properties.get(reciprocal_name)
            if (
                reciprocal is None
                or _resolve_node_path(neighbour.path, reciprocal) != rail.path
            ):
                findings.append(
                    AuthoringViolation(
                        scene_path,
                        RAIL_READABILITY_RULE,
                        f"{rail.path} ↔ {neighbour.path} links must be symmetric",
                    )
                )
    return findings


def _camera_regions(
    scene: ParsedScene,
    mode: str,
) -> list[tuple[SceneNode, Bounds]]:
    result: list[tuple[SceneNode, Bounds]] = []
    for region in _nodes_with_script(scene, CAMERA_REGION_SCRIPT):
        if _string_name(region.properties.get("camera_mode", "")) != mode:
            continue
        bounds = _collision_bounds(scene, region)
        if bounds is not None:
            result.append((region, bounds))
    return result


def _target_becomes_visible(
    start: Vector3,
    finish: Vector3,
    tangent: Vector3,
    normal: Vector3,
    target_points: list[Vector3],
    camera: CameraConfig,
) -> bool:
    for index in range(VISIBILITY_SAMPLES - 1):
        weight = index / (VISIBILITY_SAMPLES - 1)
        sample_position = _add(
            start,
            _multiply(_subtract(finish, start), weight),
        )
        frame = _wall_camera_frame(
            sample_position,
            tangent,
            normal,
            camera,
        )
        if frame is None:
            continue
        camera_position, view, screen_right, screen_up = frame
        vertical_limit = math.tan(
            math.radians(camera.field_of_view_degrees) / 2.0
        )
        horizontal_limit = vertical_limit * camera.aspect_ratio
        for target in target_points:
            relative = _subtract(target, camera_position)
            forward_distance = _dot(relative, view)
            if forward_distance <= 0.0:
                continue
            projected_x = _dot(relative, screen_right) / forward_distance
            projected_y = _dot(relative, screen_up) / forward_distance
            if (
                abs(projected_x) <= horizontal_limit * VISIBILITY_MARGIN
                and abs(projected_y) <= vertical_limit * VISIBILITY_MARGIN
            ):
                return True
    return False


def _wall_camera_frame(
    position: Vector3,
    tangent: Vector3,
    normal: Vector3,
    camera: CameraConfig,
) -> tuple[Vector3, Vector3, Vector3, Vector3] | None:
    tangent = _normalize(tangent)
    normal = _normalize(_slide(normal, tangent))
    if _is_zero(tangent) or _is_zero(normal):
        return None
    camera_up = _normalize(_cross(tangent, normal))
    if _dot(camera_up, UP) < 0.0:
        camera_up = _multiply(camera_up, -1.0)
    if _is_zero(camera_up):
        return None
    offset = camera.wall_run_offset
    camera_position = _add(
        position,
        _add(
            _multiply(normal, offset[0]),
            _add(
                _multiply(camera_up, offset[1]),
                _multiply(tangent, -offset[2]),
            ),
        ),
    )
    look_target = _add(
        position,
        _add(
            _multiply(tangent, camera.look_ahead_m),
            _multiply(camera_up, camera.look_at_height_m),
        ),
    )
    view = _normalize(_subtract(look_target, camera_position))
    camera_back = _multiply(view, -1.0)
    screen_right = _normalize(_cross(UP, camera_back))
    screen_up = _normalize(_cross(camera_back, screen_right))
    if _is_zero(view) or _is_zero(screen_right) or _is_zero(screen_up):
        return None
    return camera_position, view, screen_right, screen_up


def _collision_bounds(
    scene: ParsedScene,
    owner: SceneNode,
) -> Bounds | None:
    prefix = "" if owner.path == "." else owner.path + "/"
    for child in scene.nodes:
        if child.node_type != "CollisionShape3D":
            continue
        if not child.path.startswith(prefix) or child.path == owner.path:
            continue
        shape_id = _resource_id(child.properties.get("shape", ""))
        shape = scene.sub_resources.get(shape_id)
        if shape is None or shape.resource_type != "BoxShape3D":
            continue
        size = _parse_vector(shape.properties.get("size", ""))
        if size is None:
            continue
        return Bounds(
            center=_world_position(scene, child),
            half_size=_multiply(size, 0.5),
        )
    return None


def _node_bounds_points(
    scene: ParsedScene,
    owner: SceneNode,
) -> list[Vector3]:
    bounds = _collision_bounds(scene, owner)
    if bounds is None:
        return [_world_position(scene, owner)]
    points: list[Vector3] = []
    for x_sign in (-1.0, 1.0):
        for y_sign in (-1.0, 1.0):
            for z_sign in (-1.0, 1.0):
                points.append(
                    (
                        bounds.center[0] + bounds.half_size[0] * x_sign,
                        bounds.center[1] + bounds.half_size[1] * y_sign,
                        bounds.center[2] + bounds.half_size[2] * z_sign,
                    )
                )
    return points


def _path_endpoints(
    scene: ParsedScene,
    path_node: SceneNode,
) -> tuple[Vector3, Vector3] | None:
    markers = [
        node
        for node in scene.nodes
        if node.node_type == "Marker3D" and node.parent == path_node.path
    ]
    markers.sort(key=lambda node: node.index)
    if len(markers) < 2:
        return None
    return (
        _world_position(scene, markers[0]),
        _world_position(scene, markers[-1]),
    )


def _nodes_with_script(
    scene: ParsedScene,
    script_path: str,
) -> list[SceneNode]:
    return [
        node
        for node in scene.nodes
        if scene.ext_resources.get(
            _resource_id(node.properties.get("script", ""))
        )
        == script_path
    ]


def _world_position(scene: ParsedScene, node: SceneNode) -> Vector3:
    nodes = scene.nodes_by_path
    position = _parse_vector(node.properties.get("position", "")) or ZERO
    parent_path = node.parent
    visited = {node.path}
    while parent_path:
        parent = nodes.get(parent_path)
        if parent is None or parent.path in visited:
            break
        visited.add(parent.path)
        position = _add(
            position,
            _parse_vector(parent.properties.get("position", "")) or ZERO,
        )
        parent_path = parent.parent
    return position


def _resolve_node_path(node_path: str, raw_value: str) -> str:
    match = NODE_PATH_PATTERN.fullmatch(raw_value.strip())
    if match is None:
        return ""
    return posixpath.normpath(posixpath.join(node_path, match.group(1)))


def _parse_scene(path: Path) -> ParsedScene:
    ext_resources: dict[str, str] = {}
    sub_resources: dict[str, SubResource] = {}
    nodes: list[SceneNode] = []
    current_properties: dict[str, str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current_properties = None
            header = stripped[1:-1]
            section_name = header.split(maxsplit=1)[0]
            attributes = _header_attributes(header)
            if section_name == "ext_resource":
                resource_id = attributes.get("id", "")
                resource_path = attributes.get("path", "")
                if resource_id and resource_path:
                    ext_resources[resource_id] = resource_path
            elif section_name == "sub_resource":
                resource_id = attributes.get("id", "")
                resource = SubResource(
                    resource_type=attributes.get("type", ""),
                    properties={},
                )
                sub_resources[resource_id] = resource
                current_properties = resource.properties
            elif section_name == "node":
                name = attributes.get("name", "")
                parent = attributes.get("parent", "")
                if not nodes and not parent:
                    relative_path = "."
                elif parent == ".":
                    relative_path = name
                else:
                    relative_path = f"{parent}/{name}"
                node = SceneNode(
                    name=name,
                    node_type=attributes.get("type", ""),
                    parent=parent,
                    path=relative_path,
                    index=len(nodes),
                    properties={},
                )
                nodes.append(node)
                current_properties = node.properties
            continue
        match = PROPERTY_PATTERN.match(stripped)
        if match is not None and current_properties is not None:
            current_properties[match.group(1)] = match.group(2).strip()
    return ParsedScene(path, ext_resources, sub_resources, nodes)


def _header_attributes(header: str) -> dict[str, str]:
    attributes: dict[str, str] = {}
    for match in HEADER_ATTRIBUTE_PATTERN.finditer(header):
        attributes[match.group(1)] = (
            match.group(2)
            if match.group(2) is not None
            else match.group(3)
        )
    return attributes


def _load_camera_config(repo_root: Path) -> CameraConfig:
    camera_text = (repo_root / "data/tuning/camera.tres").read_text(
        encoding="utf-8"
    )
    project_text = (repo_root / "project.godot").read_text(encoding="utf-8")
    values = _assignment_values(camera_text)
    project_values = _assignment_values(project_text)
    width = float(project_values["window/size/viewport_width"])
    height = float(project_values["window/size/viewport_height"])
    wall_offset = _parse_vector(values["wall_run_offset"])
    if wall_offset is None:
        raise ValueError("camera.tres wall_run_offset is not a Vector3")
    return CameraConfig(
        field_of_view_degrees=float(values["field_of_view_degrees"]),
        look_ahead_m=float(values["look_ahead_m"]),
        look_at_height_m=float(values["look_at_height_m"]),
        wall_run_offset=wall_offset,
        aspect_ratio=width / height,
    )


def _assignment_values(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        match = PROPERTY_PATTERN.match(line.strip())
        if match is not None:
            values[match.group(1)] = match.group(2).strip()
    return values


def _scene_files(root: Path) -> Iterable[Path]:
    if root.is_file():
        if root.suffix == ".tscn":
            yield root
        return
    scan_root = root / "scenes" if (root / "scenes").is_dir() else root
    yield from sorted(scan_root.rglob("*.tscn"))


def _find_repo_root(root: Path) -> Path:
    start = root.parent if root.is_file() else root
    for candidate in (start, *start.parents):
        if (candidate / "data/tuning/camera.tres").is_file():
            return candidate
    return Path(__file__).resolve().parents[1]


def _display_path(path: Path, repo_root: Path) -> str:
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.as_posix()


def _parse_vector(value: str) -> Vector3 | None:
    match = VECTOR_PATTERN.fullmatch(value.strip())
    if match is None:
        return None
    return tuple(float(match.group(index)) for index in range(1, 4))  # type: ignore[return-value]


def _resource_id(value: str) -> str:
    match = RESOURCE_CALL_PATTERN.fullmatch(value.strip())
    return match.group(1) if match is not None else ""


def _string_name(value: str) -> str:
    match = STRING_NAME_PATTERN.fullmatch(value.strip())
    return match.group(1) if match is not None else ""


def _add(first: Vector3, second: Vector3) -> Vector3:
    return tuple(a + b for a, b in zip(first, second))  # type: ignore[return-value]


def _subtract(first: Vector3, second: Vector3) -> Vector3:
    return tuple(a - b for a, b in zip(first, second))  # type: ignore[return-value]


def _multiply(value: Vector3, scalar: float) -> Vector3:
    return tuple(component * scalar for component in value)  # type: ignore[return-value]


def _dot(first: Vector3, second: Vector3) -> float:
    return sum(a * b for a, b in zip(first, second))


def _cross(first: Vector3, second: Vector3) -> Vector3:
    return (
        first[1] * second[2] - first[2] * second[1],
        first[2] * second[0] - first[0] * second[2],
        first[0] * second[1] - first[1] * second[0],
    )


def _length(value: Vector3) -> float:
    return math.sqrt(_dot(value, value))


def _normalize(value: Vector3) -> Vector3:
    length = _length(value)
    return ZERO if math.isclose(length, 0.0) else _multiply(value, 1.0 / length)


def _slide(value: Vector3, normal: Vector3) -> Vector3:
    normalized_normal = _normalize(normal)
    return _subtract(
        value,
        _multiply(normalized_normal, _dot(value, normalized_normal)),
    )


def _is_zero(value: Vector3) -> bool:
    return math.isclose(_length(value), 0.0)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Scene files or roots (default: repository scenes/)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    repo_root = Path(__file__).resolve().parents[1]
    paths = arguments.paths or [repo_root]
    findings = [
        finding
        for path in paths
        for finding in find_authoring_violations(path)
    ]
    for finding in findings:
        print(f"{finding.scene_path}: {finding.rule}: {finding.detail}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
