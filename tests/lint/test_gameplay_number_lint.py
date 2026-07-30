import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from scripts.lint_gameplay_numbers import (
    SCALAR_MATH_ALLOWED_VALUES,
    _parse_args,
    check_scalar_math_channel,
    find_numeric_literals,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
LINT_SCRIPT = REPO_ROOT / "scripts" / "lint_gameplay_numbers.py"


class GameplayNumberLintTests(unittest.TestCase):
    def test_allows_only_zero_one_and_negative_one(self) -> None:
        source = """
var zero := 0
var zero_float := 0.0
var one := 1
var one_float := 1.0
var negative_one := -1
var negative_one_float := -1.0
"""

        self.assertEqual(find_numeric_literals(source, "allowed.gd"), [])

    def test_rejects_integer_decimal_scientific_and_hex_literals(self) -> None:
        source = """
var integer := 2
var decimal := 0.12
var scientific := 1.2e3
var hexadecimal := 0x20
"""

        findings = find_numeric_literals(source, "bad.gd")

        self.assertEqual(
            [finding.literal for finding in findings],
            ["2", "0.12", "1.2e3", "0x20"],
        )

    def test_ignores_numbers_inside_identifiers_strings_and_comments(self) -> None:
        source = '''
var direction: Vector3
var action := "player_2_jump"
# The design doc calls this section 5.3.
var explanation := """A multiline string containing 99."""
'''

        self.assertEqual(find_numeric_literals(source, "ignored.gd"), [])

    def test_reports_source_location(self) -> None:
        findings = find_numeric_literals("var speed := 7.0\n", "player.gd")

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].path, "player.gd")
        self.assertEqual(findings[0].line, 1)
        self.assertEqual(findings[0].column, 14)

    def test_unscannable_file_fails_closed_and_names_the_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_path = Path(temporary_directory) / "unscannable.gd"
            source_path.write_text("var broken := (\n", encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT), str(source_path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(source_path.as_posix(), result.stdout + result.stderr)
        self.assertIn("unscannable", (result.stdout + result.stderr).lower())


class ScalarMathLaunderingChannelTests(unittest.TestCase):
    """A13: src/core/scalar_math.gd sits outside src/gameplay/** (this
    lint's default scan root), but src/gameplay/** code preloads it and
    references its named constants (e.g. ScalarMathType.HALF) -- a bare
    numeric literal never appears in src/gameplay/** for these values, so
    the directory scan above cannot see them. These tests cover the
    closed, frozen allow-list check that closes that channel.
    """

    def test_allowed_values_are_frozen_to_exactly_half_and_double(self) -> None:
        # Guard the guard: if this ever silently grows, the channel is
        # open again in spirit even though the mechanism still runs.
        self.assertEqual(
            SCALAR_MATH_ALLOWED_VALUES,
            (Decimal("0.5"), Decimal("2.0")),
        )

    def test_source_matching_the_allow_list_is_accepted(self) -> None:
        source = (
            "class_name ScalarMath\n"
            "extends RefCounted\n"
            "\n"
            "const HALF := 0.5\n"
            "const DOUBLE := 2.0\n"
        )

        self.assertEqual(
            find_numeric_literals(
                source,
                "scalar_math.gd",
                SCALAR_MATH_ALLOWED_VALUES,
            ),
            [],
        )

    def test_a_value_outside_the_allow_list_is_rejected(self) -> None:
        # Simulates the exact abuse this finding is worried about: a
        # future contributor laundering a real gameplay-tunable number
        # (here, 7.0) past src/gameplay/**'s literal scan via this file.
        source = (
            "class_name ScalarMath\n"
            "extends RefCounted\n"
            "\n"
            "const HALF := 0.5\n"
            "const DOUBLE := 2.0\n"
            "const SEVEN := 7.0\n"
        )

        findings = find_numeric_literals(
            source,
            "scalar_math.gd",
            SCALAR_MATH_ALLOWED_VALUES,
        )

        self.assertEqual([finding.literal for finding in findings], ["7.0"])

    def test_the_real_scalar_math_file_matches_its_own_frozen_allow_list(
        self,
    ) -> None:
        # The audit's own claim: no instance of abuse exists yet. This is
        # that verification, pinned as a permanent regression instead of
        # a one-off manual check.
        self.assertEqual(check_scalar_math_channel(), [])

    def test_check_scalar_math_channel_flags_a_rogue_constant(self) -> None:
        # Exercises the same synthetic-file seam check_scalar_math_channel
        # itself uses, without ever touching the real repo file on disk.
        with tempfile.TemporaryDirectory() as temporary_directory:
            rogue_path = Path(temporary_directory) / "scalar_math.gd"
            rogue_path.write_text(
                (
                    "class_name ScalarMath\n"
                    "extends RefCounted\n"
                    "\n"
                    "const HALF := 0.5\n"
                    "const DOUBLE := 2.0\n"
                    "const SEVEN := 7.0\n"
                ),
                encoding="utf-8",
            )

            findings = check_scalar_math_channel(rogue_path)

        self.assertEqual([finding.literal for finding in findings], ["7.0"])

    def test_check_scalar_math_channel_is_a_noop_for_a_missing_file(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            missing_path = Path(temporary_directory) / "does_not_exist.gd"

            self.assertEqual(check_scalar_math_channel(missing_path), [])

    def test_cli_passes_on_the_real_repository_unmodified(self) -> None:
        result = subprocess.run(
            [sys.executable, str(LINT_SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class RacingScanScopeTests(unittest.TestCase):
    """Task 1 (CTR racing mode): src/racing/** must get the same numeric-
    literal coverage as src/gameplay/**, even though the directory does not
    exist in this repo yet -- lint_paths/_gdscript_files already treat a
    missing directory as contributing zero files, so the only real change
    is adding it to the default scan roots. These tests prove both halves:
    the missing directory does not break the default (no-args) scan, and a
    real violation under src/racing is caught once the directory exists.
    """

    def test_default_scan_roots_include_src_racing(self) -> None:
        arguments = _parse_args([])

        self.assertIn(Path("src/racing"), arguments.paths)

    def test_missing_racing_directory_does_not_break_the_default_scan(self) -> None:
        # The real repo has no src/racing/ yet (this task only lands the
        # tuning foundation) -- the default scan over the real repo must
        # still pass cleanly.
        self.assertFalse((REPO_ROOT / "src" / "racing").exists())

        result = subprocess.run(
            [sys.executable, str(LINT_SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_bad_file_under_src_racing_fails_the_default_scan(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            racing_dir = Path(temporary_directory) / "src" / "racing" / "kart"
            racing_dir.mkdir(parents=True)
            bad_file = racing_dir / "kart_motor.gd"
            bad_file.write_text(
                "class_name KartMotor\n"
                "extends RefCounted\n"
                "\n"
                "var top_speed_mps := 7.0\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT)],
                check=False,
                capture_output=True,
                text=True,
                cwd=temporary_directory,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("7.0", result.stdout)
        self.assertIn("src/racing", result.stdout.replace("\\", "/"))


if __name__ == "__main__":
    unittest.main()
