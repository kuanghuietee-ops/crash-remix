# crash-remix

**Crash Bandicoot: N. Sanity Remix** — a trilogy greatest-hits 3D platformer for Android,
built in Godot 4.

**Personal fan project. Sideloaded to the operator and friends only. Never publicly
distributed, never monetised.** No assets are extracted from the PS1 discs or the
N. Sane Trilogy — every model, texture and audio file in this repo is built from scratch.
Audio is original, composed in the style of the originals, not taken from them.

## Start here

**`docs/superpowers/specs/2026-07-23-crash-remix-design.md`** is the design document.
Read it before writing anything. The sections that constrain implementation most:

| Section | What it locks down |
|---|---|
| §4.2 | The verb table — every move and its starting numbers |
| §5.2–5.3 | Touch layout, and the forgiveness windows (buffer/coyote/nudge) |
| §5.4–5.5 | The depth-aid stack, and how the camera survives wall-run/grind |
| §9.4 | Performance budget — draw calls, triangles, texture, lighting |
| §11 | Godot architecture: renderer, language, physics, scene tree, save |
| §11.4 | **The tuning system.** Non-negotiable. See CLAUDE.md. |
| §12 | Phases and the gates that block them |

Manual device checks live under `docs/qa/`.

## Locked technical decisions

- **Godot 4.7.x**, pinned per phase, upgraded only at phase boundaries — never mid-world.
- **Mobile renderer (Vulkan).** Not Forward+, not Compatibility. Min spec: Vulkan-capable
  Android ~10+.
- **Typed GDScript**, not C#. (§11.3 — the reason is the on-device tuning loop.)
- **Jolt physics**, 60Hz, with 3D physics interpolation on. Gravity and jump arcs are
  hand-integrated in the controller; physics only resolves collision.
- **All lighting baked** (LightmapGI per segment). Blob shadows are a gameplay element,
  not a lighting one — constant size and opacity regardless of light.
- Landscape orientation only. arm64-v8a only.

`project.godot` and the Android export preset have been validated with Godot 4.7.1.

## Phase 0 commands

Run the graybox toybox:

```bash
/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64 --path /root/crash-remix
```

Run the automated suite and gameplay-number lint:

```bash
/root/.local/share/godot/4.7.1/Godot_v4.7.1-stable_linux.x86_64 \
  --headless --path /root/crash-remix \
  -s addons/gut/gut_cmdln.gd -gexit
python3 scripts/lint_gameplay_numbers.py
python3 scripts/check_content_vocabulary.py
python3 scripts/lint_traversal_authoring.py
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/verify_exported_tuning.sh
```

GUT 9.7.1 is intentionally vendored under `addons/gut/` so the pinned test suite
does not depend on a per-machine Asset Library installation. The repository-owned
pre-commit hook runs the numeric lint, the Phase 1 content vocabulary tripwire, and
the traversal-authoring lint before Python tests.
`lint_traversal_authoring.py` parses the `.tscn` authoring data without launching
Godot: wall strips must be enclosed by wall-run camera regions, their tangents must
remain horizontal and upright on screen, detach targets must enter the camera
frustum, and rails need grind-region coverage plus symmetric neighbour links.
`verify_exported_tuning.sh` separately exports and boots the packed runtime,
catching resource-loader differences that editor-mode tests cannot see. The
vocabulary check examines identifiers, scene-node names, and paths while ignoring
comments and prose strings; it is an early-warning check, not proof of structural
scope. Code/design review establishes that boundary.

Build, install, and launch on the single attached authorized Android device:

```bash
scripts/deploy_android.sh
```

Use `scripts/deploy_android.sh --build-only` when no phone is connected. The output is
`build/crash-remix-debug.apk`. The script restores the non-secret debug keystore
from repository-pinned material and verifies its SHA-256 before every build, so
clean builds and other machines keep the same signing certificate. If Android
reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, stop and preserve
`user://tuning/override.tres`; uninstalling the app deletes that data.

## Status

Phase 0's automated implementation is built: graybox gauntlet, unified touch/gamepad
input, base movement kit, camera rail/regions, depth aids, live typed tuning, debug
drawer, and Android debug export. The required real-phone tuning acceptance test is
still pending; follow [the Phase 0 device procedure](docs/qa/phase0-device-acceptance.md).
Gate F has not been attempted and can only be judged by the operator on a phone.

The archived earlier draft — an original-mascot version of the same design, before the
decision to use the real character — is at
`/root/game-concepts/2026-07-23-mobile-platformer-concept-draft.md`, kept in case any of
that fiction is worth reusing.

## Scope, honestly

The full 25-level plan is ~32–40 months part-time, with self-taught character art on the
critical path (~24 rigged characters, ~800–1,200 hours). The plan is deliberately shaped
so three complete games fall out of it: **Island Cut** (~month 6–9), **Warp Rooms 1–2**
(~month 17, the formal decision point), and the **15-level Trilogy Sampler** (~month 21).
See §13. Build in that order.
