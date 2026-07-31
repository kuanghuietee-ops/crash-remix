# Blender → Godot import/export contract

One documented path from `.blend` to in-game. Everything here exists so an asset
never arrives sideways, at the wrong scale, or uncompressed on device.

Enforced by `scripts/lint_art_budgets.py` where a machine can check it, and by this
document where it cannot.

## Blender side

- **Units:** Metric, unit scale 1.0. **1 Blender unit = 1 metre = 1 Godot unit.**
- **Orientation:** model facing **−Y** in Blender, which imports as **+Z model front,
  +Y up** in Godot — Godot's directional-model convention. Export with +Y up (the
  glTF exporter default); do not "correct" the axes by rotating the object. This
  mapping is verified against the imported geometry, not inferred from Blender's
  viewport labels.
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
  | `assets/models/rideables/` | 6,000–10,000 tris | Operator-approved 2026-07-28 for the first hog |
  | `assets/models/props/` | 100–2,500 tris | Operator-approved after the first crate measured 1,996 tris |
  | `assets/models/kits/` | 100–2,000 tris | Operator-approved after the first beach/jungle kit measured 100–1,564 tris |
  | `assets/models/karts/` | 150–800 tris | CTR R6: a stand-in tier vehicle chassis, chosen after the first real kart measured 360 tris -- deliberately its own category, NOT `rideable` (that band is for a creature mount) |

  An unset category **fails the lint closed** with the exact line to add to
  `data/tuning/art_budget.tres`. That is deliberate: §9.4 specifies per-asset caps for
  characters, enemies and bosses only, while props, rideables, kit pieces and karts are
  governed by the whole-frame budget instead. The operator approved the 100–2,500
  prop band on 2026-07-28 after the first real crate measured 1,996 triangles,
  the 100–2,000 kit-piece band after the first beach/jungle kit measured
  100–1,564 triangles, the 6,000–10,000 rideable band before the first hog, and the
  150–800 kart band (CTR R6 Task 3) after the first real kart measured 360 triangles
  -- a stand-in tier vehicle mesh, explicitly not held to the rideable creature-mount
  band.

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

## Textured kits: where the texture actually lives

Environment kits are the one place the "one self-contained `.glb`" rule bends, and it
bends deliberately. A kit is many meshes sharing one atlas, so embedding the texture
would put a copy of it inside every piece — twenty-five copies of a 2 MB atlas, in a
public repo's history, forever. Instead:

- The `.glb` carries **geometry, UVs and one white material**. No texture, no colour.
  One material slot per piece: the palette lives in the UVs, which is what keeps the
  kit inside §9.4's 120-draw-call budget.
- The texture is committed **once** under `assets/textures/`.
- The shipping material is a committed `StandardMaterial3D` under `assets/materials/`,
  and each `.glb.import` points its material at that file through `_subresources`:

  ```
  "materials": {
  "M_beach_kit_atlas": {
  "use_external/enabled": true,
  "use_external/path": "res://assets/materials/M_beach_kit_atlas.tres"
  }
  }
  ```

  `scripts/blender/build_beach_env_kit.py` writes this block, so it survives a rebuild.

**A post-import script cannot do this job, and the failure is silent.** An
`EditorScenePostImport` script runs on the imported *scene*, but `save_to_file` writes
the extracted mesh from the pre-script material — so the texture never reaches
`kits/mesh/*.res`. Everything still imports, every lint still passes, the level still
loads, and every piece is plain white. This was tried first and caught only by
`tests/integration/test_kit_materials.gd`, which asserts each extracted mesh has an
albedo texture. Keep that suite green; it is the only thing standing between this
pipeline and a silently untextured level. The post-import script mechanism is still
correct for models the scenes instance directly as a `PackedScene`, which is why the
crates use it.

**`compress/mode=2` is confirmed, not assumed.** Setting it and reimporting makes Godot
write `"vram_texture": true` and `"imported_formats": ["s3tc_bptc", "etc2_astc"]` into
the sidecar's own metadata — the importer stating it produced the ASTC the mobile
budget assumes. Check that metadata rather than trusting the enum ordering.

**Animated pieces are routed by name, not by hand.** Three pieces of the kit move:
the sea, the surf foam, and the plant family (palms, ferns, bushes, grass, canopy
arches). They get a `ShaderMaterial` as a `material_override` on each instance, chosen
from the table in `scripts/kit_material_routing.py` and applied by
`scripts/route_kit_materials.py`, which is idempotent and runs automatically at the end
of `dress_island_cut.py`. Routing is keyed on the **piece stem** — `palm_tall_a`, not a
mesh path — so when the operator's own palm replaces the generated one at rung 4 of the
art ladder, it inherits the sway with no change to any of this. A piece that must stay
still is listed in `STATIC_BY_DESIGN` with the reason, so stillness reads as a decision.

The shaders are vertex-only and opaque by design. They never touch `UV`: the palette
lives in the UVs — each face points at one 256 px atlas cell — so sliding a UV repaints
the piece with its neighbour's colour. Note that `water_sea_tile` and `surf_foam_edge`
each span *two* cells, so no single cell rect can bound a scroll for them; that is why
the water animates by displacement and brightness rather than by scrolling.

**`mipmaps/generate=true` is mandatory on every kit texture.** The atlas is *designed*
around mip behaviour: the 16 px guard band exists because mipmapping averages
neighbouring texels and by the fifth mip a 256 px cell is 8 px wide, and the grain is
zero-mean so every mip level averages back to the exact palette colour. Import without
mips and none of that machinery does anything — the GPU point-samples a 2048 px texture
at all distances, which shimmers as the camera rails forward and thrashes the texture
cache on a bandwidth-limited tiled GPU. It costs ~33% texture memory (~3 MB across both
sheets) and *reduces* sampling bandwidth. Both kit sheets shipped with it off until the
2026-07-29 environment review; `tests/lint/test_kit_textures.py` now fails if either
regresses, and a sidecar missing the key counts as off.

## Checking an asset before committing it

```bash
python3 scripts/lint_art_budgets.py            # per-asset caps, texture rules
scripts/deploy_android.sh                      # then open look-dev on the phone
```

The lint answers "is it within budget". The look-dev scene (`scenes/debug/look_dev.tscn`,
reachable from the debug drawer) answers "does it read at phone size", which is the
question that actually gets asked several hundred times.
