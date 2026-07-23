from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from scripts.check_content_vocabulary import find_prohibited_vocabulary


class ContentVocabularyTests(unittest.TestCase):
    def test_detects_phase_one_content_vocabulary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "src" / "gameplay" / "bad_actor.gd"
            source.parent.mkdir(parents=True)
            source.write_text(
                "class_name BadActor\nfunc spawn_enemy() -> void:\n\tpass\n",
                encoding="utf-8",
            )

            findings = find_prohibited_vocabulary(root)

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].term, "enemy")
        self.assertEqual(findings[0].path, "src/gameplay/bad_actor.gd")

    def test_ignores_comments_and_prose_strings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "src" / "gameplay" / "camera_notes.gd"
            source.parent.mkdir(parents=True)
            source.write_text(
                '# Camera can swing later.\n'
                'var notes := "enemy crate grind phase shift"\n'
                "func move_player() -> void:\n\tpass\n",
                encoding="utf-8",
            )

            findings = find_prohibited_vocabulary(root)

        self.assertEqual(findings, [])

    def test_detects_prohibited_scene_node_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            scene = root / "scenes" / "test.tscn"
            scene.parent.mkdir(parents=True)
            scene.write_text(
                '[node name="EnemySpawner" type="Node3D"]\n',
                encoding="utf-8",
            )

            findings = find_prohibited_vocabulary(root)

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].term, "enemy")

    def test_allows_phase_zero_five_traversal_vocabulary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = (
                root
                / "src"
                / "gameplay"
                / "traversal"
                / "wall_run_strip.gd"
            )
            source.parent.mkdir(parents=True)
            source.write_text(
                "class_name WallRunStrip\n"
                "func grind_swing_phase_shift() -> void:\n"
                "\tpass\n",
                encoding="utf-8",
            )

            findings = find_prohibited_vocabulary(root)

        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()
