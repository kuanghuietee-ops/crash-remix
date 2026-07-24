from __future__ import annotations

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GUT_RUNNER = REPO_ROOT / "scripts" / "run_gut.sh"


class GutRunnerTests(unittest.TestCase):
    def test_runner_isolates_and_removes_godot_user_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            fake_godot = temporary_path / "fake_godot.py"
            invocation_log = temporary_path / "invocation.json"
            fake_godot.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import json
                    import os
                    import sys
                    from pathlib import Path

                    user_root = Path(os.environ["XDG_DATA_HOME"])
                    Path(os.environ["FAKE_GODOT_LOG"]).write_text(
                        json.dumps(
                            {
                                "args": sys.argv[1:],
                                "user_root": str(user_root),
                                "user_root_existed": user_root.is_dir(),
                            }
                        ),
                        encoding="utf-8",
                    )
                    """
                ),
                encoding="utf-8",
            )
            fake_godot.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                {
                    "FAKE_GODOT_LOG": str(invocation_log),
                    "GODOT_BIN": str(fake_godot),
                }
            )

            result = subprocess.run(
                [str(GUT_RUNNER)],
                cwd=REPO_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            invocation = json.loads(invocation_log.read_text(encoding="utf-8"))
            user_root = Path(invocation["user_root"])
            self.assertTrue(invocation["user_root_existed"])
            self.assertEqual(user_root.parent, Path("/tmp"))
            self.assertTrue(user_root.name.startswith("crash-remix-gut-user."))
            self.assertFalse(user_root.exists())
            self.assertEqual(
                invocation["args"],
                [
                    "--headless",
                    "--disable-render-loop",
                    "--path",
                    str(REPO_ROOT),
                    "-s",
                    "addons/gut/gut_cmdln.gd",
                    "-gexit",
                ],
            )


if __name__ == "__main__":
    unittest.main()
