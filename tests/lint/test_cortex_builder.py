"""R8 Task 6: boundary + determinism coverage for create_cortex.py.

Mirrors tests/lint/test_papu_seated_builder.py's own shape (that file's own
module doc explains the two-tier split this file repeats):

- CortexBuilderSourceTests are plain text-scan assertions (no Blender
  invocation) -- fast, always run.
- CortexBuilderExportTests builds the real GLB once and inspects the
  exported glTF document directly -- the "export verifier" the task brief
  asks for (self-contained: no external buffer/image URIs, since this
  asset carries vertex colours only and never samples a texture).
- CortexBuilderDeterminismTests builds the real GLB twice and diffs the
  two outputs, at the exact granularity test_papu_seated_builder.py's own
  SeatBuilderDeterminismTests class doc proves is both TRUE and the
  granularity that matters (see that doc for the full investigation this
  file's tolerance/scope choices are copied from -- the same shared
  character_asset_common.py pipeline, so the same non-determinism sources
  apply here). Skipped when the blender binary is not on this box.
"""

from __future__ import annotations

import json
import re
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BUILDER_SCRIPT = REPO_ROOT / "scripts" / "blender" / "create_cortex.py"
KART_CONTROLLER_SCRIPT = REPO_ROOT / "src" / "racing" / "kart" / "kart_controller.gd"
DRIVER_ENTRY_PATH = REPO_ROOT / "data" / "racing" / "drivers" / "cortex.tres"
BLENDER_BIN = Path("/usr/bin/blender")

_WRAPPER_TEMPLATE = """
import sys
sys.path.insert(0, {scripts_dir!r})
import create_cortex
from pathlib import Path

create_cortex.main(
    export_path=Path({export_path!r}),
    source_path=Path({source_path!r}),
    preview_path=Path({preview_path!r}),
    render_preview=False,
    render_gate=False,
)
"""


class CortexBuilderSourceTests(unittest.TestCase):
    def test_builder_script_exists(self) -> None:
        self.assertTrue(BUILDER_SCRIPT.is_file())

    def test_seated_action_name_matches_kart_controllers_seat_clip(self) -> None:
        # Same literal-name-match requirement create_papu_seated.py's own
        # test proves -- see kart_controller.gd's SEAT_ANIMATION_CLIP doc
        # ("same StringName, reused verbatim"). A differently-named action
        # here would silently fall through to _apply_static_seat_pose(),
        # which only overrides bones literally named "DEF-*" -- Cortex's
        # own compact custom rig (build_rig() below) does not have those,
        # so he would mount standing, not seated.
        controller_source = KART_CONTROLLER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('const SEAT_ANIMATION_CLIP := &"A_crash_hog_ride"', controller_source)
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('SEATED_ACTION_NAME = "A_crash_hog_ride"', builder_source)

    def test_exports_into_the_characters_hero_budget_directory(self) -> None:
        # Unlike Papu (whose real geometry was already 15000-25000 "boss"
        # triangles, shipped to assets/models/bosses/), Cortex is a brand
        # new build authored to the "characters" directory's own hero band
        # (10000-12000 triangles, data/tuning/art_budget.tres) -- see
        # scripts/lint_art_budgets.py's own CATEGORY_BY_DIRECTORY.
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        self.assertIn(
            'EXPORT_PATH = REPO_ROOT / "assets/models/characters/SK_cortex.glb"',
            builder_source,
        )

    def test_reuses_character_asset_common_never_redefines_its_helpers(self) -> None:
        # The whole point of building on character_asset_common.py (the
        # same shared kit create_papu.py already uses) is that the rig/
        # part/action primitives are IMPORTED, not copy-pasted -- a fresh
        # local reimplementation is exactly the kind of drift this task's
        # own STOP-rule (byte-deterministic, shared pipeline) forbids.
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")
        for helper in (
            "add_cone_between",
            "add_cylinder_between",
            "add_rounded_box",
            "add_sphere",
            "begin_action",
            "create_rig",
            "join_and_skin",
            "key_pose",
            "validate_asset",
        ):
            self.assertIn(helper, builder_source)
        self.assertNotIn("def add_sphere", builder_source)
        self.assertNotIn("def join_and_skin", builder_source)
        self.assertNotIn("def create_rig(", builder_source)
        self.assertNotIn("def validate_asset", builder_source)

    def test_cortex_driver_entry_stays_fallback(self) -> None:
        # The gate is human-only (repo rule 3 / this plan's own Global
        # Constraints) -- this builder must never be the thing that flips
        # cortex.tres. Reading it here pins the current, correct state and
        # would catch an accidental flip landing in the SAME commit as this
        # builder.
        entry_source = DRIVER_ENTRY_PATH.read_text(encoding="utf-8")
        self.assertIn('character_scene_path = ""', entry_source)

    def test_seated_action_only_poses_the_allowlisted_bones(self) -> None:
        # Same static-source derivation test_papu_seated_builder.py's own
        # identically-named test uses: parsed straight out of the SEATED_
        # POSE dict literal (the only place create_seated() ever calls
        # key_pose() with non-default rotations), not a hand-maintained
        # duplicate list that could drift out of sync with the real
        # behaviour. Cortex's own seated action is a static two-keyframe
        # hold with no mid-cycle exception (see create_seated()'s own doc
        # for why), so unlike Papu's allowlist there is no "chest" entry
        # to carry.
        builder_source = BUILDER_SCRIPT.read_text(encoding="utf-8")

        seated_pose_match = re.search(
            r"SEATED_POSE = \{(.*?)\n\}", builder_source, re.DOTALL
        )
        self.assertIsNotNone(seated_pose_match, "SEATED_POSE dict literal not found")
        posed_bones = set(
            re.findall(r'"([\w.]+)":\s*\(', seated_pose_match.group(1))
        )

        allowlist = {
            "thigh.L",
            "thigh.R",
            "shin.L",
            "shin.R",
            "upper_arm.L",
            "upper_arm.R",
            "forearm.L",
            "forearm.R",
        }
        self.assertEqual(
            posed_bones,
            allowlist,
            "the set of bones ever given a non-identity rotation in the "
            "seated action drifted from the allowlist -- update BOTH this "
            "allowlist and create_cortex.py's own SEATED_POSE doc comment "
            "together, and re-confirm the likeness read if a face/torso "
            "bone was added",
        )
        never_posed = {"head", "jaw", "neck", "spine", "pelvis"}
        self.assertFalse(
            posed_bones & never_posed,
            "a face/torso bone was given a non-identity rotation in the "
            "seated action -- this would reopen the likeness read the "
            "gate renders were captured against",
        )
        create_seated_match = re.search(
            r"def create_seated\(.*?return finish_action", builder_source, re.DOTALL
        )
        self.assertIsNotNone(create_seated_match, "create_seated() body not found")
        self.assertNotIn(
            "mid_pose",
            create_seated_match.group(0),
            "create_seated() grew a mid-frame pose override -- this "
            "builder is documented as a plain two-keyframe static hold; "
            "if a mid-cycle exception is intentional, update this test's "
            "allowlist derivation the same way test_papu_seated_builder.py "
            "does for its own mid_pose overrides, not just this comment",
        )


def _build_once(output_dir: Path) -> Path:
    export_path = output_dir / "SK_cortex.glb"
    wrapper_path = output_dir / "run_builder.py"
    wrapper_path.write_text(
        _WRAPPER_TEMPLATE.format(
            scripts_dir=str(BUILDER_SCRIPT.parent),
            export_path=str(export_path),
            source_path=str(output_dir / "SK_cortex.blend"),
            preview_path=str(output_dir / "SK_cortex_preview.png"),
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
            "create_cortex builder failed:\n"
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


def _animation_sampler_accessor_bytes(document: dict, binary: bytes) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    for animation_index, animation in enumerate(document.get("animations", [])):
        for sampler_index, sampler in enumerate(animation.get("samplers", [])):
            for key in ("input", "output"):
                accessor_index = sampler[key]
                result[f"{animation_index}:{sampler_index}:{key}"] = _accessor_bytes(
                    document, binary, accessor_index
                )
    return result


_INDEX_FORMAT_BY_COMPONENT_TYPE = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}


def _triangle_set(document: dict, binary: bytes) -> set[tuple[int, int, int]]:
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
class CortexBuilderExportTests(unittest.TestCase):
    """The GLB export verifier the task brief asks for: a single real
    build, inspected for self-containment and the authored triangle band.

    "Self-contained" here means exactly what glTF's own spec makes
    possible for a GLB (as opposed to a .gltf + loose files): no buffer
    carries an external "uri" (the binary chunk is embedded in the file
    itself -- save_source_and_export()'s own export_format="GLB" already
    guarantees this at the Blender-export level, this test proves it held
    on the real output) and no image references an external file (this
    asset is vertex-colour only -- create_vertex_material() never wires a
    texture into the shader -- so the correct assertion is that the
    document carries no images at all, not merely that any it had were
    embedded).
    """

    def test_glb_is_self_contained_with_no_external_references(self) -> None:
        with tempfile.TemporaryDirectory() as output_dir_name:
            glb_path = _build_once(Path(output_dir_name))
            document, _binary = _read_glb(glb_path)

            for buffer_index, buffer in enumerate(document.get("buffers", [])):
                self.assertNotIn(
                    "uri",
                    buffer,
                    f"buffers[{buffer_index}] carries an external uri -- a "
                    "shipped GLB must embed its binary chunk, not point "
                    "outside the file",
                )
            self.assertEqual(
                document.get("images", []),
                [],
                "SK_cortex.glb must carry no images/textures at all -- the "
                "likeness read is vertex-colour only (module doc: 'no "
                "textures beyond the palette conventions'), so any image "
                "entry would itself be an unauthored external dependency",
            )

    def test_triangle_count_is_within_the_hero_budget_band(self) -> None:
        # data/tuning/art_budget.tres: hero_min_triangles=10000, hero_max_
        # triangles=12000. The real, committed export lint (scripts/lint_
        # art_budgets.py) already proves this for the shipped file; this
        # is the same proof against a fresh, independent build, matching
        # this class's own "build once, inspect the export verifier" scope
        # rather than trusting validate_asset()'s in-Blender check alone.
        with tempfile.TemporaryDirectory() as output_dir_name:
            glb_path = _build_once(Path(output_dir_name))
            document, binary = _read_glb(glb_path)
            triangles = len(_triangle_set(document, binary))
            self.assertGreaterEqual(triangles, 10000)
            self.assertLessEqual(triangles, 12000)


## See test_papu_seated_builder.py's own SeatedBuilderDeterminismTests class
## doc for the full investigation behind this tolerance and scope -- the
## same shared character_asset_common.py pipeline (smart_project() UV
## packing, glTF triangle-list export order, per-vertex NORMAL summation
## order) applies unchanged here, none of it re-derived per builder.
NORMAL_TOLERANCE = 1e-3


@unittest.skipUnless(
    BLENDER_BIN.is_file(), "blender binary not available at /usr/bin/blender"
)
class CortexBuilderDeterminismTests(unittest.TestCase):
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
                animation_bytes_a = _animation_sampler_accessor_bytes(document_a, binary_a)
                animation_bytes_b = _animation_sampler_accessor_bytes(document_b, binary_b)
                self.assertTrue(
                    animation_bytes_a,
                    "expected at least one animation sampler in the "
                    "exported GLB -- idle + the seated action are this "
                    "builder's own two deliverables",
                )
                self.assertEqual(
                    animation_bytes_a.keys(),
                    animation_bytes_b.keys(),
                    "the two builds must carry the same set of animation "
                    "samplers",
                )
                for sampler_key in animation_bytes_a:
                    self.assertEqual(
                        animation_bytes_a[sampler_key],
                        animation_bytes_b[sampler_key],
                        f"animation sampler accessor {sampler_key} "
                        "(keyframe time/value bytes) must be byte-identical "
                        "between two builds -- these are authored Python "
                        "constants, not Blender-computed geometry, so no "
                        "jitter tolerance applies",
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
