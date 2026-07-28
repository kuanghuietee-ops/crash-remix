# Phase 1 Art Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the four code-side units of `2026-07-27-phase1-art-pivot-design.md` §4 — an import/export contract, a per-asset budget lint, a look-dev scene, and on-device budget telemetry — so they are all in place *before* the operator models the crate family (§9.2 rung 1).

**Architecture:** Nothing here is a new subsystem. Each unit slots into machinery the repo already has: the budget lint joins the existing pre-commit lint family and reuses `scripts/scene_transform_parsing.py`; the thresholds live in a typed `Resource` under `data/tuning/` like every other number in this project; the look-dev scene reaches the device through the existing `scripts/deploy_android.sh`; and the telemetry extends `src/debug/perf_readout.gd`, which already mounts in `scenes/main.tscn` and already has a `rendering_info_source` test seam. All of it is valid against graybox and none of it depends on what the art turns out to look like.

**Tech Stack:** Godot 4.7.1 (Mobile/Vulkan renderer, typed GDScript), GUT for engine-side tests, Python 3 + `unittest` for the lint family, glTF 2.0 binary (`.glb`) as the Blender→Godot interchange format.

## Global Constraints

Copied verbatim from `2026-07-23-crash-remix-design.md` §9.4 and the repo `CLAUDE.md`. Every task's requirements implicitly include this section.

- **No gameplay numbers in code (repo rule 1, hard).** Every threshold in this plan lives in a typed `Resource` under `data/tuning/`. Numeric literals in `src/gameplay/**` are banned apart from `0`, `1` and `-1`.
- **Per-asset triangle caps:** Crash 10–12k tris; enemies 3–6k; bosses 15–25k.
- **Whole-frame budgets:** ≤120 draw calls typical / 180 peak; ≤150k visible tris typical / 250k peak. These are *frame* budgets and can only be checked in an assembled scene — never on a lone mesh.
- **Textures:** 1–2×2048 atlases + trim sheet per kit, ASTC.
- **Renderer:** Mobile/Vulkan. NOT Forward+, NOT Compatibility.
- **Gates are human-only (repo rule 3, hard).** Nothing in this plan marks, infers or proceeds past Gate F, Gate F2 or the likeness gate.
- **Never claim a thing works without having run it (repo rule 4).** Report test counts. Report what you did not test.
- **Assets:** nothing extracted from any shipped Crash game, ever. The repo is public; this is the project's only legal defence.
- **Shared tree.** Stage explicit paths only. Never `git add -A`, never `git checkout -- <path>`.
- **Baseline at plan time (2026-07-28, `wave-e-integration`):** Python suite **81 tests green**. Re-run rather than quoting this; later tasks add to it.

## Prior art to imitate rather than reinvent

- `scripts/lint_gameplay_numbers.py` — the smallest lint. Copy its shape: pure functions, a `main(argv)` returning an int, and a fail-closed exception (`UnscannableSourceError`) when the scan cannot prove it read what it claimed to.
- `scripts/lint_level_authoring.py:1782` — the R11 precedent: a scan root that exists but contains zero files fails *closed* rather than reporting zero violations. Task 6 deliberately departs from this (see its rationale) because zero models is the legitimate starting state.
- `src/debug/perf_readout.gd:80` — the `rendering_info_source` seam. Headless rendering counters are all zero and would agree with any mistake, so tests substitute a source that answers each metric id differently.
- `tests/config/test_project_configuration.gd:12` — how project settings get asserted.

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `docs/art/import-export-contract.md` | The human contract: Blender-side units/axis/scale/naming/material rules and the Godot-side import expectations. |
| `src/tuning/art_budget_tuning.gd` | Typed `Resource` holding every per-asset cap, frame budget and texture rule. |
| `data/tuning/art_budget.tres` | The authored values. Standalone, following the `LevelMeta` precedent — see Task 3's rationale for why it is not a `TuningService` section. |
| `scripts/gltf_budget.py` | Pure `.glb` parsing: JSON chunk extraction and triangle counting. No Godot, no third-party deps. |
| `scripts/texture_budget.py` | Pure texture parsing: PNG dimensions, and `.import` VRAM-compression inspection. |
| `scripts/lint_art_budgets.py` | The lint proper: resolves each asset's category from its directory, applies `art_budget.tres`, fails closed on unknown categories. |
| `scenes/debug/look_dev.tscn` + `src/debug/look_dev.gd` | One asset, shipping material and lighting, turntable, budget readout. |
| `tests/lint/test_gltf_budget.py`, `tests/lint/test_texture_budget.py`, `tests/lint/test_art_budget_lint.py` | Python suites for the three modules above. |
| `tests/debug/test_look_dev.gd` | GUT suite for the look-dev controller. |

**Modified:**

| Path | Change |
|---|---|
| `scripts/scene_transform_parsing.py` | Gains the shared `assignment_values()` currently duplicated in two lints. |
| `scripts/lint_level_authoring.py`, `scripts/lint_traversal_authoring.py` | Drop their private copies, import the shared one. |
| `.githooks/pre-commit` | Runs the new lint. |
| `src/debug/perf_readout.gd` | Gains texture memory and budget-comparison output. |
| `src/debug/tuning_debug_ui.gd` + `scenes/debug/tuning_debug_ui.tscn` | Gains the debug-only entry point into look-dev. |
| `tests/config/test_project_configuration.gd` | Asserts the ASTC setting the contract depends on. |
| `tests/debug/test_perf_readout.gd` | Covers the new telemetry. |

---

### Task 1: Share the `.tres` assignment parser

`_assignment_values` is copy-pasted in both `lint_level_authoring.py:1764` and `lint_traversal_authoring.py:599`, and the new lint needs a third copy. `scripts/scene_transform_parsing.py` is already the shared home both lints import from — it owns `PROPERTY_PATTERN`, which is the regex both copies use. Move the function there.

**Files:**
- Modify: `scripts/scene_transform_parsing.py` (add after `PROPERTY_PATTERN`, line 49)
- Modify: `scripts/lint_level_authoring.py:1764-1770` (delete), plus its import block at lines 15 and 32, plus call sites at 1602, 1607, 1612, 1617, 1665
- Modify: `scripts/lint_traversal_authoring.py:599-605` (delete), plus its import block at lines 16 and 28, plus call sites at 583, 584
- Test: `tests/lint/test_scene_transform_parsing.py` (create if absent; otherwise add to it)

**Interfaces:**
- Consumes: nothing.
- Produces: `assignment_values(text: str) -> dict[str, str]` in `scripts/scene_transform_parsing.py`. Tasks 3 and 6 rely on this exact name.

- [ ] **Step 1: Write the failing test**

Create or extend `tests/lint/test_scene_transform_parsing.py`:

```python
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
```

Note the first case's `type` entry: the existing regex is line-oriented and does match inside a header line. That is pre-existing behaviour of both copies, and the callers only ever look up known property names, so the test pins the behaviour as-is rather than changing it. Do not "fix" this in this task — it would change what two working lints see.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.lint.test_scene_transform_parsing -v`
Expected: FAIL with `ImportError: cannot import name 'assignment_values'`

- [ ] **Step 3: Add the shared function**

In `scripts/scene_transform_parsing.py`, immediately after the `PROPERTY_PATTERN` definition:

```python
def assignment_values(text: str) -> dict[str, str]:
    """Return the `key = value` assignments in a .tres/.tscn body.

    Line-oriented on purpose: callers look up known property names, so a
    header line that happens to match is harmless and this stays cheap.
    """
    values: dict[str, str] = {}
    for line in text.splitlines():
        match = PROPERTY_PATTERN.match(line.strip())
        if match is not None:
            values[match.group(1)] = match.group(2).strip()
    return values
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.lint.test_scene_transform_parsing -v`
Expected: PASS

- [ ] **Step 5: Point both lints at the shared function**

In `scripts/lint_level_authoring.py` and `scripts/lint_traversal_authoring.py`, add `assignment_values` to **both** halves of the dual import shim (the bare `from scene_transform_parsing import (...)` and the `from scripts.scene_transform_parsing import (...)` fallback — both must list it, or the lint breaks depending on how it is invoked). Then delete each private `def _assignment_values` and rename its call sites.

Run this to confirm no call site was missed:

```bash
grep -rn '_assignment_values' scripts/
```

Expected: no output.

- [ ] **Step 6: Run the full Python suite**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: OK, count ≥ 83 (81 baseline + the 2 new tests). The existing `tests/lint/test_level_authoring_lint.py` and `test_traversal_authoring_lint.py` are the real regression check here — they drive the lints end to end.

- [ ] **Step 7: Commit**

```bash
git add scripts/scene_transform_parsing.py scripts/lint_level_authoring.py scripts/lint_traversal_authoring.py tests/lint/test_scene_transform_parsing.py
git commit -m "Share the .tres assignment parser across the lint family"
```

---

### Task 2: Write the import/export contract

The contract exists so an asset never arrives sideways at the wrong scale. It is a document plus one project-settings assertion — the per-asset enforcement lands in Tasks 4–6.

**One deliberate narrowing, stated rather than hidden.** Pivot design §4.1 asks for "Godot-side import presets committed to the repo". This task commits the *project-wide* settings that matter (ASTC compression, pinned and now asserted) and the rule that every per-asset `.import` sidecar is committed, but it does **not** author a `[importer_defaults]` block in `project.godot`. Those keys and their value ranges are per-importer and version-specific, and writing them from memory is precisely how a config ends up dead-wired — the failure this repo exists to prevent. The right way to add them is to set the defaults once in the Godot editor's Import dock with a real asset loaded, let the editor write the block, and commit it with a test asserting the keys. That cannot be done before the first asset exists, so it belongs to rung 1, not here. Recorded in the contract document as an open item.

**Files:**
- Create: `docs/art/import-export-contract.md`
- Modify: `tests/config/test_project_configuration.gd` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: the directory convention `assets/models/{characters,enemies,bosses,rideables,props,kits}/` that Task 6's category resolution depends on, and the `.glb` choice that Task 4 parses.

- [ ] **Step 1: Write the failing test**

Append to `tests/config/test_project_configuration.gd`:

```gdscript
## The import/export contract (docs/art/import-export-contract.md) assumes every
## texture arrives ASTC-compressed on device, which is a project-wide import
## setting rather than a per-asset one. If this flips off, every asset imported
## afterwards is silently wrong and nothing else in the pipeline notices.
func test_astc_vram_compression_is_enabled_for_imported_textures() -> void:
	assert_true(
		ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc"),
		"ASTC/ETC2 VRAM compression must stay on -- see docs/art/import-export-contract.md"
	)
```

- [ ] **Step 2: Run test to verify it fails**

Temporarily flip `textures/vram_compression/import_etc2_astc` to `false` in `project.godot`, then run:

`scripts/run_gut.sh`

Expected: this test FAILS. Restore the setting to `true` and re-run; expected PASS. Do this rather than trusting a test that has never been seen red — the setting is already `true`, so a test written against it passes for free and proves nothing.

- [ ] **Step 3: Write the contract document**

Create `docs/art/import-export-contract.md`:

```markdown
# Blender → Godot import/export contract

One documented path from `.blend` to in-game. Everything here exists so an asset
never arrives sideways, at the wrong scale, or uncompressed on device.

Enforced by `scripts/lint_art_budgets.py` where a machine can check it, and by this
document where it cannot.

## Blender side

- **Units:** Metric, unit scale 1.0. **1 Blender unit = 1 metre = 1 Godot unit.**
- **Orientation:** model facing **−Y** in Blender, which exports to **−Z forward, +Y up**
  in glTF — the axis convention Godot expects. Export with +Y up (the glTF exporter
  default); do not "correct" the axes by rotating the object.
- **Transforms:** apply all location/rotation/scale before export (`Ctrl+A → All
  Transforms`). Object scale must read 1.0/1.0/1.0. Unapplied scale is the single most
  common cause of an asset arriving at the wrong size.
- **Origin:** at the character's feet / the prop's resting contact point, centred on
  X and Z. Not at the mesh centroid.
- **Modifiers:** applied on export (`Export → Include → Apply Modifiers`).
- **Excluded from export:** cameras, lights, empties that are not bones, and anything
  on a hidden collection. Lighting is baked in Godot per §9.4; a Blender light in the
  `.glb` is noise at best.
- **Naming:**
  - `SM_<name>` — static mesh (`SM_crate_standard`)
  - `SK_<name>` — skinned mesh (`SK_crash`)
  - `A_<name>_<clip>` — animation clip (`A_crash_run`)
  - `M_<name>` — material (`M_crash_body`)
  - Lower snake case after the prefix. No spaces, no `.001` duplicate suffixes.
- **Materials:** one material slot per atlas. A character is one slot; a kit piece uses
  the kit's shared trim/atlas slot. Slot count is the draw-call multiplier, and §9.4
  allows ≤120 draw calls in a typical frame.
- **Textures:** PNG, square, power-of-two, ≤2048. Hand-painted matte per §9.3 — not
  N. Sane-style fur.

## Export

- Format: **glTF 2.0 binary (`.glb`)** — one self-contained file, no sidecar `.bin` or
  loose texture references to go missing.
- Destination decides the budget category, so put the file in the right directory:

  | Directory | Category | Cap source |
  |---|---|---|
  | `assets/models/characters/` | `hero` | §9.4: 10–12k tris |
  | `assets/models/enemies/` | `enemy` | §9.4: 3–6k tris |
  | `assets/models/bosses/` | `boss` | §9.4: 15–25k tris |
  | `assets/models/rideables/` | *unset* | §9.4 gives no figure — operator sets it |
  | `assets/models/props/` | *unset* | §9.4 gives no figure — operator sets it |
  | `assets/models/kits/` | *unset* | §9.4 gives no figure — operator sets it |

  An unset category **fails the lint closed** with the exact line to add to
  `data/tuning/art_budget.tres`. That is deliberate: §9.4 specifies per-asset caps for
  characters, enemies and bosses only, and props and kit pieces are governed by the
  whole-frame budget instead. Rather than invent a per-asset number nobody chose, the
  lint stops and asks the operator to choose one the first time such an asset lands.

## Godot side

- ASTC/ETC2 VRAM compression is on project-wide
  (`rendering/textures/vram_compression/import_etc2_astc=true`), asserted by
  `tests/config/test_project_configuration.gd`.
- The Mobile (Vulkan) renderer is pinned, asserted by the same suite.
- Godot writes a `.import` sidecar next to each asset on first import. **Commit it.**
  It carries the UID other scenes reference; without it the import is not reproducible.
- All lighting is baked (LightmapGI per segment, §9.4). Imported meshes carry no lights.

**Open item — project-wide importer defaults.** `project.godot` carries no
`[importer_defaults]` block yet, so every asset's import settings are currently
per-asset. Once the first real model and texture exist, set the defaults once in the
editor's Import dock (Import dock → set options → *Preset… → Set as Default for…*),
commit the block Godot writes, and add a test asserting the keys. Doing it before an
asset exists would mean authoring importer keys blind, which is how a config ends up
dead-wired. Until then, check each new asset's sidecar by hand against the rules above.

## Checking an asset before committing it

```bash
python3 scripts/lint_art_budgets.py            # per-asset caps, texture rules
scripts/deploy_android.sh                      # then open look-dev on the phone
```

The lint answers "is it within budget". The look-dev scene (`scenes/debug/look_dev.tscn`,
reachable from the debug drawer) answers "does it read at phone size", which is the
question that actually gets asked several hundred times.
```

- [ ] **Step 4: Create the asset directories**

The directory convention is load-bearing for Task 6's category resolution, so it must exist before an asset does:

```bash
mkdir -p assets/models/{characters,enemies,bosses,rideables,props,kits}
for d in characters enemies bosses rideables props kits; do touch "assets/models/$d/.gitkeep"; done
```

- [ ] **Step 5: Run the GUT suite**

Run: `scripts/run_gut.sh`
Expected: PASS, with one more test than the previous run. Record the count.

- [ ] **Step 6: Commit**

```bash
git add docs/art/import-export-contract.md tests/config/test_project_configuration.gd assets/models
git commit -m "Document the Blender-to-Godot import contract and pin ASTC compression"
```

---

### Task 3: The art budget resource

Every threshold the pipeline enforces, in one typed `Resource`.

**Why standalone rather than a `TuningService` section:** `TuningService.SECTION_NAMES` (`src/tuning/tuning_service.gd:4`) is the *gameplay* catalog — it drives the on-device tuning drawer, the override save/restore path, the legacy-field migration machinery and the boot fingerprint. Art budgets are none of those things: they are build-time constraints, not values anyone tunes by thumb mid-session, and folding them in would put triangle caps in the player's slider panel and move the tuning fingerprint for a change that cannot affect feel. `LevelMeta` (`src/tuning/level_meta.gd`, authored under `data/tuning/levels/*.tres`) is the existing precedent for a typed tuning resource that lives outside the catalog. Follow it.

**Files:**
- Create: `src/tuning/art_budget_tuning.gd`
- Create: `data/tuning/art_budget.tres`
- Test: `tests/tuning/test_art_budget_tuning.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: class `ArtBudgetTuning` with exported fields `hero_min_triangles`, `hero_max_triangles`, `enemy_min_triangles`, `enemy_max_triangles`, `boss_min_triangles`, `boss_max_triangles`, `max_texture_dimension_px`, `frame_draw_calls_typical`, `frame_draw_calls_peak`, `frame_triangles_typical`, `frame_triangles_peak`, and methods `max_triangles_for(category: StringName) -> int` / `min_triangles_for(category: StringName) -> int` returning `-1` for an unbudgeted category. Task 6 reads the `.tres` through Python; Task 8 loads the resource in-engine. Both depend on these exact field names.

- [ ] **Step 1: Write the failing test**

Create `tests/tuning/test_art_budget_tuning.gd`:

```gdscript
extends GutTest

const ArtBudgetTuningType := preload("res://src/tuning/art_budget_tuning.gd")
const AUTHORED_PATH := "res://data/tuning/art_budget.tres"


func test_authored_budget_matches_the_design_doc_per_asset_caps() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_not_null(budget, "art_budget.tres must load as an ArtBudgetTuning")
	assert_eq(budget.hero_min_triangles, 10000)
	assert_eq(budget.hero_max_triangles, 12000)
	assert_eq(budget.enemy_min_triangles, 3000)
	assert_eq(budget.enemy_max_triangles, 6000)
	assert_eq(budget.boss_min_triangles, 15000)
	assert_eq(budget.boss_max_triangles, 25000)


func test_authored_budget_matches_the_design_doc_frame_budgets() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.frame_draw_calls_typical, 120)
	assert_eq(budget.frame_draw_calls_peak, 180)
	assert_eq(budget.frame_triangles_typical, 150000)
	assert_eq(budget.frame_triangles_peak, 250000)
	assert_eq(budget.max_texture_dimension_px, 2048)


func test_lookup_returns_the_category_cap() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.max_triangles_for(&"hero"), 12000)
	assert_eq(budget.min_triangles_for(&"enemy"), 3000)
	assert_eq(budget.max_triangles_for(&"boss"), 25000)


## Props, kit pieces and rideables have no per-asset figure in design doc §9.4 --
## they are governed by the whole-frame budget instead. An unbudgeted category
## must report itself as unbudgeted so the lint can fail closed and ask the
## operator, rather than silently passing everything through a default nobody chose.
func test_unbudgeted_categories_report_no_cap() -> void:
	var budget: ArtBudgetTuning = load(AUTHORED_PATH)

	assert_eq(budget.max_triangles_for(&"prop"), -1)
	assert_eq(budget.max_triangles_for(&"kit_piece"), -1)
	assert_eq(budget.max_triangles_for(&"rideable"), -1)
	assert_eq(budget.max_triangles_for(&"not_a_category"), -1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/run_gut.sh`
Expected: FAIL — the script and the `.tres` do not exist yet.

- [ ] **Step 3: Write the resource script**

Create `src/tuning/art_budget_tuning.gd`:

```gdscript
class_name ArtBudgetTuning
extends Resource

## Build-time art constraints from design doc §9.4. Deliberately outside
## TuningService.SECTION_NAMES: these are not values anyone tunes by thumb
## mid-session, and they must not move the gameplay tuning fingerprint.
## Follows the LevelMeta precedent for a standalone authored resource.

## Per-asset triangle caps. §9.4 specifies these three categories and no others;
## props, kit pieces and rideables are governed by the frame budgets below, so
## their per-asset caps are deliberately absent rather than invented.
@export var hero_min_triangles: int = 0
@export var hero_max_triangles: int = 0
@export var enemy_min_triangles: int = 0
@export var enemy_max_triangles: int = 0
@export var boss_min_triangles: int = 0
@export var boss_max_triangles: int = 0

## Texture rules. §9.4: 1-2 x 2048 atlases + trim sheet per kit, ASTC.
@export var max_texture_dimension_px: int = 0

## Whole-frame budgets. These can only be measured in an assembled scene, so
## they belong to the on-device readout (src/debug/perf_readout.gd), never to a
## per-asset lint.
@export var frame_draw_calls_typical: int = 0
@export var frame_draw_calls_peak: int = 0
@export var frame_triangles_typical: int = 0
@export var frame_triangles_peak: int = 0

const UNBUDGETED := -1


func max_triangles_for(category: StringName) -> int:
	match category:
		&"hero":
			return hero_max_triangles
		&"enemy":
			return enemy_max_triangles
		&"boss":
			return boss_max_triangles
	return UNBUDGETED


func min_triangles_for(category: StringName) -> int:
	match category:
		&"hero":
			return hero_min_triangles
		&"enemy":
			return enemy_min_triangles
		&"boss":
			return boss_min_triangles
	return UNBUDGETED
```

- [ ] **Step 4: Author the values**

Create `data/tuning/art_budget.tres`. Match the format of the existing resources exactly (compare against `data/tuning/depth.tres`):

```
[gd_resource type="Resource" script_class="ArtBudgetTuning" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/tuning/art_budget_tuning.gd" id="1_art_budget"]

[resource]
script = ExtResource("1_art_budget")
hero_min_triangles = 10000
hero_max_triangles = 12000
enemy_min_triangles = 3000
enemy_max_triangles = 6000
boss_min_triangles = 15000
boss_max_triangles = 25000
max_texture_dimension_px = 2048
frame_draw_calls_typical = 120
frame_draw_calls_peak = 180
frame_triangles_typical = 150000
frame_triangles_peak = 250000
```

- [ ] **Step 5: Run test to verify it passes**

Run: `scripts/run_gut.sh`
Expected: PASS, 4 more tests than the previous run. Record the count.

- [ ] **Step 6: Commit**

```bash
git add src/tuning/art_budget_tuning.gd src/tuning/art_budget_tuning.gd.uid data/tuning/art_budget.tres tests/tuning/test_art_budget_tuning.gd tests/tuning/test_art_budget_tuning.gd.uid
git commit -m "Author the art budget resource from design doc 9.4"
```

If Godot did not generate the `.uid` files (it does so on first editor/headless import), run `scripts/run_gut.sh` once more and re-check `git status` before staging.

---

### Task 4: Count triangles in a `.glb`

Pure Python, no dependencies, no Godot. A `.glb` is a 12-byte header followed by length-prefixed chunks; the first is JSON and describes every mesh.

**Files:**
- Create: `scripts/gltf_budget.py`
- Test: `tests/lint/test_gltf_budget.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `read_glb_json(data: bytes) -> dict`, `triangle_count(document: dict) -> int`, `triangle_count_of_file(path: Path) -> int`, and `MalformedGlbError(Exception)`. Task 6 calls `triangle_count_of_file`.

- [ ] **Step 1: Write the failing test**

Create `tests/lint/test_gltf_budget.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.lint.test_gltf_budget -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.gltf_budget'`

- [ ] **Step 3: Write the implementation**

Create `scripts/gltf_budget.py`:

```python
#!/usr/bin/env python3
"""Read triangle counts out of glTF 2.0 binary (.glb) assets.

Pure parsing, no Godot and no third-party dependencies, so the budget lint
runs in the same pre-commit hook as the rest of the lint family.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

GLB_MAGIC = 0x46546C67  # 'glTF'
JSON_CHUNK_TYPE = 0x4E4F534A  # 'JSON'
GLB_HEADER_SIZE = 12
CHUNK_HEADER_SIZE = 8

# glTF 2.0 primitive modes. 0-3 are points and lines and carry no triangles.
MODE_TRIANGLES = 4
MODE_TRIANGLE_STRIP = 5
MODE_TRIANGLE_FAN = 6
DEFAULT_MODE = MODE_TRIANGLES

VERTICES_PER_TRIANGLE = 3
STRIP_FAN_OVERHEAD = 2


class MalformedGlbError(Exception):
    """Raised when a .glb cannot be parsed well enough to prove a count."""


def read_glb_json(data: bytes) -> dict:
    """Return the JSON chunk of a .glb as a dict."""
    if len(data) < GLB_HEADER_SIZE:
        raise MalformedGlbError("file is shorter than a glTF header")
    magic, version, total_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise MalformedGlbError("not a glTF binary file (bad magic)")
    if version != 2:
        raise MalformedGlbError(f"unsupported glTF binary version {version}")
    if total_length > len(data):
        raise MalformedGlbError(
            f"header declares {total_length} bytes but the file holds {len(data)}"
        )
    offset = GLB_HEADER_SIZE
    if offset + CHUNK_HEADER_SIZE > len(data):
        raise MalformedGlbError("file ends before its first chunk header")
    chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
    offset += CHUNK_HEADER_SIZE
    if chunk_type != JSON_CHUNK_TYPE:
        raise MalformedGlbError("first chunk is not the JSON chunk")
    if offset + chunk_length > len(data):
        raise MalformedGlbError("JSON chunk runs past the end of the file")
    try:
        return json.loads(data[offset : offset + chunk_length].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise MalformedGlbError(f"JSON chunk is not readable: {error}") from error


def triangle_count(document: dict) -> int:
    """Return the total triangles across every mesh primitive in a glTF document."""
    accessors = document.get("accessors", [])
    total = 0
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        for primitive_index, primitive in enumerate(mesh.get("primitives", [])):
            total += _primitive_triangles(
                primitive, accessors, f"meshes[{mesh_index}].primitives[{primitive_index}]"
            )
    return total


def triangle_count_of_file(path: Path) -> int:
    """Return the triangle count of a .glb on disk."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise MalformedGlbError(f"{path}: cannot be read: {error}") from error
    return triangle_count(read_glb_json(data))


def _primitive_triangles(primitive: dict, accessors: list, where: str) -> int:
    mode = primitive.get("mode", DEFAULT_MODE)
    if mode not in (MODE_TRIANGLES, MODE_TRIANGLE_STRIP, MODE_TRIANGLE_FAN):
        return 0
    if "indices" in primitive:
        vertex_count = _accessor_count(accessors, primitive["indices"], where)
    else:
        attributes = primitive.get("attributes", {})
        if "POSITION" not in attributes:
            raise MalformedGlbError(
                f"{where}: has neither an index accessor nor a POSITION attribute, "
                "so its triangle count cannot be proven"
            )
        vertex_count = _accessor_count(accessors, attributes["POSITION"], where)
    if mode == MODE_TRIANGLES:
        return vertex_count // VERTICES_PER_TRIANGLE
    return max(vertex_count - STRIP_FAN_OVERHEAD, 0)


def _accessor_count(accessors: list, index: int, where: str) -> int:
    if not isinstance(index, int) or index < 0 or index >= len(accessors):
        raise MalformedGlbError(f"{where}: accessor index {index!r} does not exist")
    count = accessors[index].get("count")
    if not isinstance(count, int) or count < 0:
        raise MalformedGlbError(f"{where}: accessor {index} has no usable count")
    return count
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.lint.test_gltf_budget -v`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/gltf_budget.py tests/lint/test_gltf_budget.py
git commit -m "Add a dependency-free glb triangle counter"
```

---

### Task 5: Check texture dimensions and compression

**Files:**
- Create: `scripts/texture_budget.py`
- Test: `tests/lint/test_texture_budget.py`

**Interfaces:**
- Consumes: `scripts.scene_transform_parsing.assignment_values` (Task 1).
- Produces: `png_dimensions(path: Path) -> tuple[int, int]`, `is_power_of_two(value: int) -> bool`, `import_uses_vram_compression(import_path: Path) -> bool`, and `MalformedTextureError(Exception)`. Task 6 calls all three.

- [ ] **Step 1: Write the failing test**

Create `tests/lint/test_texture_budget.py`:

```python
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from scripts.texture_budget import (
    MalformedTextureError,
    import_uses_vram_compression,
    is_power_of_two,
    png_dimensions,
)


def build_png(width: int, height: int) -> bytes:
    """Assemble a PNG signature plus a valid IHDR chunk. Pixels are not needed."""
    signature = b"\x89PNG\r\n\x1a\n"
    body = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    chunk = struct.pack(">I", len(body)) + b"IHDR" + body
    chunk += struct.pack(">I", zlib.crc32(b"IHDR" + body))
    return signature + chunk


class PngDimensionsTests(unittest.TestCase):
    def test_reads_width_and_height(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png"
            path.write_bytes(build_png(2048, 2048))

            self.assertEqual(png_dimensions(path), (2048, 2048))

    def test_reads_a_non_square_texture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_wide.png"
            path.write_bytes(build_png(1024, 512))

            self.assertEqual(png_dimensions(path), (1024, 512))

    def test_rejects_a_file_that_is_not_a_png(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_bogus.png"
            path.write_bytes(b"JFIF nonsense")

            with self.assertRaises(MalformedTextureError):
                png_dimensions(path)

    def test_rejects_a_truncated_png(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_short.png"
            path.write_bytes(build_png(64, 64)[:12])

            with self.assertRaises(MalformedTextureError):
                png_dimensions(path)


class PowerOfTwoTests(unittest.TestCase):
    def test_accepts_powers_of_two(self) -> None:
        for value in (1, 2, 256, 1024, 2048):
            self.assertTrue(is_power_of_two(value), value)

    def test_rejects_everything_else(self) -> None:
        for value in (0, -2048, 3, 1000, 2047):
            self.assertFalse(is_power_of_two(value), value)


class ImportCompressionTests(unittest.TestCase):
    def test_detects_vram_compressed_import(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png.import"
            path.write_text(
                '[remap]\n\nimporter="texture"\n\n[params]\n\ncompress/mode=2\n',
                encoding="utf-8",
            )

            self.assertTrue(import_uses_vram_compression(path))

    def test_detects_lossless_import(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "T_crash_body.png.import"
            path.write_text(
                '[remap]\n\nimporter="texture"\n\n[params]\n\ncompress/mode=0\n',
                encoding="utf-8",
            )

            self.assertFalse(import_uses_vram_compression(path))

    def test_a_missing_import_file_is_not_compressed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse(
                import_uses_vram_compression(Path(directory) / "absent.png.import")
            )
```

`compress/mode=2` is Godot's VRAM-compressed mode and `0` is lossless. Godot 4.7's `CompressedTexture2D` documents five methods in the order Lossless, Lossy, VRAM Compressed, VRAM Uncompressed, Basis Universal, and every `.import` in this repo today carries `compress/mode=0` for an uncompressed SVG — but **do not ship the constant on that reasoning alone.** Step 3a verifies it against the real importer.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.lint.test_texture_budget -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.texture_budget'`

- [ ] **Step 3: Write the implementation**

Create `scripts/texture_budget.py`:

```python
#!/usr/bin/env python3
"""Read texture dimensions and Godot import settings for the art budget lint."""

from __future__ import annotations

import struct
from pathlib import Path

try:
    from scene_transform_parsing import assignment_values
except ModuleNotFoundError:  # invoked as scripts.texture_budget
    from scripts.scene_transform_parsing import assignment_values

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
IHDR_OFFSET = 16  # 8-byte signature + 4-byte length + 4-byte "IHDR"
IHDR_END = 24
# Godot's texture importer: 0 = lossless, 1 = lossy, 2 = VRAM compressed,
# 3 = uncompressed. Only mode 2 yields the ASTC/ETC2 the mobile budget assumes.
VRAM_COMPRESSED_MODE = "2"


class MalformedTextureError(Exception):
    """Raised when a texture cannot be parsed well enough to prove its size."""


def png_dimensions(path: Path) -> tuple[int, int]:
    """Return (width, height) from a PNG's IHDR chunk."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise MalformedTextureError(f"{path}: cannot be read: {error}") from error
    if not data.startswith(PNG_SIGNATURE):
        raise MalformedTextureError(f"{path}: not a PNG (bad signature)")
    if len(data) < IHDR_END:
        raise MalformedTextureError(f"{path}: truncated before its IHDR chunk")
    width, height = struct.unpack_from(">II", data, IHDR_OFFSET)
    if width <= 0 or height <= 0:
        raise MalformedTextureError(f"{path}: IHDR reports a zero dimension")
    return width, height


def is_power_of_two(value: int) -> bool:
    return value > 0 and value & (value - 1) == 0


def import_uses_vram_compression(import_path: Path) -> bool:
    """Return whether a .import sidecar selects Godot's VRAM-compressed mode."""
    if not import_path.is_file():
        return False
    values = assignment_values(import_path.read_text(encoding="utf-8"))
    return values.get("compress/mode") == VRAM_COMPRESSED_MODE
```

`PROPERTY_PATTERN` already allows `/` in a key (`[A-Za-z_][A-Za-z0-9_/]*`), which is why `compress/mode` parses without touching the regex.

- [ ] **Step 3a: Verify `compress/mode=2` against the real importer**

The whole texture check hangs on one integer, taken from an enum ordering. Prove it rather than trusting it — this is exactly the "execute the failure scenario, don't read the docs and assume" lesson. Import a real PNG in the Godot editor, set **Compress > Mode** to **VRAM Compressed**, reimport, and read the generated sidecar:

```bash
grep 'compress/mode' assets/textures/<the-test-file>.png.import
```

Expected: `compress/mode=2`. If it is any other number, fix `VRAM_COMPRESSED_MODE` in `scripts/texture_budget.py` and the two test fixtures before continuing, and say so in the report. Delete the test PNG afterwards and confirm with `git status --porcelain assets/`.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.lint.test_texture_budget -v`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add scripts/texture_budget.py tests/lint/test_texture_budget.py
git commit -m "Add texture dimension and compression checks for the art budget"
```

---

### Task 6: The art budget lint

Joins `lint_gameplay_numbers`, `check_content_vocabulary`, `lint_traversal_authoring` and `lint_level_authoring` in the pre-commit hook. A bust asset fails at the moment it is made rather than months later.

**On the empty-scan-root question:** `lint_level_authoring.py:1782` fails *closed* when its scan root holds zero scenes, because a real level set should never be empty. The opposite is true here — zero models is the correct state of `assets/models/` today and will be until the operator finishes the crate. So this lint passes on an empty tree but always prints the number of assets scanned, so "0 assets" is visible rather than indistinguishable from "0 violations".

**Files:**
- Create: `scripts/lint_art_budgets.py`
- Modify: `.githooks/pre-commit`
- Test: `tests/lint/test_art_budget_lint.py`

**Interfaces:**
- Consumes: `scripts.gltf_budget.triangle_count_of_file` (Task 4); `scripts.texture_budget.png_dimensions`, `is_power_of_two`, `import_uses_vram_compression` (Task 5); `scripts.scene_transform_parsing.assignment_values` (Task 1); `data/tuning/art_budget.tres` (Task 3); the `assets/models/<category-dir>/` convention (Task 2).
- Produces: `category_for(path: Path) -> str | None`, `load_budget(repo_root: Path) -> ArtBudget`, `find_violations(repo_root: Path) -> list[BudgetViolation]`, `main(argv) -> int`.

- [ ] **Step 1: Write the failing test**

Create `tests/lint/test_art_budget_lint.py`:

```python
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

from scripts.lint_art_budgets import category_for, find_violations, load_budget

REPO_ROOT = Path(__file__).resolve().parents[2]
LINT_SCRIPT = REPO_ROOT / "scripts" / "lint_art_budgets.py"

AUTHORED_BUDGET = (REPO_ROOT / "data" / "tuning" / "art_budget.tres").read_text(
    encoding="utf-8"
)


def build_glb(triangles: int) -> bytes:
    document = {
        "asset": {"version": "2.0"},
        "accessors": [{"count": triangles * 3}],
        "meshes": [{"primitives": [{"mode": 4, "indices": 0}]}],
    }
    payload = json.dumps(document).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    return struct.pack("<III", 0x46546C67, 2, 12 + len(chunk)) + chunk


def build_png(width: int, height: int) -> bytes:
    body = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    chunk = struct.pack(">I", len(body)) + b"IHDR" + body
    chunk += struct.pack(">I", zlib.crc32(b"IHDR" + body))
    return b"\x89PNG\r\n\x1a\n" + chunk


def make_repo(directory: str) -> Path:
    """A throwaway tree with the real authored budget and empty asset dirs."""
    root = Path(directory)
    (root / "data" / "tuning").mkdir(parents=True)
    (root / "data" / "tuning" / "art_budget.tres").write_text(
        AUTHORED_BUDGET, encoding="utf-8"
    )
    for name in ("characters", "enemies", "bosses", "rideables", "props", "kits"):
        (root / "assets" / "models" / name).mkdir(parents=True)
    (root / "assets" / "textures").mkdir(parents=True)
    return root


class CategoryResolutionTests(unittest.TestCase):
    def test_maps_each_asset_directory_to_its_category(self) -> None:
        self.assertEqual(category_for(Path("assets/models/characters/SK_crash.glb")), "hero")
        self.assertEqual(category_for(Path("assets/models/enemies/SK_skink.glb")), "enemy")
        self.assertEqual(category_for(Path("assets/models/bosses/SK_papu.glb")), "boss")
        self.assertEqual(category_for(Path("assets/models/props/SM_crate.glb")), "prop")
        self.assertEqual(category_for(Path("assets/models/kits/SM_palm.glb")), "kit_piece")
        self.assertEqual(category_for(Path("assets/models/rideables/SK_hog.glb")), "rideable")

    def test_an_unknown_directory_has_no_category(self) -> None:
        self.assertIsNone(category_for(Path("assets/models/SK_loose.glb")))


class BudgetLoadingTests(unittest.TestCase):
    def test_reads_the_authored_caps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            budget = load_budget(make_repo(directory))

            self.assertEqual(budget.max_triangles["hero"], 12000)
            self.assertEqual(budget.min_triangles["enemy"], 3000)
            self.assertEqual(budget.max_texture_dimension_px, 2048)


class TriangleBudgetTests(unittest.TestCase):
    def test_an_in_budget_hero_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(11000))

            self.assertEqual(find_violations(root), [])

    def test_an_over_budget_hero_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(20000))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("20000", violations[0].message)
            self.assertIn("12000", violations[0].message)

    def test_an_under_budget_asset_is_reported_too(self) -> None:
        # Under the floor means the silhouette is probably not what 9.4 assumed.
        # It is a budget band, not a ceiling.
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/enemies/SK_skink.glb").write_bytes(build_glb(200))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("3000", violations[0].message)

    def test_an_unbudgeted_category_fails_closed_with_the_line_to_add(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/props/SM_crate_standard.glb").write_bytes(build_glb(400))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("prop_max_triangles", violations[0].message)
            self.assertIn("art_budget.tres", violations[0].message)

    def test_a_model_outside_every_category_directory_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/SM_loose.glb").write_bytes(build_glb(100))

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("category", violations[0].message)

    def test_an_unparseable_model_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/props/SM_broken.glb").write_bytes(b"not a glb")

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("SM_broken.glb", violations[0].path)


class TextureBudgetTests(unittest.TestCase):
    def test_an_oversized_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(4096, 4096))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("4096", violations[0].message)

    def test_a_non_power_of_two_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_odd.png").write_bytes(build_png(1000, 1000))
            (root / "assets/textures/T_odd.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("power of two", violations[0].message)

    def test_an_uncompressed_texture_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(2048, 2048))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=0\n", encoding="utf-8"
            )

            violations = find_violations(root)

            self.assertEqual(len(violations), 1)
            self.assertIn("VRAM", violations[0].message)

    def test_an_in_budget_texture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/textures/T_crash_body.png").write_bytes(build_png(2048, 2048))
            (root / "assets/textures/T_crash_body.png.import").write_text(
                "[params]\n\ncompress/mode=2\n", encoding="utf-8"
            )

            self.assertEqual(find_violations(root), [])


class LintEntryPointTests(unittest.TestCase):
    def test_an_empty_asset_tree_passes_and_says_it_scanned_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT), "--repo-root", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("0 asset", result.stdout)

    def test_the_real_repo_passes(self) -> None:
        result = subprocess.run(
            [sys.executable, str(LINT_SCRIPT), "--repo-root", str(REPO_ROOT)],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_violation_exits_non_zero(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = make_repo(directory)
            (root / "assets/models/characters/SK_crash.glb").write_bytes(build_glb(99000))

            result = subprocess.run(
                [sys.executable, str(LINT_SCRIPT), "--repo-root", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("SK_crash.glb", result.stdout)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest tests.lint.test_art_budget_lint -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.lint_art_budgets'`

- [ ] **Step 3: Write the implementation**

Create `scripts/lint_art_budgets.py`:

```python
#!/usr/bin/env python3
"""Assert design doc 9.4's per-asset art budgets on every committed asset.

Per-asset caps only. The whole-frame budgets (draw calls, visible triangles)
cannot be checked on a lone mesh -- they belong to the on-device readout in
src/debug/perf_readout.gd.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

try:
    from gltf_budget import MalformedGlbError, triangle_count_of_file
    from scene_transform_parsing import assignment_values
    from texture_budget import (
        MalformedTextureError,
        import_uses_vram_compression,
        is_power_of_two,
        png_dimensions,
    )
except ModuleNotFoundError:  # invoked as scripts.lint_art_budgets
    from scripts.gltf_budget import MalformedGlbError, triangle_count_of_file
    from scripts.scene_transform_parsing import assignment_values
    from scripts.texture_budget import (
        MalformedTextureError,
        import_uses_vram_compression,
        is_power_of_two,
        png_dimensions,
    )

# The directory an asset lives in decides its budget category. Documented for
# humans in docs/art/import-export-contract.md.
CATEGORY_BY_DIRECTORY = {
    "characters": "hero",
    "enemies": "enemy",
    "bosses": "boss",
    "rideables": "rideable",
    "props": "prop",
    "kits": "kit_piece",
}
BUDGET_PATH = Path("data/tuning/art_budget.tres")
MODEL_ROOT = Path("assets/models")
TEXTURE_ROOT = Path("assets/textures")


@dataclass(frozen=True)
class BudgetViolation:
    path: str
    message: str


@dataclass(frozen=True)
class ArtBudget:
    min_triangles: dict[str, int] = field(default_factory=dict)
    max_triangles: dict[str, int] = field(default_factory=dict)
    max_texture_dimension_px: int = 0


def category_for(path: Path) -> str | None:
    """Return the budget category implied by an asset's directory, or None."""
    for part in path.parts:
        if part in CATEGORY_BY_DIRECTORY:
            return CATEGORY_BY_DIRECTORY[part]
    return None


def load_budget(repo_root: Path) -> ArtBudget:
    """Read the authored caps out of data/tuning/art_budget.tres."""
    values = assignment_values(
        (repo_root / BUDGET_PATH).read_text(encoding="utf-8")
    )
    minimums: dict[str, int] = {}
    maximums: dict[str, int] = {}
    for category in set(CATEGORY_BY_DIRECTORY.values()):
        minimum = values.get(f"{category}_min_triangles")
        maximum = values.get(f"{category}_max_triangles")
        if minimum is not None:
            minimums[category] = int(float(minimum))
        if maximum is not None:
            maximums[category] = int(float(maximum))
    return ArtBudget(
        min_triangles=minimums,
        max_triangles=maximums,
        max_texture_dimension_px=int(float(values["max_texture_dimension_px"])),
    )


def find_violations(repo_root: Path) -> list[BudgetViolation]:
    budget = load_budget(repo_root)
    violations: list[BudgetViolation] = []
    violations.extend(_model_violations(repo_root, budget))
    violations.extend(_texture_violations(repo_root, budget))
    return violations


def scanned_asset_count(repo_root: Path) -> int:
    return len(_model_files(repo_root)) + len(_texture_files(repo_root))


def _model_files(repo_root: Path) -> list[Path]:
    root = repo_root / MODEL_ROOT
    return sorted(root.rglob("*.glb")) if root.is_dir() else []


def _texture_files(repo_root: Path) -> list[Path]:
    root = repo_root / TEXTURE_ROOT
    return sorted(root.rglob("*.png")) if root.is_dir() else []


def _model_violations(repo_root: Path, budget: ArtBudget) -> list[BudgetViolation]:
    violations: list[BudgetViolation] = []
    for path in _model_files(repo_root):
        relative = path.relative_to(repo_root)
        category = category_for(relative)
        if category is None:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        "sits outside every budget category directory -- move it "
                        f"into one of {sorted(CATEGORY_BY_DIRECTORY)} under "
                        "assets/models/ (see docs/art/import-export-contract.md)"
                    ),
                )
            )
            continue
        try:
            triangles = triangle_count_of_file(path)
        except MalformedGlbError as error:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"could not be counted, so its budget cannot be proven: {error}",
                )
            )
            continue
        maximum = budget.max_triangles.get(category)
        minimum = budget.min_triangles.get(category)
        if maximum is None or minimum is None:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is category {category!r}, which has no authored budget. "
                        f"Design doc 9.4 gives no per-asset figure for it, so add "
                        f"{category}_min_triangles and {category}_max_triangles to "
                        "data/tuning/art_budget.tres (and to "
                        "src/tuning/art_budget_tuning.gd) with a number you chose "
                        f"deliberately. This asset measures {triangles} triangles."
                    ),
                )
            )
            continue
        if triangles > maximum:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is {triangles} triangles, over the {category} budget of {maximum}"
                    ),
                )
            )
        elif triangles < minimum:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is {triangles} triangles, under the {category} floor of {minimum} "
                        "-- 9.4's caps are a band, not a ceiling; a silhouette this cheap "
                        "is probably not the asset the budget assumed"
                    ),
                )
            )
    return violations


def _texture_violations(repo_root: Path, budget: ArtBudget) -> list[BudgetViolation]:
    violations: list[BudgetViolation] = []
    for path in _texture_files(repo_root):
        relative = path.relative_to(repo_root)
        try:
            width, height = png_dimensions(path)
        except MalformedTextureError as error:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"could not be measured, so its budget cannot be proven: {error}",
                )
            )
            continue
        limit = budget.max_texture_dimension_px
        if width > limit or height > limit:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"is {width}x{height}, over the {limit}px texture budget",
                )
            )
        elif not (is_power_of_two(width) and is_power_of_two(height)):
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"is {width}x{height}; texture dimensions must be a power of two",
                )
            )
        elif not import_uses_vram_compression(
            path.with_name(path.name + ".import")
        ):
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        "is not imported with VRAM compression (compress/mode=2). "
                        "Set Compress > Mode to VRAM Compressed and commit the "
                        ".import sidecar."
                    ),
                )
            )
    return violations


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root to scan (default: the repo this script lives in)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    repo_root = arguments.repo_root
    try:
        violations = find_violations(repo_root)
    except (OSError, KeyError, ValueError) as error:
        print(f"Art budget lint failed closed: {error}", file=sys.stderr)
        return 2
    for violation in violations:
        print(f"{violation.path}: {violation.message}")
    count = scanned_asset_count(repo_root)
    if violations:
        print(f"Art budget lint failed: {len(violations)} violation(s) across {count} asset(s).")
        return 1
    # Always print the count. Zero assets is the correct state until the crate
    # lands, but it must not be indistinguishable from zero violations.
    print(f"Art budget lint passed: {count} asset(s) scanned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest tests.lint.test_art_budget_lint -v`
Expected: PASS, 16 tests.

- [ ] **Step 5: Wire it into the pre-commit hook**

In `.githooks/pre-commit`, add after the `lint_level_authoring.py` line:

```bash
python3 scripts/lint_art_budgets.py
```

- [ ] **Step 6: Prove the hook actually runs it**

```bash
python3 scripts/lint_art_budgets.py; echo "exit=$?"
```

Expected: `Art budget lint passed: 0 asset(s) scanned.` and `exit=0`.

Then prove it fails on a real bust asset rather than only on a synthetic one — write an over-budget `.glb` into `assets/models/characters/`, run the hook, watch it reject, then delete the file:

```bash
python3 - <<'PY'
import json, struct
from pathlib import Path
document = {"asset": {"version": "2.0"}, "accessors": [{"count": 60000}],
            "meshes": [{"primitives": [{"mode": 4, "indices": 0}]}]}
payload = json.dumps(document).encode()
payload += b" " * ((4 - len(payload) % 4) % 4)
chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload
Path("assets/models/characters/SK_scratch.glb").write_bytes(
    struct.pack("<III", 0x46546C67, 2, 12 + len(chunk)) + chunk)
PY
.githooks/pre-commit; echo "exit=$?"
rm assets/models/characters/SK_scratch.glb
```

Expected: the hook prints `assets/models/characters/SK_scratch.glb: is 20000 triangles, over the hero budget of 12000` and exits non-zero. Confirm the file is gone before continuing (`git status --porcelain assets/`).

- [ ] **Step 7: Run the full Python suite**

Run: `python3 -m unittest discover -s tests -p 'test_*.py'`
Expected: OK. Record the count.

- [ ] **Step 8: Commit**

```bash
git add scripts/lint_art_budgets.py tests/lint/test_art_budget_lint.py .githooks/pre-commit
git commit -m "Enforce the per-asset art budgets in the pre-commit lint family"
```

---

### Task 7: The look-dev scene

Turns "how does this read at phone size" from an hour into minutes. Deployed through the existing `scripts/deploy_android.sh` and reached from the debug drawer, because the project's `run/main_scene` is fixed at `res://scenes/main.tscn` and rewriting that at build time would make the deployed APK differ from the committed project.

**Files:**
- Create: `src/debug/look_dev.gd`
- Create: `scenes/debug/look_dev.tscn`
- Modify: `src/debug/tuning_debug_ui.gd`, `scenes/debug/tuning_debug_ui.tscn`
- Test: `tests/debug/test_look_dev.gd`

**Interfaces:**
- Consumes: `ArtBudgetTuning` (Task 3); the `assets/models/**` convention (Task 2).
- Produces: class `LookDev` with `discover_assets(root: String) -> PackedStringArray`, `set_assets(assets: PackedStringArray) -> void`, `select(index: int) -> void`, `current_asset_path() -> String`, `advance_turntable(delta_s: float) -> void`, `turntable_degrees() -> float`, `close() -> void`, and a `closed` signal. Also `LevelListOverlay.look_dev_requested` and `GameRoot.DEBUG_LOOK_DEV_LEVEL_ID`.

- [ ] **Step 1: Write the failing test**

Create `tests/debug/test_look_dev.gd`:

```gdscript
extends GutTest

const LookDevType := preload("res://src/debug/look_dev.gd")


func test_discovers_glb_assets_under_a_root() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	var found := look_dev.discover_assets("res://assets/models")

	# The tree legitimately holds no models yet, so this asserts the contract
	# (a sorted list of .glb paths, never null) rather than a fixed count.
	assert_not_null(found)
	for path: String in found:
		assert_true(path.ends_with(".glb"), "%s should be a .glb" % path)


func test_selection_wraps_around_an_empty_list_without_erroring() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())
	look_dev.set_assets(PackedStringArray())

	look_dev.select(0)

	assert_eq(look_dev.current_asset_path(), "")


func test_selection_wraps_forward_and_backward() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())
	look_dev.set_assets(
		PackedStringArray(["res://a.glb", "res://b.glb", "res://c.glb"])
	)

	look_dev.select(1)
	assert_eq(look_dev.current_asset_path(), "res://b.glb")

	look_dev.select(3)
	assert_eq(look_dev.current_asset_path(), "res://a.glb", "index past the end wraps")

	look_dev.select(-1)
	assert_eq(look_dev.current_asset_path(), "res://c.glb", "negative index wraps")


func test_turntable_advances_and_wraps_at_a_full_turn() -> void:
	var look_dev: LookDev = autofree(LookDevType.new())

	look_dev.advance_turntable(1.0)
	var after_one_second := look_dev.turntable_degrees()
	assert_gt(after_one_second, 0.0)

	look_dev.advance_turntable(LookDevType.FULL_TURN_DEGREES)
	assert_lt(
		look_dev.turntable_degrees(),
		LookDevType.FULL_TURN_DEGREES,
		"the turntable angle must stay bounded rather than growing all session"
	)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/run_gut.sh`
Expected: FAIL — `src/debug/look_dev.gd` does not exist.

- [ ] **Step 3: Write the controller**

Create `src/debug/look_dev.gd`:

```gdscript
class_name LookDev
extends Node3D

## One asset, the shipping material and lighting setup, on a turntable, at real
## device resolution. Answers "does this read at phone size", which is the
## question the art ladder asks several hundred times. Debug-only: reached from
## the tuning drawer, never from a release path.

signal closed

const FULL_TURN_DEGREES := 360.0
## Degrees per second. A slow turn: fast enough to read the silhouette from every
## angle in a few seconds, slow enough to stop on a bad one.
const TURNTABLE_DEGREES_PER_SECOND := 30.0

var _assets := PackedStringArray()
var _selected_index := 0
var _turntable_degrees := 0.0


func discover_assets(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	_collect_assets(root, found)
	found.sort()
	return found


func set_assets(assets: PackedStringArray) -> void:
	_assets = assets
	_selected_index = 0


func select(index: int) -> void:
	if _assets.is_empty():
		_selected_index = 0
		return
	_selected_index = posmod(index, _assets.size())


func current_asset_path() -> String:
	if _assets.is_empty():
		return ""
	return _assets[_selected_index]


func advance_turntable(delta_s: float) -> void:
	_turntable_degrees = fmod(
		_turntable_degrees + TURNTABLE_DEGREES_PER_SECOND * delta_s,
		FULL_TURN_DEGREES
	)


func turntable_degrees() -> float:
	return _turntable_degrees


func close() -> void:
	closed.emit()


func normalize_resource_path(path: String) -> String:
	for suffix: String in [".import", ".remap"]:
		if path.ends_with(suffix):
			return path.trim_suffix(suffix)
	return path


func _collect_assets(directory_path: String, into: PackedStringArray) -> void:
	for entry: String in ResourceLoader.list_directory(directory_path):
		if entry.ends_with("/"):
			_collect_assets(
				directory_path.path_join(entry.trim_suffix("/")),
				into
			)
			continue
		var full_path := normalize_resource_path(directory_path.path_join(entry))
		if full_path.ends_with(".glb") and not into.has(full_path):
			into.append(full_path)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `scripts/run_gut.sh`
Expected: PASS, 4 more tests. Record the count.

- [ ] **Step 5: Build the scene**

Create `scenes/debug/look_dev.tscn` in the Godot editor (or by hand, matching the format of `scenes/debug/tuning_debug_ui.tscn`) with:

- Root `Node3D` named `LookDev`, script `res://src/debug/look_dev.gd`
- `Camera3D` at `(0, 1.2, 3)` looking at origin — roughly a character's head height at a readable distance
- `WorldEnvironment` using the project's default environment, so the asset is lit the way the game lights it
- `Node3D` named `Turntable` at the origin — the loaded asset is parented here and rotated by `turntable_degrees()`
- A `Label` showing the current asset path
- Prev / Next / Close buttons sized for a thumb

The scene deliberately carries **no triangle readout of its own.** `PerfReadout` lives on `main.tscn`'s `UI` CanvasLayer, which survives the `Content` swap, so its `PRIM` figure is already the live triangle count of whatever look-dev is displaying — and after Task 8 it carries the budget status too. A second, separately-computed count would be a second thing to keep honest.

Wire `_process(delta)` to call `advance_turntable(delta)` and apply `turntable_degrees()` to `Turntable.rotation_degrees.y`.

- [ ] **Step 6: Add the debug entry point, mirroring the traversal toybox exactly**

The repo already has a debug-only scene reachable on device: the traversal toybox. Do not invent a second mechanism — copy that one. Its five sites in `src/core/game_root.gd`:

| Line | Site | Look-dev equivalent |
|---|---|---|
| 37, 59 | `TOYBOX_SCENE := preload(...)`, `DEBUG_TOYBOX_LEVEL_ID := &"debug_traversal_toybox"` | `LOOK_DEV_SCENE := preload("res://scenes/debug/look_dev.tscn")`, `DEBUG_LOOK_DEV_LEVEL_ID := &"debug_look_dev"` |
| 654 | connects `&"toybox_requested"` → `_on_toybox_requested` | connect `&"look_dev_requested"` → `_on_look_dev_requested` |
| 711–719 | `_render_state` branch instantiating the toybox into `_content` | add the same branch for `DEBUG_LOOK_DEV_LEVEL_ID`, instantiating `LOOK_DEV_SCENE` and calling `set_assets(look_dev.discover_assets("res://assets/models"))` |
| 1349 | `_sync_ui_visibility` passes `set_run_display_visible` false for the toybox | must be false for look-dev too — a wumpa counter over a turntable is nonsense |
| 1436 | `_on_toybox_requested` gated on `OS.is_debug_build()` | `_on_look_dev_requested`, same gate |

`_refresh_active_level_tuning` (line 1064) needs **no** look-dev branch — look-dev reads `art_budget.tres`, not the gameplay catalog, so a tuning change has nothing to refresh in it.

In `src/ui/level_list_overlay.gd`, add the signal and button alongside the existing toybox one (lines 5 and 22), and extend `configure(debug_tools_enabled)` at line 30 so the new button is hidden in release exactly like `Toybox` is:

```gdscript
signal look_dev_requested
```

```gdscript
	$SafeArea/Center/Panel/Margin/Rows/LookDev.pressed.connect(
		func() -> void: look_dev_requested.emit()
	)
```

```gdscript
func configure(debug_tools_enabled: bool) -> void:
	$SafeArea/Center/Panel/Margin/Rows/Toybox.visible = (
		debug_tools_enabled
	)
	$SafeArea/Center/Panel/Margin/Rows/LookDev.visible = (
		debug_tools_enabled
	)
```

Add the matching `LookDev` Button node to `scenes/ui/level_list_overlay.tscn` under `SafeArea/Center/Panel/Margin/Rows`, copying the `Toybox` button's properties.

Then confirm nothing else keys off the toybox id that look-dev also needs:

```bash
grep -n 'DEBUG_TOYBOX_LEVEL_ID' src/core/game_root.gd
```

Every hit must have been considered against the table above. Per the repo rule, grep every call site before calling the change done.

- [ ] **Step 7: Verify on device**

```bash
scripts/deploy_android.sh
```

Then, on the phone: open the debug drawer, tap into look-dev, confirm it opens, the turntable spins, and Close returns to the game. **Record what you observed.** If no device is attached, run `scripts/deploy_android.sh --build-only` and report explicitly that the on-device path was not exercised — per repo rule 4, "should work" is not a status.

- [ ] **Step 8: Commit**

```bash
git add src/debug/look_dev.gd src/debug/look_dev.gd.uid scenes/debug/look_dev.tscn src/debug/tuning_debug_ui.gd src/core/game_root.gd tests/debug/test_look_dev.gd tests/debug/test_look_dev.gd.uid
git commit -m "Add the look-dev scene for reading assets at phone size"
```

---

### Task 8: Budget telemetry on the debug HUD

An over-budget frame becomes visible *on the device* rather than inferred from a lint. `PerfReadout` already reports draw calls, primitives and objects; this adds texture memory and, more importantly, the comparison against §9.4's frame budgets.

**Files:**
- Modify: `src/debug/perf_readout.gd`
- Modify: `tests/debug/test_perf_readout.gd`

**Interfaces:**
- Consumes: `ArtBudgetTuning` (Task 3), loaded from `res://data/tuning/art_budget.tres`.
- Produces: `texture_memory_mb() -> float`, `budget_status() -> String`, and an extended `readout_text()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/debug/test_perf_readout.gd`. Note the existing suite's `rendering_info_source` seam — headless rendering counters are all zero and would agree with any mistake, so the test must substitute a source that answers each metric id differently:

```gdscript
func _fixed_rendering_info(draw_calls: int, primitives: int, texture_bytes: int) -> Callable:
	return func(info_id: int) -> int:
		match info_id:
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME:
				return draw_calls
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME:
				return primitives
			RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED:
				return texture_bytes
		return 0


func test_texture_memory_reports_megabytes() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	var one_megabyte := 1024 * 1024
	readout.rendering_info_source = _fixed_rendering_info(0, 0, 64 * one_megabyte)

	assert_almost_eq(readout.texture_memory_mb(), 64.0, 0.01)


func test_budget_status_is_ok_inside_the_typical_budget() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	readout.rendering_info_source = _fixed_rendering_info(100, 140000, 0)

	assert_eq(readout.budget_status(), "OK")


func test_budget_status_warns_between_typical_and_peak() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	readout.rendering_info_source = _fixed_rendering_info(150, 140000, 0)

	assert_eq(readout.budget_status(), "OVER-TYPICAL")


func test_budget_status_reports_over_peak() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	readout.rendering_info_source = _fixed_rendering_info(100, 300000, 0)

	assert_eq(readout.budget_status(), "OVER-PEAK")


func test_the_worst_of_the_two_metrics_wins() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	readout.rendering_info_source = _fixed_rendering_info(200, 140000, 0)

	assert_eq(
		readout.budget_status(),
		"OVER-PEAK",
		"draw calls over peak must not be masked by triangles being fine"
	)


func test_readout_text_carries_the_budget_status_and_texture_memory() -> void:
	var readout: PerfReadout = autofree(PerfReadout.new())
	readout.rendering_info_source = _fixed_rendering_info(100, 140000, 1024 * 1024)

	var text := readout.readout_text()

	assert_string_contains(text, "TEX")
	assert_string_contains(text, "OK")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/run_gut.sh`
Expected: FAIL — `texture_memory_mb` and `budget_status` do not exist.

- [ ] **Step 3: Extend the readout**

In `src/debug/perf_readout.gd`, add near the top:

```gdscript
## Frame budgets come from data/tuning/art_budget.tres (design doc 9.4), not from
## literals here -- the same rule the gameplay code follows. Loaded once: this
## runs inside the per-frame readout and must not touch the disk on a refresh.
const ART_BUDGET_PATH := "res://data/tuning/art_budget.tres"
const BYTES_PER_MEGABYTE := 1024 * 1024
const STATUS_OK := "OK"
const STATUS_OVER_TYPICAL := "OVER-TYPICAL"
const STATUS_OVER_PEAK := "OVER-PEAK"

var _art_budget: ArtBudgetTuning = load(ART_BUDGET_PATH)
```

and these methods:

```gdscript
func texture_memory_mb() -> float:
	return float(_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) \
		/ float(BYTES_PER_MEGABYTE)


## The worst of the two whole-frame metrics wins: draw calls over peak must not
## be hidden by a triangle count that happens to be fine.
func budget_status() -> String:
	if _art_budget == null:
		return STATUS_OK
	var calls := draw_calls()
	var triangles := primitives()
	if calls > _art_budget.frame_draw_calls_peak \
			or triangles > _art_budget.frame_triangles_peak:
		return STATUS_OVER_PEAK
	if calls > _art_budget.frame_draw_calls_typical \
			or triangles > _art_budget.frame_triangles_typical:
		return STATUS_OVER_TYPICAL
	return STATUS_OK
```

and extend `readout_text()`:

```gdscript
func readout_text() -> String:
	return (
		"FPS %.1f  1%% LOW %.1f  DRAW %d  PRIM %d  OBJ %d  SCALE %.2f  TEX %.1fMB  %s"
		% [
			sampled_average_fps(),
			sampled_one_percent_low_fps(),
			draw_calls(),
			primitives(),
			objects_in_frame(),
			render_scale(),
			texture_memory_mb(),
			budget_status(),
		]
	)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `scripts/run_gut.sh`
Expected: PASS, 6 more tests. Record the count.

- [ ] **Step 5: Verify on device**

```bash
scripts/deploy_android.sh
```

Play any Island Cut level and read the HUD. Record the actual `DRAW`, `PRIM`, `TEX` and status values observed — this is the **first real measurement of the graybox build against §9.4's frame budgets**, and it is worth writing down before any art exists, because it establishes how much headroom the art actually has. If no device is attached, say so plainly instead of reporting a number you did not see.

- [ ] **Step 6: Commit**

```bash
git add src/debug/perf_readout.gd tests/debug/test_perf_readout.gd
git commit -m "Show frame budget status and texture memory on the debug HUD"
```

---

## Done when

1. `python3 -m unittest discover -s tests -p 'test_*.py'` is green, with the count reported.
2. `scripts/run_gut.sh` is green, with the count reported.
3. `.githooks/pre-commit` runs `lint_art_budgets.py` and has been seen to reject a real over-budget asset (Task 6 Step 6).
4. `docs/art/import-export-contract.md` exists and the `assets/models/**` category directories are committed.
5. The look-dev scene and the HUD budget readout have been exercised **on a real device**, or the report says explicitly that they were not.

## Deliberately not in this plan

- **Frame-budget enforcement in a lint.** §9.4's ≤120 draw calls and ≤150k visible triangles are whole-frame figures; they can only be measured in an assembled scene, so they live on the HUD (Task 8) and nowhere else.
- **Per-asset budgets for props, kit pieces and rideables.** §9.4 gives no figure. The lint fails closed and names the exact line to add, so the operator chooses the number the first time such an asset lands — which will be the crate, at rung 1.
- **Anything that touches a human gate.** The likeness gate, Gate F and Gate F2 are untouched by every task here.
- **Art itself.** No asset in this plan. Rung 1 is the operator's, in Blender, and §6.4 of the pivot design asks him to time it and re-baseline the ladder against what it actually took.
