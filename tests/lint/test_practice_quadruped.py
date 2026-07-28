import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "blender" / "create_practice_quadruped.py"
SHIPPED_MODELS = REPO_ROOT / "assets" / "models"


class PracticeQuadrupedBoundaryTests(unittest.TestCase):
    def test_practice_rig_generator_exists_and_never_exports_to_assets(self) -> None:
        self.assertTrue(SCRIPT_PATH.is_file())
        source = SCRIPT_PATH.read_text(encoding="utf-8")

        self.assertIn("build/art-practice/SK_practice_quadruped.glb", source)
        self.assertNotIn("assets/models", source)

    def test_practice_quadruped_cannot_become_shipped_content(self) -> None:
        shipped = list(SHIPPED_MODELS.rglob("*practice*quadruped*.glb"))

        self.assertEqual(shipped, [])

    def test_practice_rig_covers_the_motion_lessons_needed_by_the_hog(self) -> None:
        self.assertTrue(SCRIPT_PATH.is_file())
        source = SCRIPT_PATH.read_text(encoding="utf-8")

        for lesson in (
            "A_practice_quadruped_idle",
            "A_practice_quadruped_walk",
            "A_practice_quadruped_run",
            "A_practice_quadruped_jump",
            "A_practice_quadruped_land",
        ):
            self.assertIn(lesson, source)
        for required_bone in (
            "spine",
            "neck",
            "leg_front.L",
            "leg_front.R",
            "leg_back.L",
            "leg_back.R",
        ):
            self.assertIn(required_bone, source)


if __name__ == "__main__":
    unittest.main()
