import unittest
from pathlib import Path

from scripts.kit_material_routing import (
    ANIMATED_PIECES,
    FOLIAGE_MATERIAL,
    STATIC_BY_DESIGN,
    material_for,
    material_names,
    material_path,
)
from scripts.route_kit_materials import (
    material_ids,
    mesh_ids,
    route_scene_text,
    scene_paths,
)

REPO_ROOT = Path(__file__).resolve().parents[2]


class RoutingTableTests(unittest.TestCase):
    def test_every_routed_material_exists_on_disk(self) -> None:
        # A routing table pointing at a missing .tres fails at load time in a
        # level, not here, which is the worst place to find out.
        for name in material_names():
            relative = material_path(name).removeprefix("res://")

            self.assertTrue(
                (REPO_ROOT / relative).is_file(),
                f"{name} is routed but {relative} does not exist",
            )

    def test_every_routed_piece_exists_in_the_kit(self) -> None:
        mesh_dir = REPO_ROOT / "assets" / "models" / "kits" / "mesh"
        for piece in ANIMATED_PIECES:
            self.assertTrue(
                (mesh_dir / f"{piece}.res").is_file(),
                f"{piece} is routed but is not in the kit",
            )

    def test_static_pieces_are_not_also_routed(self) -> None:
        overlap = set(STATIC_BY_DESIGN) & set(ANIMATED_PIECES)

        self.assertEqual(overlap, set(), f"{overlap} are both animated and static")

    def test_static_pieces_carry_a_stated_reason(self) -> None:
        for piece, reason in STATIC_BY_DESIGN.items():
            self.assertTrue(reason.strip(), f"{piece} needs a reason it stays still")

    def test_the_plant_family_is_routed_to_the_foliage_material(self) -> None:
        for piece in ("palm_tall_a", "fern_cluster_a", "jungle_tree_b", "grass_patch_a"):
            self.assertEqual(material_for(piece), FOLIAGE_MATERIAL, piece)

    def test_dead_wood_does_not_sway(self) -> None:
        # Swaying a beached log reads as a physics bug, not as wind.
        for piece in ("driftwood_a", "coconut_cluster_a"):
            self.assertIsNone(material_for(piece), piece)


class SceneRewritingTests(unittest.TestCase):
    SCENE = (
        "[gd_scene load_steps=2 format=3]\n\n"
        '[ext_resource type="Mesh" '
        'path="res://assets/models/kits/mesh/palm_tall_a.res" id="1_palm"]\n\n'
        '[node name="Root" type="Node3D"]\n\n'
        '[node name="Palm" type="MeshInstance3D" parent="."]\n'
        'mesh = ExtResource("1_palm")\n'
    )

    def test_a_routed_piece_gets_an_override(self) -> None:
        routed, added = route_scene_text(self.SCENE)

        self.assertEqual(added, 1)
        self.assertIn("material_override = ExtResource(", routed)
        self.assertIn(FOLIAGE_MATERIAL, routed)

    def test_routing_is_idempotent(self) -> None:
        once, first = route_scene_text(self.SCENE)
        twice, second = route_scene_text(once)

        self.assertEqual(second, 0, "a second run must change nothing")
        self.assertEqual(once, twice)

    def test_load_steps_is_kept_honest(self) -> None:
        routed, _ = route_scene_text(self.SCENE)

        self.assertIn("load_steps=3", routed)

    def test_an_unrouted_piece_is_left_alone(self) -> None:
        scene = self.SCENE.replace("palm_tall_a", "driftwood_a").replace(
            "1_palm", "1_drift"
        )

        routed, added = route_scene_text(scene)

        self.assertEqual(added, 0)
        self.assertEqual(routed, scene)

    def test_an_existing_override_is_not_replaced(self) -> None:
        # Hand-authored intent wins; this script only fills gaps.
        scene = self.SCENE + 'material_override = ExtResource("9_custom")\n'

        _, added = route_scene_text(scene)

        self.assertEqual(added, 0)

    def test_one_material_resource_serves_many_instances(self) -> None:
        scene = self.SCENE + (
            '\n[node name="Palm2" type="MeshInstance3D" parent="."]\n'
            'mesh = ExtResource("1_palm")\n'
        )

        routed, added = route_scene_text(scene)

        self.assertEqual(added, 2)
        self.assertEqual(
            len(material_ids(routed)),
            1,
            "the material must be declared once and shared, not per instance",
        )


class RepositoryStateTests(unittest.TestCase):
    def test_no_scene_in_the_repo_has_stale_routing(self) -> None:
        # The lint proper. If this fails, run:
        #   python3 scripts/route_kit_materials.py
        stale: list[str] = []
        for path in scene_paths(REPO_ROOT):
            _, added = route_scene_text(path.read_text(encoding="utf-8"))
            if added:
                stale.append(f"{path.name} ({added} unrouted)")

        self.assertEqual(stale, [], f"stale kit material routing: {stale}")

    def test_the_sea_actually_reached_the_beach(self) -> None:
        # The single most visible instance in the game: if routing silently
        # missed it, the ocean is a still photograph.
        text = (REPO_ROOT / "scenes/segments/beach_landing.tscn").read_text(
            encoding="utf-8"
        )
        pieces = set(mesh_ids(text).values())

        self.assertIn("water_sea_tile", pieces, "beach_landing should hold the sea")
        self.assertIn(
            "M_beach_kit_sea",
            set(material_ids(text)),
            "the sea material must be declared in the scene that holds the sea",
        )
