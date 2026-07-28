import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

from scripts.lint_art_budgets import category_for, find_violations, load_budget

REPO_ROOT = Path(__file__).resolve().parents[2]
LINT_SCRIPT = REPO_ROOT / "scripts" / "lint_art_budgets.py"

AUTHORED_BUDGET = (REPO_ROOT / "data" / "tuning" / "art_budget.tres").read_text(
    encoding="utf-8"
)


def build_glb(triangles: int) -> bytes:
    document = {
        "asset": {"version": "2.0"},
        "accessors": [{"count": triangles * 3}],
        "meshes": [{"primitives": [{"mode": 4, "indices": 0}]}],
    }
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    return struct.pack("<III", 0x46546C67, 2, 12 + len(chunk)) + chunk


def build_png(width: int, height: int) -> bytes:
    body = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    chunk = struct.pack(">I", len(body)) + b"IHDR" + body
    chunk += struct.pack(">I", zlib.crc32(b"IHDR" + body))
    return b"\x89PNG\r\n\x1a\n" + chunk


def make_repo(directory: str) -> Path:
    """A throwaway tree with the real authored budget and empty asset dirs."""
    root = Path(directory)
    (root / "data" / "tuning").mkdir(parents=True)
    (root / "data" / "tuning" / "art_budget.tres").write_text(
        AUTHORED_BUDGET, encoding="utf-8"
    )
    for name in ("characters", "enemies", "bosses", "rideables", "props", "kits"):
        (root / "assets" / "models" / name).mkdir(parents=True)
    (root / "assets" / "textures").mkdir(parents=True)
    return root


class CategoryResolutionTests(unittest.TestCase):
    def test_maps_each_asset_directory_to_its_category(self) -> None:
        self.assertEqual(category_for(Path("assets/models/characters/SK_crash.glb")), "hero")
        self.assertEqual(category_for(Path("assets/models/enemies/SK_skink.glb")), "enemy")
        self.assertEqual(category_for(Path("assets/models/bosses/SK_papu.glb")), "boss")
        self.assertEqual(category_for(Path("assets/models/props/SM_crate.glb")), "prop")
        self.assertEqual(category_for(Path("assets/models/kits/SM_palm.glb")), "kit_piece")
        self.assertEqual(category_for(Path("assets/models/rideables/SK_hog.glb")), "rideable")

    def test_an_unknown_directory_has_no_category(self) -> None:
        self.assertIsNone(category_for(Path("assets/models/SK_loose.glb")))


class BudgetLoadingTests(unittest.TestCase):
    def test_reads_the_authored_caps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            budget = load_budget(make_repo(directory))

            self.assertEqual(budget.max_triangles["hero"], 12000)
            self.assertEqual(budget.min_triangles["enemy"], 3000)
            self.assertEqual(budget.min_triangles["prop"], 100)
            self.assertEqual(budget.max_triangles["prop"], 2500)
            self.assertEqual(budget.min_triangles["kit_piece"], 100)
            self.assertEqual(budget.max_triangles["kit_piece"], 2000)
            self.assertEqual(budget.min_triangles["rideable"], 6000)
            self.assertEqual(budget.max_triangles["rideable"], 10000)
            self.assertEqual(budget.max_texture_dimension_px, 2048)


class TriangleBudgetTests(unittest.TestCase):
    def test_an_in_budget_hero_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(11000))

            self.assertEqual(find_violations(root), [])

    def test_an_over_budget_hero_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(20000))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("20000", violations[0].message)
            self.assertIn("12000", violations[0].message)

    def test_an_under_budget_asset_is_reported_too(self) -> None:
        # Under the floor means the silhouette is probably not what 9.4 assumed.
        # It is a budget band, not a ceiling.
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/enemies/SK_skink.glb").write_bytes(build_glb(200))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("3000", violations[0].message)

    def test_the_operator_approved_prop_band_accepts_the_first_crate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/props/SM_crate_standard.glb").write_bytes(
                build_glb(1996)
            )

            self.assertEqual(find_violations(root), [])

    def test_the_operator_approved_kit_band_accepts_the_whole_beach_kit(self) -> None:
        # The real kit's extremes, measured with scripts/gltf_budget.py:
        # stone_cairn_a at 100 and fringe_grass_a at 1,564.
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/kits/SM_stone_cairn_a.glb").write_bytes(
                build_glb(100)
            )
            (root / "assets/models/kits/SM_fringe_grass_a.glb").write_bytes(
                build_glb(1564)
            )

            self.assertEqual(find_violations(root), [])

    def test_the_operator_approved_rideable_band_accepts_the_hog(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/rideables/SK_hog.glb").write_bytes(
                build_glb(8000)
            )

            self.assertEqual(find_violations(root), [])

    def test_an_over_budget_kit_piece_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/kits/SM_overgrown.glb").write_bytes(build_glb(2400))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("2400", violations[0].message)
            self.assertIn("2000", violations[0].message)

    def test_an_under_budget_rideable_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/rideables/SK_hog.glb").write_bytes(build_glb(400))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("400", violations[0].message)
            self.assertIn("6000", violations[0].message)

    def test_a_model_outside_every_category_directory_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/SM_loose.glb").write_bytes(build_glb(100))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("category", violations[0].message)

    def test_an_unparseable_model_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/props/SM_broken.glb").write_bytes(b"not a glb")

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("SM_broken.glb", violations[0].path)


class TextureBudgetTests(unittest.TestCase):
    def test_an_oversized_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(4096, 4096))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("4096", violations[0].message)

    def test_a_non_power_of_two_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_odd.png").write_bytes(build_png(1000, 1000))
            (root / "assets/textures/T_odd.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("power of two", violations[0].message)

    def test_an_uncompressed_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(2048, 2048))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=0\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("VRAM", violations[0].message)

    def test_an_in_budget_texture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(2048, 2048))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            self.assertEqual(find_violations(root), [])


class LintEntryPointTests(unittest.TestCase):
    def test_an_empty_asset_tree_passes_and_says_it_scanned_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT), "--repo-root", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("0 asset", result.stdout)

    def test_the_real_repo_passes(self) -> None:
        result = subprocess.run(
            [sys.executable, str(LINT_SCRIPT), "--repo-root", str(REPO_ROOT)],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_violation_exits_non_zero(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(99000))

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT), "--repo-root", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("SK_crash.glb", result.stdout)
