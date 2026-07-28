import json
import struct
import tempfile
import unittest
from pathlib import Path

from scripts.gltf_budget import (
    MalformedGlbError,
    read_glb_json,
    triangle_count,
    triangle_count_of_file,
)


def build_glb(document: dict) -> bytes:
    """Assemble a minimal single-chunk .glb around a glTF JSON document."""
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)  # chunks are 4-byte aligned
    chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload  # 'JSON'
    header = struct.pack("<III", 0x46546C67, 2, 12 + len(chunk))  # 'glTF', v2
    return header + chunk


class ReadGlbJsonTests(unittest.TestCase):
    def test_reads_the_json_chunk(self) -> None:
        document = {"asset": {"version": "2.0"}, "meshes": []}

        self.assertEqual(read_glb_json(build_glb(document)), document)

    def test_rejects_a_file_that_is_not_a_glb(self) -> None:
        with self.assertRaises(MalformedGlbError):
            read_glb_json(b"this is a .blend file, not a .glb")

    def test_rejects_a_truncated_file(self) -> None:
        with self.assertRaises(MalformedGlbError):
            read_glb_json(build_glb({"meshes": []})[:20])


class TriangleCountTests(unittest.TestCase):
    def test_counts_indexed_triangles(self) -> None:
        document = {
            "accessors": [{"count": 36}],
            "meshes": [{"primitives": [{"mode": 4, "indices": 0}]}],
        }

        self.assertEqual(triangle_count(document), 12)

    def test_counts_non_indexed_triangles_from_the_position_accessor(self) -> None:
        document = {
            "accessors": [{"count": 9}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }

        self.assertEqual(triangle_count(document), 3)

    def test_sums_every_primitive_of_every_mesh(self) -> None:
        document = {
            "accessors": [{"count": 36}, {"count": 6}],
            "meshes": [
                {"primitives": [{"mode": 4, "indices": 0}]},
                {"primitives": [{"mode": 4, "indices": 1}, {"mode": 4, "indices": 1}]},
            ],
        }

        self.assertEqual(triangle_count(document), 12 + 2 + 2)

    def test_counts_strips_and_fans_as_count_minus_two(self) -> None:
        strip = {"accessors": [{"count": 10}], "meshes": [{"primitives": [{"mode": 5, "indices": 0}]}]}
        fan = {"accessors": [{"count": 10}], "meshes": [{"primitives": [{"mode": 6, "indices": 0}]}]}

        self.assertEqual(triangle_count(strip), 8)
        self.assertEqual(triangle_count(fan), 8)

    def test_ignores_point_and_line_primitives(self) -> None:
        document = {
            "accessors": [{"count": 30}],
            "meshes": [{"primitives": [{"mode": 0, "indices": 0}, {"mode": 1, "indices": 0}]}],
        }

        self.assertEqual(triangle_count(document), 0)

    def test_a_document_with_no_meshes_counts_zero(self) -> None:
        self.assertEqual(triangle_count({"meshes": []}), 0)

    def test_rejects_a_primitive_whose_accessor_is_missing(self) -> None:
        document = {"accessors": [], "meshes": [{"primitives": [{"mode": 4, "indices": 7}]}]}

        with self.assertRaises(MalformedGlbError):
            triangle_count(document)

    def test_rejects_a_primitive_with_neither_indices_nor_positions(self) -> None:
        document = {"accessors": [{"count": 3}], "meshes": [{"primitives": [{"mode": 4}]}]}

        with self.assertRaises(MalformedGlbError):
            triangle_count(document)


class TriangleCountOfFileTests(unittest.TestCase):
    def test_reads_a_glb_from_disk(self) -> None:
        document = {
            "accessors": [{"count": 36}],
            "meshes": [{"primitives": [{"mode": 4, "indices": 0}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SM_crate_standard.glb"
            path.write_bytes(build_glb(document))

            self.assertEqual(triangle_count_of_file(path), 12)
