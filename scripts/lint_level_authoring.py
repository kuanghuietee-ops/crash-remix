#!/usr/bin/env python3
"""Validate Phase 1 level authoring without launching Godot."""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

try:
    from scene_transform_parsing import (
        IDENTITY_TRANSFORM,
        ONE,
        PROPERTY_PATTERN,
        UP,
        Basis3,
        SpatialTransform,
        Vector3,
        ZERO,
        header_attributes as _header_attributes,
        parse_basis as _parse_basis,
        parse_transform as _parse_transform,
        parse_vector as _parse_vector,
        raise_on_unrecognized_section,
        resource_id as _resource_id,
    )
except ImportError:  # pragma: no cover - exercised via scripts.* imports
    from scripts.scene_transform_parsing import (
        IDENTITY_TRANSFORM,
        ONE,
        PROPERTY_PATTERN,
        UP,
        Basis3,
        SpatialTransform,
        Vector3,
        ZERO,
        header_attributes as _header_attributes,
        parse_basis as _parse_basis,
        parse_transform as _parse_transform,
        parse_vector as _parse_vector,
        raise_on_unrecognized_section,
        resource_id as _resource_id,
    )


CHECKPOINT_SPACING_RULE = "checkpoint_spacing"
CHECKPOINT_PROGRESSION_RULE = "checkpoint_progression"
SPINE_ORDER_RULE = "spine_document_order"
CHECKPOINT_OFF_SPINE_RULE = "checkpoint_off_spine"
CRATE_AUTHORING_RULE = "crate_count_and_segment_membership"
CRATE_ID_RULE = "crate_id_unique"
REQUIRED_JUMP_RULE = "required_jump_depression"
TIME_CRATE_RULE = "time_crate_relic_only"
SPAWN_FLOOR_RULE = "player_spawn_has_reachable_floor"

BREAKABLE_CRATE_SCRIPT = (
    "res://src/gameplay/crates/breakable_crate.gd"
)
CAMERA_REGION_SCRIPT = (
    "res://src/gameplay/camera/camera_region.gd"
)
CAMERA_RAIL_CONTROLLER_SCRIPT = (
    "res://src/gameplay/camera/camera_rail_controller.gd"
)
GRAYBOX_PLATFORM_SCRIPT = (
    "res://src/graybox/graybox_platform.gd"
)
LEVEL_META_SCRIPT = "res://src/tuning/level_meta.gd"
PLAYER_CONTROLLER_SCRIPT = (
    "res://src/gameplay/player/player_controller.gd"
)
LEVEL_FINISH_NODE_NAME = "Finish"
LEVEL_FINISH_NODE_TYPE = "Area3D"
LEVEL_META_EXEMPT_SCENES = {
    "phase05_gauntlet.tscn",
    "warp_room_1.tscn",
}
TIME_CRATE_TYPE = "time"
IRON_CRATE_TYPE = "iron"
CHECKPOINT_CRATE_TYPE = "checkpoint"
RELIC_ONLY_GROUP = "relic_only"
SEGMENT_CONTAINER_SLUGS = {"segments"}

STRING_PATTERN = re.compile(r'(?:&)?"([^"]*)"')
GROUPS_PATTERN = re.compile(r"groups=\[([^\]]*)\]")


@dataclass(frozen=True)
class AuthoringViolation:
    scene_path: str
    rule: str
    detail: str


@dataclass(frozen=True)
class ResourceReference:
    resource_type: str
    path: str


@dataclass
class SubResource:
    resource_type: str
    properties: dict[str, str]


@dataclass
class SceneNode:
    name: str
    node_type: str
    parent: str
    path: str
    instance_id: str
    groups: set[str]
    index: int
    properties: dict[str, str]


@dataclass
class ParsedScene:
    path: Path
    ext_resources: dict[str, ResourceReference]
    sub_resources: dict[str, SubResource]
    nodes: list[SceneNode]


@dataclass
class FlatNode:
    name: str
    node_type: str
    path: str
    parent: str
    properties: dict[str, str]
    groups: set[str]
    script_path: str
    world_transform: SpatialTransform
    world_position: Vector3
    order: int
    source_scene: ParsedScene


@dataclass(frozen=True)
class Bounds:
    transform: SpatialTransform
    half_size: Vector3

    def contains(self, point: Vector3) -> bool:
        local_point = _basis_inverse_xform(
            self.transform.basis,
            _subtract(point, self.transform.origin),
        )
        if local_point is None:
            return False
        return all(
            abs(local_point[axis])
            <= self.half_size[axis]
            for axis in range(3)
        )


@dataclass(frozen=True)
class LevelMetaValues:
    crate_count: int
    design_pace_mps: float


@dataclass(frozen=True)
class AuthoringTuning:
    checkpoint_spacing_limit_s: float
    minimum_jump_depression_degrees: float
    camera_look_ahead_m: float
    camera_offsets: dict[str, Vector3]
    respawn_floor_y_m: float


def find_authoring_violations(root: Path) -> list[AuthoringViolation]:
    root = root.resolve()
    repo_root = _find_repo_root(root)
    tuning = _load_authoring_tuning(repo_root)
    findings: list[AuthoringViolation] = []
    for scene_path in _scene_files(root):
        parsed = _parse_scene(scene_path)
        meta_path = _level_meta_path(parsed, repo_root)
        if meta_path is None:
            if (
                scene_path.parent.name == "levels"
                and scene_path.name not in LEVEL_META_EXEMPT_SCENES
            ):
                findings.append(
                    AuthoringViolation(
                        _display_path(scene_path, repo_root),
                        CRATE_AUTHORING_RULE,
                        "Phase 1 level has no LevelMeta resource",
                    )
                )
            continue
        meta = _load_level_meta(meta_path)
        flat_nodes = _flatten_scene(scene_path, repo_root)
        findings.extend(
            _level_findings(
                scene_path,
                flat_nodes,
                meta,
                tuning,
                repo_root,
            )
        )
    return sorted(
        findings,
        key=lambda finding: (
            finding.scene_path,
            finding.rule,
            finding.detail,
        ),
    )


def _level_findings(
    scene_path: Path,
    nodes: list[FlatNode],
    meta: LevelMetaValues,
    tuning: AuthoringTuning,
    repo_root: Path,
) -> list[AuthoringViolation]:
    scene_name = _display_path(scene_path, repo_root)
    findings: list[AuthoringViolation] = []
    findings.extend(
        _checkpoint_findings(scene_name, nodes, meta, tuning)
    )
    findings.extend(_crate_findings(scene_name, nodes, meta))
    findings.extend(
        _required_jump_findings(scene_name, nodes, tuning)
    )
    findings.extend(_time_crate_findings(scene_name, nodes))
    findings.extend(
        _spawn_floor_findings(scene_name, nodes, tuning)
    )
    return findings


def _spine_extent_gaps(
    nodes: list[FlatNode],
    spine: list[FlatNode],
) -> tuple[float, float]:
    """Distance from the spine's own ends to the level's real edges.

    The spine is an authored approximation of the playable route, not
    the playable extent itself: nothing else ties its first/last point
    to where the player actually starts or where the level actually
    ends. When the root ``Player`` and root ``Finish`` trigger the
    runtime already requires (``LevelSession.configure``) are present,
    fold the residual straight-line gap into the pacing measurement so
    a spine that stops short of either real edge cannot hide an
    unpaced stretch beyond it.
    """
    head_gap = 0.0
    tail_gap = 0.0
    player = next(
        (
            node
            for node in nodes
            if (
                node.parent == "."
                and node.script_path == PLAYER_CONTROLLER_SCRIPT
            )
        ),
        None,
    )
    if player is not None:
        head_gap = _length(
            _subtract(player.world_position, spine[0].world_position)
        )
    finish = next(
        (
            node
            for node in nodes
            if (
                node.parent == "."
                and node.path == LEVEL_FINISH_NODE_NAME
                and node.node_type == LEVEL_FINISH_NODE_TYPE
            )
        ),
        None,
    )
    if finish is not None:
        tail_gap = _length(
            _subtract(finish.world_position, spine[-1].world_position)
        )
    return head_gap, tail_gap


def _spawn_floor_findings(
    scene_name: str,
    nodes: list[FlatNode],
    tuning: AuthoringTuning,
) -> list[AuthoringViolation]:
    """The root Player's authored spawn must have real floor beneath it.

    P0-2 was a single coordinate correction (a spawn authored past the
    edge of its floor piece, dropping the player into the void) with no
    generalized guard: nothing checks that ANY authored spawn actually has
    floor underneath it, so the next level can silently reintroduce the
    exact same shape. This walks every authored ``GrayboxPlatform`` in the
    level and requires at least one whose horizontal footprint covers the
    spawn's X/Z, with a top surface at or below the spawn and at or above
    ``move.respawn_floor_y_m`` -- the catalog's own "how far is definitely
    too far" distance scale (the same value R1 reused for
    ``checkpoint_respawn_offset``), rather than inventing a fresh
    tolerance here. A platform whose top sits below that threshold cannot
    actually be reached: the player would trigger the fall-recovery
    respawn first, and since the recovery target is this same broken
    spawn, that is the exact unrecoverable death loop P0-2 was.
    """
    player = next(
        (
            node
            for node in nodes
            if (
                node.parent == "."
                and node.script_path == PLAYER_CONTROLLER_SCRIPT
            )
        ),
        None,
    )
    if player is None:
        return []
    for platform in nodes:
        if platform.script_path != GRAYBOX_PLATFORM_SCRIPT:
            continue
        size = _parse_vector(platform.properties.get("size", ""))
        if size is None:
            continue
        half_size = _multiply(size, 0.5)
        local_point = _basis_inverse_xform(
            platform.world_transform.basis,
            _subtract(
                player.world_position,
                platform.world_transform.origin,
            ),
        )
        if local_point is None:
            continue
        if (
            abs(local_point[0]) > half_size[0]
            or abs(local_point[2]) > half_size[2]
        ):
            continue
        top_center = _add(
            platform.world_transform.origin,
            _basis_xform(
                platform.world_transform.basis,
                (0.0, half_size[1], 0.0),
            ),
        )
        if (
            top_center[1] <= player.world_position[1]
            and top_center[1] >= tuning.respawn_floor_y_m
        ):
            return []
    return [
        AuthoringViolation(
            scene_name,
            SPAWN_FLOOR_RULE,
            (
                "no authored GrayboxPlatform has a reachable top surface "
                f"(between respawn_floor_y_m={tuning.respawn_floor_y_m} "
                f"and the spawn) beneath the root Player's spawn "
                f"{player.world_position}"
            ),
        )
    ]


def _spine_order_findings(
    scene_name: str,
    spine: list[FlatNode],
) -> list[AuthoringViolation]:
    """Cross-check the spine's declared order against its own geometry.

    Every distance-along-the-route computation trusts that sorting the
    spine's Marker3D nodes by ``order`` (the order they were declared
    in their scene file) reproduces the level's real, spatial
    traversal order. Nothing else confirms the two agree, so a segment
    (or a marker within one) that is authored out of sequence — a
    reordered instance line, a copy-paste, a shuffled marker — silently
    corrupts every checkpoint's "distance so far" with no error.

    This walks the declared order and asserts each marker makes
    non-negative progress along the chord from the spine's own first
    point to its own last point; a marker that lands behind an earlier
    one is out of order.
    """
    chord = _subtract(
        spine[-1].world_position,
        spine[0].world_position,
    )
    chord_length_squared = _dot(chord, chord)
    if math.isclose(chord_length_squared, 0.0):
        return []
    findings: list[AuthoringViolation] = []
    previous_progress = 0.0
    previous_node = spine[0]
    for node in spine[1:]:
        progress = (
            _dot(
                _subtract(
                    node.world_position,
                    spine[0].world_position,
                ),
                chord,
            )
            / chord_length_squared
        )
        if progress < previous_progress and not math.isclose(
            progress,
            previous_progress,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    SPINE_ORDER_RULE,
                    (
                        f"{node.path} is declared after "
                        f"{previous_node.path} but sits earlier "
                        "along the spine's start-to-end route"
                    ),
                )
            )
        previous_progress = progress
        previous_node = node
    return findings


def _checkpoint_findings(
    scene_name: str,
    nodes: list[FlatNode],
    meta: LevelMetaValues,
    tuning: AuthoringTuning,
) -> list[AuthoringViolation]:
    spine = sorted(
        (
            node
            for node in nodes
            if node.node_type == "Marker3D"
            and _is_spine_marker(node)
        ),
        key=lambda node: node.order,
    )
    if len(spine) < 2:
        return [
            AuthoringViolation(
                scene_name,
                CHECKPOINT_SPACING_RULE,
                "level needs at least two ordered Spine Marker3D nodes",
            )
        ]
    findings = _spine_order_findings(scene_name, spine)
    if meta.design_pace_mps <= 0.0:
        return findings + [
            AuthoringViolation(
                scene_name,
                CHECKPOINT_SPACING_RULE,
                "LevelMeta.design_pace_mps must be positive",
            )
        ]

    points = [node.world_position for node in spine]
    cumulative = _polyline_cumulative_lengths(points)
    if not cumulative or math.isclose(cumulative[-1], 0.0):
        return findings + [
            AuthoringViolation(
                scene_name,
                CHECKPOINT_SPACING_RULE,
                "level Spine must have non-zero authored distance",
            )
        ]
    checkpoints_with_distances = [
        (
            node,
            _project_onto_polyline(
                node.world_position,
                points,
                cumulative,
            ),
        )
        for node in _crate_nodes(nodes)
        if _crate_type(node) == CHECKPOINT_CRATE_TYPE
    ]
    findings.extend(
        _checkpoint_progression_findings(
            scene_name,
            checkpoints_with_distances,
        )
    )
    findings.extend(
        _checkpoint_off_spine_findings(
            scene_name,
            nodes,
            checkpoints_with_distances,
        )
    )
    checkpoint_distances = [
        distance
        for _, distance in checkpoints_with_distances
    ]
    head_gap, tail_gap = _spine_extent_gaps(nodes, spine)
    boundaries = sorted(
        [
            -head_gap,
            *checkpoint_distances,
            cumulative[-1] + tail_gap,
        ]
    )
    interval_times = [
        (finish - start) / meta.design_pace_mps
        for start, finish in zip(boundaries, boundaries[1:])
    ]
    violating_times = [
        elapsed_s
        for elapsed_s in interval_times
        if elapsed_s > tuning.checkpoint_spacing_limit_s
    ]
    if violating_times:
        longest_s = max(violating_times)
        findings.append(
            AuthoringViolation(
                scene_name,
                CHECKPOINT_SPACING_RULE,
                (
                    f"checkpoint interval is {longest_s:.3f}s; "
                    f"limit from EconomyTuning is "
                    f"{tuning.checkpoint_spacing_limit_s:.3f}s"
                ),
            )
        )
    return findings


def _camera_region_bounds(nodes: list[FlatNode]) -> list[Bounds]:
    return [
        bounds
        for node in nodes
        if node.script_path == CAMERA_REGION_SCRIPT
        for bounds in (_collision_bounds(node, nodes),)
        if bounds is not None
    ]


def _checkpoint_off_spine_findings(
    scene_name: str,
    nodes: list[FlatNode],
    checkpoints_with_distances: list[tuple[FlatNode, float]],
) -> list[AuthoringViolation]:
    """A checkpoint's "distance so far" is only ever a projection onto
    the spine polyline — nothing checks the checkpoint is actually
    near that polyline. §5.2 of the design doc is explicit that "a
    trail bending off-spine always means something" for crates and
    wumpa, but a checkpoint anchors pacing and death respawn, so it
    cannot legitimately be one of those excursions.

    Reuses the same authored, per-segment CameraRegion geometry (and
    the same enclosure check) rule (c) already uses to decide whether
    a required jump sits on the intended route — not a new numeric
    constant, the level's own authored corridor.
    """
    region_bounds = _camera_region_bounds(nodes)
    if not region_bounds:
        return []
    return [
        AuthoringViolation(
            scene_name,
            CHECKPOINT_OFF_SPINE_RULE,
            (
                f"{checkpoint.path} is not enclosed by any authored "
                "CameraRegion; it is too far from the level's Spine "
                "to be a valid checkpoint"
            ),
        )
        for checkpoint, _ in checkpoints_with_distances
        if not any(
            bounds.contains(checkpoint.world_position)
            for bounds in region_bounds
        )
    ]


def _checkpoint_progression_findings(
    scene_name: str,
    checkpoints_with_distances: list[tuple[FlatNode, float]],
) -> list[AuthoringViolation]:
    ordered = sorted(
        checkpoints_with_distances,
        key=lambda item: item[1],
    )
    findings: list[AuthoringViolation] = []
    for (checkpoint, _), (successor, _) in zip(
        ordered,
        ordered[1:],
    ):
        checkpoint_id = _integer_value(
            checkpoint.properties.get("crate_id", "")
        )
        expected_successor_id = _integer_value(
            successor.properties.get("crate_id", "")
        )
        if checkpoint_id is None or expected_successor_id is None:
            continue
        authored_successor_id = _integer_value(
            checkpoint.properties.get(
                "metadata/next_checkpoint_id",
                "",
            )
        )
        if authored_successor_id == expected_successor_id:
            continue
        findings.append(
            AuthoringViolation(
                scene_name,
                CHECKPOINT_PROGRESSION_RULE,
                (
                    f"checkpoint {checkpoint_id} links to "
                    f"{authored_successor_id}; next spatial "
                    f"checkpoint is {expected_successor_id}"
                ),
            )
        )
    if not ordered:
        return findings
    final_checkpoint = ordered[-1][0]
    final_checkpoint_id = _integer_value(
        final_checkpoint.properties.get("crate_id", "")
    )
    final_successor_id = _integer_value(
        final_checkpoint.properties.get(
            "metadata/next_checkpoint_id",
            "",
        )
    )
    if (
        final_checkpoint_id is not None
        and final_successor_id is not None
        and final_successor_id >= 0
    ):
        findings.append(
            AuthoringViolation(
                scene_name,
                CHECKPOINT_PROGRESSION_RULE,
                (
                    f"final checkpoint {final_checkpoint_id} "
                    f"must not link to checkpoint "
                    f"{final_successor_id}"
                ),
            )
        )
    return findings


def _crate_findings(
    scene_name: str,
    nodes: list[FlatNode],
    meta: LevelMetaValues,
) -> list[AuthoringViolation]:
    crates = _crate_nodes(nodes)
    normal_crates = [
        crate
        for crate in crates
        if _crate_type(crate)
        not in {TIME_CRATE_TYPE, IRON_CRATE_TYPE}
    ]
    membership_errors: list[str] = []
    normal_crates_by_segment: dict[str, int] = {}
    for crate in crates:
        segment_name = _string_value(
            crate.properties.get("segment_group", "")
        )
        ancestor_names = [
            component
            for component in crate.path.split("/")[:-1]
            if component and component != "."
        ]
        segment_slug = _slug(segment_name)
        matching_ancestors = [
            name
            for name in ancestor_names
            if (
                _slug(name) == segment_slug
                and _slug(name) not in SEGMENT_CONTAINER_SLUGS
            )
        ]
        if not segment_name or len(matching_ancestors) != 1:
            membership_errors.append(crate.path)
            continue
        if _crate_type(crate) not in {
            TIME_CRATE_TYPE,
            IRON_CRATE_TYPE,
        }:
            concrete_segment = matching_ancestors[0]
            normal_crates_by_segment[concrete_segment] = (
                normal_crates_by_segment.get(concrete_segment, 0) + 1
            )

    details: list[str] = []
    if len(normal_crates) != meta.crate_count:
        details.append(
            f"authored normal crates={len(normal_crates)}, "
            f"LevelMeta.crate_count={meta.crate_count}"
        )
    per_segment_normal_total = sum(
        normal_crates_by_segment.values()
    )
    if per_segment_normal_total != meta.crate_count:
        details.append(
            f"per-segment normal crate sum={per_segment_normal_total}, "
            f"LevelMeta.crate_count={meta.crate_count}"
        )
    if membership_errors:
        details.append(
            "crates without one matching segment membership: "
            + ", ".join(membership_errors)
        )
    findings: list[AuthoringViolation] = []
    if details:
        findings.append(
            AuthoringViolation(
                scene_name,
                CRATE_AUTHORING_RULE,
                "; ".join(details),
            )
        )

    ids_by_value: dict[int, list[str]] = {}
    invalid_ids: list[str] = []
    for crate in crates:
        crate_id = _integer_value(
            crate.properties.get("crate_id", "")
        )
        if crate_id is None or crate_id < 0:
            invalid_ids.append(crate.path)
            continue
        ids_by_value.setdefault(crate_id, []).append(crate.path)
    duplicate_ids = {
        crate_id: paths
        for crate_id, paths in ids_by_value.items()
        if len(paths) > 1
    }
    if invalid_ids or duplicate_ids:
        detail_parts: list[str] = []
        if invalid_ids:
            detail_parts.append(
                "missing/invalid crate_id: "
                + ", ".join(invalid_ids)
            )
        for crate_id, paths in sorted(duplicate_ids.items()):
            detail_parts.append(
                f"crate_id {crate_id} is shared by "
                + ", ".join(paths)
            )
        findings.append(
            AuthoringViolation(
                scene_name,
                CRATE_ID_RULE,
                "; ".join(detail_parts),
            )
        )
    return findings


def _required_jump_findings(
    scene_name: str,
    nodes: list[FlatNode],
    tuning: AuthoringTuning,
) -> list[AuthoringViolation]:
    nodes_by_parent: dict[str, list[FlatNode]] = {}
    for node in nodes:
        nodes_by_parent.setdefault(node.parent, []).append(node)
    regions = [
        (node, _collision_bounds(node, nodes))
        for node in nodes
        if node.script_path == CAMERA_REGION_SCRIPT
    ]
    camera_rails = _camera_rail_polylines(nodes)
    findings: list[AuthoringViolation] = []
    for required_jump in nodes:
        if (
            not required_jump.parent
            or not required_jump.name.casefold().startswith(
                "requiredjump"
            )
        ):
            continue
        children = {
            child.name.casefold(): child
            for child in nodes_by_parent.get(
                required_jump.path,
                [],
            )
        }
        takeoff = children.get("takeoff")
        landing = children.get("landing")
        if (
            takeoff is None
            or landing is None
            or takeoff.node_type != "Marker3D"
            or landing.node_type != "Marker3D"
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    REQUIRED_JUMP_RULE,
                    (
                        f"{required_jump.path} needs direct "
                        "Takeoff and Landing Marker3D children"
                    ),
                )
            )
            continue
        matching_regions = [
            region
            for region, bounds in regions
            if (
                bounds is not None
                and bounds.contains(takeoff.world_position)
                and bounds.contains(landing.world_position)
            )
        ]
        if not matching_regions:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    REQUIRED_JUMP_RULE,
                    (
                        f"{required_jump.path} is not enclosed "
                        "by one camera region"
                    ),
                )
            )
            continue
        camera_frame = _camera_frame_at(
            takeoff.world_position,
            camera_rails,
            tuning.camera_look_ahead_m,
        )
        if camera_frame is None:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    REQUIRED_JUMP_RULE,
                    (
                        f"{required_jump.path} has no usable "
                        "CameraRailController Rail"
                    ),
                )
            )
            continue
        rail_position, corridor_forward = camera_frame
        region_offsets = [
            _runtime_camera_offset(
                _string_value(
                    region.properties.get("camera_mode", "")
                )
                or "default",
                tuning,
            )
            for region in matching_regions
        ]
        blended_offset = _blend_camera_offsets(region_offsets)
        camera_position = _camera_position(
            rail_position,
            corridor_forward,
            blended_offset,
        )
        depression = _jump_depression_degrees(
            camera_position,
            landing.world_position,
        )
        if depression >= tuning.minimum_jump_depression_degrees:
            continue
        findings.append(
            AuthoringViolation(
                scene_name,
                REQUIRED_JUMP_RULE,
                (
                    f"{required_jump.path} depression is "
                    f"{depression:.3f} degrees; minimum from "
                    "CameraTuning is "
                    f"{tuning.minimum_jump_depression_degrees:.3f}"
                ),
            )
        )
    return findings


def _time_crate_findings(
    scene_name: str,
    nodes: list[FlatNode],
) -> list[AuthoringViolation]:
    return [
        AuthoringViolation(
            scene_name,
            TIME_CRATE_RULE,
            f"{crate.path} must be inside the relic_only group",
        )
        for crate in _crate_nodes(nodes)
        if (
            _crate_type(crate) == TIME_CRATE_TYPE
            and RELIC_ONLY_GROUP not in crate.groups
        )
    ]


def _flatten_scene(
    scene_path: Path,
    repo_root: Path,
) -> list[FlatNode]:
    flattened: list[FlatNode] = []
    nodes_by_path: dict[str, FlatNode] = {}
    order = [0]
    _flatten_into(
        scene_path,
        repo_root,
        ".",
        "",
        IDENTITY_TRANSFORM,
        set(),
        {},
        flattened,
        nodes_by_path,
        order,
        set(),
    )
    return flattened


def _flatten_into(
    scene_path: Path,
    repo_root: Path,
    prefix: str,
    parent_path: str,
    parent_world: SpatialTransform,
    inherited_groups: set[str],
    root_overrides: dict[str, str],
    flattened: list[FlatNode],
    nodes_by_path: dict[str, FlatNode],
    order: list[int],
    stack: set[Path],
) -> FlatNode:
    scene_path = scene_path.resolve()
    if scene_path in stack:
        raise ValueError(f"cyclic PackedScene reference: {scene_path}")
    stack = {*stack, scene_path}
    scene = _parse_scene(scene_path)
    if not scene.nodes:
        raise ValueError(f"scene has no nodes: {scene_path}")

    local_to_flat: dict[str, FlatNode] = {}
    root_result: FlatNode | None = None
    for source_node in scene.nodes:
        flat_path = _prefixed_path(prefix, source_node.path)
        if (
            not source_node.node_type
            and not source_node.instance_id
            and flat_path in nodes_by_path
        ):
            existing = nodes_by_path[flat_path]
            existing.properties.update(source_node.properties)
            existing.groups.update(source_node.groups)
            local_to_flat[source_node.path] = existing
            continue

        source_parent = local_to_flat.get(source_node.parent)
        resolved_parent_path = (
            source_parent.path
            if source_parent is not None
            else parent_path
        )
        resolved_parent_world = (
            source_parent.world_transform
            if source_parent is not None
            else parent_world
        )
        properties = dict(source_node.properties)
        if source_node.path == ".":
            properties.update(root_overrides)
        groups = set(source_node.groups)
        if source_node.path == ".":
            groups.update(inherited_groups)

        if source_node.instance_id:
            reference = scene.ext_resources.get(
                source_node.instance_id
            )
            if reference is None:
                raise ValueError(
                    f"{scene_path}: missing ExtResource "
                    f"{source_node.instance_id}"
                )
            instance_path = _resource_path(
                reference.path,
                scene_path,
                repo_root,
            )
            instance_root = _flatten_into(
                instance_path,
                repo_root,
                flat_path,
                resolved_parent_path,
                resolved_parent_world,
                groups,
                properties,
                flattened,
                nodes_by_path,
                order,
                stack,
            )
            local_to_flat[source_node.path] = instance_root
            if source_node.path == ".":
                root_result = instance_root
            continue

        script_path = _script_path(
            properties,
            scene.ext_resources,
        )
        world_transform = _compose_transform(
            resolved_parent_world,
            _node_transform(properties),
        )
        flat_node = FlatNode(
            name=(
                source_node.name
                if source_node.path != "."
                else _path_name(prefix, source_node.name)
            ),
            node_type=source_node.node_type,
            path=flat_path,
            parent=resolved_parent_path,
            properties=properties,
            groups=groups,
            script_path=script_path,
            world_transform=world_transform,
            world_position=world_transform.origin,
            order=order[0],
            source_scene=scene,
        )
        order[0] += 1
        flattened.append(flat_node)
        nodes_by_path[flat_path] = flat_node
        local_to_flat[source_node.path] = flat_node
        if source_node.path == ".":
            root_result = flat_node

    if root_result is None:
        raise ValueError(f"scene root could not be flattened: {scene_path}")
    return root_result


def _parse_scene(path: Path) -> ParsedScene:
    ext_resources: dict[str, ResourceReference] = {}
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
            raise_on_unrecognized_section(path, section_name)
            attributes = _header_attributes(header)
            if section_name == "ext_resource":
                resource_id = attributes.get("id", "")
                resource_path = attributes.get("path", "")
                if resource_id and resource_path:
                    ext_resources[resource_id] = ResourceReference(
                        resource_type=attributes.get("type", ""),
                        path=resource_path,
                    )
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
                    instance_id=_resource_id(
                        attributes.get("instance", "")
                    ),
                    groups=_header_groups(header),
                    index=len(nodes),
                    properties={},
                )
                nodes.append(node)
                current_properties = node.properties
            continue
        match = PROPERTY_PATTERN.match(stripped)
        if match is None or current_properties is None:
            raise ValueError(
                f"{path}: unclassifiable line outside any parsed "
                f"section: {stripped!r} — the authoring lint cannot "
                "silently drop authored content it doesn't recognize"
            )
        current_properties[match.group(1)] = match.group(2).strip()
    return ParsedScene(path, ext_resources, sub_resources, nodes)


def _collision_bounds(
    region: FlatNode,
    nodes: list[FlatNode],
) -> Bounds | None:
    prefix = region.path + "/"
    for child in nodes:
        if (
            child.node_type != "CollisionShape3D"
            or not child.path.startswith(prefix)
        ):
            continue
        resource_id = _resource_id(
            child.properties.get("shape", "")
        )
        shape = child.source_scene.sub_resources.get(resource_id)
        if shape is None or shape.resource_type != "BoxShape3D":
            continue
        size = _parse_vector(shape.properties.get("size", ""))
        if size is None:
            continue
        return Bounds(
            transform=child.world_transform,
            half_size=_multiply(size, 0.5),
        )
    return None


def _camera_rail_polylines(
    nodes: list[FlatNode],
) -> list[list[Vector3]]:
    nodes_by_path = {node.path: node for node in nodes}
    polylines: list[list[Vector3]] = []
    for rail in nodes:
        controller = nodes_by_path.get(rail.parent)
        if (
            rail.node_type != "Path3D"
            or controller is None
            or controller.script_path
            != CAMERA_RAIL_CONTROLLER_SCRIPT
        ):
            continue
        points = [
            marker.world_position
            for marker in sorted(nodes, key=lambda node: node.order)
            if (
                marker.node_type == "Marker3D"
                and marker.parent == rail.path
            )
        ]
        if len(points) >= 2:
            polylines.append(points)
    return polylines


def _camera_frame_at(
    player_position: Vector3,
    camera_rails: list[list[Vector3]],
    look_ahead_m: float,
) -> tuple[Vector3, Vector3] | None:
    candidates: list[
        tuple[float, list[Vector3], list[float], float, Vector3]
    ] = []
    for points in camera_rails:
        cumulative = _polyline_cumulative_lengths(points)
        if not cumulative or math.isclose(cumulative[-1], 0.0):
            continue
        rail_offset = _project_onto_polyline(
            player_position,
            points,
            cumulative,
        )
        rail_position = _sample_polyline(
            points,
            cumulative,
            rail_offset,
        )
        candidates.append(
            (
                _length(
                    _subtract(player_position, rail_position)
                ),
                points,
                cumulative,
                rail_offset,
                rail_position,
            )
        )
    if not candidates:
        return None
    (
        _distance,
        points,
        cumulative,
        rail_offset,
        rail_position,
    ) = min(candidates, key=lambda candidate: candidate[0])
    sample_distance = max(look_ahead_m, 0.0)
    look_position = _sample_polyline(
        points,
        cumulative,
        min(rail_offset + sample_distance, cumulative[-1]),
    )
    forward = _normalize(_subtract(look_position, rail_position))
    if _is_zero(forward):
        behind = _sample_polyline(
            points,
            cumulative,
            max(rail_offset - sample_distance, 0.0),
        )
        forward = _normalize(_subtract(rail_position, behind))
    corridor_forward = _normalize((forward[0], 0.0, forward[2]))
    if _is_zero(corridor_forward):
        return None
    return rail_position, corridor_forward


def _runtime_camera_offset(
    mode: str,
    tuning: AuthoringTuning,
) -> Vector3:
    offset = tuning.camera_offsets.get(
        mode,
        tuning.camera_offsets["default"],
    )
    if mode == "wall_run":
        return (offset[2], offset[1], offset[0])
    return offset


def _blend_camera_offsets(offsets: list[Vector3]) -> Vector3:
    """Mirror ``CameraBlend.resolve_offset``'s real overlap resolution.

    The runtime does not pick one active region's offset over another:
    every currently-overlapping ``CameraRegion`` contributes, and the
    camera uses the plain average of all of them
    (``camera_blend.gd:resolve_offset``). A jump enclosed by two or
    more overlapping regions is a jump the real camera sees through
    that blended average, never through any single region alone —
    checking each region independently and accepting the best one
    describes a camera the player never actually gets.
    """
    total = ZERO
    for offset in offsets:
        total = _add(total, offset)
    return _multiply(total, 1.0 / len(offsets))


def _camera_position(
    rail_position: Vector3,
    corridor_forward: Vector3,
    camera_offset: Vector3,
) -> Vector3:
    camera_right = _normalize(_cross(corridor_forward, UP))
    if _is_zero(camera_right):
        camera_right = (1.0, 0.0, 0.0)
    return _add(
        rail_position,
        _add(
            _multiply(camera_right, camera_offset[0]),
            _add(
                _multiply(UP, camera_offset[1]),
                _multiply(
                    corridor_forward,
                    -camera_offset[2],
                ),
            ),
        ),
    )


def _jump_depression_degrees(
    camera_position: Vector3,
    landing: Vector3,
) -> float:
    to_landing = _subtract(landing, camera_position)
    horizontal_distance = math.hypot(
        to_landing[0],
        to_landing[2],
    )
    vertical_drop = -to_landing[1]
    return math.degrees(
        math.atan2(vertical_drop, horizontal_distance)
    )


def _polyline_cumulative_lengths(
    points: list[Vector3],
) -> list[float]:
    if not points:
        return []
    cumulative = [0.0]
    for start, finish in zip(points, points[1:]):
        cumulative.append(
            cumulative[-1] + _length(_subtract(finish, start))
        )
    return cumulative


def _project_onto_polyline(
    point: Vector3,
    points: list[Vector3],
    cumulative: list[float],
) -> float:
    best_distance = math.inf
    best_along = 0.0
    for index, (start, finish) in enumerate(
        zip(points, points[1:])
    ):
        segment = _subtract(finish, start)
        length_squared = _dot(segment, segment)
        if math.isclose(length_squared, 0.0):
            continue
        weight = max(
            0.0,
            min(
                1.0,
                _dot(_subtract(point, start), segment)
                / length_squared,
            ),
        )
        projected = _add(start, _multiply(segment, weight))
        distance = _length(_subtract(point, projected))
        if distance < best_distance:
            best_distance = distance
            best_along = (
                cumulative[index]
                + math.sqrt(length_squared) * weight
            )
    return best_along


def _sample_polyline(
    points: list[Vector3],
    cumulative: list[float],
    distance: float,
) -> Vector3:
    clamped_distance = max(
        0.0,
        min(distance, cumulative[-1]),
    )
    for index, (start, finish) in enumerate(
        zip(points, points[1:])
    ):
        segment_start = cumulative[index]
        segment_finish = cumulative[index + 1]
        if clamped_distance > segment_finish:
            continue
        segment_length = segment_finish - segment_start
        if math.isclose(segment_length, 0.0):
            continue
        weight = (
            clamped_distance - segment_start
        ) / segment_length
        return _add(
            start,
            _multiply(_subtract(finish, start), weight),
        )
    return points[-1]


def _load_authoring_tuning(repo_root: Path) -> AuthoringTuning:
    economy = _assignment_values(
        (repo_root / "data/tuning/economy.tres").read_text(
            encoding="utf-8"
        )
    )
    camera = _assignment_values(
        (repo_root / "data/tuning/camera.tres").read_text(
            encoding="utf-8"
        )
    )
    move = _assignment_values(
        (repo_root / "data/tuning/move.tres").read_text(
            encoding="utf-8"
        )
    )
    offsets: dict[str, Vector3] = {}
    for mode, property_name in {
        "default": "default_offset",
        "close": "close_offset",
        "side_on": "side_on_offset",
        "grind": "grind_offset",
        "wall_run": "wall_run_offset",
        "swing": "swing_offset",
        "toward_camera": "toward_camera_offset",
    }.items():
        parsed = _parse_vector(camera[property_name])
        if parsed is None:
            raise ValueError(
                f"CameraTuning.{property_name} is not a Vector3"
            )
        offsets[mode] = parsed
    return AuthoringTuning(
        checkpoint_spacing_limit_s=float(
            economy["checkpoint_spacing_limit_s"]
        ),
        minimum_jump_depression_degrees=float(
            camera["minimum_jump_depression_degrees"]
        ),
        camera_look_ahead_m=float(camera["look_ahead_m"]),
        camera_offsets=offsets,
        respawn_floor_y_m=float(move["respawn_floor_y_m"]),
    )


def _load_level_meta(path: Path) -> LevelMetaValues:
    values = _assignment_values(
        path.read_text(encoding="utf-8")
    )
    return LevelMetaValues(
        crate_count=int(float(values["crate_count"])),
        design_pace_mps=float(values["design_pace_mps"]),
    )


def _level_meta_path(
    scene: ParsedScene,
    repo_root: Path,
) -> Path | None:
    if not scene.nodes:
        return None
    resource_id = _resource_id(
        scene.nodes[0].properties.get("metadata/level_meta", "")
    )
    reference = scene.ext_resources.get(resource_id)
    if reference is None or not reference.path.endswith(".tres"):
        return None
    candidate = _resource_path(
        reference.path,
        scene.path,
        repo_root,
    )
    if (
        not candidate.is_file()
        or LEVEL_META_SCRIPT
        not in candidate.read_text(encoding="utf-8")
    ):
        return None
    return candidate


def _crate_nodes(nodes: list[FlatNode]) -> list[FlatNode]:
    return [
        node
        for node in nodes
        if node.script_path == BREAKABLE_CRATE_SCRIPT
    ]


def _crate_type(crate: FlatNode) -> str:
    return (
        _string_value(crate.properties.get("crate_type", ""))
        or "standard"
    )


def _is_spine_marker(node: FlatNode) -> bool:
    return any(
        component.casefold().startswith("spine")
        for component in node.path.split("/")[:-1]
    )


def _script_path(
    properties: dict[str, str],
    resources: dict[str, ResourceReference],
) -> str:
    resource_id = _resource_id(properties.get("script", ""))
    reference = resources.get(resource_id)
    return reference.path if reference is not None else ""


def _prefixed_path(prefix: str, local_path: str) -> str:
    if local_path == ".":
        return prefix
    if prefix == ".":
        return local_path
    return f"{prefix}/{local_path}"


def _path_name(prefix: str, fallback: str) -> str:
    return fallback if prefix == "." else prefix.rsplit("/", 1)[-1]


def _resource_path(
    authored_path: str,
    owning_scene: Path,
    repo_root: Path,
) -> Path:
    if authored_path.startswith("res://"):
        return repo_root / authored_path.removeprefix("res://")
    return owning_scene.parent / authored_path


def _header_groups(header: str) -> set[str]:
    match = GROUPS_PATTERN.search(header)
    if match is None:
        return set()
    return {
        group
        for group in re.findall(r'"([^"]+)"', match.group(1))
    }


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
    levels_root = root / "scenes" / "levels"
    if levels_root.is_dir():
        scene_files = sorted(levels_root.rglob("*.tscn"))
        if not scene_files:
            # R11: a scan root that exists but contains zero scenes is
            # just as silently-wrong a signal as one that fails to
            # resolve at all -- fail closed instead of reporting zero
            # violations for zero scanned files.
            raise ValueError(
                f"{levels_root}: exists but contains no .tscn files -- "
                "a real level set should never scan empty; fix the "
                "directory contents instead of silently reporting zero "
                "violations"
            )
        yield from scene_files
        return
    if (root / "scenes").is_dir():
        # R11: P1-10's scan-root fix only ever proved the recursion half
        # (rglob vs glob) is caught; the path STRING half ("levels")
        # was not -- a one-character sabotage of that segment (or a
        # genuine directory-structure regression) leaves scenes/levels/
        # unresolved. The old fallback silently widened the scan to the
        # whole `root` tree in that case, which happened to still find
        # real level content nested somewhere underneath (a coincidence
        # of the broad fallback, not a verified mechanism) while also
        # picking up unrelated content (e.g. addons/gut/**) this lint
        # has no rule for. `scenes/` existing without its expected
        # `levels/` child is exactly that sabotage's shape, so fail
        # loudly here instead of silently scanning the wrong root.
        raise ValueError(
            f"{root}: scenes/ exists but scenes/levels/ does not -- the "
            "authoring lint's scan root failed to resolve to real level "
            "content; fix the path or the directory structure instead "
            "of letting the scan silently widen to the whole tree"
        )


def _find_repo_root(root: Path) -> Path:
    start = root.parent if root.is_file() else root
    for candidate in (start, *start.parents):
        if (
            (candidate / "project.godot").is_file()
            and (candidate / "data/tuning/economy.tres").is_file()
        ):
            return candidate
    return Path(__file__).resolve().parents[1]


def _display_path(path: Path, repo_root: Path) -> str:
    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return path.as_posix()


def _node_transform(
    properties: dict[str, str],
) -> SpatialTransform:
    authored_transform = _parse_transform(
        properties.get("transform", "")
    )
    if authored_transform is not None:
        return authored_transform

    origin = (
        _parse_vector(properties.get("position", ""))
        or ZERO
    )
    authored_basis = _parse_basis(properties.get("basis", ""))
    if authored_basis is not None:
        return SpatialTransform(authored_basis, origin)

    rotation = _parse_vector(properties.get("rotation", ""))
    if rotation is None:
        rotation_degrees = _parse_vector(
            properties.get("rotation_degrees", "")
        )
        rotation = (
            tuple(
                math.radians(component)
                for component in rotation_degrees
            )
            if rotation_degrees is not None
            else ZERO
        )
    scale = (
        _parse_vector(properties.get("scale", ""))
        or ONE
    )
    return SpatialTransform(
        _scale_basis_columns(
            _basis_from_euler_yxz(rotation),
            scale,
        ),
        origin,
    )


def _string_value(value: str) -> str:
    match = STRING_PATTERN.fullmatch(value.strip())
    return match.group(1) if match is not None else ""


def _integer_value(value: str) -> int | None:
    try:
        numeric = float(value)
    except ValueError:
        return None
    if not math.isfinite(numeric) or numeric != math.floor(numeric):
        return None
    return int(numeric)


def _slug(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


def _add(first: Vector3, second: Vector3) -> Vector3:
    return tuple(
        first[index] + second[index] for index in range(3)
    )  # type: ignore[return-value]


def _subtract(first: Vector3, second: Vector3) -> Vector3:
    return tuple(
        first[index] - second[index] for index in range(3)
    )  # type: ignore[return-value]


def _multiply(value: Vector3, scalar: float) -> Vector3:
    return tuple(
        component * scalar for component in value
    )  # type: ignore[return-value]


def _basis_xform(basis: Basis3, value: Vector3) -> Vector3:
    return _add(
        _multiply(basis[0], value[0]),
        _add(
            _multiply(basis[1], value[1]),
            _multiply(basis[2], value[2]),
        ),
    )


def _basis_multiply(first: Basis3, second: Basis3) -> Basis3:
    return tuple(
        _basis_xform(first, column)
        for column in second
    )  # type: ignore[return-value]


def _scale_basis_columns(
    basis: Basis3,
    scale: Vector3,
) -> Basis3:
    return tuple(
        _multiply(column, scale[index])
        for index, column in enumerate(basis)
    )  # type: ignore[return-value]


def _basis_from_euler_yxz(rotation: Vector3) -> Basis3:
    x_angle, y_angle, z_angle = rotation
    x_cos = math.cos(x_angle)
    x_sin = math.sin(x_angle)
    y_cos = math.cos(y_angle)
    y_sin = math.sin(y_angle)
    z_cos = math.cos(z_angle)
    z_sin = math.sin(z_angle)
    x_basis: Basis3 = (
        (1.0, 0.0, 0.0),
        (0.0, x_cos, x_sin),
        (0.0, -x_sin, x_cos),
    )
    y_basis: Basis3 = (
        (y_cos, 0.0, -y_sin),
        (0.0, 1.0, 0.0),
        (y_sin, 0.0, y_cos),
    )
    z_basis: Basis3 = (
        (z_cos, z_sin, 0.0),
        (-z_sin, z_cos, 0.0),
        (0.0, 0.0, 1.0),
    )
    return _basis_multiply(
        _basis_multiply(y_basis, x_basis),
        z_basis,
    )


def _compose_transform(
    parent: SpatialTransform,
    local: SpatialTransform,
) -> SpatialTransform:
    return SpatialTransform(
        basis=_basis_multiply(parent.basis, local.basis),
        origin=_add(
            parent.origin,
            _basis_xform(parent.basis, local.origin),
        ),
    )


def _basis_inverse_xform(
    basis: Basis3,
    value: Vector3,
) -> Vector3 | None:
    first, second, third = basis
    determinant = _dot(first, _cross(second, third))
    if math.isclose(determinant, 0.0):
        return None
    inverse_determinant = 1.0 / determinant
    return (
        _dot(_cross(second, third), value)
        * inverse_determinant,
        _dot(_cross(third, first), value)
        * inverse_determinant,
        _dot(_cross(first, second), value)
        * inverse_determinant,
    )


def _dot(first: Vector3, second: Vector3) -> float:
    return sum(
        first[index] * second[index] for index in range(3)
    )


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
    return (
        ZERO
        if math.isclose(length, 0.0)
        else _multiply(value, 1.0 / length)
    )


def _is_zero(value: Vector3) -> bool:
    return math.isclose(_length(value), 0.0)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="Level scenes or roots (default: repository scenes/levels)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    repo_root = Path(__file__).resolve().parents[1]
    paths = arguments.paths or [repo_root]
    missing_paths = [path for path in paths if not path.exists()]
    if missing_paths:
        for path in missing_paths:
            print(f"{path}: does not exist", file=sys.stderr)
        return 2
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
