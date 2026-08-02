# CTR R8 — Characters, select, classes

Date: 2026-08-02. Operator-approved (brainstorm dialogue, approach A:
mechanics first, faces stream in behind likeness gates). Extends the racing
spec + R6/R7 specs; all hard rules unchanged (every byte original,
likeness gates human-only, tuning provably live, mobile budgets, TDD,
seam ruling). Feel gates the operator's throughout.

## Roster

Six drivers — exactly the 6-kart grid: **Crash** (exists, gated),
**Papu Papu** (mesh exists+gated; needs seated pose + authored seat fit —
he is huge, the fit is authored, never assumed), **Dr. Neo Cortex**,
**Coco**, **Ripper Roo** (all three NEW builds), **lab assistant**
(exists; stays the proven fallback and the sixth roster slot).

## A. Driver registry

One resource per driver under `data/racing/drivers/`: id, display name,
character scene path, class id, seat scale/offset, tint. Replaces the two
character sources RaceSession hardcodes today (SK_crash player / lab
assistant AI — see race_session.gd's Task-3 R6 note). A driver whose
scene is missing or not-yet-gated resolves to the lab-assistant mesh
silently — an unfinished face can never break a race or block the round.

## B. CTR classes

`DriverClass` resource with exactly three multipliers over base
`KartTuning`: `top_speed_mps`, `accel_mps2`, `steer_rate_degrees_per_s`.
Four classes: **Balanced** (Crash, Cortex, lab assistant — all 1.0),
**Speed** (Papu — faster top, slower steer), **Acceleration** (Coco),
**Turning** (Ripper Roo — sharper steer, lower top). Composition happens
at kart configure onto a per-kart copy; the shared KartTuning resource is
NEVER mutated, and the live-tuning refresh recomposes base×class so the
tuning-provably-live rule holds mid-race. The existing rubber-band
already acts on actual pace and absorbs class spread. **Named risk:**
Speed class (reduced steer) on Temple Twilight's hairpins — per-class
real-physics health races there are mandatory (wedge/respawn bounds per
class, the East-turn precedent applied per class).

## C. Character select

CHOOSE DRIVER screen (6 tiles: face, name, class chip) in front of
race / time-trial / cup starts, wired through the R7 menu/track registry.
Cup: pick once at cup start, held across both races (AI lineup continuity
stays free by construction from the grid-slot scheme). Last pick
persists (see E). Tiles for ungated drivers show the fallback mesh — the
screen never lies about what will actually race.

## D. AI fill

The 5 AI karts seat the 5 drivers the player did not pick — no
duplicates, deterministic slot order. AI karts take their driver's class
multipliers exactly like the player kart (hence the per-class health
races in B). Per-slot personalities and tints stay slot traits,
untouched (what R6's tests pin) — the character contributes mesh and
class, never personality.

## E. Save v3→v4

`racing.selected_driver` (string id). Same migration rigor as v1→v2 and
v2→v3: scratch-verified full chain v1→v4, corrupt or unknown driver id
fails closed to Crash. No other schema change.

## F. Ghost + best times

Ghost header version bumps and gains the driver id; an old-version ghost
still loads and renders Crash. Best-time boards remain one per track,
class-agnostic (operator ruling: class choice is strategy, CTR-style).

## G. Faces pipeline (async, non-blocking)

Three new byte-deterministic Blender builders sharing
`character_asset_common.py`: `create_cortex.py`, `create_coco.py`
(reuses Crash's proportion scaffolding), `create_ripper_roo.py`
(distinct body plan — most builder work). Each goes to the operator's
likeness gate; acceptance flips that driver's registry entry from
fallback to real scene. A rejected face re-enters the builder loop
without blocking anything else. Papu's seated-pose variant reuses his
gated mesh (pose + fit only — not a new likeness gate unless the pose
materially changes the read).

## Testing

TDD throughout. Units: class multiplier math, registry resolution +
fallback, select-screen flow, ghost header versioning. Scratch: save
v1→v4 / v2→v4 / v3→v4 / corrupt chains. Physics: per-class Temple
Twilight health race. E2E: pick Papu → full cup → standings → save →
reload shows the pick and the seat.

## Operator gates

Three likeness gates (Cortex, Coco, Ripper Roo — async, streamed), plus
on-device class feel. All R1–R7 feel gates remain pending and are not
discharged by anything in R8.

## Phases

T1 registry + classes (mechanics vs existing gated trio) → T2 select
screen + AI fill → T3 save v4 + ghost header → T4 Papu seated + seat
fit → T5 three builders → likeness gates (async from here) → T6
integration/verification → R8 APK.

## Out of scope

Audio, new tracks, adventure mode, multiplayer, per-character animations
beyond the seated idle, class-specific AI personality changes, per-class
best-time boards.

## Status (Task 9, 2026-08-02)

Shipped and verified on the merged tree: `DriverRegistry` (six-driver
roster, fixed order) + four `DriverClass` resources composed onto kart
tuning for player and AI alike; the CHOOSE DRIVER select screen in front
of every RACE/TIME TRIAL/CUP entry, cup pick-once held across both races;
AI fill excluding the player's own pick, deterministic and duplicate-free;
save v3→v4 (`racing.selected_driver`) and ghost v1→v2 (recorded driver
id), both scratch-verified; Papu's seated variant LIVE (real gated scene,
no longer fallback). End-to-end proof: `tests/integration/test_r8_papu_
cup_reload_e2e.gd` — real Driver Select tap, real countdown, a full 2-race
cup, a real save write, and a fresh app-relaunch-style reload that mounts
the persisted pick again with no re-pick. Task 2's per-class Temple
Twilight health-race battery and Task 3's ghost-compat suite both re-run
green post-Papu-flip.

**Gates pending, not passed:** Cortex, Coco, and Ripper Roo are each
code-complete (builder + gate renders delivered to the operator) but all
three remain fallback-active — `character_scene_path` is still empty on
each of their `DriverEntry` rows, so every race seats the lab assistant
in their place until an explicit operator likeness acceptance flips each
one individually. On-device class feel is likewise still an open operator
gate, same as every R1-R7 feel gate before it. See `task-9-report.md` and
the base spec's own Recorded-debts section (#20-#24) for the full sweep
results and newly recorded debts.
