import unittest
from pathlib import Path

from scripts.dress_island_cut import (
    BAND_DEPTH_M,
    CLEARANCE_M,
    CANYON_STYLE,
    JUNGLE_STYLE,
    Corridor,
    Platform,
    STYLE_BY_PREFIX,
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

        for style in (CANYON_STYLE, JUNGLE_STYLE):
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

    def test_every_boulders_and_hog_segment_is_dressed(self) -> None:
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
