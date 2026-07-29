import unittest
from pathlib import Path

from scripts.lint_traversal_authoring import (
    DETACH_VISIBILITY_RULE,
    RAIL_READABILITY_RULE,
    ROTATED_ANCESTOR_RULE,
    WALL_CAMERA_RULE,
    _parse_scene,
    _path_endpoints,
    find_authoring_violations,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = REPO_ROOT / "tests" / "fixtures"


class TraversalAuthoringLintTests(unittest.TestCase):
    def test_wall_run_fixture_fails_only_the_wall_camera_rule(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_wall_camera_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [WALL_CAMERA_RULE],
        )

    def test_detach_fixture_fails_only_target_visibility(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_detach_visibility_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [DETACH_VISIBILITY_RULE],
        )

    def test_rail_fixture_checks_region_coverage_and_symmetric_links(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_rail_readability_bad.tscn"
        )

        self.assertTrue(findings)
        self.assertEqual(
            {finding.rule for finding in findings},
            {RAIL_READABILITY_RULE},
        )
        details = " ".join(finding.detail for finding in findings)
        self.assertIn("grind camera region", details)
        self.assertIn("symmetric", details)

    def test_rotated_ancestor_fixture_flags_transform_rotation_and_self(
        self,
    ) -> None:
        # Corridor turns (spec 2026-07-29) rotate level segments, but
        # _world_position only ever sums ancestor origins and ignores
        # basis entirely -- porting oriented math is deferred. Until
        # then any rotation in a wall-run strip or traversal rail's
        # ancestor chain -- expressed either as a Transform3D with a
        # non-identity basis (Group1) or a bare rotation = Vector3(...)
        # property (Group2) -- must fail closed. So must a strip/rail's
        # own rotation (SelfRotatedStrip): the runtime honours it via
        # global_basis, but this lint's geometry rules cannot.
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_rotated_ancestor_bad.tscn"
        )

        self.assertEqual(
            {finding.rule for finding in findings},
            {ROTATED_ANCESTOR_RULE},
        )
        self.assertEqual(len(findings), 3)
        details = " ".join(finding.detail for finding in findings)
        self.assertIn("Group1/RunStrip", details)
        self.assertIn("Group2/RailA", details)
        self.assertIn("SelfRotatedStrip", details)
        self.assertIn("spec 2026-07-29", details)
        self.assertIn("deferred", details)

    def test_unrotated_identity_transform_ancestor_stays_clean(self) -> None:
        # An editor re-save of a translated-only node produces
        # transform = Transform3D(...) with an *identity* basis (see
        # test_editor_transform_form_computes_real_world_position); the
        # rotated-ancestor guard must not false-positive on that common
        # form.
        findings = find_authoring_violations(
            FIXTURE_ROOT / "traversal_rotated_ancestor_ok.tscn"
        )

        self.assertEqual(findings, [])

    def test_all_real_traversal_segments_pass(self) -> None:
        findings = find_authoring_violations(
            REPO_ROOT / "scenes" / "segments"
        )

        self.assertEqual(findings, [])

    def test_editor_transform_form_computes_real_world_position(
        self,
    ) -> None:
        # R2: this lint carries its own copy of lint_level_authoring.py's
        # scene parser, and never received the P1-1 fix -- _world_position
        # only ever read properties["position"], so a node Godot's editor
        # re-saved as transform = Transform3D(...) (identity basis,
        # translation-only, exactly what a real PackedScene.pack() re-save
        # produces) silently flattened to (0, 0, 0) instead of its real
        # authored position.
        scene = _parse_scene(
            FIXTURE_ROOT / "traversal_marker_transform_form.tscn"
        )
        rail = next(node for node in scene.nodes if node.name == "Rail")
        endpoints = _path_endpoints(scene, rail)

        self.assertIsNotNone(endpoints)
        assert endpoints is not None
        start, finish = endpoints
        self.assertEqual(start, (0.0, 0.0, 50.0))
        self.assertEqual(finish, (0.0, 0.0, -50.0))

    def test_parser_fails_loudly_on_an_unrecognized_scene_section(
        self,
    ) -> None:
        # R2: the sibling lint_level_authoring.py raises loudly on a
        # scene section it has no rule for (G13/N3) instead of silently
        # dropping it; this lint's own parser had no such check at all --
        # an ordinary editor-authored [connection ...] section (created
        # the instant anyone wires a signal through the Node dock instead
        # of in code) parsed with no error and no finding.
        with self.assertRaises(ValueError) as raised:
            find_authoring_violations(
                FIXTURE_ROOT / "traversal_connection_section_bad.tscn"
            )

        self.assertIn("connection", str(raised.exception))
        self.assertIn(
            "unrecognized scene section",
            str(raised.exception),
        )


if __name__ == "__main__":
    unittest.main()
