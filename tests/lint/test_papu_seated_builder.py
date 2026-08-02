"""R8 Task 5: boundary + determinism coverage for create_papu_seated.py.

Two kinds of check live here, deliberately separated by cost:

- SeatedBuilderSourceTests are plain text-scan assertions (no Blender
  invocation) -- fast, always run, mirror tests/lint/test_practice_
  quadruped.py's own source-scan shape.
- SeatedBuilderDeterminismTests actually run the real Blender builder
  twice and inspect the two GLBs it writes -- see that class's own doc
  for what "deterministic" is proven to mean here and why a literal
  byte-for-byte ``cmp`` of the whole file is not that property for this
  shared pipeline. Skipped when the blender binary is not on this box
  (never silently "passes" -- unittest reports it as a skip, not green).
"""

from __future__ import annotations

import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BUILDER_SCRIPT = REPO_ROOT / "scripts" / "blender" / "create_papu_seated.py"
KART_CONTROLLER_SCRIPT = REPO_ROOT / "src" / "racing" / "kart" / "kart_controller.gd"
BLENDER_BIN = Path("/usr/bin/blender")

_WRAPPER_TEMPLATE = """
import sys
sys.path.insert(0, {scripts_dir!r})
import create_papu_seated
from pathlib import Path

create_papu_seated.main(
    export_path=Path({export_path!r}),
    source_path=Path({source_path!r}),
    preview_path=Path({preview_path!r}),
    render_preview=False,
)
"""


class SeatedBuilderSourceTests(unittest.TestCase):
    def test_builder_script_exists(self) -> None:
        self.assertTrue(BUILDER_SCRIPT.is_file())

    def test_seated_action_name_matches_kart_controllers_seat_clip(self) -> None:
        # kart_controller.gd's mount_character() plays whatever animation
        # is literally named SEAT_ANIMATION_CLIP -- see that const's own
        # doc ("same StringName, reused verbatim"). If this builder ever
        # authored a differently-named action, mounting Papu would silently
        # fall through to _apply_static_seat_pose(), which -- per that
        # method's own doc -- only overrides bones named "DEF-*", bones
        # Papu's own custom rig does not have, leaving him standing.
        controller_source = KART_CONTROLLER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('const SEAT_ANIMATION_CLIP := &"A_crash_hog_ride"', controller_source)
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('SEATED_ACTION_NAME = "A_crash_hog_ride"', builder_source)

    def test_exports_into_the_boss_budget_directory(self) -> None:
        # See the builder's own module doc: assets/models/characters/ would
        # categorize this GLB as "hero" (10000-12000 triangles per data/
        # tuning/art_budget.tres), and Papu's real mesh is a "boss"-budget
        # asset (15000-25000) reused unshrunk -- "bosses/" is the only
        # directory both honest about his real triangle count and passing
        # scripts/lint_art_budgets.py.
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn(
            'EXPORT_PATH = REPO_ROOT / "assets/models/bosses/SK_papu_seated.glb"',
            builder_source,
        )

    def test_reuses_create_papu_geometry_never_redefines_it(self) -> None:
        # The whole point of a sibling script (this task's own STOP-rule
        # concern: a re-sculpt reads as a new face) is that build_rig()/
        # build_parts() are loaded from create_papu.py, not copy-pasted.
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("load_papu_base", builder_source)
        self.assertIn("papu_base.build_rig()", builder_source)
        self.assertIn("papu_base.build_parts(material)", builder_source)
        self.assertNotIn("def build_rig", builder_source)
        self.assertNotIn("def build_parts", builder_source)


def _build_once(output_dir: Path) -> Path:
    export_path = output_dir / "SK_papu_seated.glb"
    wrapper_path = output_dir / "run_builder.py"
    wrapper_path.write_text(
        _WRAPPER_TEMPLATE.format(
            scripts_dir=str(BUILDER_SCRIPT.parent),
            export_path=str(export_path),
            source_path=str(output_dir / "SK_papu_seated.blend"),
            preview_path=str(output_dir / "SK_papu_seated_preview.png"),
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            str(BLENDER_BIN),
            "--background",
            "--factory-startup",
            "--python",
            str(wrapper_path),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0 or not export_path.is_file():
        raise RuntimeError(
            "create_papu_seated builder failed:\n"
            f"returncode={result.returncode}\n"
            f"stdout={result.stdout}\n"
            f"stderr={result.stderr}"
        )
    return export_path


def _read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    offset = 12
    json_len, _json_type = struct.unpack_from("<II", data, offset)
    offset += 8
    document = json.loads(data[offset : offset + json_len])
    offset += json_len
    binary = b""
    if offset < len(data):
        bin_len, _bin_type = struct.unpack_from("<II", data, offset)
        offset += 8
        binary = data[offset : offset + bin_len]
    return document, binary


def _accessor_bytes(document: dict, binary: bytes, accessor_index: int) -> bytes:
    accessor = document["accessors"][accessor_index]
    buffer_view = document["bufferViews"][accessor["bufferView"]]
    start = buffer_view["byteOffset"]
    end = start + buffer_view["byteLength"]
    return binary[start:end]


def _attribute_bytes(document: dict, binary: bytes, attribute_name: str) -> bytes:
    primitive = document["meshes"][0]["primitives"][0]
    return _accessor_bytes(document, binary, primitive["attributes"][attribute_name])


def _attribute_floats(document: dict, binary: bytes, attribute_name: str) -> tuple[float, ...]:
    raw = _attribute_bytes(document, binary, attribute_name)
    return struct.unpack("<%df" % (len(raw) // 4), raw)


## Two consecutive real builds, traced attribute-by-attribute (scratch
## investigation, not committed): NORMAL carries up to ~5e-5 of jitter on a
## small handful of vertices -- per-vertex normals are averaged from
## adjacent triangles, and the same face-iteration-order non-determinism
## that reorders the triangle index buffer (see SeatedBuilderDeterminism
## Tests' own doc) changes the floating-point SUMMATION order for that
## average by construction, not the shading result. 1e-3 is roughly two
## orders of magnitude above every jitter this investigation actually
## measured (max observed 4.6e-5) -- tight enough to fail on a real
## geometry regression, loose enough to never flake on this known,
## harmless summation-order noise.
NORMAL_TOLERANCE = 1e-3


_INDEX_FORMAT_BY_COMPONENT_TYPE = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}


def _triangle_set(document: dict, binary: bytes) -> set[tuple[int, int, int]]:
    """The mesh's triangles as winding-preserving, rotation-normalized

    tuples -- comparing this SET (not the raw index buffer) between two
    builds proves "the same geometry" without being sensitive to the
    triangle-list SERIALIZATION order, which is exactly the axis Blender's
    export is not stable on -- see SeatedBuilderDeterminismTests' own doc.
    """
    primitive = document["meshes"][0]["primitives"][0]
    accessor = document["accessors"][primitive["indices"]]
    buffer_view = document["bufferViews"][accessor["bufferView"]]
    start = buffer_view["byteOffset"]
    count = accessor["count"]
    format_code, size = _INDEX_FORMAT_BY_COMPONENT_TYPE[accessor["componentType"]]
    raw = binary[start : start + count * size]
    flat = struct.unpack("<%d%s" % (count, format_code), raw)
    triangles: set[tuple[int, int, int]] = set()
    for index in range(0, len(flat), 3):
        triangle = flat[index : index + 3]
        rotation = triangle.index(min(triangle))
        triangles.add(triangle[rotation:] + triangle[:rotation])
    return triangles


@unittest.skipUnless(
    BLENDER_BIN.is_file(), "blender binary not available at /usr/bin/blender"
)
class SeatedBuilderDeterminismTests(unittest.TestCase):
    """Two independent builds of the same source must be the same asset.

    Every scripts/blender/*.py module doc in this repo claims "byte-
    deterministic" -- but a literal byte-for-byte ``cmp`` of two real
    builds of this SHARED pipeline (character_asset_common.py, used by
    every character builder here, not something this task touches) is not
    actually that property. Proven, not assumed: building the pre-
    existing, already-shipped create_papu.py twice in this same
    environment (scratch investigation, not committed) diverges too, and
    tracing the divergence attribute-by-attribute through the real glTF
    buffers shows the same handful of culprits every time, all upstream
    Blender behaviour tied to one root cause -- face/loop iteration order
    is not stable across runs of this pipeline. That single cause surfaces
    as three symptoms: ``bpy.ops.uv.smart_project()``'s packing search
    lands a few hundredths of a UV unit off on a couple percent of
    vertices; glTF export serializes the triangle index buffer in a
    different order (the same SET of triangles, same winding, different
    sequence); and per-vertex NORMAL averaging (summed from each vertex's
    adjacent triangles) sums in a different order, landing within ~5e-5 of
    the other run. All three are cosmetically inert for THIS asset
    specifically: create_vertex_material() wires only COLOR_0 into the
    shader and never samples TEXCOORD_0, a reordered-but-identical
    triangle list renders pixel-identical geometry, and ~5e-5 of normal
    drift is far below anything a display can show.

    So "deterministic" is pinned at exactly the granularity that is both
    TRUE and the granularity that matters for a shipped, likeness-gated
    character: the whole glTF JSON scene graph (topology, skeleton,
    animation-keyframe structure, materials) byte-identical; POSITION,
    COLOR_0, JOINTS_0, WEIGHTS_0 -- the buffers a real geometry or skinning
    regression would actually move -- byte-identical; NORMAL within
    NORMAL_TOLERANCE (a real shading-direction bug would blow past it, see
    that constant's own doc); and the triangle SET (not its serialization)
    unchanged. Only TEXCOORD_0 and raw index-buffer ORDER are left
    unpinned, and only because they are provably inert, not because this
    test gave up on them.
    """

    def test_two_builds_are_geometrically_identical(self) -> None:
        with tempfile.TemporaryDirectory() as first_dir_name:
            with tempfile.TemporaryDirectory() as second_dir_name:
                first_glb = _build_once(Path(first_dir_name))
                second_glb = _build_once(Path(second_dir_name))

                document_a, binary_a = _read_glb(first_glb)
                document_b, binary_b = _read_glb(second_glb)

                self.assertEqual(
                    document_a,
                    document_b,
                    "the glTF JSON scene graph (topology, hierarchy, "
                    "skeleton, animation metadata, materials) must be "
                    "identical between two builds of the same source",
                )
                for attribute_name in ("POSITION", "COLOR_0", "JOINTS_0", "WEIGHTS_0"):
                    self.assertEqual(
                        _attribute_bytes(document_a, binary_a, attribute_name),
                        _attribute_bytes(document_b, binary_b, attribute_name),
                        f"{attribute_name} must be byte-identical between "
                        "two builds -- a real difference here would be "
                        "actual geometry or skinning drift, not inert "
                        "UV/ordering noise",
                    )
                normals_a = _attribute_floats(document_a, binary_a, "NORMAL")
                normals_b = _attribute_floats(document_b, binary_b, "NORMAL")
                max_normal_delta = max(
                    abs(a - b) for a, b in zip(normals_a, normals_b)
                )
                self.assertLessEqual(
                    max_normal_delta,
                    NORMAL_TOLERANCE,
                    "NORMAL must be within NORMAL_TOLERANCE between two "
                    f"builds -- got a max delta of {max_normal_delta}, "
                    "consistent with real shading drift, not the known "
                    "summation-order jitter this tolerance exists for",
                )
                self.assertEqual(
                    _triangle_set(document_a, binary_a),
                    _triangle_set(document_b, binary_b),
                    "the exported mesh must cover the exact same "
                    "triangles, winding included, between two builds",
                )


if __name__ == "__main__":
    unittest.main()
