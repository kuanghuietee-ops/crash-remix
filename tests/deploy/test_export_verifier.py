from __future__ import annotations

import re
import shutil
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
EXPORT_VERIFIER = REPO_ROOT / "scripts" / "verify_exported_tuning.sh"
SHELL_BUILTINS = {
    "cleanup",
    "do",
    "done",
    "echo",
    "exit",
    "export",
    "export_log",
    "fi",
    "for",
    "godot_bin",
    "if",
    "local",
    "pack_path",
    "readonly",
    "repo_root",
    "runtime_log",
    "set",
    "temp_dir",
    "then",
    "trap",
}


class ExportVerifierTests(unittest.TestCase):
    def test_export_verifier_only_invokes_available_commands(self) -> None:
        source = EXPORT_VERIFIER.read_text(encoding="utf-8")

        invoked = {
            token
            for token in re.findall(
                r"^\s*(?:if\s+)?([a-z][a-z0-9_-]*)\b",
                source,
                re.MULTILINE,
            )
            if token not in SHELL_BUILTINS
        }
        missing = sorted(name for name in invoked if shutil.which(name) is None)

        self.assertEqual(
            missing,
            [],
            f"script invokes unavailable commands: {missing}",
        )

    def test_export_verifier_reports_success_on_a_good_pack(self) -> None:
        result = subprocess.run(
            [str(EXPORT_VERIFIER)],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=600,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Exported tuning smoke passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
