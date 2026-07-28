import unittest

from scripts.scene_transform_parsing import assignment_values


class AssignmentValuesTests(unittest.TestCase):
    def test_reads_property_assignments_from_a_resource_body(self) -> None:
        text = """[gd_resource type="Resource" format=3]

[resource]
script = ExtResource("1_x")
hero_max_triangles = 12000
shadow_diameter_m = 0.8
"""

        self.assertEqual(
            assignment_values(text),
            {
                "type": '"Resource" format=3]',
                "script": 'ExtResource("1_x")',
                "hero_max_triangles": "12000",
                "shadow_diameter_m": "0.8",
            },
        )

    def test_ignores_lines_that_are_not_assignments(self) -> None:
        text = "[resource]\n\n; a comment\nhero_max_triangles = 12000\n"

        self.assertEqual(assignment_values(text), {"hero_max_triangles": "12000"})
