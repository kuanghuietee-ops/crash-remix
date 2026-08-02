"""Build Papu Papu's seated racing variant for Godot.

R8 Task 5 (characters/select/classes): CTR's kart mount only ever looks for
one hardcoded seated-riding clip -- KartController.SEAT_ANIMATION_CLIP
(src/racing/kart/kart_controller.gd), the literal StringName
``A_crash_hog_ride`` Crash's own SK_crash.glb already carries (see
create_crash_likeness.py's own HOG_RIDE_ACTION_NAME). That is the ONLY
mechanism the R6 seated precedent actually supports for a model whose rig
does not share Crash's/the lab assistant's Rigify ``DEF-*`` deform-bone
names (see kart_controller.gd's own SEAT_POSE_BONE_* doc: "both character
rigs share this exact DEF-* naming"). Papu's own rig (build_rig() in
create_papu.py, reused verbatim below) is a compact CUSTOM skeleton with
plain bone names ("thigh.L", not "DEF-thigh.L") -- mounting him through
kart_controller.gd's OTHER path, the runtime Skeleton3D bone-pose fallback
(_apply_static_seat_pose(), the lab assistant's own path), would silently
skip every SEAT_POSE_BONE_* lookup (Skeleton3D.find_bone() fails closed,
returns -1, no-ops) and leave him standing, only translated down -- broken,
not seated. Baking a real ``A_crash_hog_ride`` action into his own GLB, the
same clip-presence check _play_seat_pose() already uses for Crash, is the
only one of the two mechanisms that actually poses him. This module does
NOT invent a second seating mechanism; it feeds the existing one a second
model.

Kept a SIBLING of create_papu.py rather than a modification to it: the
platformer's own SK_papu.glb (assets/models/bosses/SK_papu.glb) ships
today with six boss-fight actions (idle/taunt/slam/hit/phase/defeat) that
mean nothing to a kart race, and this script's own single racing-relevant
action would be dead weight on that shipped asset. Both scripts import the
SAME build_rig()/build_parts() from create_papu.py (loaded here via
importlib, the identical "reuse a sibling script's own geometry functions
without running its own main()" pattern create_crash_likeness.py already
uses on create_lab_assistant.py) -- the mesh, material, and skeleton this
script exports are BYTE-FOR-BYTE the same geometry as the platformer boss,
just carrying one additional action instead of his six. No re-sculpt, no
re-paint: this is posing, not a new face.

Ships to assets/models/bosses/, not assets/models/characters/, despite
being racing-facing: scripts/lint_art_budgets.py's CATEGORY_BY_DIRECTORY
maps a GLB's triangle budget purely off its PARENT DIRECTORY (see that
module's own doc), and Papu's boss-scale mesh (15000-25000 triangles,
validate_asset()'s own band below) already exceeds the "characters"
directory's hero budget (10000-12000, data/tuning/art_budget.tres) by
construction -- shrinking the geometry to fit would be exactly the
re-sculpt this task's own STOP rule and the plan's YAGNI note forbid.
"bosses" keeps him in the SAME budget band as the platformer asset he is
posed from, the only directory that is honest about what he already is.

Run from the repository root:

    blender --background --factory-startup \
        --python scripts/blender/create_papu_seated.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import bpy

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from character_asset_common import (  # noqa: E402
    begin_action,
    configure_metric_scene,
    create_preview,
    create_vertex_material,
    finish_action,
    join_and_skin,
    key_pose,
    reset_scene,
    save_source_and_export,
    validate_asset,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_NAME = "SK_papu_seated"
SOURCE_PATH = REPO_ROOT / "build/art-source/SK_papu_seated.blend"
EXPORT_PATH = REPO_ROOT / "assets/models/bosses/SK_papu_seated.glb"
PREVIEW_PATH = REPO_ROOT / "build/art-previews/SK_papu_seated.png"

## The literal clip name kart_controller.gd's SEAT_ANIMATION_CLIP checks
## for -- see this module's own doc above. Not a "papu" name: the mount
## code matches this exact StringName regardless of which driver's model
## carries it (Crash's own doc: "same StringName, reused verbatim, not
## re-authored" -- this script follows that identical convention one
## character further, the mount code was already written to support
## exactly this reuse).
SEATED_ACTION_NAME = "A_crash_hog_ride"
ACTION_NAMES = (SEATED_ACTION_NAME,)
SEATED_LAST_FRAME = 25

## Required bones for validate_asset(), copied from create_papu.py's own
## main() call -- the rig is the identical build_rig() output, so the same
## set is guaranteed present.
REQUIRED_BONES = (
    "pelvis",
    "spine",
    "chest",
    "head",
    "upper_arm.L",
    "upper_arm.R",
    "forearm.L",
    "forearm.R",
    "thigh.L",
    "thigh.R",
    "staff",
)


def load_papu_base():
    """Load create_papu.py as a plain module, never running its own main().

    Mirrors create_crash_likeness.py's load_geometry_helpers() on create_
    lab_assistant.py exactly: spec_from_file_location() under a name other
    than "__main__" so create_papu.py's own ``if __name__ == "__main__":
    main()`` guard never fires, while build_rig()/build_parts()/ASSET_KEY
    stay callable off the loaded module.
    """
    spec = importlib.util.spec_from_file_location(
        "papu_base",
        SCRIPT_DIR / "create_papu.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load create_papu.py as a module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


## Seated-in-kart bend for legs/arms/staff only -- head, jaw, neck, and
## spine are left at their platformer bind-pose rotation (never keyed to
## a non-identity value anywhere in this action) so his face and torso
## silhouette stay pixel-for-pixel the likeness the operator already
## accepted. ONE exception, and it is deliberate, not an oversight:
## "chest" gets a single barely-perceptible +1.5-degree X-axis tilt at
## frame 13 only (create_seated()'s own mid_pose override below), back to
## 0 at frames 1 and 25 -- part of the mid-cycle breathing lift alongside
## the small upper_arm adjustment and root lift there. 1.5 degrees on one
## axis, held for one frame of a 25-frame loop, was visually confirmed at
## frame 13 not to move the torso silhouette during this task's likeness
## review (see task-5-report.md's "Likeness judgment" section) -- every
## OTHER bone not listed in SEATED_POSE keeps the strict never-keyed
## discipline this comment describes. Every keyframe below re-states this
## FULL dict rather than a per-frame delta: key_pose() zeroes any bone
## omitted from its own rotations argument at THAT call (see its own doc
## in character_asset_common.py), so a frame that only listed what changed
## would snap the omitted bones back to a standing bind pose on every
## keyframe, breaking the seated read exactly on the frames meant to hold
## it.
SEATED_POSE = {
    # Hip flexion brings the thigh from its hanging bind-pose orientation
    # up toward horizontal -- the same X-axis-is-flex/extend convention
    # create_papu.py's own create_slam()/create_defeat() already
    # established for this exact bone pair (thigh.L/R X-only rotations
    # there), carried to the full ~90 degrees a seated hip needs instead
    # of those attacks' partial crouch. Y/Z add a small outward spread so
    # the knees clear the belly rather than colliding through it.
    "thigh.L": (-82.0, -20.0, -14.0),
    "thigh.R": (-82.0, 20.0, 14.0),
    # Knee flexion folds the shin back down in front of the seat -- same
    # X-axis convention and sign create_slam()'s own shin.L/R keys use,
    # carried past that pose's partial +25 to a full seated fold.
    "shin.L": (92.0, 0.0, 0.0),
    "shin.R": (92.0, 0.0, 0.0),
    # Arms rest low and slightly forward, as if braced on the kart's own
    # sides -- deliberately smaller angles than any combat action (create_
    # taunt/create_slam swing 25-80 degrees); a seated resting arm reads
    # as relaxed, not a boss mid-attack.
    "upper_arm.L": (28.0, 0.0, -18.0),
    "upper_arm.R": (28.0, 0.0, 18.0),
    "forearm.L": (38.0, 0.0, 0.0),
    "forearm.R": (38.0, 0.0, 0.0),
    # The staff's own bind pose stands it nearly vertical off his hip
    # (build_rig()'s own staff bone doc) -- wide enough unposed to be the
    # single largest contributor to his standing AABB width. Leaning it
    # back and inward keeps it reading as "held while seated" without
    # sweeping out past the kart's own body width.
    "staff": (-18.0, 0.0, -12.0),
}


def create_seated(rig: bpy.types.Object) -> bpy.types.Action:
    action = begin_action(rig, SEATED_ACTION_NAME, SEATED_LAST_FRAME)
    key_pose(rig, 1, SEATED_POSE)
    # A barely-perceptible mid-cycle breathing lift -- chest/arms only,
    # legs and staff held exactly at SEATED_POSE so the seated silhouette
    # never wavers -- keeps the loop from reading as a single frozen
    # frame without risking a pose big enough to read as a new likeness.
    mid_pose = dict(SEATED_POSE)
    mid_pose["chest"] = (1.5, 0.0, 0.0)
    mid_pose["upper_arm.L"] = (30.0, 0.0, -18.0)
    mid_pose["upper_arm.R"] = (30.0, 0.0, 18.0)
    key_pose(rig, 13, mid_pose, {"root": (0.0, 0.0, 0.01)})
    key_pose(rig, SEATED_LAST_FRAME, SEATED_POSE)
    return finish_action(action, "ride", True)


def create_actions(rig: bpy.types.Object) -> dict[str, bpy.types.Action]:
    return {SEATED_ACTION_NAME: create_seated(rig)}


def main(
    *,
    export_path: Path = EXPORT_PATH,
    source_path: Path = SOURCE_PATH,
    preview_path: Path = PREVIEW_PATH,
    render_preview: bool = True,
) -> None:
    """Build and export the seated GLB.

    The three ``*_path`` keywords and ``render_preview`` exist for exactly
    one caller outside ``__main__`` below: tests/lint/test_papu_seated_
    builder.py's own determinism test, which needs two independent builds
    written to a scratch directory rather than the real committed GLB (a
    test must never mutate tracked repo content -- CLAUDE.md's "never write
    to live state from tests" rule applies just as much to a committed
    asset as to trading state) and skips the EEVEE preview render (slow,
    GPU-dependent, and irrelevant to whether the EXPORTED glTF is stable).
    Every default reproduces this module's own unparameterized CLI
    behaviour exactly -- ``python create_papu_seated.py`` still writes the
    real shipped paths and still renders the preview, unchanged.
    """
    papu_base = load_papu_base()
    reset_scene()
    configure_metric_scene()
    material = create_vertex_material(papu_base.MATERIAL_NAME, 0.82)
    rig = papu_base.build_rig()
    character = join_and_skin(
        ASSET_NAME,
        papu_base.ASSET_KEY,
        "boss",
        papu_base.build_parts(material),
        material,
        rig,
        ACTION_NAMES,
    )
    actions = create_actions(rig)
    vertices, faces, triangles = validate_asset(
        asset_name=ASSET_NAME,
        character=character,
        rig=rig,
        actions=actions,
        action_names=ACTION_NAMES,
        required_bones=REQUIRED_BONES,
        minimum_triangles=15000,
        maximum_triangles=25000,
        minimum_colors=10,
    )
    save_source_and_export(
        source_path=source_path,
        export_path=export_path,
        character=character,
        rig=rig,
    )
    if render_preview:
        create_preview(
            preview_path=preview_path,
            character=character,
            rig=rig,
            target=(0.0, -0.15, 1.0),
            camera_location=(3.1, -4.9, 2.1),
            floor_size=7.0,
            poses=((SEATED_ACTION_NAME, 1, "A_papu_seated_pose.png"),),
            key_color=(1.0, 0.50, 0.22),
        )
    print(
        "PAPU_SEATED_BUILD_OK "
        f"name={ASSET_NAME} vertices={vertices} faces={faces} "
        f"triangles={triangles} materials=1 rig=custom_papu "
        f"animations={len(actions)}"
    )
    print(f"PAPU_SEATED_SOURCE={source_path}")
    print(f"PAPU_SEATED_GLB={export_path}")
    print(f"PAPU_SEATED_PREVIEW={preview_path}")


if __name__ == "__main__":
    main()
