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
ISOLATED_SUITES = [
    "res://tests/integration/test_main_boot.gd",
    "res://tests/integration/test_island_slice.gd",
    "res://tests/integration/test_warp_room.gd",
]
COMMON_GODOT_ARGS = [
    "--headless",
    "--disable-render-loop",
    "--path",
    str(REPO_ROOT),
    "-s",
    "addons/gut/gut_cmdln.gd",
    "-gexit",
]


class GutRunnerTests(unittest.TestCase):
    def _write_fake_godot(self, path: Path) -> None:
        path.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json
                import os
                import sys
                from pathlib import Path

                user_root = Path(os.environ["XDG_DATA_HOME"])
                with Path(os.environ["FAKE_GODOT_LOG"]).open(
                    "a", encoding="utf-8"
                ) as log:
                    log.write(
                        json.dumps(
                            {
                                "args": sys.argv[1:],
                                "user_root": str(user_root),
                                "user_root_existed": user_root.is_dir(),
                            }
                        )
                        + "\\n"
                    )
                if (
                    os.environ.get("FAKE_GODOT_FAIL_SHARED") == "1"
                    and any(
                        arg.startswith("-gtest=") and "," in arg
                        for arg in sys.argv[1:]
                    )
                ):
                    raise SystemExit(1)
                """
            ),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def _run_fake_godot(
        self,
        temporary_path: Path,
        *runner_args: str,
        fail_shared: bool = False,
    ) -> tuple[subprocess.CompletedProcess[str], list[dict[str, object]]]:
        fake_godot = temporary_path / "fake_godot.py"
        invocation_log = temporary_path / "invocations.jsonl"
        self._write_fake_godot(fake_godot)
        environment = os.environ.copy()
        environment.update(
            {
                "FAKE_GODOT_LOG": str(invocation_log),
                "GODOT_BIN": str(fake_godot),
            }
        )
        if fail_shared:
            environment["FAKE_GODOT_FAIL_SHARED"] = "1"

        result = subprocess.run(
            [str(GUT_RUNNER), *runner_args],
            cwd=REPO_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        invocations = [
            json.loads(line)
            for line in invocation_log.read_text(encoding="utf-8").splitlines()
        ]
        return result, invocations

    def test_full_runner_isolates_main_scene_suites_and_user_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            result, invocations = self._run_fake_godot(temporary_path)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(invocations), 4)

            user_roots = [
                Path(str(invocation["user_root"])) for invocation in invocations
            ]
            self.assertEqual(len(set(user_roots)), 4)
            for invocation, user_root in zip(invocations, user_roots):
                self.assertTrue(invocation["user_root_existed"])
                self.assertEqual(user_root.parent, Path("/tmp"))
                self.assertTrue(user_root.name.startswith("crash-remix-gut-user."))
                self.assertFalse(user_root.exists())

            all_gut_suites = sorted(
                "res://" + path.relative_to(REPO_ROOT).as_posix()
                for path in (REPO_ROOT / "tests").rglob("test_*.gd")
            )
            shared_process_suites = [
                path for path in all_gut_suites if path not in ISOLATED_SUITES
            ]
            self.assertEqual(
                invocations[0]["args"],
                COMMON_GODOT_ARGS
                + ["-gdir=", "-gtest=" + ",".join(shared_process_suites)],
            )
            for invocation, suite in zip(invocations[1:], ISOLATED_SUITES):
                self.assertEqual(
                    invocation["args"],
                    COMMON_GODOT_ARGS + ["-gdir=", "-gtest=" + suite],
                )

    def test_full_runner_attempts_isolated_suites_after_shared_failure(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            result, invocations = self._run_fake_godot(
                temporary_path,
                fail_shared=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(len(invocations), 4)
            for invocation, suite in zip(invocations[1:], ISOLATED_SUITES):
                self.assertEqual(
                    invocation["args"],
                    COMMON_GODOT_ARGS + ["-gdir=", "-gtest=" + suite],
                )

    def test_targeted_runner_keeps_a_single_unmodified_gut_invocation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            targeted_arg = "-gtest=res://tests/gameplay/test_crate_logic.gd"
            result, invocations = self._run_fake_godot(
                temporary_path, targeted_arg
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(invocations), 1)
            self.assertEqual(
                invocations[0]["args"], COMMON_GODOT_ARGS + [targeted_arg]
            )
            user_root = Path(str(invocations[0]["user_root"]))
            self.assertTrue(invocations[0]["user_root_existed"])
            self.assertFalse(user_root.exists())


if __name__ == "__main__":
    unittest.main()
