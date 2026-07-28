import unittest

from scripts.blender.env_kit_palette import (
    ATLAS_CELL_MARGIN_PX,
    ATLAS_CELL_PX,
    ATLAS_CELLS_PER_SIDE,
    ATLAS_ORDER,
    ATLAS_SIZE,
    PALETTE,
    TRIM_BAND_MARGIN_PX,
    TRIM_BAND_PX,
    TRIM_BANDS,
    TRIM_HEIGHT,
    TRIM_WIDTH,
    UnknownPaletteError,
    atlas_cell_index,
    atlas_cell_pixels,
    atlas_uv_rect,
    trim_band_pixels,
    trim_uv_rect,
)


class PaletteTests(unittest.TestCase):
    def test_every_colour_is_a_unit_range_srgb_triple(self) -> None:
        for name, colour in PALETTE.items():
            self.assertEqual(len(colour), 3, name)
            for channel in colour:
                self.assertGreaterEqual(channel, 0.0, name)
                self.assertLessEqual(channel, 1.0, name)

    def test_the_atlas_order_covers_the_palette_exactly_once(self) -> None:
        self.assertEqual(sorted(ATLAS_ORDER), sorted(PALETTE))
        self.assertEqual(len(set(ATLAS_ORDER)), len(ATLAS_ORDER))

    def test_the_order_is_sorted_so_the_layout_is_stable(self) -> None:
        # Cell assignment is by position in this tuple. If the order depended on
        # dict insertion, editing the palette would silently reshuffle every UV
        # already baked into the kit's meshes.
        self.assertEqual(list(ATLAS_ORDER), sorted(ATLAS_ORDER))

    def test_the_palette_fits_the_atlas_grid(self) -> None:
        self.assertLessEqual(
            len(ATLAS_ORDER), ATLAS_CELLS_PER_SIDE * ATLAS_CELLS_PER_SIDE
        )


class AtlasLayoutTests(unittest.TestCase):
    def test_cells_are_assigned_in_reading_order(self) -> None:
        self.assertEqual(atlas_cell_index(ATLAS_ORDER[0]), 0)
        self.assertEqual(atlas_cell_pixels(ATLAS_ORDER[0]), (0, 0, 256, 256))
        # Cell 8 starts the second row on an 8-wide grid.
        self.assertEqual(
            atlas_cell_pixels(ATLAS_ORDER[8]), (0, ATLAS_CELL_PX, 256, 2 * ATLAS_CELL_PX)
        )

    def test_every_cell_sits_inside_the_atlas(self) -> None:
        for name in ATLAS_ORDER:
            left, top, right, bottom = atlas_cell_pixels(name)
            self.assertGreaterEqual(left, 0, name)
            self.assertGreaterEqual(top, 0, name)
            self.assertLessEqual(right, ATLAS_SIZE, name)
            self.assertLessEqual(bottom, ATLAS_SIZE, name)

    def test_uv_rects_are_inset_by_the_guard_band(self) -> None:
        left, top, right, bottom = atlas_cell_pixels("sand_light")
        u0, v0, u1, v1 = atlas_uv_rect("sand_light")

        self.assertAlmostEqual(u0, (left + ATLAS_CELL_MARGIN_PX) / ATLAS_SIZE)
        self.assertAlmostEqual(v0, (top + ATLAS_CELL_MARGIN_PX) / ATLAS_SIZE)
        self.assertAlmostEqual(u1, (right - ATLAS_CELL_MARGIN_PX) / ATLAS_SIZE)
        self.assertAlmostEqual(v1, (bottom - ATLAS_CELL_MARGIN_PX) / ATLAS_SIZE)

    def test_uv_rects_stay_in_the_unit_square(self) -> None:
        for name in ATLAS_ORDER:
            for value in atlas_uv_rect(name):
                self.assertGreaterEqual(value, 0.0, name)
                self.assertLessEqual(value, 1.0, name)

    def test_no_two_palette_entries_share_texture_space(self) -> None:
        # A guard band is only worth having if the rects it protects are
        # genuinely disjoint -- overlapping rects would bleed at every mip level.
        rects = [atlas_uv_rect(name) for name in ATLAS_ORDER]
        for first in range(len(rects)):
            for second in range(first + 1, len(rects)):
                a_u0, a_v0, a_u1, a_v1 = rects[first]
                b_u0, b_v0, b_u1, b_v1 = rects[second]
                disjoint = a_u1 <= b_u0 or b_u1 <= a_u0 or a_v1 <= b_v0 or b_v1 <= a_v0
                self.assertTrue(
                    disjoint, f"{ATLAS_ORDER[first]} overlaps {ATLAS_ORDER[second]}"
                )

    def test_an_unknown_colour_fails_closed(self) -> None:
        with self.assertRaises(UnknownPaletteError):
            atlas_cell_index("chrome")
        with self.assertRaises(UnknownPaletteError):
            atlas_uv_rect("chrome")


class TrimLayoutTests(unittest.TestCase):
    def test_the_bands_are_all_rock_family_palette_entries(self) -> None:
        for name in TRIM_BANDS:
            self.assertIn(name, PALETTE, name)

    def test_bands_tile_the_sheet_exactly(self) -> None:
        self.assertEqual(TRIM_BAND_PX * len(TRIM_BANDS), TRIM_HEIGHT)
        expected_top = 0
        for name in TRIM_BANDS:
            left, top, right, bottom = trim_band_pixels(name)
            self.assertEqual((left, right), (0, TRIM_WIDTH), name)
            self.assertEqual(top, expected_top, name)
            self.assertEqual(bottom - top, TRIM_BAND_PX, name)
            expected_top = bottom
        self.assertEqual(expected_top, TRIM_HEIGHT)

    def test_uv_rects_are_inset_and_in_the_unit_square(self) -> None:
        for name in TRIM_BANDS:
            u0, v0, u1, v1 = trim_uv_rect(name)
            for value in (u0, v0, u1, v1):
                self.assertGreaterEqual(value, 0.0, name)
                self.assertLessEqual(value, 1.0, name)
            self.assertAlmostEqual(u0, TRIM_BAND_MARGIN_PX / TRIM_WIDTH)
            self.assertLess(v0, v1, name)

    def test_a_colour_with_no_band_fails_closed_and_says_why(self) -> None:
        # Only the rock family has strata. A piece painted "leaf_mid" asking for
        # trim is a mistake, and silently handing back band zero would put grey
        # rock on a leaf.
        with self.assertRaises(UnknownPaletteError) as caught:
            trim_uv_rect("leaf_mid")

        self.assertIn("trim band", str(caught.exception))
