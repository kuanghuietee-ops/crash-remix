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
        assignment_values,
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
        assignment_values,
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
WUMPA_TOTAL_RULE = "wumpa_total"
REQUIRED_JUMP_RULE = "required_jump_depression"
TIME_CRATE_RULE = "time_crate_relic_only"
SPAWN_FLOOR_RULE = "player_spawn_has_reachable_floor"
CHASE_START_GAP_RULE = "chase_start_gap"
ENEMY_FLOOR_CONTACT_RULE = "enemy_floor_contact"
# Task 8 (CTR racing mode, R2): rules for racing-track scenes (scenes under
# scenes/racing/ that author a TrackSpine directly -- see
# _scene_declares_script/_track_findings). These are a separate rule family
# from the platformer LevelMeta rules above: a track scene has no LevelMeta
# at all, so it takes the "meta_path is None" branch in
# find_authoring_violations that platformer scenes only hit as a bug.
TRACK_SPINE_RING_RULE = "track_spine_ring"
TRACK_GATE_SEQUENCE_RULE = "track_gate_sequence"
TRACK_GATE_ORDER_RULE = "track_gate_order"
TRACK_GATE_WIDTH_RULE = "track_gate_width"
TRACK_SPAWN_RULE = "track_spawn_before_start"
# Task 5 (CTR R3 integration): the AI starting grid needs markers to spawn
# opponents on -- see race_session.gd's _spawn_ai_karts().
TRACK_GRID_SLOTS_RULE = "track_grid_slots"
# Task 5 (CTR R4 items): item boxes must exist, sit on-road, and stay clear
# of this scene's own origin -- see ITEM_BOX_SCRIPT's own doc below.
TRACK_ITEM_BOX_RULE = "track_item_boxes"
# Task 2 (CTR R6, circuit polish): dressing clearance, gate flags, start/
# finish arch -- see each rule's own constants block below for the numbers.
TRACK_DRESSING_CLEARANCE_RULE = "track_dressing_clearance"
TRACK_GATE_FLAG_RULE = "track_gate_flags"
TRACK_ARCH_RULE = "track_start_finish_arch"

BREAKABLE_CRATE_SCRIPT = (
    "res://src/gameplay/crates/breakable_crate.gd"
)
CAMERA_REGION_SCRIPT = (
    "res://src/gameplay/camera/camera_region.gd"
)
CAMERA_RAIL_CONTROLLER_SCRIPT = (
    "res://src/gameplay/camera/camera_rail_controller.gd"
)
CHASE_HAZARD_SCRIPT = (
    "res://src/gameplay/chase/chase_hazard.gd"
)
GRAYBOX_PLATFORM_SCRIPT = (
    "res://src/graybox/graybox_platform.gd"
)
# The three EnemyBase subclasses. Static .tscn parsing only sees the exact
# script attached to a node, not its GDScript "extends" chain, so a new
# enemy type must be added here too -- the same shape as
# LEVEL_META_EXEMPT_SCENES and the crate-type constants below.
ENEMY_SCRIPTS = frozenset(
    {
        "res://src/gameplay/enemies/enemy_plant.gd",
        "res://src/gameplay/enemies/enemy_crab.gd",
        "res://src/gameplay/enemies/enemy_skink.gd",
    }
)
# How far an authored enemy's base may sit from the top surface of the
# GrayboxPlatform beneath it before it reads as floating or embedded on a
# real phone. Matches the tolerance used to diagnose the "plant is hanging
# in the air" report (root-caused to scenes/enemies/plant.tscn -- see
# _enemy_floor_contact_findings).
ENEMY_FLOOR_TOLERANCE_M = 0.05
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
STANDARD_CRATE_TYPE = "standard"
BOUNCE_CRATE_TYPE = "bounce"
CHECKPOINT_CRATE_TYPE = "checkpoint"
RELIC_ONLY_GROUP = "relic_only"
WUMPA_PICKUP_GROUP = "wumpa_pickup"
SEGMENT_CONTAINER_SLUGS = {"segments"}
TRACK_SPINE_SCRIPT = "res://src/racing/track/track_spine.gd"
CHECKPOINT_GATE_SCRIPT = "res://src/racing/track/checkpoint_gate.gd"
TRACK_SPAWN_NODE_NAME = "KartSpawn"
# Spine markers closer together than this (including the wrap segment from
# the last authored marker back to the first, which closes the ring) read as
# an authoring accident -- a duplicated or near-duplicated point -- rather
# than a legitimately tight corner. RailCurveBuilder's Catmull-Rom shaping
# can produce a degenerate (near-zero-length) tangent segment at a true
# duplicate, which is the failure this guards against, not tight-radius
# corners: track_sanity_shores.tscn's tightest hairpin still spaces markers
# several meters apart (see task-8-report.md's gate table).
TRACK_SPINE_MIN_MARKER_SPACING_M = 0.5
# A closed ring needs at least a triangle's worth of points to mean anything
# as a "ring" rather than a line or a single dangling point.
TRACK_SPINE_MIN_MARKER_COUNT = 3
# The lint has no runtime access to a racing road-width tuning resource --
# there isn't one; a track's road width is authored directly into its
# floor/wall geometry, not read from a Resource at authoring time the way
# LevelMeta/EconomyTuning/CameraTuning are above. This mirrors the width
# every current circuit authors (track_graybox_loop.tscn's
# Shape_floor_straight z=14, track_sanity_shores.tscn's own floor pieces).
# Keep this in sync by hand if a future track ever authors a different road
# width -- acceptable for a lint-side constant per the task brief.
TRACK_ROAD_WIDTH_M = 14.0
# Task 5 (CTR R3 integration): race_session.gd spawns one AI kart per
# GridSlot1..N marker (see its own _spawn_ai_karts() doc) -- the player
# spawns from the separate KartSpawn/slot 0 marker, which this rule never
# counts. The lint has no runtime access to AiTuning.opponent_count (there
# IS a tuning resource here, unlike TRACK_ROAD_WIDTH_M above, but reading it
# would mean this static-parsing lint importing and trusting a live
# Resource load, a much bigger dependency than one constant kept in sync by
# hand) -- this is fixed at ai.tres's own current default (opponent_count=
# 5.0) for the same "keep in sync by hand if it ever changes" reason.
# Fix-wave LOW-8: a GridSlot0 duplicating KartSpawn's own transform used to
# be authored too (and counted here) -- deleted as a redundant second
# source of truth for the same spawn, so this floor dropped from 6 to 5.
TRACK_GRID_SLOT_MIN_COUNT = 5
TRACK_GRID_SLOT_NAME_PATTERN = re.compile(r"^GridSlot\d+$")
# Fix-wave MEDIUM-3: mirrors ai_kart_agent.gd's own _compute_lateral_target_m()
# inputs (ai.tres's current opponent_count/lateral_slot_spacing_m) -- same
# "the lint has no runtime access to a tuning resource, keep in sync by
# hand" rationale as TRACK_GRID_SLOT_MIN_COUNT/TRACK_ROAD_WIDTH_M above.
TRACK_GRID_SLOT_INDEX_PATTERN = re.compile(r"^GridSlot(\d+)$")
AI_OPPONENT_COUNT_FOR_GRID = 5.0
AI_LATERAL_SLOT_SPACING_M = 1.7
# Authoring/measurement slack around the formula's own exact value -- not a
# feel tolerance, just enough to absorb the track scene's own decimal
# rounding (see the two real tracks' own GridSlot positions).
TRACK_GRID_SLOT_OFFSET_TOLERANCE_M = 0.01
# Task 5 (CTR R4 items): race_session.gd discovers ItemBox instances by a
# TYPE/SCRIPT scan under Track (_discover_item_boxes(), the same shape
# _discover_gates() already uses for CheckpointGate) -- not by a GridSlotN-
# style fixed root-level name, so an authored box can legally sit anywhere
# in the flattened tree. This rule discovers them the same way, by script
# match against ITEM_BOX_SCRIPT.
ITEM_BOX_SCRIPT = "res://src/racing/items/item_box.gd"
# Two on-road lines of three boxes each, per track (the R4 item-box
# authoring brief) -- 6/track.
TRACK_ITEM_BOX_MIN_COUNT = 6
# Spec Recorded-debt #10 (R4 Task 4 fix round 1 [LOW-b], CARRIED to this
# task): the PLAYER kart's own Kart node sits at Transform3D.IDENTITY --
# this scene's own local origin -- for one full physics-server-registration
# instant before configure()'s own _seed_kart_transform() moves it, and an
# item box authored close enough to that point can register a real, sticky
# false pickup against that one-frame flash (VERIFIED empirically in the R4
# Task 4 fix-round-1 report, not just reasoned there). "This scene's own
# local origin" and "world origin" are the SAME point under both real race
# scenes' current wiring -- race_time_trial.tscn/race_sanity_shores.tscn
# each instance their Track child with no transform override at all (hand-
# verified by inspection) -- and this lint can only ever see a single
# track_*.tscn file in isolation anyway (race_time_trial.tscn/race_sanity_
# shores.tscn are never themselves parsed as "racing-track" scenes, see
# _scene_declares_script's own doc), so Vector3.ZERO in THIS scene's own
# coordinate frame is the one and only thing checkable here, and it covers
# both readings the spec debt names as long as that "Track sits at
# identity" wiring holds. Keep this comment in sync if a future race scene
# ever offsets its Track child.
TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M = 10.0
# Task 2 (CTR R6, circuit polish): racing-line dressing (EnvironmentArt scatter
# props -- kit palms/rocks/foliage) must clear the road by more than the bare
# TRACK_ROAD_WIDTH_M/2 half-width every ON-road check above uses, because
# unlike a gate or item box a dressing piece is a real multi-metre mesh, not a
# point. The largest ground-level footprint among the small-prop roster this
# rule is meant to cover is rock_cluster_a's own ~5.17m (four boulders
# scattered up to sqrt(3.4^2+3.4^2)+0.36m from its own origin -- see
# scripts/blender/build_beach_env_kit.py's build_rock_cluster()); every other
# piece in the roster (palms, bushes, ferns, grass, single boulders) measures
# smaller. Rounded up to a real margin, not a knife's-edge one.
TRACK_ENVIRONMENT_ART_NODE_NAME = "EnvironmentArt"
TRACK_DRESSING_CLEARANCE_MARGIN_M = 5.5
# Task 2: per-gate flag posts must sit at "the gate's road edge" -- beyond the
# bare half-width (so a torch_post_a's own ~0.5m bowl footprint, see
# build_torch_post(), clears the wall that already sits centered ON that
# half-width with its own ~0.2m half-thickness) but not implausibly far out,
# so a hand-tweaked post still reads as belonging to this gate. Checked
# against the gate's OWN authored basis (not a re-derived spine tangent) --
# the task brief's "derive positions/rotations from the gate transforms" --
# so a gate whose authored rotation drifts a few degrees from the spine's own
# tangent (real, see the sanity_shores gate-transform survey) isn't
# double-penalized here for a mismatch TRACK_GATE_WIDTH_RULE already owns.
GATE_FLAG_NODE_NAME_PATTERN = re.compile(r"^Gate(\d+)Flag[LR]$")
TRACK_GATE_FLAG_MAX_CLEARANCE_M = 3.0
TRACK_GATE_FLAG_FORWARD_TOLERANCE_M = 0.5
# Task 2: the start/finish arch at gate 0 -- two posts (pre-existing on
# sanity_shores, reused rather than re-checked at a fixed offset since a
# hand-placed post can legitimately vary) plus a NEW crossbar and banner,
# both of which must actually be centered over gate 0 rather than just
# somewhere on the Arch node.
TRACK_ARCH_NODE_NAME = "Arch"
ARCH_POST_NAME_SUBSTRING = "Post"
ARCH_CROSSBAR_NODE_NAME = "Crossbar"
ARCH_BANNER_NODE_NAME = "Banner"
TRACK_ARCH_POST_MAX_CLEARANCE_M = 3.0
TRACK_ARCH_CENTER_TOLERANCE_M = 1.5
# Imported glTF scenes can only contribute visual hierarchy/material data to
# these authoring checks; unlike .tscn files, they cannot carry Godot scripts,
# groups, crate IDs, checkpoint links, or tuning resources. Keep their instance
# roots in the flattened hierarchy, but do not decode their binary payload as
# UTF-8. Unknown/binary Godot scene formats still fail closed.
OPAQUE_VISUAL_SCENE_SUFFIXES = frozenset({".glb", ".gltf"})

STRING_PATTERN = re.compile(r'(?:&)?"([^"]*)"')
NODE_PATH_PATTERN = re.compile(r'NodePath\("([^"]*)"\)')
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
    wumpa_total: int
    design_pace_mps: float


@dataclass(frozen=True)
class AuthoringTuning:
    checkpoint_spacing_limit_s: float
    wumpa_per_standard_crate: int
    wumpa_per_pickup: int
    bounce_crate_max_bounces: int
    bounce_crate_wumpa_per_bounce: int
    minimum_jump_depression_degrees: float
    camera_look_ahead_m: float
    camera_offsets: dict[str, Vector3]
    respawn_floor_y_m: float
    boulder_start_gap_m: float


def find_authoring_violations(root: Path) -> list[AuthoringViolation]:
    root = root.resolve()
    repo_root = _find_repo_root(root)
    tuning = _load_authoring_tuning(repo_root)
    findings: list[AuthoringViolation] = []
    for scene_path in _scene_files(root):
        parsed = _parse_scene(scene_path)
        meta_path = _level_meta_path(parsed, repo_root)
        if meta_path is None:
            if _scene_declares_script(parsed, TRACK_SPINE_SCRIPT):
                flat_nodes = _flatten_scene(scene_path, repo_root)
                findings.extend(
                    _track_findings(
                        _display_path(scene_path, repo_root),
                        flat_nodes,
                    )
                )
                continue
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
        _wumpa_findings(scene_name, nodes, meta, tuning)
    )
    findings.extend(
        _required_jump_findings(scene_name, nodes, tuning)
    )
    findings.extend(_time_crate_findings(scene_name, nodes))
    findings.extend(
        _spawn_floor_findings(scene_name, nodes, tuning)
    )
    findings.extend(
        _chase_start_gap_findings(scene_name, nodes, tuning)
    )
    findings.extend(_enemy_floor_contact_findings(scene_name, nodes))
    return findings


def _scene_declares_script(parsed: ParsedScene, script_path: str) -> bool:
    """True when one of the scene's OWN (unflattened) nodes carries script_path.

    Deliberately checks ``parsed.nodes`` (the raw, file-local node list from
    ``_parse_scene``), not a flattened tree: a race scene like
    ``race_time_trial.tscn`` instances a track scene as a child
    (``instance=ExtResource(...)``) rather than authoring a TrackSpine node
    itself, so it must read as NOT a racing-track scene here even though a
    TrackSpine exists somewhere in its flattened descendants. Only a scene
    that authors the TrackSpine node directly -- a track_*.tscn -- takes the
    track-rule branch in find_authoring_violations.
    """
    for node in parsed.nodes:
        resource_id = _resource_id(node.properties.get("script", ""))
        reference = parsed.ext_resources.get(resource_id)
        if reference is not None and reference.path == script_path:
            return True
    return False


def _track_findings(
    scene_name: str,
    nodes: list[FlatNode],
) -> list[AuthoringViolation]:
    """Task 8 rule family for a racing-track scene (see class doc above).

    Mirrors _level_findings' shape: gather the scene's own spine markers and
    checkpoint gates once, then hand them to each rule in turn. Rules (c)-(e)
    need a real polyline to project onto, so -- like _checkpoint_findings'
    own "fewer than two spine markers" early return above -- a ring too
    short to mean anything short-circuits those three and leaves only the
    ring-count finding itself, rather than cascading into confusing
    zero-progress findings from every gate.
    """
    spine_node = next(
        (node for node in nodes if node.script_path == TRACK_SPINE_SCRIPT),
        None,
    )
    if spine_node is None:
        return []
    markers = sorted(
        (
            node
            for node in nodes
            if node.parent == spine_node.path
            and node.node_type == "Marker3D"
        ),
        key=lambda node: node.order,
    )
    gates = sorted(
        (
            node
            for node in nodes
            if node.script_path == CHECKPOINT_GATE_SCRIPT
        ),
        key=lambda node: node.order,
    )
    findings: list[AuthoringViolation] = []
    findings.extend(_track_spine_ring_findings(scene_name, markers))
    findings.extend(_track_gate_sequence_findings(scene_name, gates))
    if len(markers) < TRACK_SPINE_MIN_MARKER_COUNT:
        return findings
    points = [marker.world_position for marker in markers]
    cumulative = _polyline_cumulative_lengths(points)
    findings.extend(
        _track_gate_order_findings(scene_name, gates, points, cumulative)
    )
    findings.extend(
        _track_gate_width_findings(
            scene_name,
            gates,
            nodes,
            points,
            cumulative,
        )
    )
    findings.extend(
        _track_spawn_findings(scene_name, nodes, gates, points, cumulative)
    )
    findings.extend(
        _track_grid_slot_findings(scene_name, nodes, gates, points, cumulative)
    )
    findings.extend(
        _track_item_box_findings(scene_name, nodes, points, cumulative)
    )
    findings.extend(
        _track_dressing_findings(scene_name, nodes, points, cumulative)
    )
    findings.extend(_track_gate_flag_findings(scene_name, gates, nodes))
    findings.extend(_track_arch_findings(scene_name, gates, nodes))
    return findings


def _track_spine_ring_findings(
    scene_name: str,
    markers: list[FlatNode],
) -> list[AuthoringViolation]:
    """Rule (a): the spine markers form a closed ring, no near-duplicates.

    "Closed ring" here means: enough points to be a ring at all (at least
    TRACK_SPINE_MIN_MARKER_COUNT), and no two markers ADJACENT IN THE RING --
    including the wrap segment from the last authored marker back to the
    first, which is exactly what actually closes the loop, since TrackSpine
    always bakes with closed=true (see track_spine.gd) -- sitting close
    enough together to read as a duplicated point rather than a genuinely
    tight corner.
    """
    if len(markers) < TRACK_SPINE_MIN_MARKER_COUNT:
        return [
            AuthoringViolation(
                scene_name,
                TRACK_SPINE_RING_RULE,
                (
                    f"TrackSpine has {len(markers)} marker(s); a closed "
                    f"ring needs at least {TRACK_SPINE_MIN_MARKER_COUNT}"
                ),
            )
        ]
    findings: list[AuthoringViolation] = []
    ring = markers + [markers[0]]
    for previous, current in zip(ring, ring[1:]):
        distance = _length(
            _subtract(current.world_position, previous.world_position)
        )
        if distance < TRACK_SPINE_MIN_MARKER_SPACING_M:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_SPINE_RING_RULE,
                    (
                        f"{previous.path} and {current.path} are "
                        f"{distance:.3f}m apart -- near-duplicate "
                        "consecutive spine markers (minimum "
                        f"{TRACK_SPINE_MIN_MARKER_SPACING_M:.3f}m)"
                    ),
                )
            )
    return findings


def _track_gate_indices(
    gates: list[FlatNode],
) -> tuple[dict[int, FlatNode], list[str]]:
    by_index: dict[int, FlatNode] = {}
    invalid: list[str] = []
    for gate in gates:
        value = _integer_value(gate.properties.get("gate_index", ""))
        if value is None:
            invalid.append(gate.path)
        else:
            by_index[value] = gate
    return by_index, invalid


def _track_gate_sequence_findings(
    scene_name: str,
    gates: list[FlatNode],
) -> list[AuthoringViolation]:
    """Rule (b): CheckpointGate.gate_index values are exactly 0..N-1.

    Walks the RAW list of authored index values, not a dict keyed by index --
    a dict silently collapses two gates sharing the same gate_index down to
    one entry (last-wins), which would hide the exact "gaps/dupes" shape
    this rule exists to catch. ``values.count(value) > 1`` below is what
    actually detects a duplicate; the missing/unexpected sets alone cannot
    (a duplicate that still falls inside the valid 0..N-1 range is invisible
    to a plain set comparison).
    """
    values: list[int] = []
    invalid: list[str] = []
    for gate in gates:
        value = _integer_value(gate.properties.get("gate_index", ""))
        if value is None:
            invalid.append(gate.path)
        else:
            values.append(value)
    findings: list[AuthoringViolation] = []
    if invalid:
        findings.append(
            AuthoringViolation(
                scene_name,
                TRACK_GATE_SEQUENCE_RULE,
                "missing/invalid gate_index: " + ", ".join(sorted(invalid)),
            )
        )
        return findings
    expected = set(range(len(gates)))
    actual = set(values)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    duplicated = sorted(
        {value for value in values if values.count(value) > 1}
    )
    if missing or unexpected or duplicated:
        detail_parts = []
        if missing:
            detail_parts.append(f"missing {missing}")
        if duplicated:
            detail_parts.append(f"duplicated {duplicated}")
        if unexpected:
            detail_parts.append(f"out of range {unexpected}")
        findings.append(
            AuthoringViolation(
                scene_name,
                TRACK_GATE_SEQUENCE_RULE,
                (
                    f"{len(gates)} CheckpointGate(s) must have gate_index "
                    f"0..{len(gates) - 1} with no gaps or duplicates; "
                    + "; ".join(detail_parts)
                ),
            )
        )
    return findings


def _track_gate_order_findings(
    scene_name: str,
    gates: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (c): gates are ordered monotonically along the spine.

    Gate 0 is excluded from the chain entirely -- it is both the start AND
    the finish line, sitting at the spine's own seam (see track_spine.gd's
    "SEAM AMBIGUITY" doc: the closed polyline's two ends are the same
    physical point, so a point authored right there can project to either
    ~0 or ~the full spine length almost arbitrarily). Gate 0's own position
    is checked by TRACK_SPAWN_RULE instead (the spawn must sit behind it);
    this rule only walks gates 1..N-1, which is what "allow the wrap at
    gate 0" means in the task brief.
    """
    by_index, invalid = _track_gate_indices(gates)
    if invalid:
        # TRACK_GATE_SEQUENCE_RULE already reports this; a gate with no
        # readable index has no position in the chain to check here.
        return []
    ordered_indices = sorted(index for index in by_index if index >= 1)
    findings: list[AuthoringViolation] = []
    previous_index: int | None = None
    previous_distance: float | None = None
    previous_gate: FlatNode | None = None
    for index in ordered_indices:
        gate = by_index[index]
        distance = _project_onto_polyline(
            gate.world_position,
            points,
            cumulative,
        )
        if (
            previous_distance is not None
            and distance < previous_distance
            and not math.isclose(distance, previous_distance)
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GATE_ORDER_RULE,
                    (
                        f"{gate.path} (gate_index {index}) projects to "
                        f"{distance:.3f}m along the spine, before "
                        f"{previous_gate.path} (gate_index {previous_index}) "
                        f"at {previous_distance:.3f}m"
                    ),
                )
            )
        previous_index = index
        previous_distance = distance
        previous_gate = gate
    return findings


def _track_gate_width_findings(
    scene_name: str,
    gates: list[FlatNode],
    nodes: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (d): every gate's box spans at least the road width.

    "Spans" is measured perpendicular to the spine's own tangent at the
    gate's projected position -- not the gate's raw authored box size --
    so a gate authored with the right box but rotated to face the wrong way
    still fails honestly instead of passing on unrelated geometry. Reuses
    _bounds_half_extent_along, the same OBB-onto-arbitrary-direction
    projection _chase_start_gap_findings already uses for a trigger's
    leading face.
    """
    findings: list[AuthoringViolation] = []
    for gate in gates:
        bounds = _collision_bounds(gate, nodes)
        if bounds is None:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GATE_WIDTH_RULE,
                    (
                        f"{gate.path} has no BoxShape3D CollisionShape3D "
                        "child to measure its width"
                    ),
                )
            )
            continue
        progress = _project_onto_polyline(
            gate.world_position,
            points,
            cumulative,
        )
        tangent = _polyline_direction_at_distance(points, cumulative, progress)
        if _is_zero(tangent):
            continue
        across = (-tangent[2], 0.0, tangent[0])
        span_m = 2.0 * _bounds_half_extent_along(bounds, across)
        if span_m < TRACK_ROAD_WIDTH_M and not math.isclose(
            span_m,
            TRACK_ROAD_WIDTH_M,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GATE_WIDTH_RULE,
                    (
                        f"{gate.path} spans {span_m:.3f}m across the road; "
                        f"the road is {TRACK_ROAD_WIDTH_M:.3f}m wide"
                    ),
                )
            )
    return findings


def _track_spawn_findings(
    scene_name: str,
    nodes: list[FlatNode],
    gates: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (e): a spawn marker exists, positioned before gate 0.

    "Before" is measured as a signed distance along gate 0's own spine
    tangent (spawn_position - gate0_position, dotted with the tangent),
    not a spine-progress comparison -- gate 0 sits at the spine's seam
    (see TRACK_GATE_ORDER_RULE's doc), so a KartSpawn authored just
    upstream of it can project to a spine progress near the FULL length,
    not near 0, and a naive progress compare would read that as "after"
    instead of "before".
    """
    spawn = next(
        (
            node
            for node in nodes
            if node.parent == "."
            and node.name == TRACK_SPAWN_NODE_NAME
            and node.node_type == "Marker3D"
        ),
        None,
    )
    if spawn is None:
        return [
            AuthoringViolation(
                scene_name,
                TRACK_SPAWN_RULE,
                f"no root {TRACK_SPAWN_NODE_NAME} Marker3D found",
            )
        ]
    by_index, _invalid = _track_gate_indices(gates)
    gate0 = by_index.get(0)
    if gate0 is None:
        return [
            AuthoringViolation(
                scene_name,
                TRACK_SPAWN_RULE,
                (
                    "no gate_index 0 CheckpointGate found to measure the "
                    f"{TRACK_SPAWN_NODE_NAME} against"
                ),
            )
        ]
    progress = _project_onto_polyline(gate0.world_position, points, cumulative)
    tangent = _polyline_direction_at_distance(points, cumulative, progress)
    if _is_zero(tangent):
        return []
    offset = _dot(
        _subtract(spawn.world_position, gate0.world_position),
        tangent,
    )
    if offset < 0.0 and not math.isclose(offset, 0.0):
        return []
    return [
        AuthoringViolation(
            scene_name,
            TRACK_SPAWN_RULE,
            (
                f"{TRACK_SPAWN_NODE_NAME} is {offset:.3f}m ahead of gate 0 "
                "along the direction of travel; it must sit behind the "
                "start/finish gate"
            ),
        )
    ]


def _expected_grid_slot_lateral_offset_m(slot_index: int) -> float:
    """Reproduces ai_kart_agent.gd's own _compute_lateral_target_m() exactly.

    total_karts = opponent_count + 1; centered_slot = slot_index - HALF of
    (total_karts - 1); lateral_target_m = centered_slot * spacing -- see
    that function's own doc (fix-wave MEDIUM-3's producer of the value this
    checks the authored scene against).
    """
    total_karts = AI_OPPONENT_COUNT_FOR_GRID + 1.0
    centered_slot = float(slot_index) - (total_karts - 1.0) / 2.0
    return centered_slot * AI_LATERAL_SLOT_SPACING_M


def _track_grid_slot_findings(
    scene_name: str,
    nodes: list[FlatNode],
    gates: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (f): the AI starting grid exists, sits behind gate 0, on the road.

    Task 5 (CTR R3 integration): race_session.gd's _spawn_ai_karts() spawns
    one AI kart per root Marker3D named GridSlotN (N >= 1) it finds under the
    track; the player spawns from the separate, pre-existing KartSpawn marker
    (TRACK_SPAWN_RULE above). Fix-wave LOW-8: a GridSlot0 duplicating
    KartSpawn's own transform used to also be authored (included in the
    count here but never itself checked against KartSpawn) -- deleted as a
    redundant second source of truth for the same spawn; this rule's own
    TRACK_GRID_SLOT_NAME_PATTERN still matches "GridSlot0" if a scene ever
    authors one again, so nothing here silently ignores a stray one.
    """
    slots = [
        node
        for node in nodes
        if node.parent == "."
        and node.node_type == "Marker3D"
        and TRACK_GRID_SLOT_NAME_PATTERN.match(node.name)
    ]
    findings: list[AuthoringViolation] = []
    if len(slots) < TRACK_GRID_SLOT_MIN_COUNT:
        findings.append(
            AuthoringViolation(
                scene_name,
                TRACK_GRID_SLOTS_RULE,
                (
                    f"found {len(slots)} GridSlot* marker(s) behind gate 0; "
                    f"need at least {TRACK_GRID_SLOT_MIN_COUNT} (matching "
                    "ai.tres's own opponent_count default)"
                ),
            )
        )
    by_index, _invalid = _track_gate_indices(gates)
    gate0 = by_index.get(0)
    if gate0 is None:
        # TRACK_SPAWN_RULE (or TRACK_GATE_SEQUENCE_RULE, if gate_index itself
        # is unreadable) already reports a missing/unreadable gate 0; there
        # is nothing here to measure a grid slot's position against.
        return findings
    progress = _project_onto_polyline(gate0.world_position, points, cumulative)
    tangent = _polyline_direction_at_distance(points, cumulative, progress)
    if _is_zero(tangent):
        return findings
    across = (-tangent[2], 0.0, tangent[0])
    half_width_m = TRACK_ROAD_WIDTH_M / 2.0
    for slot in slots:
        relative = _subtract(slot.world_position, gate0.world_position)
        offset_along = _dot(relative, tangent)
        if offset_along > 0.0 and not math.isclose(offset_along, 0.0):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GRID_SLOTS_RULE,
                    (
                        f"{slot.path} is {offset_along:.3f}m ahead of gate 0 "
                        "along the direction of travel; every grid slot must "
                        "sit behind the start/finish gate"
                    ),
                )
            )
        offset_across = _dot(relative, across)
        off_road = abs(offset_across) > half_width_m and not math.isclose(
            abs(offset_across),
            half_width_m,
        )
        if off_road:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GRID_SLOTS_RULE,
                    (
                        f"{slot.path} is {offset_across:.3f}m off the spine "
                        f"centerline; the road is only {TRACK_ROAD_WIDTH_M:.3f}m "
                        f"wide (max {half_width_m:.3f}m each side)"
                    ),
                )
            )
        # Fix-wave MEDIUM-3: an authored slot's lateral offset must match
        # ai_kart_agent.gd's own _compute_lateral_target_m() centering
        # formula for its slot_index, or the AI kart that spawns on it steers
        # hard for its real target the instant the race starts instead of
        # holding the grid line it was placed on (measured before this fix:
        # t=0 lateral errors up to 7.25m, adjacent slots steering AT each
        # other). Skipped when off_road already fired above -- an off-road
        # slot obviously will not match the on-road formula target either,
        # and reporting both would just duplicate the same underlying
        # authoring mistake as two findings instead of one. GridSlot0 is
        # exempt -- see this function's own doc: it is never read by
        # _spawn_ai_karts() at all (the player spawns from KartSpawn), and
        # the formula's own slot_index=0 value is not "center" (the player
        # conventionally sits there instead; see ai_kart_agent.gd's LATERAL
        # SLOT CENTERING doc).
        index_match = TRACK_GRID_SLOT_INDEX_PATTERN.match(slot.name)
        if off_road or index_match is None:
            continue
        slot_index = int(index_match.group(1))
        if slot_index == 0:
            continue
        expected_offset_m = _expected_grid_slot_lateral_offset_m(slot_index)
        if not math.isclose(
            offset_across,
            expected_offset_m,
            abs_tol=TRACK_GRID_SLOT_OFFSET_TOLERANCE_M,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GRID_SLOTS_RULE,
                    (
                        f"{slot.path} has a lateral offset of "
                        f"{offset_across:.3f}m; ai_kart_agent.gd's own "
                        "centering formula for this slot_index expects "
                        f"{expected_offset_m:.3f}m (opponent_count="
                        f"{AI_OPPONENT_COUNT_FOR_GRID:.1f}, "
                        f"lateral_slot_spacing_m={AI_LATERAL_SLOT_SPACING_M}) "
                        "-- an AI kart spawned here steers hard for its real "
                        "target the instant the race starts instead of "
                        "holding the grid line"
                    ),
                )
            )
    return findings


def _track_item_box_findings(
    scene_name: str,
    nodes: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (g): item boxes exist, sit on-road, and stay clear of this
    scene's own origin (Task 5, CTR R4 items -- spec Recorded-debt #10; see
    TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M's own doc for why "this scene's own
    origin" is the one and only thing this lint can check for that debt).

    Discovered by SCRIPT match (ITEM_BOX_SCRIPT), like CheckpointGate --
    NOT by a GridSlotN-style root-level name pattern -- since race_session.
    gd's own _discover_item_boxes() finds them the same type/script-scan
    way, so an authored box can legally sit anywhere in the flattened tree.

    "On-road" reuses _track_gate_width_findings's own per-node independent-
    projection shape (project onto the whole polyline, take the LOCAL
    tangent at that projected point) rather than TRACK_GRID_SLOTS_RULE's
    single "relative to gate 0" tangent -- grid slots all cluster in one
    spot right behind gate 0, but item boxes are authored at scattered
    points all the way around the loop, so each one needs its own local
    road direction, not one global reference.
    """
    boxes = [node for node in nodes if node.script_path == ITEM_BOX_SCRIPT]
    findings: list[AuthoringViolation] = []
    if len(boxes) < TRACK_ITEM_BOX_MIN_COUNT:
        findings.append(
            AuthoringViolation(
                scene_name,
                TRACK_ITEM_BOX_RULE,
                (
                    f"found {len(boxes)} ItemBox node(s); need at least "
                    f"{TRACK_ITEM_BOX_MIN_COUNT} (two on-road lines of "
                    "three, per the R4 item-box authoring brief)"
                ),
            )
        )

    half_width_m = TRACK_ROAD_WIDTH_M / 2.0
    for box in boxes:
        origin_distance_m = _length(box.world_position)
        if origin_distance_m < TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M and not math.isclose(
            origin_distance_m,
            TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_ITEM_BOX_RULE,
                    (
                        f"{box.path} is {origin_distance_m:.3f}m from this "
                        "scene's own origin; must stay at least "
                        f"{TRACK_ITEM_BOX_ORIGIN_CLEARANCE_M:.3f}m clear "
                        "(spec Recorded-debt #10 -- the player kart's own "
                        "one-frame origin flash can steal an origin-adjacent "
                        "box)"
                    ),
                )
            )

        progress = _project_onto_polyline(box.world_position, points, cumulative)
        tangent = _polyline_direction_at_distance(points, cumulative, progress)
        if _is_zero(tangent):
            continue
        across = (-tangent[2], 0.0, tangent[0])
        centerline_point = _sample_polyline(points, cumulative, progress)
        offset_across_m = _dot(
            _subtract(box.world_position, centerline_point), across
        )
        if abs(offset_across_m) > half_width_m and not math.isclose(
            abs(offset_across_m),
            half_width_m,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_ITEM_BOX_RULE,
                    (
                        f"{box.path} is {offset_across_m:.3f}m off the spine "
                        f"centerline; the road is only {TRACK_ROAD_WIDTH_M:.3f}m "
                        f"wide (max {half_width_m:.3f}m each side)"
                    ),
                )
            )
    return findings


def _track_dressing_findings(
    scene_name: str,
    nodes: list[FlatNode],
    points: list[Vector3],
    cumulative: list[float],
) -> list[AuthoringViolation]:
    """Rule (h): every EnvironmentArt dressing piece clears the road+wall.

    Task 2 (CTR R6, circuit polish): reuses _track_item_box_findings's own
    "project onto the whole polyline, take the LOCAL tangent at that
    projected point" shape (each piece gets its own local road direction,
    since dressing scatters all the way around the loop, not clustered near
    one gate) -- INVERTED, since dressing must stay OFF the road rather than
    on it. See TRACK_DRESSING_CLEARANCE_MARGIN_M's own doc for the margin.
    """
    art_node = next(
        (
            node
            for node in nodes
            if node.parent == "."
            and node.node_type == "Node3D"
            and node.name == TRACK_ENVIRONMENT_ART_NODE_NAME
        ),
        None,
    )
    if art_node is None:
        return []
    pieces = [
        node
        for node in nodes
        if node.parent == art_node.path and node.node_type == "MeshInstance3D"
    ]
    min_offset_m = TRACK_ROAD_WIDTH_M / 2.0 + TRACK_DRESSING_CLEARANCE_MARGIN_M
    findings: list[AuthoringViolation] = []
    for piece in pieces:
        progress = _project_onto_polyline(piece.world_position, points, cumulative)
        tangent = _polyline_direction_at_distance(points, cumulative, progress)
        if _is_zero(tangent):
            continue
        across = (-tangent[2], 0.0, tangent[0])
        centerline_point = _sample_polyline(points, cumulative, progress)
        offset_across_m = _dot(
            _subtract(piece.world_position, centerline_point), across
        )
        if abs(offset_across_m) < min_offset_m and not math.isclose(
            abs(offset_across_m),
            min_offset_m,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_DRESSING_CLEARANCE_RULE,
                    (
                        f"{piece.path} is only {abs(offset_across_m):.3f}m off "
                        "the spine centerline; racing-line dressing must clear "
                        f"the road+wall by at least {min_offset_m:.3f}m (road "
                        f"half-width {TRACK_ROAD_WIDTH_M / 2.0:.3f}m + "
                        f"{TRACK_DRESSING_CLEARANCE_MARGIN_M:.3f}m prop-footprint "
                        "margin)"
                    ),
                )
            )
    return findings


def _track_gate_flag_findings(
    scene_name: str,
    gates: list[FlatNode],
    nodes: list[FlatNode],
) -> list[AuthoringViolation]:
    """Rule (i): every gate has a left AND a right flag post at its edge.

    Task 2 (CTR R6, circuit polish): discovers Gate{N}FlagL/Gate{N}FlagR
    containers by NAME PATTERN (there is no script to match against -- these
    are plain Node3D groups, like GridSlot markers) and checks each one's
    position against the GATE'S OWN authored basis (its "across"/lateral
    axis is basis column 0, the same axis TRACK_GATE_WIDTH_RULE measures the
    gate box against) -- not a re-derived spine tangent, per the task
    brief's "derive positions/rotations from the gate transforms".
    """
    by_index, invalid = _track_gate_indices(gates)
    if invalid:
        # TRACK_GATE_SEQUENCE_RULE already reports this.
        return []
    flags_by_gate: dict[int, list[FlatNode]] = {}
    for node in nodes:
        match = GATE_FLAG_NODE_NAME_PATTERN.match(node.name)
        if match is None:
            continue
        flags_by_gate.setdefault(int(match.group(1)), []).append(node)
    half_width_m = TRACK_ROAD_WIDTH_M / 2.0
    max_offset_m = half_width_m + TRACK_GATE_FLAG_MAX_CLEARANCE_M
    findings: list[AuthoringViolation] = []
    for index, gate in by_index.items():
        flags = flags_by_gate.get(index, [])
        if len(flags) < 2:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_GATE_FLAG_RULE,
                    (
                        f"gate_index {index} ({gate.path}) has {len(flags)} "
                        f"Gate{index}Flag[LR] node(s); every gate needs a flag "
                        "post at both road edges"
                    ),
                )
            )
            continue
        across = (
            gate.world_transform.basis[0][0],
            0.0,
            gate.world_transform.basis[0][2],
        )
        forward = (
            gate.world_transform.basis[2][0],
            0.0,
            gate.world_transform.basis[2][2],
        )
        for flag in flags:
            relative = _subtract(flag.world_position, gate.world_position)
            lateral_m = _dot(relative, across)
            forward_m = _dot(relative, forward)
            if abs(forward_m) > TRACK_GATE_FLAG_FORWARD_TOLERANCE_M and not math.isclose(
                abs(forward_m),
                TRACK_GATE_FLAG_FORWARD_TOLERANCE_M,
            ):
                findings.append(
                    AuthoringViolation(
                        scene_name,
                        TRACK_GATE_FLAG_RULE,
                        (
                            f"{flag.path} is {forward_m:.3f}m along gate "
                            f"{index}'s own travel axis; a flag post must sit "
                            "at the gate itself, not drifted along the track"
                        ),
                    )
                )
                continue
            in_band = half_width_m <= abs(lateral_m) <= max_offset_m
            if not in_band and not (
                math.isclose(abs(lateral_m), half_width_m)
                or math.isclose(abs(lateral_m), max_offset_m)
            ):
                findings.append(
                    AuthoringViolation(
                        scene_name,
                        TRACK_GATE_FLAG_RULE,
                        (
                            f"{flag.path} is {lateral_m:.3f}m across gate "
                            f"{index}'s own basis; a flag post must sit between "
                            f"{half_width_m:.3f}m (the road edge) and "
                            f"{max_offset_m:.3f}m from the gate"
                        ),
                    )
                )
    return findings


def _track_arch_findings(
    scene_name: str,
    gates: list[FlatNode],
    nodes: list[FlatNode],
) -> list[AuthoringViolation]:
    """Rule (j): a start/finish arch (posts + crossbar + banner) at gate 0.

    Task 2 (CTR R6, circuit polish): posts are checked against the SAME
    edge band TRACK_GATE_FLAG_RULE uses (a post beyond the road edge, not
    implausibly far); the crossbar and banner must instead sit centered
    directly over gate 0 (near-zero lateral AND forward offset), since
    their whole job is to frame the start/finish line itself.
    """
    by_index, invalid = _track_gate_indices(gates)
    if invalid:
        return []
    gate0 = by_index.get(0)
    if gate0 is None:
        # TRACK_SPAWN_RULE (or TRACK_GATE_SEQUENCE_RULE) already reports a
        # missing/unreadable gate 0.
        return []
    arch_node = next(
        (
            node
            for node in nodes
            if node.parent == "."
            and node.node_type == "Node3D"
            and node.name == TRACK_ARCH_NODE_NAME
        ),
        None,
    )
    if arch_node is None:
        return [
            AuthoringViolation(
                scene_name,
                TRACK_ARCH_RULE,
                "no root Arch node found; gate 0 needs a start/finish arch",
            )
        ]
    children = [node for node in nodes if node.parent == arch_node.path]
    posts = [
        node
        for node in children
        if ARCH_POST_NAME_SUBSTRING in node.name
        and node.node_type == "MeshInstance3D"
    ]
    crossbar = next(
        (node for node in children if node.name == ARCH_CROSSBAR_NODE_NAME), None
    )
    banner = next(
        (node for node in children if node.name == ARCH_BANNER_NODE_NAME), None
    )
    half_width_m = TRACK_ROAD_WIDTH_M / 2.0
    max_post_offset_m = half_width_m + TRACK_ARCH_POST_MAX_CLEARANCE_M
    across = (
        gate0.world_transform.basis[0][0],
        0.0,
        gate0.world_transform.basis[0][2],
    )
    findings: list[AuthoringViolation] = []
    if len(posts) < 2:
        findings.append(
            AuthoringViolation(
                scene_name,
                TRACK_ARCH_RULE,
                (
                    f"Arch has {len(posts)} Post* MeshInstance3D child(ren); "
                    "needs posts on both sides of gate 0"
                ),
            )
        )
    else:
        for post in posts:
            lateral_m = _dot(
                _subtract(post.world_position, gate0.world_position), across
            )
            in_band = half_width_m <= abs(lateral_m) <= max_post_offset_m
            if not in_band and not (
                math.isclose(abs(lateral_m), half_width_m)
                or math.isclose(abs(lateral_m), max_post_offset_m)
            ):
                findings.append(
                    AuthoringViolation(
                        scene_name,
                        TRACK_ARCH_RULE,
                        (
                            f"{post.path} is {lateral_m:.3f}m across gate 0's "
                            f"own basis; an arch post must sit between "
                            f"{half_width_m:.3f}m and {max_post_offset_m:.3f}m "
                            "from the gate"
                        ),
                    )
                )
    for label, node in (
        (ARCH_CROSSBAR_NODE_NAME, crossbar),
        (ARCH_BANNER_NODE_NAME, banner),
    ):
        if node is None:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_ARCH_RULE,
                    f"Arch has no {label} child",
                )
            )
            continue
        lateral_m = _dot(
            _subtract(node.world_position, gate0.world_position), across
        )
        if abs(lateral_m) > TRACK_ARCH_CENTER_TOLERANCE_M and not math.isclose(
            abs(lateral_m),
            TRACK_ARCH_CENTER_TOLERANCE_M,
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    TRACK_ARCH_RULE,
                    (
                        f"Arch/{label} is {lateral_m:.3f}m off-center from "
                        f"gate 0; must stay within "
                        f"{TRACK_ARCH_CENTER_TOLERANCE_M:.3f}m to frame the "
                        "start/finish line"
                    ),
                )
            )
    return findings


def _enemy_floor_contact_findings(
    scene_name: str,
    nodes: list[FlatNode],
) -> list[AuthoringViolation]:
    """Every authored enemy must stand on the graybox floor beneath it.

    P0-2 got a generalized "spawn has floor beneath it" guard
    (SPAWN_FLOOR_RULE); enemies never did, and a real one shipped floating:
    ``scenes/enemies/plant.tscn``'s hidden "Visual" proxy mesh -- the only
    input to ``EnemyBase._apply_visual_shape_ratios()``'s runtime hurtbox
    sizing -- has no ``position`` offset, unlike ``crab.tscn`` and
    ``skink.tscn``, whose proxies are both bottom-anchored a little above
    their node root. Segment authors compensated by raising every Plant
    instance's root 0.75m so the runtime hurtbox would still land near the
    floor, which floated the already-base-anchored visible glTF model
    instead. This walks every authored enemy and requires at least one
    GrayboxPlatform whose horizontal footprint covers its X/Z with a top
    surface within ``ENEMY_FLOOR_TOLERANCE_M`` of the enemy's own base --
    the same footprint-and-top-surface test SPAWN_FLOOR_RULE already uses,
    narrowed to a tight band instead of a wide reachability range because
    an enemy, unlike a spawn, is expected to be standing exactly on it.
    """
    findings: list[AuthoringViolation] = []
    for enemy in nodes:
        if enemy.script_path not in ENEMY_SCRIPTS:
            continue
        if _enemy_has_floor_contact(enemy, nodes):
            continue
        findings.append(
            AuthoringViolation(
                scene_name,
                ENEMY_FLOOR_CONTACT_RULE,
                (
                    f"{enemy.path} base is at "
                    f"y={enemy.world_position[1]:.3f} but no authored "
                    "GrayboxPlatform has a top surface within "
                    f"{ENEMY_FLOOR_TOLERANCE_M:.3f}m of it"
                ),
            )
        )
    return findings


def _enemy_has_floor_contact(
    enemy: FlatNode,
    nodes: list[FlatNode],
) -> bool:
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
                enemy.world_position,
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
            abs(top_center[1] - enemy.world_position[1])
            <= ENEMY_FLOOR_TOLERANCE_M
        ):
            return True
    return False


def _chase_start_gap_findings(
    scene_name: str,
    nodes: list[FlatNode],
    tuning: AuthoringTuning,
) -> list[AuthoringViolation]:
    """Require enough path upstream of the trigger's leading face.

    ``ChaseHazard.start_at_progress`` clamps negative boulder progress
    to the start of its path. A trigger can therefore appear to sit the
    tuned distance from the first marker while its leading collision
    face fires earlier and silently shortens the real opening gap.
    """
    nodes_by_path = {node.path: node for node in nodes}
    findings: list[AuthoringViolation] = []
    for hazard in nodes:
        if hazard.script_path != CHASE_HAZARD_SCRIPT:
            continue
        path_path = _resolve_node_path(
            hazard.path,
            hazard.properties.get("chase_path_path", ""),
        )
        trigger_path = _resolve_node_path(
            hazard.path,
            hazard.properties.get("start_trigger_path", ""),
        )
        path = nodes_by_path.get(path_path)
        trigger = nodes_by_path.get(trigger_path)
        if (
            path is None
            or path.node_type != "Path3D"
            or trigger is None
            or trigger.node_type != "Area3D"
        ):
            findings.append(
                AuthoringViolation(
                    scene_name,
                    CHASE_START_GAP_RULE,
                    (
                        f"{hazard.path} must resolve a Path3D and "
                        "start-trigger Area3D before its authored "
                        "boulder_start_gap_m can be verified"
                    ),
                )
            )
            continue
        markers = sorted(
            (
                node
                for node in nodes
                if (
                    node.parent == path.path
                    and node.node_type == "Marker3D"
                )
            ),
            key=lambda node: node.order,
        )
        if len(markers) < 2:
            findings.append(
                AuthoringViolation(
                    scene_name,
                    CHASE_START_GAP_RULE,
                    (
                        f"{path.path} needs at least two direct "
                        "Marker3D children to verify "
                        "boulder_start_gap_m"
                    ),
                )
            )
            continue
        points = [marker.world_position for marker in markers]
        cumulative = _polyline_cumulative_lengths(points)
        trigger_progress = _project_onto_polyline(
            trigger.world_position,
            points,
            cumulative,
        )
        path_forward = _polyline_direction_at_distance(
            points,
            cumulative,
            trigger_progress,
        )
        leading_position = trigger.world_position
        trigger_bounds = _collision_bounds(trigger, nodes)
        if trigger_bounds is not None and not _is_zero(path_forward):
            leading_position = _subtract(
                trigger.world_position,
                _multiply(
                    path_forward,
                    _bounds_half_extent_along(
                        trigger_bounds,
                        path_forward,
                    ),
                ),
            )
        available_gap_m = _project_onto_polyline(
            leading_position,
            points,
            cumulative,
        )
        if (
            available_gap_m > tuning.boulder_start_gap_m
            or math.isclose(
                available_gap_m,
                tuning.boulder_start_gap_m,
            )
        ):
            continue
        findings.append(
            AuthoringViolation(
                scene_name,
                CHASE_START_GAP_RULE,
                (
                    f"{hazard.path} has {available_gap_m:.3f}m "
                    "from path start to the trigger's leading face; "
                    "boulder_start_gap_m requires "
                    f"{tuning.boulder_start_gap_m:.3f}m"
                ),
            )
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


def _wumpa_findings(
    scene_name: str,
    nodes: list[FlatNode],
    meta: LevelMetaValues,
    tuning: AuthoringTuning,
) -> list[AuthoringViolation]:
    authored_total = (
        sum(
            tuning.wumpa_per_standard_crate
            for crate in _crate_nodes(nodes)
            if _crate_type(crate) == STANDARD_CRATE_TYPE
        )
        + sum(
            (
                tuning.bounce_crate_max_bounces
                * tuning.bounce_crate_wumpa_per_bounce
            )
            for crate in _crate_nodes(nodes)
            if _crate_type(crate) == BOUNCE_CRATE_TYPE
        )
        + sum(
            tuning.wumpa_per_pickup
            for node in nodes
            if WUMPA_PICKUP_GROUP in node.groups
        )
    )
    if authored_total == meta.wumpa_total:
        return []
    return [
        AuthoringViolation(
            scene_name,
            WUMPA_TOTAL_RULE,
            (
                f"authored wumpa={authored_total}, "
                f"LevelMeta.wumpa_total={meta.wumpa_total}"
            ),
        )
    ]


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
            if (
                instance_path.suffix.lower()
                in OPAQUE_VISUAL_SCENE_SUFFIXES
            ):
                world_transform = _compose_transform(
                    resolved_parent_world,
                    _node_transform(properties),
                )
                instance_root = FlatNode(
                    name=(
                        source_node.name
                        if source_node.path != "."
                        else _path_name(prefix, source_node.name)
                    ),
                    node_type="Node3D",
                    path=flat_path,
                    parent=resolved_parent_path,
                    properties=properties,
                    groups=groups,
                    script_path=_script_path(
                        properties,
                        scene.ext_resources,
                    ),
                    world_transform=world_transform,
                    world_position=world_transform.origin,
                    order=order[0],
                    source_scene=scene,
                )
                order[0] += 1
                flattened.append(instance_root)
                nodes_by_path[flat_path] = instance_root
                local_to_flat[source_node.path] = instance_root
                if source_node.path == ".":
                    root_result = instance_root
                continue
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


def _polyline_direction_at_distance(
    points: list[Vector3],
    cumulative: list[float],
    distance: float,
) -> Vector3:
    for index, (start, finish) in enumerate(
        zip(points, points[1:])
    ):
        if distance > cumulative[index + 1]:
            continue
        direction = _normalize(_subtract(finish, start))
        if not _is_zero(direction):
            return direction
    for start, finish in reversed(list(zip(points, points[1:]))):
        direction = _normalize(_subtract(finish, start))
        if not _is_zero(direction):
            return direction
    return ZERO


def _bounds_half_extent_along(
    bounds: Bounds,
    direction: Vector3,
) -> float:
    return sum(
        abs(_dot(direction, bounds.transform.basis[axis]))
        * bounds.half_size[axis]
        for axis in range(3)
    )


def _load_authoring_tuning(repo_root: Path) -> AuthoringTuning:
    economy = assignment_values(
        (repo_root / "data/tuning/economy.tres").read_text(
            encoding="utf-8"
        )
    )
    camera = assignment_values(
        (repo_root / "data/tuning/camera.tres").read_text(
            encoding="utf-8"
        )
    )
    move = assignment_values(
        (repo_root / "data/tuning/move.tres").read_text(
            encoding="utf-8"
        )
    )
    chase = assignment_values(
        (repo_root / "data/tuning/chase.tres").read_text(
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
        wumpa_per_standard_crate=int(
            float(economy["wumpa_per_standard_crate"])
        ),
        wumpa_per_pickup=int(
            float(economy["wumpa_per_pickup"])
        ),
        bounce_crate_max_bounces=int(
            float(economy["bounce_crate_max_bounces"])
        ),
        bounce_crate_wumpa_per_bounce=int(
            float(economy["bounce_crate_wumpa_per_bounce"])
        ),
        minimum_jump_depression_degrees=float(
            camera["minimum_jump_depression_degrees"]
        ),
        camera_look_ahead_m=float(camera["look_ahead_m"]),
        camera_offsets=offsets,
        respawn_floor_y_m=float(move["respawn_floor_y_m"]),
        boulder_start_gap_m=float(chase["boulder_start_gap_m"]),
    )


def _load_level_meta(path: Path) -> LevelMetaValues:
    values = assignment_values(
        path.read_text(encoding="utf-8")
    )
    return LevelMetaValues(
        crate_count=int(float(values["crate_count"])),
        wumpa_total=int(float(values["wumpa_total"])),
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
        # Task 8 (CTR racing mode, R2): racing tracks live outside
        # scenes/levels/ entirely (they have no LevelMeta, so they were
        # never part of the platformer's level set) and are scanned as an
        # addendum, not a replacement -- a repo with scenes/levels/ but no
        # scenes/racing/ (e.g. a fixture sandbox) is unaffected.
        racing_root = root / "scenes" / "racing"
        if racing_root.is_dir():
            yield from sorted(racing_root.rglob("*.tscn"))
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


def _resolve_node_path(origin: str, authored_value: str) -> str:
    match = NODE_PATH_PATTERN.fullmatch(authored_value.strip())
    if match is None or not match.group(1):
        return ""
    raw_path = match.group(1)
    components = (
        []
        if raw_path.startswith("/") or origin == "."
        else origin.split("/")
    )
    for component in raw_path.strip("/").split("/"):
        if not component or component == ".":
            continue
        if component == "..":
            if components:
                components.pop()
            continue
        components.append(component)
    return "/".join(components) or "."


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
