import tempfile
import unittest
from pathlib import Path

from scripts.lint_level_authoring import (
    CHECKPOINT_SPACING_RULE,
    CRATE_AUTHORING_RULE,
    CRATE_ID_RULE,
    REQUIRED_JUMP_RULE,
    TIME_CRATE_RULE,
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

    def _rules(self, fixture_name: str) -> list[str]:
        findings = find_authoring_violations(
            FIXTURE_ROOT / fixture_name
        )
        return [finding.rule for finding in findings]


if __name__ == "__main__":
    unittest.main()
