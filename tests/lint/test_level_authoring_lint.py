import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.lint_level_authoring import (
    CHECKPOINT_PROGRESSION_RULE,
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

    def test_spine_stopping_short_of_the_finish_still_fires_spacing(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_spine_extent_gap_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_SPACING_RULE],
        )
        self.assertIn("88.889s", findings[0].detail)

    def test_checkpoint_links_must_follow_spatial_route_order(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_progression_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_PROGRESSION_RULE],
        )
        self.assertIn("checkpoint 2 links to 2", findings[0].detail)
        self.assertIn("next spatial checkpoint is 1", findings[0].detail)

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

    def test_segment_container_cannot_satisfy_crate_membership(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_segment_container_membership_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CRATE_AUTHORING_RULE],
        )
        self.assertIn("ContainerClaim", findings[0].detail)
        self.assertIn(
            "per-segment normal crate sum=1",
            findings[0].detail,
        )

    def test_crate_must_match_exactly_one_concrete_segment(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_repeated_segment_membership_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CRATE_AUTHORING_RULE],
        )
        self.assertIn(
            "per-segment normal crate sum=0",
            findings[0].detail,
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

    def test_jump_depression_uses_camera_rail_anchor(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_rail_anchor_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("14.801 degrees", findings[0].detail)

    def test_jump_depression_uses_camera_corridor_alignment(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_required_jump_corridor_alignment_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("14.907 degrees", findings[0].detail)

    def test_wall_run_camera_mode_cannot_bypass_jump_depression(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_wall_run_required_jump_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("3.302 degrees", findings[0].detail)

    def test_time_crate_outside_relic_group_fires_its_rule(self) -> None:
        self.assertEqual(
            self._rules("level_time_crate_outside_relic_bad.tscn"),
            [TIME_CRATE_RULE],
        )

    def test_time_crate_does_not_inherit_parent_group(self) -> None:
        self.assertEqual(
            self._rules("level_time_crate_parent_group_bad.tscn"),
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

    def test_no_argument_cli_recursively_scans_nested_level_scenes(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repo_root = Path(temporary_directory)
            (repo_root / "scripts").mkdir()
            shutil.copy2(
                REPO_ROOT / "scripts" / "lint_level_authoring.py",
                repo_root / "scripts" / "lint_level_authoring.py",
            )
            tuning_root = repo_root / "data" / "tuning"
            tuning_root.mkdir(parents=True)
            for file_name in ["economy.tres", "camera.tres"]:
                shutil.copy2(
                    REPO_ROOT / "data" / "tuning" / file_name,
                    tuning_root / file_name,
                )
            meta_root = tuning_root / "levels"
            meta_root.mkdir()
            (meta_root / "nested_bad.tres").write_text(
                "\n".join(
                    [
                        "[gd_resource load_steps=2 format=3]",
                        "",
                        (
                            "[ext_resource type=\"Script\" "
                            "path=\"res://src/tuning/level_meta.gd\" "
                            "id=\"1\"]"
                        ),
                        "",
                        "[resource]",
                        "script = ExtResource(\"1\")",
                        "crate_count = 1",
                        "design_pace_mps = 4.5",
                    ]
                ),
                encoding="utf-8",
            )
            level_root = (
                repo_root / "scenes" / "levels" / "warp_room_2"
            )
            level_root.mkdir(parents=True)
            (level_root / "nested_bad.tscn").write_text(
                "\n".join(
                    [
                        "[gd_scene load_steps=2 format=3]",
                        "",
                        (
                            "[ext_resource type=\"Resource\" "
                            "path=\"res://data/tuning/levels/"
                            "nested_bad.tres\" id=\"1\"]"
                        ),
                        "",
                        (
                            "[node name=\"NestedBad\" "
                            "type=\"Node3D\"]"
                        ),
                        "metadata/level_meta = ExtResource(\"1\")",
                    ]
                ),
                encoding="utf-8",
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    "scripts/lint_level_authoring.py",
                ],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 1)
            self.assertIn(
                "scenes/levels/warp_room_2/nested_bad.tscn",
                completed.stdout,
            )
            self.assertIn(
                CHECKPOINT_SPACING_RULE,
                completed.stdout,
            )

    def test_cli_fails_closed_for_an_unresolvable_requested_path(
        self,
    ) -> None:
        missing_path = (
            FIXTURE_ROOT / "missing_level_requested_by_operator.tscn"
        )
        self.assertFalse(missing_path.exists())

        completed = subprocess.run(
            [
                sys.executable,
                "scripts/lint_level_authoring.py",
                str(missing_path),
            ],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(str(missing_path), completed.stderr)
        self.assertIn("does not exist", completed.stderr)

    def _rules(self, fixture_name: str) -> list[str]:
        findings = find_authoring_violations(
            FIXTURE_ROOT / fixture_name
        )
        return [finding.rule for finding in findings]


if __name__ == "__main__":
    unittest.main()
