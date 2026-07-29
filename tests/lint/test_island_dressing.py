import math
import unittest
from pathlib import Path

from scripts.dress_island_cut import (
    BAND_DEPTH_M,
    BANK_TILE_LENGTH_M,
    CLEARANCE_M,
    CANYON_STYLE,
    JUNGLE_STYLE,
    Corridor,
    Platform,
    STYLE_BY_PREFIX,
    PORTAL_KEEPOUT_M,
    WALL_PIECE_LENGTH_M,
    WARP_ROOM_PATH,
    WARP_ROOM_PLACEMENTS,
    WARP_ROOM_PORTALS,
    VILLAGE_STYLE,
    corridor_of,
    ensure_ext_resources,
    nested_segments,
    parse_platforms,
    placements_for,
    strip_existing,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
SEGMENT_DIR = REPO_ROOT / "scenes" / "segments"


def dressed_segments() -> list[Path]:
    """The segments that should carry scenery.

    Excludes reusable blocks instanced inside other segments -- dressing those
    would duplicate scenery at every use site and place it inside the corridor.
    """
    nested = nested_segments(SEGMENT_DIR)
    return sorted(
        path
        for path in SEGMENT_DIR.glob("*.tscn")
        if any(path.name.startswith(prefix) for prefix in STYLE_BY_PREFIX)
        and path.stem not in nested
    )


class CorridorTests(unittest.TestCase):
    def test_the_corridor_spans_the_widest_platform(self) -> None:
        platforms = [
            Platform(position=(0.0, -0.5, -4.0), size=(16.0, 1.0, 12.0)),
            Platform(position=(0.0, -0.5, -32.0), size=(20.0, 1.0, 52.0)),
        ]

        corridor = corridor_of(platforms)

        self.assertEqual(corridor.half_width, 10.0)

    def test_ground_level_comes_from_the_largest_slab_not_the_highest(self) -> None:
        # Hog Wild's gate obstacles are platforms too. Taking the highest top
        # surface floats every tree on the segment into the air.
        platforms = [
            Platform(position=(0.0, -0.5, -64.0), size=(18.0, 1.0, 116.0)),
            Platform(position=(-7.25, 1.6, -52.0), size=(2.5, 4.2, 3.0)),
        ]

        corridor = corridor_of(platforms)

        self.assertEqual(corridor.floor_y, 0.0)

    def test_a_segment_with_no_platforms_has_no_corridor(self) -> None:
        self.assertIsNone(corridor_of([]))

    def test_every_dressed_segment_parses_to_a_corridor(self) -> None:
        for path in dressed_segments():
            corridor = corridor_of(parse_platforms(path.read_text(encoding="utf-8")))

            self.assertIsNotNone(corridor, path.name)
            self.assertGreater(corridor.half_width, 0.0, path.name)
            self.assertGreater(corridor.length, 0.0, path.name)


class ClearanceTests(unittest.TestCase):
    """The one rule that makes a level unplayable if broken."""

    def test_no_placement_sits_inside_the_play_corridor(self) -> None:
        corridor = Corridor(half_width=9.0, z_near=2.0, z_far=-130.0, floor_y=0.0)

        for style in (CANYON_STYLE, JUNGLE_STYLE, VILLAGE_STYLE):
            for placement in placements_for("probe_segment", corridor, style):
                self.assertGreaterEqual(
                    abs(placement.position[0]),
                    corridor.half_width + CLEARANCE_M,
                    f"{placement.node} ({placement.piece}) is inside the corridor",
                )

    def test_no_placement_strays_past_the_dressing_band(self) -> None:
        corridor = Corridor(half_width=8.0, z_near=2.0, z_far=-66.0, floor_y=0.0)

        for style in (CANYON_STYLE, JUNGLE_STYLE):
            for placement in placements_for("probe_segment", corridor, style):
                self.assertLessEqual(
                    abs(placement.position[0]), BAND_DEPTH_M + 4.0, placement.node
                )

    def test_placements_stay_within_the_segments_length(self) -> None:
        corridor = Corridor(half_width=8.0, z_near=2.0, z_far=-66.0, floor_y=0.0)

        for style in (CANYON_STYLE, JUNGLE_STYLE):
            for placement in placements_for("probe", corridor, style):
                self.assertLessEqual(placement.position[2], corridor.z_near, placement.node)
                self.assertGreaterEqual(
                    placement.position[2], corridor.z_far - 8.0, placement.node
                )

    def test_both_verges_are_dressed(self) -> None:
        corridor = Corridor(half_width=8.0, z_near=2.0, z_far=-66.0, floor_y=0.0)

        placements = placements_for("probe", corridor, CANYON_STYLE)
        left = [one for one in placements if one.position[0] < 0]
        right = [one for one in placements if one.position[0] > 0]

        self.assertTrue(left)
        self.assertTrue(right)

    def test_placement_is_deterministic(self) -> None:
        corridor = Corridor(half_width=8.0, z_near=2.0, z_far=-66.0, floor_y=0.0)

        first = placements_for("boulders_intro", corridor, CANYON_STYLE)
        second = placements_for("boulders_intro", corridor, CANYON_STYLE)

        self.assertEqual(first, second)

    def test_different_segments_are_dressed_differently(self) -> None:
        corridor = Corridor(half_width=8.0, z_near=2.0, z_far=-66.0, floor_y=0.0)

        first = placements_for("boulders_intro", corridor, CANYON_STYLE)
        second = placements_for("boulders_coda", corridor, CANYON_STYLE)

        self.assertNotEqual(
            [one.position for one in first], [one.position for one in second]
        )


class SceneRewritingTests(unittest.TestCase):
    def test_stripping_removes_only_the_environment_subtree(self) -> None:
        text = (
            '[node name="Root" type="Node3D"]\n\n'
            '[node name="EnvironmentArt" type="Node3D" parent="."]\n\n'
            '[node name="Tree" type="MeshInstance3D" parent="EnvironmentArt"]\n'
            "position = Vector3(1, 2, 3)\n\n"
            '[node name="Crate" type="Node3D" parent="."]\n'
        )

        stripped = strip_existing(text)

        self.assertNotIn("EnvironmentArt", stripped)
        self.assertNotIn("Tree", stripped)
        self.assertIn('[node name="Root"', stripped)
        self.assertIn('[node name="Crate"', stripped)

    def test_stripping_is_a_no_op_when_there_is_nothing_to_strip(self) -> None:
        text = '[node name="Root" type="Node3D"]\n'

        self.assertEqual(strip_existing(text), text)

    def test_rewriting_twice_is_idempotent(self) -> None:
        # The generator has to be safe to re-run after a segment is re-authored,
        # or it accumulates duplicate scenery every time.
        text = (
            '[node name="Root" type="Node3D"]\n\n'
            '[node name="EnvironmentArt" type="Node3D" parent="."]\n\n'
            '[node name="Tree" type="MeshInstance3D" parent="EnvironmentArt"]\n\n'
        )

        self.assertEqual(strip_existing(strip_existing(text)), strip_existing(text))

    def test_existing_mesh_resources_are_reused_not_duplicated(self) -> None:
        text = (
            "[gd_scene load_steps=2 format=3]\n\n"
            '[ext_resource type="Mesh" '
            'path="res://assets/models/kits/mesh/palm_tall_a.res" id="15_palm"]\n\n'
            '[node name="Root" type="Node3D"]\n'
        )

        rewritten, ids = ensure_ext_resources(text, ["palm_tall_a"])

        self.assertEqual(ids["palm_tall_a"], "15_palm")
        self.assertEqual(rewritten.count("palm_tall_a.res"), 1)

    def test_new_mesh_resources_are_added(self) -> None:
        text = (
            "[gd_scene load_steps=2 format=3]\n\n"
            '[ext_resource type="Script" path="res://src/x.gd" id="1_x"]\n\n'
            '[node name="Root" type="Node3D"]\n'
        )

        rewritten, ids = ensure_ext_resources(text, ["fern_cluster_a"])

        self.assertIn("fern_cluster_a.res", rewritten)
        self.assertIn("fern_cluster_a", ids)


class DressedSceneTests(unittest.TestCase):
    """Checks the committed scenes, not just the generator."""

    def test_every_dressed_scene_has_scenery(self) -> None:
        for path in dressed_segments():
            self.assertIn(
                '[node name="EnvironmentArt" type="Node3D" parent="."]',
                path.read_text(encoding="utf-8"),
                f"{path.name} has no scenery",
            )

    def test_dressed_scenery_carries_no_collision_or_script(self) -> None:
        # Scenery is decoration. A collision shape or script here would change
        # how the level plays, which is not what an art pass is allowed to do.
        for path in dressed_segments():
            text = path.read_text(encoding="utf-8")
            start = text.find('[node name="EnvironmentArt"')
            if start < 0:
                continue
            subtree = text[start:]

            self.assertNotIn("CollisionShape3D", subtree, path.name)
            self.assertNotIn("StaticBody3D", subtree, path.name)
            self.assertNotIn("script = ", subtree, path.name)
            self.assertNotIn("groups=", subtree, path.name)

    def test_committed_scenery_clears_the_committed_corridor(self) -> None:
        # The generator's own margin is checked above; this checks the files as
        # they actually sit on disk, which is what the game loads.
        import re

        for path in dressed_segments():
            text = path.read_text(encoding="utf-8")
            corridor = corridor_of(parse_platforms(text))
            start = text.find('[node name="EnvironmentArt"')
            self.assertGreater(start, -1, path.name)
            for match in re.finditer(
                r"^position = Vector3\(([-\d.]+),", text[start:], flags=re.MULTILINE
            ):
                self.assertGreaterEqual(
                    abs(float(match.group(1))),
                    corridor.half_width + CLEARANCE_M,
                    f"{path.name}: scenery at x={match.group(1)} is in the corridor",
                )


class ArenaTests(unittest.TestCase):
    def test_scenery_follows_the_arena_terraces(self) -> None:
        # Papu's arena climbs from y=0 to y=4 across three terraces. A single
        # floor height would bury the far end's totems four metres underground.
        arena = SEGMENT_DIR / "papu_arena.tscn"
        corridor = corridor_of(parse_platforms(arena.read_text(encoding="utf-8")))

        self.assertEqual(corridor.floor_at(-10.0), 0.0)
        self.assertEqual(corridor.floor_at(-44.0), 2.0)
        self.assertEqual(corridor.floor_at(-70.0), 4.0)

    def test_the_arena_is_dressed_with_village_props(self) -> None:
        text = (SEGMENT_DIR / "papu_arena.tscn").read_text(encoding="utf-8")

        self.assertIn("totem_tall_a", text)

    def test_arena_scenery_spans_more_than_one_height(self) -> None:
        import re

        text = (SEGMENT_DIR / "papu_arena.tscn").read_text(encoding="utf-8")
        start = text.find('[node name="EnvironmentArt"')
        heights = {
            match.group(1)
            for match in re.finditer(
                r"^position = Vector3\([-\d.]+, ([-\d.]+),", text[start:], flags=re.MULTILINE
            )
        }

        self.assertGreater(len(heights), 1, "arena scenery is all at one height")


class WarpRoomTests(unittest.TestCase):
    def test_the_room_is_dressed(self) -> None:
        text = (REPO_ROOT / WARP_ROOM_PATH).read_text(encoding="utf-8")

        self.assertIn('[node name="EnvironmentArt" type="Node3D" parent="."]', text)
        self.assertIn("pillar_carved_a", text)

    def test_nothing_blocks_a_portal(self) -> None:
        # A pillar in front of a portal makes a level unreachable from the hub.
        for placement in WARP_ROOM_PLACEMENTS:
            for portal_x, portal_z in WARP_ROOM_PORTALS:
                distance = math.hypot(
                    placement.position[0] - portal_x, placement.position[2] - portal_z
                )
                self.assertGreaterEqual(
                    distance, PORTAL_KEEPOUT_M, f"{placement.node} blocks a portal"
                )

    def test_everything_stays_inside_the_chamber(self) -> None:
        # The chamber is 24 m square with walls at +-12.
        for placement in WARP_ROOM_PLACEMENTS:
            self.assertLess(abs(placement.position[0]), 12.0, placement.node)
            self.assertLess(abs(placement.position[2]), 12.0, placement.node)

    def test_placements_have_unique_names(self) -> None:
        names = [placement.node for placement in WARP_ROOM_PLACEMENTS]

        self.assertEqual(len(names), len(set(names)))


def _straight_corridor(length_m: float, half_width: float = 9.0) -> Corridor:
    """A single flat slab running `length_m` metres away from the origin."""
    return corridor_of(
        [
            Platform(
                position=(0.0, -0.5, -length_m / 2.0),
                size=(half_width * 2.0, 1.0, length_m),
            )
        ]
    )


class CoverageTests(unittest.TestCase):
    """The dressing must actually reach the end of the segment it dresses.

    The kit builds its bank tiles 96 m long because "segments are 96 m end to
    end" -- true of the beach, which was hand-dressed to that rhythm. Boulders
    segments are 64 m and Hog Wild's are 128 m, and the dresser placed exactly
    one bank and one wall piece per style entry per side regardless. So a 128 m
    Hog Wild segment ran 32 m per side with no verge ground under its scatter
    and ~104 m per side with no back wall, showing flat background colour
    between the trees at the speed the level is built around.

    The pre-existing lints checked clearance, determinism and band depth --
    every question except whether the scenery covers the corridor -- which is
    why this passed review. These tests ask the coverage question directly, on
    synthetic corridors, so they hold for any segment length a future level
    uses rather than only the ones that exist today.
    """

    def _by_side(self, placements, prefix: str) -> dict[str, list]:
        sides: dict[str, list] = {"L": [], "R": []}
        for placement in placements:
            if not placement.node.startswith(prefix):
                continue
            # Bank nodes spell the side out; scatter/wall nodes abbreviate it.
            side = "L" if "Left" in placement.node or placement.node[len(prefix)] == "L" else "R"
            sides[side].append(placement)
        return sides

    def test_banks_tile_the_full_corridor_on_both_sides(self) -> None:
        for length in (64.0, 96.0, 128.0, 200.0):
            for style_name, style in (("canyon", CANYON_STYLE), ("jungle", JUNGLE_STYLE)):
                corridor = _straight_corridor(length)

                placements = placements_for("probe_segment", corridor, style)

                expected = math.ceil(length / BANK_TILE_LENGTH_M)
                for side, banks in self._by_side(placements, "Bank").items():
                    self.assertGreaterEqual(
                        len(banks),
                        expected,
                        f"{style_name} {length} m needs {expected} bank tiles on {side}, "
                        f"got {len(banks)}",
                    )

    def test_bank_tiles_leave_no_gap_between_them(self) -> None:
        corridor = _straight_corridor(200.0)

        placements = placements_for("probe_segment", corridor, JUNGLE_STYLE)

        for side, banks in self._by_side(placements, "Bank").items():
            zs = sorted((placement.position[2] for placement in banks), reverse=True)
            for near, far in zip(zs, zs[1:]):
                self.assertLessEqual(
                    abs(near - far),
                    BANK_TILE_LENGTH_M + 1e-6,
                    f"{side} bank tiles are more than one tile length apart",
                )

    def test_banks_span_from_the_near_edge_to_the_far_edge(self) -> None:
        length = 128.0
        corridor = _straight_corridor(length)

        placements = placements_for("probe_segment", corridor, JUNGLE_STYLE)

        for side, banks in self._by_side(placements, "Bank").items():
            zs = [placement.position[2] for placement in banks]
            self.assertAlmostEqual(max(zs), corridor.z_near, places=6, msg=side)
            # The last tile must start early enough that its 96 m body reaches
            # the far edge of the corridor.
            self.assertLessEqual(
                min(zs) - BANK_TILE_LENGTH_M,
                corridor.z_far + 1e-6,
                f"{side} banks stop short of the corridor's far edge",
            )

    def test_walls_tile_the_full_corridor_on_both_sides(self) -> None:
        for length in (64.0, 128.0):
            for style_name, style in (("canyon", CANYON_STYLE), ("jungle", JUNGLE_STYLE)):
                corridor = _straight_corridor(length)

                placements = placements_for("probe_segment", corridor, style)

                per_entry = math.ceil(length / WALL_PIECE_LENGTH_M)
                expected = per_entry * len(style["walls"])
                for side, walls in self._by_side(placements, "Wall").items():
                    self.assertGreaterEqual(
                        len(walls),
                        expected,
                        f"{style_name} {length} m needs {expected} wall pieces on {side}, "
                        f"got {len(walls)} -- the horizon leaks between them",
                    )

    def test_coverage_still_respects_the_clearance_rule(self) -> None:
        # Tiling must not be bought by moving scenery into the play corridor.
        corridor = _straight_corridor(128.0)

        placements = placements_for("probe_segment", corridor, JUNGLE_STYLE)

        inner = corridor.half_width + CLEARANCE_M
        for placement in placements:
            self.assertGreaterEqual(
                abs(placement.position[0]) + 1e-6,
                inner,
                f"{placement.node} sits inside the clearance band",
            )

    def test_placement_names_stay_unique_once_tiled(self) -> None:
        corridor = _straight_corridor(200.0)

        placements = placements_for("probe_segment", corridor, JUNGLE_STYLE)

        names = [placement.node for placement in placements]
        self.assertEqual(len(names), len(set(names)))
