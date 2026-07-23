from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEPLOY_SCRIPT = REPO_ROOT / "scripts" / "deploy_android.sh"


class AndroidDeployScriptTests(unittest.TestCase):
    def test_script_exists_and_is_valid_bash(self) -> None:
        self.assertTrue(DEPLOY_SCRIPT.is_file())
        result = subprocess.run(
            ["bash", "-n", str(DEPLOY_SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_one_command_builds_installs_and_launches(self) -> None:
        source = DEPLOY_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('--export-debug "Android Debug"', source)
        self.assertIn("android_source.zip", source)
        self.assertIn("unzip", source)
        self.assertIn('install -r', source)
        self.assertIn('shell monkey', source)
        self.assertIn('--build-only', source)

    def test_debug_certificate_comes_from_repository_owned_stable_material(self) -> None:
        source = DEPLOY_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("android_debug_keystore.b64", source)
        self.assertIn("debug_keystore_sha256=", source)
        self.assertNotIn("-genkeypair", source)

    def test_installer_writes_godot_gradle_template_version_marker(self) -> None:
        source = DEPLOY_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('android_version_marker="$repo_root/android/.build_version"', source)
        self.assertIn('godot_template_identifier="4.7.1.stable"', source)
        self.assertIn('printf \'%s\\n\' "$godot_template_identifier"', source)

    def test_build_only_creates_apk_and_reproducible_debug_keystore(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "android" / "build").mkdir(parents=True)
            (root / "android" / "build" / "build.gradle").write_text(
                "// test template\n",
                encoding="utf-8",
            )
            fake_godot = self._write_executable(
                root / "fake-godot",
                """#!/usr/bin/env bash
set -euo pipefail
for output_path in "$@"; do :; done
mkdir -p "$(dirname "$output_path")"
printf 'fake apk' > "$output_path"
""",
            )
            environment = os.environ.copy()
            environment.update(
                {
                    "CRASH_REMIX_REPO_ROOT": str(root),
                    "GODOT_BIN": str(fake_godot),
                }
            )

            first_result = subprocess.run(
                [str(DEPLOY_SCRIPT), "--build-only"],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            keystore_path = root / "build" / "debug.keystore"
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertTrue((root / "build" / "crash-remix-debug.apk").is_file())
            self.assertTrue(keystore_path.is_file())
            first_digest = hashlib.sha256(keystore_path.read_bytes()).hexdigest()
            keystore_path.unlink()
            second_result = subprocess.run(
                [str(DEPLOY_SCRIPT), "--build-only"],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )
            second_digest = hashlib.sha256(keystore_path.read_bytes()).hexdigest()
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            self.assertEqual(first_digest, second_digest)

    def test_single_device_path_installs_force_stops_and_launches(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "android" / "build").mkdir(parents=True)
            (root / "android" / "build" / "build.gradle").write_text(
                "// test template\n",
                encoding="utf-8",
            )
            fake_godot = self._write_executable(
                root / "fake-godot",
                """#!/usr/bin/env bash
set -euo pipefail
for output_path in "$@"; do :; done
mkdir -p "$(dirname "$output_path")"
printf 'fake apk' > "$output_path"
""",
            )
            adb_log = root / "adb.log"
            fake_adb = self._write_executable(
                root / "fake-adb",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "devices" ]]; then
    printf 'List of devices attached\\nDEVICE-1\\tdevice\\n'
    exit 0
fi
printf '%s\\n' "$*" >> "$ADB_TEST_LOG"
""",
            )
            environment = os.environ.copy()
            environment.update(
                {
                    "CRASH_REMIX_REPO_ROOT": str(root),
                    "GODOT_BIN": str(fake_godot),
                    "ADB_BIN": str(fake_adb),
                    "ADB_TEST_LOG": str(adb_log),
                }
            )

            result = subprocess.run(
                [str(DEPLOY_SCRIPT)],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            adb_calls = adb_log.read_text(encoding="utf-8")
            self.assertIn("-s DEVICE-1 install -r", adb_calls)
            self.assertIn(
                "-s DEVICE-1 shell am force-stop com.personal.crashremix",
                adb_calls,
            )
            self.assertIn(
                "-s DEVICE-1 shell monkey -p com.personal.crashremix",
                adb_calls,
            )

    def test_certificate_mismatch_stops_before_data_wiping_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "android" / "build").mkdir(parents=True)
            (root / "android" / "build" / "build.gradle").write_text(
                "// test template\n",
                encoding="utf-8",
            )
            fake_godot = self._write_executable(
                root / "fake-godot",
                """#!/usr/bin/env bash
set -euo pipefail
for output_path in "$@"; do :; done
mkdir -p "$(dirname "$output_path")"
printf 'fake apk' > "$output_path"
""",
            )
            adb_log = root / "adb.log"
            fake_adb = self._write_executable(
                root / "fake-adb",
                """#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "devices" ]]; then
    printf 'List of devices attached\\nDEVICE-1\\tdevice\\n'
    exit 0
fi
printf '%s\\n' "$*" >> "$ADB_TEST_LOG"
if [[ "$*" == *" install -r "* ]]; then
    printf 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]\\n' >&2
    exit 1
fi
""",
            )
            environment = os.environ.copy()
            environment.update(
                {
                    "CRASH_REMIX_REPO_ROOT": str(root),
                    "GODOT_BIN": str(fake_godot),
                    "ADB_BIN": str(fake_adb),
                    "ADB_TEST_LOG": str(adb_log),
                }
            )

            result = subprocess.run(
                [str(DEPLOY_SCRIPT)],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            output = result.stdout + result.stderr
            adb_calls = adb_log.read_text(encoding="utf-8")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("INSTALL_FAILED_UPDATE_INCOMPATIBLE", output)
            self.assertIn("user://tuning/override.tres", output)
            self.assertIn("Do not uninstall", output)
            self.assertNotIn("force-stop", adb_calls)
            self.assertNotIn("shell monkey", adb_calls)

    @staticmethod
    def _write_executable(path: Path, source: str) -> Path:
        path.write_text(source, encoding="utf-8")
        path.chmod(0o755)
        return path


if __name__ == "__main__":
    unittest.main()
