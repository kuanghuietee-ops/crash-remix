import tempfile
import unittest
from pathlib import Path

from scripts.lint_level_authoring import (
    CHECKPOINT_SPACING_RULE,
    CRATE_AUTHORING_RULE,
    CRATE_ID_RULE,
    REQUIRED_JUMP_RULE,
    TIME_CRATE_RULE,
    _flatten_scene,
    find_authoring_violations,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = REPO_ROOT / "tests" / "fixtures"


class LevelAuthoringLintTests(unittest.TestCase):
    def test_checkpoint_gap_fires_the_spacing_rule(self) -> None:
        self.assertEqual(
            self._rules("level_checkpoint_gap_bad.tscn"),
            [CHECKPOINT_SPACING_RULE],
        )

    def test_editor_transform_form_drives_checkpoint_distance(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_transform_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_SPACING_RULE],
        )
        self.assertIn("88.889s", findings[0].detail)

    def test_flatten_composes_transform_basis_rotation_and_scale(
        self,
    ) -> None:
        nodes = _flatten_scene(
            FIXTURE_ROOT / "level_transform_hierarchy.tscn",
            REPO_ROOT,
        )
        positions = {
            node.path: node.world_position
            for node in nodes
            if node.node_type == "Marker3D"
        }

        expected = {
            "TransformParent/TransformChild": (10.0, 2.0, 2.0),
            "BasisParent/BasisChild": (10.0, 0.0, 7.0),
            "RotationParent/RotationChild": (10.0, 0.0, 8.0),
            "ScaleParent/ScaleChild": (12.0, 3.0, 19.0),
            "MixedRotationParent/MixedRotationChild": (
                11.135776,
                1.591050,
                23.190387,
            ),
        }
        self.assertEqual(set(positions), set(expected))
        for path, expected_position in expected.items():
            for actual, authored in zip(
                positions[path],
                expected_position,
            ):
                self.assertAlmostEqual(actual, authored, places=5)

    def test_nested_crate_total_fires_the_authoring_rule(self) -> None:
        self.assertEqual(
            self._rules("level_crate_count_bad.tscn"),
            [CRATE_AUTHORING_RULE],
        )

    def test_required_jump_fires_the_depression_rule(self) -> None:
        self.assertEqual(
            self._rules("level_required_jump_bad.tscn"),
            [REQUIRED_JUMP_RULE],
        )

    def test_editor_transform_form_drives_jump_depression(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_transform_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("9.486 degrees", findings[0].detail)

    def test_time_crate_outside_relic_group_fires_its_rule(self) -> None:
        self.assertEqual(
            self._rules("level_time_crate_outside_relic_bad.tscn"),
            [TIME_CRATE_RULE],
        )

    def test_duplicate_crate_id_fires_the_identity_rule(self) -> None:
        self.assertEqual(
            self._rules("level_duplicate_crate_id_bad.tscn"),
            [CRATE_ID_RULE],
        )

    def test_lint_passes_an_empty_level_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            self.assertEqual(
                find_authoring_violations(
                    Path(temporary_directory)
                ),
                [],
            )

    def test_collectible_level_without_meta_still_fires(self) -> None:
        self.assertEqual(
            self._rules("levels/level_no_meta_bad.tscn"),
            [CRATE_AUTHORING_RULE],
        )

    def test_real_n_sanity_beach_level_passes_the_authoring_lint(
        self,
    ) -> None:
        level_path = (
            REPO_ROOT
            / "scenes"
            / "levels"
            / "wr1_n_sanity_beach.tscn"
        )
        self.assertTrue(level_path.is_file())
        self.assertEqual(
            find_authoring_violations(level_path),
            [],
        )

    def test_warp_room_is_not_misclassified_as_a_collectible_level(
        self,
    ) -> None:
        hub_path = (
            REPO_ROOT
            / "scenes"
            / "levels"
            / "warp_room_1.tscn"
        )
        self.assertTrue(hub_path.is_file())
        self.assertEqual(
            find_authoring_violations(hub_path),
            [],
        )

    def _rules(self, fixture_name: str) -> list[str]:
        findings = find_authoring_violations(
            FIXTURE_ROOT / fixture_name
        )
        return [finding.rule for finding in findings]


if __name__ == "__main__":
    unittest.main()
