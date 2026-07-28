import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from scripts.texture_budget import (
    MalformedTextureError,
    import_uses_vram_compression,
    is_power_of_two,
    png_dimensions,
)


def build_png(width: int, height: int) -> bytes:
    """Assemble a PNG signature plus a valid IHDR chunk. Pixels are not needed."""
    signature = b"\x89PNG\r\n\x1a\n"
    body = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    chunk = struct.pack(">I", len(body)) + b"IHDR" + body
    chunk += struct.pack(">I", zlib.crc32(b"IHDR" + body))
    return signature + chunk


class PngDimensionsTests(unittest.TestCase):
    def test_reads_width_and_height(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png"
            path.write_bytes(build_png(2048, 2048))

            self.assertEqual(png_dimensions(path), (2048, 2048))

    def test_reads_a_non_square_texture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_wide.png"
            path.write_bytes(build_png(1024, 512))

            self.assertEqual(png_dimensions(path), (1024, 512))

    def test_rejects_a_file_that_is_not_a_png(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_bogus.png"
            path.write_bytes(b"JFIF nonsense")

            with self.assertRaises(MalformedTextureError):
                png_dimensions(path)

    def test_rejects_a_truncated_png(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_short.png"
            path.write_bytes(build_png(64, 64)[:12])

            with self.assertRaises(MalformedTextureError):
                png_dimensions(path)


class PowerOfTwoTests(unittest.TestCase):
    def test_accepts_powers_of_two(self) -> None:
        for value in (1, 2, 256, 1024, 2048):
            self.assertTrue(is_power_of_two(value), value)

    def test_rejects_everything_else(self) -> None:
        for value in (0, -2048, 3, 1000, 2047):
            self.assertFalse(is_power_of_two(value), value)


class ImportCompressionTests(unittest.TestCase):
    def test_detects_vram_compressed_import(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png.import"
            path.write_text(
                '[remap]\n\nimporter="texture"\n\n[params]\n\ncompress/mode=2\n',
                encoding="utf-8",
            )

            self.assertTrue(import_uses_vram_compression(path))

    def test_detects_lossless_import(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png.import"
            path.write_text(
                '[remap]\n\nimporter="texture"\n\n[params]\n\ncompress/mode=0\n',
                encoding="utf-8",
            )

            self.assertFalse(import_uses_vram_compression(path))

    def test_a_missing_import_file_is_not_compressed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse(
                import_uses_vram_compression(Path(directory) / "absent.png.import")
            )
