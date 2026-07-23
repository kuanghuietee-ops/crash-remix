import unittest
from pathlib import Path

from scripts.lint_traversal_authoring import (
    DETACH_VISIBILITY_RULE,
    RAIL_READABILITY_RULE,
    WALL_CAMERA_RULE,
    find_authoring_violations,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = REPO_ROOT / "tests" / "fixtures"


class TraversalAuthoringLintTests(unittest.TestCase):
    def test_wall_run_fixture_fails_only_the_wall_camera_rule(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_wall_camera_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [WALL_CAMERA_RULE],
        )

    def test_detach_fixture_fails_only_target_visibility(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_detach_visibility_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [DETACH_VISIBILITY_RULE],
        )

    def test_rail_fixture_checks_region_coverage_and_symmetric_links(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_rail_readability_bad.tscn"
        )

        self.assertTrue(findings)
        self.assertEqual(
            {finding.rule for finding in findings},
            {RAIL_READABILITY_RULE},
        )
        details = " ".join(finding.detail for finding in findings)
        self.assertIn("grind camera region", details)
        self.assertIn("symmetric", details)

    def test_all_real_traversal_segments_pass(self) -> None:
        findings = find_authoring_violations(
            REPO_ROOT / "scenes" / "segments"
        )

        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()
