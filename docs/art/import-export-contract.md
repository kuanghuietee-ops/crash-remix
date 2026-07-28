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
