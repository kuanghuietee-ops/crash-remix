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


class ExportedTuningContractTests(unittest.TestCase):
    def test_export_verifier_catalog_paths_match_tuning_service_sections(
        self,
    ) -> None:
        section_names = _tuning_service_sections()
        verifier_paths = _export_verifier_catalog_paths()

        self.assertIn("economy", section_names)
        self.assertEqual(verifier_paths, ["gameplay", *section_names])


if __name__ == "__main__":
    unittest.main()
