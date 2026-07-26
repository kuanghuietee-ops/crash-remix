from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def _tuning_service_sections() -> list[str]:
    source = (REPO_ROOT / "src/tuning/tuning_service.gd").read_text(
        encoding="utf-8"
    )
    match = re.search(
        r"const SECTION_NAMES:[^=]+=\s*\[(.*?)\]",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError("TuningService.SECTION_NAMES was not found")
    return re.findall(r'&"([^"]+)"', match.group(1))


def _export_verifier_catalog_paths() -> list[str]:
    source = (REPO_ROOT / "scripts/verify_exported_tuning.sh").read_text(
        encoding="utf-8"
    )
    match = re.search(
        r"for\s+tuning_path\s+in\s+([^;]+);\s*do",
        source,
    )
    if match is None:
        raise AssertionError("export verifier tuning_path loop was not found")
    return match.group(1).split()


def _export_verifier_boot_failure_pattern() -> str:
    source = (REPO_ROOT / "scripts/verify_exported_tuning.sh").read_text(
        encoding="utf-8"
    )
    match = re.search(
        r'grep -qE "([^"]+)" "\$runtime_log"',
        source,
    )
    if match is None:
        raise AssertionError(
            "export verifier's boot-failure detection grep was not found"
        )
    return match.group(1)


def _game_root_boot_failure_message() -> str:
    source = (REPO_ROOT / "src/core/game_root.gd").read_text(encoding="utf-8")
    match = re.search(
        r'push_error\("(Phase \d+ tuning failed to load): "',
        source,
    )
    if match is None:
        raise AssertionError(
            "GameRoot's tuning boot-failure push_error message was not found"
        )
    return match.group(1)


class ExportedTuningContractTests(unittest.TestCase):
    def test_export_verifier_catalog_paths_match_tuning_service_sections(
        self,
    ) -> None:
        section_names = _tuning_service_sections()
        verifier_paths = _export_verifier_catalog_paths()

        self.assertIn("economy", section_names)
        for enemy_section in (
            "enemy_crab",
            "enemy_skink",
            "enemy_plant",
        ):
            self.assertIn(enemy_section, section_names)
        self.assertEqual(verifier_paths, ["gameplay", *section_names])

    def test_export_verifier_asserts_every_authored_level_meta_path(
        self,
    ) -> None:
        source = (
            REPO_ROOT / "scripts/verify_exported_tuning.sh"
        ).read_text(encoding="utf-8")
        loop_bodies = re.findall(
            r'for level_meta_path in "\$repo_root"'
            r"/data/tuning/levels/\*\.tres; do\n(.*?)\ndone",
            source,
            flags=re.DOTALL,
        )

        self.assertTrue(
            any(
                '"$runtime_log"' in body
                and 'res://${level_meta_path#"$repo_root"/}' in body
                for body in loop_bodies
            ),
            "the exported runtime log must assert every authored "
            "LevelMeta path, not only n_sanity_beach",
        )

    def test_export_verifier_detects_game_root_s_real_boot_failure_message(
        self,
    ) -> None:
        # A9: the exported build boots through scenes/main.tscn -> GameRoot,
        # not the retired Phase 0 toybox, so the string the verifier greps
        # the runtime log for must actually match what GameRoot prints when
        # tuning fails to load. A hardcoded "Phase 0" (or any other fixed
        # phase number) silently stops matching the moment GameRoot's own
        # message is bumped to a later phase, and the smoke can never fire
        # again — exactly what happened here.
        failure_message = _game_root_boot_failure_message()
        pattern = _export_verifier_boot_failure_pattern()

        self.assertRegex(
            failure_message,
            pattern,
            "verify_exported_tuning.sh's boot-failure grep "
            f"{pattern!r} does not match GameRoot's real boot-failure "
            f"message {failure_message!r} — the exported-tuning smoke can "
            "never detect a real boot failure",
        )


if __name__ == "__main__":
    unittest.main()
