import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.lint_gameplay_numbers import find_numeric_literals


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


if __name__ == "__main__":
    unittest.main()
