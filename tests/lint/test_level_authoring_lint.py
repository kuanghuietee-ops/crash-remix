import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.lint_level_authoring import (
    CHASE_START_GAP_RULE,
    CHECKPOINT_OFF_SPINE_RULE,
    CHECKPOINT_PROGRESSION_RULE,
    CHECKPOINT_SPACING_RULE,
    CRATE_AUTHORING_RULE,
    CRATE_ID_RULE,
    REQUIRED_JUMP_RULE,
    SPAWN_FLOOR_RULE,
    SPINE_ORDER_RULE,
    TIME_CRATE_RULE,
    WUMPA_TOTAL_RULE,
    _flatten_scene,
    find_authoring_violations,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = REPO_ROOT / "tests" / "fixtures"


class LevelAuthoringLintTests(unittest.TestCase):
    def test_chase_path_without_start_gap_fires_its_rule(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_chase_start_gap_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHASE_START_GAP_RULE],
        )
        self.assertIn("boulder_start_gap_m", findings[0].detail)
        self.assertIn(
            "4.500m",
            findings[0].detail,
            "the lint must measure the leading collision face, not center",
        )

    def test_checkpoint_gap_fires_the_spacing_rule(self) -> None:
        self.assertEqual(
            self._rules("level_checkpoint_gap_bad.tscn"),
            [CHECKPOINT_SPACING_RULE],
        )

    def test_spine_with_fewer_than_two_markers_fires_the_spacing_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_spine_too_short_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_SPACING_RULE],
        )
        self.assertIn(
            "at least two ordered Spine Marker3D nodes",
            findings[0].detail,
        )

    def test_nonpositive_design_pace_fires_the_spacing_rule(
        self,
    ) -> None:
        self.assertEqual(
            self._rules("level_zero_pace_bad.tscn"),
            [CHECKPOINT_SPACING_RULE],
        )

    def test_zero_length_spine_fires_the_spacing_rule(self) -> None:
        self.assertEqual(
            self._rules("level_spine_zero_length_bad.tscn"),
            [CHECKPOINT_SPACING_RULE],
        )

    def test_final_checkpoint_linking_forward_fires_progression_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_final_link_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_PROGRESSION_RULE],
        )
        self.assertIn(
            "final checkpoint 20 must not link to checkpoint 10",
            findings[0].detail,
        )

    def test_editor_transform_form_drives_checkpoint_distance(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_transform_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_SPACING_RULE],
        )
        self.assertIn("88.889s", findings[0].detail)

    def test_spine_stopping_short_of_the_finish_still_fires_spacing(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_spine_extent_gap_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_SPACING_RULE],
        )
        self.assertIn("88.889s", findings[0].detail)

    def test_checkpoint_far_off_the_spine_fires_its_own_rule(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_off_spine_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_OFF_SPINE_RULE],
        )
        self.assertIn("Sidetrack", findings[0].detail)

    def test_spine_marker_declared_out_of_spatial_order_fires_its_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_spine_order_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [SPINE_ORDER_RULE],
        )
        self.assertIn("Doubleback", findings[0].detail)
        self.assertIn("Overshoot", findings[0].detail)

    def test_checkpoint_links_must_follow_spatial_route_order(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_checkpoint_progression_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CHECKPOINT_PROGRESSION_RULE],
        )
        self.assertIn("checkpoint 2 links to 2", findings[0].detail)
        self.assertIn("next spatial checkpoint is 1", findings[0].detail)

    def test_flatten_composes_transform_basis_rotation_and_scale(
        self,
    ) -> None:
        nodes = _flatten_scene(
            FIXTURE_ROOT / "level_transform_hierarchy.tscn",
            REPO_ROOT,
        )
        positions = {
            node.path: node.world_position
            for node in nodes
            if node.node_type == "Marker3D"
        }

        expected = {
            "TransformParent/TransformChild": (10.0, 2.0, 2.0),
            "BasisParent/BasisChild": (10.0, 0.0, 7.0),
            "RotationParent/RotationChild": (10.0, 0.0, 8.0),
            "ScaleParent/ScaleChild": (12.0, 3.0, 19.0),
            "MixedRotationParent/MixedRotationChild": (
                11.135776,
                1.591050,
                23.190387,
            ),
        }
        self.assertEqual(set(positions), set(expected))
        for path, expected_position in expected.items():
            for actual, authored in zip(
                positions[path],
                expected_position,
            ):
                self.assertAlmostEqual(actual, authored, places=5)

    def test_nested_crate_total_fires_the_authoring_rule(self) -> None:
        self.assertEqual(
            self._rules("level_crate_count_bad.tscn"),
            [CRATE_AUTHORING_RULE],
        )

    def test_wumpa_total_must_match_authored_scene_rewards(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_wumpa_total_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [WUMPA_TOTAL_RULE],
        )
        self.assertIn("authored wumpa=7", findings[0].detail)
        self.assertIn("LevelMeta.wumpa_total=6", findings[0].detail)

    def test_segment_container_cannot_satisfy_crate_membership(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_segment_container_membership_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CRATE_AUTHORING_RULE],
        )
        self.assertIn("ContainerClaim", findings[0].detail)
        self.assertIn(
            "per-segment normal crate sum=1",
            findings[0].detail,
        )

    def test_crate_must_match_exactly_one_concrete_segment(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_repeated_segment_membership_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CRATE_AUTHORING_RULE],
        )
        self.assertIn(
            "per-segment normal crate sum=0",
            findings[0].detail,
        )

    def test_required_jump_fires_the_depression_rule(self) -> None:
        self.assertEqual(
            self._rules("level_required_jump_bad.tscn"),
            [REQUIRED_JUMP_RULE],
        )

    def test_editor_transform_form_drives_jump_depression(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_transform_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("9.486 degrees", findings[0].detail)

    def test_jump_depression_uses_camera_rail_anchor(self) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_rail_anchor_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("14.801 degrees", findings[0].detail)

    def test_jump_depression_uses_camera_corridor_alignment(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_required_jump_corridor_alignment_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("14.907 degrees", findings[0].detail)

    def test_wall_run_camera_mode_cannot_bypass_jump_depression(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_wall_run_required_jump_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("3.302 degrees", findings[0].detail)

    def test_overlapping_regions_are_blended_like_the_runtime_camera(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_required_jump_overlap_blend_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn("7.306 degrees", findings[0].detail)

    def test_required_jump_missing_a_child_marker_fires_its_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT
            / "level_required_jump_missing_children_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn(
            "needs direct Takeoff and Landing Marker3D children",
            findings[0].detail,
        )

    def test_required_jump_with_no_enclosing_region_fires_its_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_no_region_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn(
            "is not enclosed by one camera region",
            findings[0].detail,
        )

    def test_required_jump_with_no_usable_rail_fires_its_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_required_jump_no_rail_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [REQUIRED_JUMP_RULE],
        )
        self.assertIn(
            "has no usable CameraRailController Rail",
            findings[0].detail,
        )

    def test_crate_with_no_authored_id_fires_the_identity_rule(
        self,
    ) -> None:
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_crate_missing_id_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [CRATE_ID_RULE],
        )
        self.assertIn(
            "missing/invalid crate_id",
            findings[0].detail,
        )

    def test_time_crate_outside_relic_group_fires_its_rule(self) -> None:
        self.assertEqual(
            self._rules("level_time_crate_outside_relic_bad.tscn"),
            [TIME_CRATE_RULE],
        )

    def test_time_crate_does_not_inherit_parent_group(self) -> None:
        self.assertEqual(
            self._rules("level_time_crate_parent_group_bad.tscn"),
            [TIME_CRATE_RULE],
        )

    def test_duplicate_crate_id_fires_the_identity_rule(self) -> None:
        self.assertEqual(
            self._rules("level_duplicate_crate_id_bad.tscn"),
            [CRATE_ID_RULE],
        )

    def test_lint_passes_an_empty_level_set(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            self.assertEqual(
                find_authoring_violations(
                    Path(temporary_directory)
                ),
                [],
            )

    def test_scan_root_fails_closed_when_scenes_levels_does_not_resolve(
        self,
    ) -> None:
        # R11: P1-10's fix was only ever proven for the recursion half
        # (rglob vs glob); the scan-root PATH STRING half ("levels") was
        # unprotected -- sabotaging it (e.g. to "levelz") leaves
        # scenes/levels unresolved, and the old fallback silently widened
        # the scan to the whole tree instead of failing. That "safety"
        # was a coincidence of the broad fallback (real level content
        # still happened to be nested somewhere underneath), not a
        # verified mechanism, and it let unrelated content (e.g.
        # addons/gut/**) reach rules it was never meant to be checked
        # against. A scenes/ tree that exists but has no levels/ child
        # must fail loudly instead of silently scanning something else.
        with tempfile.TemporaryDirectory() as temporary_directory:
            sandbox_root = Path(temporary_directory)
            unrelated_root = sandbox_root / "scenes" / "segments"
            unrelated_root.mkdir(parents=True)
            (unrelated_root / "unrelated.tscn").write_text(
                "\n".join(
                    [
                        "[gd_scene load_steps=1 format=3]",
                        "",
                        "[node name=\"Unrelated\" type=\"Node3D\"]",
                    ]
                ),
                encoding="utf-8",
            )

            with self.assertRaises(ValueError) as raised:
                find_authoring_violations(sandbox_root)

            self.assertIn("scenes", str(raised.exception))
            self.assertIn("levels", str(raised.exception))

    def test_scan_root_fails_closed_on_an_empty_levels_directory(
        self,
    ) -> None:
        # A real scenes/levels/ directory that resolves but contains zero
        # scenes is just as silently-wrong a signal as a scan root that
        # fails to resolve at all -- fail closed instead of reporting
        # zero violations for zero scanned files.
        with tempfile.TemporaryDirectory() as temporary_directory:
            sandbox_root = Path(temporary_directory)
            (sandbox_root / "scenes" / "levels").mkdir(parents=True)

            with self.assertRaises(ValueError) as raised:
                find_authoring_violations(sandbox_root)

            self.assertIn("levels", str(raised.exception))

    def test_collectible_level_without_meta_still_fires(self) -> None:
        self.assertEqual(
            self._rules("levels/level_no_meta_bad.tscn"),
            [CRATE_AUTHORING_RULE],
        )

    def test_real_n_sanity_beach_level_passes_the_authoring_lint(
        self,
    ) -> None:
        level_path = (
            REPO_ROOT
            / "scenes"
            / "levels"
            / "wr1_n_sanity_beach.tscn"
        )
        self.assertTrue(level_path.is_file())
        self.assertEqual(
            find_authoring_violations(level_path),
            [],
        )

    def test_real_boulders_level_passes_the_authoring_lint(
        self,
    ) -> None:
        level_path = (
            REPO_ROOT
            / "scenes"
            / "levels"
            / "wr1_boulders.tscn"
        )
        self.assertTrue(level_path.is_file())
        self.assertEqual(
            find_authoring_violations(level_path),
            [],
        )

    def test_spawn_with_no_authored_floor_beneath_it_fires_its_rule(
        self,
    ) -> None:
        # R9: P0-2's fix was a single coordinate correction with no
        # generalized guard -- nothing asserted that floor exists under an
        # authored spawn, so a future level could silently reintroduce the
        # exact "spawn over a hole" shape. This fixture authors a Player
        # with no GrayboxPlatform anywhere in the scene at all.
        findings = find_authoring_violations(
            FIXTURE_ROOT / "level_spawn_over_a_hole_bad.tscn"
        )

        self.assertEqual(
            [finding.rule for finding in findings],
            [SPAWN_FLOOR_RULE],
        )
        self.assertIn("no authored GrayboxPlatform", findings[0].detail)

    def test_warp_room_is_not_misclassified_as_a_collectible_level(
        self,
    ) -> None:
        hub_path = (
            REPO_ROOT
            / "scenes"
            / "levels"
            / "warp_room_1.tscn"
        )
        self.assertTrue(hub_path.is_file())
        self.assertEqual(
            find_authoring_violations(hub_path),
            [],
        )

    def test_no_argument_cli_recursively_scans_nested_level_scenes(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repo_root = Path(temporary_directory)
            (repo_root / "scripts").mkdir()
            shutil.copy2(
                REPO_ROOT / "scripts" / "lint_level_authoring.py",
                repo_root / "scripts" / "lint_level_authoring.py",
            )
            # R2: lint_level_authoring.py's low-level parsing primitives
            # (transform/vector parsing, known-vs-inert scene section
            # classification) now live in a small shared module so this
            # lint's sibling (lint_traversal_authoring.py) cannot drift
            # out of sync with them again -- this sandboxed mini-repo
            # needs its own copy for the subprocess CLI run below to
            # import successfully.
            shutil.copy2(
                REPO_ROOT / "scripts" / "scene_transform_parsing.py",
                repo_root / "scripts" / "scene_transform_parsing.py",
            )
            tuning_root = repo_root / "data" / "tuning"
            tuning_root.mkdir(parents=True)
            for file_name in [
                "economy.tres",
                "camera.tres",
                "move.tres",
                "chase.tres",
            ]:
                shutil.copy2(
                    REPO_ROOT / "data" / "tuning" / file_name,
                    tuning_root / file_name,
                )
            meta_root = tuning_root / "levels"
            meta_root.mkdir()
            (meta_root / "nested_bad.tres").write_text(
                "\n".join(
                    [
                        "[gd_resource load_steps=2 format=3]",
                        "",
                        (
                            "[ext_resource type=\"Script\" "
                            "path=\"res://src/tuning/level_meta.gd\" "
                            "id=\"1\"]"
                        ),
                        "",
                        "[resource]",
                        "script = ExtResource(\"1\")",
                        "crate_count = 1",
                        "wumpa_total = 0",
                        "design_pace_mps = 4.5",
                    ]
                ),
                encoding="utf-8",
            )
            level_root = (
                repo_root / "scenes" / "levels" / "warp_room_2"
            )
            level_root.mkdir(parents=True)
            (level_root / "nested_bad.tscn").write_text(
                "\n".join(
                    [
                        "[gd_scene load_steps=2 format=3]",
                        "",
                        (
                            "[ext_resource type=\"Resource\" "
                            "path=\"res://data/tuning/levels/"
                            "nested_bad.tres\" id=\"1\"]"
                        ),
                        "",
                        (
                            "[node name=\"NestedBad\" "
                            "type=\"Node3D\"]"
                        ),
                        "metadata/level_meta = ExtResource(\"1\")",
                    ]
                ),
                encoding="utf-8",
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    "scripts/lint_level_authoring.py",
                ],
                cwd=repo_root,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(completed.returncode, 1)
            self.assertIn(
                "scenes/levels/warp_room_2/nested_bad.tscn",
                completed.stdout,
            )
            self.assertIn(
                CHECKPOINT_SPACING_RULE,
                completed.stdout,
            )

    def test_parser_fails_loudly_on_an_unrecognized_scene_section(
        self,
    ) -> None:
        with self.assertRaises(ValueError) as raised:
            find_authoring_violations(
                FIXTURE_ROOT / "level_unclassifiable_section_bad.tscn"
            )

        self.assertIn("wholly_unrecognized_section", str(raised.exception))
        self.assertIn(
            "unrecognized scene section",
            str(raised.exception),
        )

    def test_editable_children_directive_is_recognized_as_inert(
        self,
    ) -> None:
        # [editable path="..."] only toggles the Godot editor's
        # "Editable Children" display for an instanced sub-scene node
        # (Node.set_editable_instance / is_editable_instance in
        # Godot 4.7.1's own scene/main/node.cpp) so a designer can see
        # and tweak the instance's internal nodes in the scene tree
        # dock. It carries no geometry, crate, checkpoint, or camera
        # data of its own for the authoring rules to act on, and
        # PackedScene instancing applies every override line in the
        # file unconditionally regardless of this flag. The real
        # scenes/segments/seg_phase_gauntlet.tscn authors four of
        # these; the lint must parse it cleanly, not choke on it, once
        # Task 17 reconnects that content (see N3).
        segment_path = (
            REPO_ROOT
            / "scenes"
            / "segments"
            / "seg_phase_gauntlet.tscn"
        )
        self.assertTrue(segment_path.is_file())
        self.assertEqual(
            find_authoring_violations(segment_path),
            [],
        )

    def test_parser_fails_loudly_on_a_line_it_cannot_classify(
        self,
    ) -> None:
        with self.assertRaises(ValueError) as raised:
            find_authoring_violations(
                FIXTURE_ROOT / "level_unclassifiable_line_bad.tscn"
            )

        self.assertIn("mystery_field", str(raised.exception))
        self.assertIn("unclassifiable line", str(raised.exception))

    def test_cli_fails_closed_for_an_unresolvable_requested_path(
        self,
    ) -> None:
        missing_path = (
            FIXTURE_ROOT / "missing_level_requested_by_operator.tscn"
        )
        self.assertFalse(missing_path.exists())

        completed = subprocess.run(
            [
                sys.executable,
                "scripts/lint_level_authoring.py",
                str(missing_path),
            ],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(str(missing_path), completed.stderr)
        self.assertIn("does not exist", completed.stderr)

    def _rules(self, fixture_name: str) -> list[str]:
        findings = find_authoring_violations(
            FIXTURE_ROOT / fixture_name
        )
        return [finding.rule for finding in findings]


if __name__ == "__main__":
    unittest.main()
