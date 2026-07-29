import tempfile
import unittest
from pathlib import Path

import numpy as np

from scripts.blender.env_kit_palette import (
    ATLAS_CELL_MARGIN_PX,
    ATLAS_ORDER,
    ATLAS_SIZE,
    PALETTE,
    TRIM_BANDS,
    TRIM_HEIGHT,
    TRIM_WIDTH,
    atlas_cell_pixels,
    trim_band_pixels,
)
from scripts.build_kit_textures import (
    ATLAS_NAME,
    TRIM_NAME,
    atlas_pixels,
    encode_png,
    grain_field,
    main,
    trim_pixels,
)
from scripts.texture_budget import (
    import_generates_mipmaps,
    is_power_of_two,
    png_dimensions,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
TEXTURE_DIR = REPO_ROOT / "assets" / "textures"

# The images are ~2 MB and every test wants one. Paint each once.
ATLAS = atlas_pixels()
TRIM = trim_pixels()


class GrainTests(unittest.TestCase):
    def test_every_family_produces_zero_mean_noise(self) -> None:
        # The whole colour-fidelity argument rests on this: a biased field would
        # drag the cell off its palette colour, and mipmaps would spread the
        # error across the whole piece at distance.
        for family in ("fine", "mottle", "leaf", "bark", "smooth"):
            field = grain_field(family, 64, 64, seed=7)
            self.assertAlmostEqual(float(field.mean()), 0.0, places=12, msg=family)

    def test_grain_is_reproducible_for_a_seed(self) -> None:
        first = grain_field("mottle", 32, 32, seed=11)
        second = grain_field("mottle", 32, 32, seed=11)

        np.testing.assert_array_equal(first, second)

    def test_different_seeds_give_different_grain(self) -> None:
        first = grain_field("fine", 32, 32, seed=11)
        second = grain_field("fine", 32, 32, seed=12)

        self.assertFalse(np.array_equal(first, second))

    def test_the_families_are_actually_different(self) -> None:
        fine = grain_field("fine", 64, 64, seed=3)
        mottle = grain_field("mottle", 64, 64, seed=3)

        # Mottling is blurred, so neighbouring texels agree far more than in
        # fine speckle. If these ever match, the blur has stopped happening.
        self.assertLess(float(np.abs(np.diff(mottle, axis=1)).mean()),
                        float(np.abs(np.diff(fine, axis=1)).mean()))


class AtlasTests(unittest.TestCase):
    def test_the_atlas_is_the_authored_size(self) -> None:
        self.assertEqual(ATLAS.shape, (ATLAS_SIZE, ATLAS_SIZE, 3))
        self.assertEqual(ATLAS.dtype, np.uint8)

    def test_every_cell_averages_to_its_palette_colour(self) -> None:
        for name in ATLAS_ORDER:
            left, top, right, bottom = atlas_cell_pixels(name)
            cell = ATLAS[top:bottom, left:right].astype(np.float64) / 255.0
            measured = cell.reshape(-1, 3).mean(axis=0)
            for channel, (got, want) in enumerate(zip(measured, PALETTE[name])):
                self.assertAlmostEqual(got, want, places=2, msg=f"{name} ch{channel}")

    def test_the_guard_band_carries_the_cells_own_colour(self) -> None:
        # The margin exists so mip bleeding pulls in the same hue. If the margin
        # were left unpainted this would show up as a large delta.
        for name in ATLAS_ORDER:
            left, top, right, bottom = atlas_cell_pixels(name)
            margin = ATLAS_CELL_MARGIN_PX
            edge = ATLAS[top : top + margin, left:right].astype(np.float64) / 255.0
            centre = (
                ATLAS[top + margin : bottom - margin, left + margin : right - margin]
                .astype(np.float64)
                / 255.0
            )
            for got, want in zip(edge.reshape(-1, 3).mean(0), centre.reshape(-1, 3).mean(0)):
                self.assertAlmostEqual(got, want, places=1, msg=name)

    def test_no_cell_is_void(self) -> None:
        # Spare cells repeat the palette rather than staying black, so a UV that
        # escapes its rectangle still samples a kit colour.
        cells_per_side = ATLAS_SIZE // (ATLAS_SIZE // 8)
        for index in range(cells_per_side * cells_per_side):
            column = index % 8
            row = index // 8
            size = ATLAS_SIZE // 8
            patch = ATLAS[row * size : (row + 1) * size, column * size : (column + 1) * size]
            self.assertGreater(int(patch.max()), 0, f"cell {index} is black")

    def test_painting_is_reproducible(self) -> None:
        np.testing.assert_array_equal(ATLAS, atlas_pixels())


class TrimTests(unittest.TestCase):
    def test_the_trim_sheet_is_the_authored_size(self) -> None:
        self.assertEqual(TRIM.shape, (TRIM_HEIGHT, TRIM_WIDTH, 3))

    def test_every_band_averages_to_its_palette_colour(self) -> None:
        for name in TRIM_BANDS:
            _, top, _, bottom = trim_band_pixels(name)
            band = TRIM[top:bottom].astype(np.float64) / 255.0
            for got, want in zip(band.reshape(-1, 3).mean(0), PALETTE[name]):
                self.assertAlmostEqual(got, want, places=2, msg=name)

    def test_bands_carry_strata_rather_than_a_flat_fill(self) -> None:
        # The trim sheet's entire reason for existing is vertical layering. A
        # band whose rows are all identical would be an atlas cell wearing a hat.
        _, top, _, bottom = trim_band_pixels(TRIM_BANDS[0])
        row_means = TRIM[top:bottom].astype(np.float64).reshape(bottom - top, -1).mean(axis=1)

        self.assertGreater(float(row_means.std()), 1.0)

    def test_painting_is_reproducible(self) -> None:
        np.testing.assert_array_equal(TRIM, trim_pixels())


class PngEncodingTests(unittest.TestCase):
    def test_the_encoder_round_trips_through_the_repos_own_reader(self) -> None:
        # Cross-check against scripts/texture_budget.py rather than a second copy
        # of the same assumption: the lint has to be able to measure what we write.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_probe.png"
            path.write_bytes(encode_png(np.zeros((64, 128, 3), dtype=np.uint8)))

            self.assertEqual(png_dimensions(path), (128, 64))

    def test_it_rejects_an_array_that_is_not_rgb(self) -> None:
        with self.assertRaises(ValueError):
            encode_png(np.zeros((8, 8), dtype=np.uint8))

    def test_written_textures_satisfy_the_art_budget_rules(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            out_dir = Path(directory)

            self.assertEqual(main(["--out-dir", str(out_dir)]), 0)

            for name in (ATLAS_NAME, TRIM_NAME):
                width, height = png_dimensions(out_dir / name)
                self.assertTrue(is_power_of_two(width), name)
                self.assertTrue(is_power_of_two(height), name)
                self.assertLessEqual(max(width, height), 2048, name)


class MipmapImportTests(unittest.TestCase):
    """The atlas is designed around mip behaviour; importing without mips
    silently throws that design away.

    The 16 px guard band exists because mipmapping averages neighbouring texels
    and by the fifth mip a 256 px cell is 8 px wide, and the grain is zero-mean
    precisely so every mip level averages back to the exact palette colour. With
    mipmaps/generate=false none of that machinery does anything: the GPU point-
    samples a 2048 px texture at all distances, which shimmers as the camera
    rails forward and thrashes the texture cache on a bandwidth-limited tiled
    mobile GPU. Nothing errors, so it needs a lint.
    """

    def test_kit_textures_are_imported_with_mipmaps(self) -> None:
        for name in (ATLAS_NAME, TRIM_NAME):
            sidecar = TEXTURE_DIR / f"{name}.import"

            self.assertTrue(sidecar.is_file(), f"{name} must have a .import sidecar")
            self.assertTrue(
                import_generates_mipmaps(sidecar),
                f"{name} must set mipmaps/generate=true; the atlas guard band and "
                "zero-mean grain exist to make mips correct and do nothing without them",
            )

    def test_a_sidecar_without_the_key_is_not_treated_as_mipmapped(self) -> None:
        # Absent means false in Godot's importer, and a lint that reads absence
        # as success would pass on a sidecar that never opted in.
        with tempfile.TemporaryDirectory() as directory:
            sidecar = Path(directory) / "T_probe.png.import"
            sidecar.write_text("[params]\ncompress/mode=2\n", encoding="utf-8")

            self.assertFalse(import_generates_mipmaps(sidecar))

    def test_a_missing_sidecar_is_not_treated_as_mipmapped(self) -> None:
        self.assertFalse(import_generates_mipmaps(TEXTURE_DIR / "T_absent.png.import"))
