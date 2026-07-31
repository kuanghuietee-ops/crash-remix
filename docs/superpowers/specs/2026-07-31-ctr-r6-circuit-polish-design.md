# CTR R6 — circuit polish: render, characters, smarter AI, more items

Date: 2026-07-31. Operator-approved same day (scope: all four workstreams).
Extends `2026-07-30-ctr-racing-mode-design.md`; all hard rules unchanged —
every byte original (the likeness-gated hand-made models are the ONLY
character sources), no gameplay numbers in code, tuning provably live,
human-only feel gates, mobile budgets enforced by the art lints.

## A. Circuit render pass

Sanity Shores dressed to racing density along the racing line (kit pieces,
existing palette); a start/finish arch with banner; flag posts marking every
checkpoint gate so they read at speed; item boxes get a spinning crate-style
visual. **Drift sparks colored by boost stage** (the CTR exhaust language —
this is feel infrastructure for the 3-tap game, not garnish) + a boost
flame, as budget-aware GPU particles with tuning-resource parameters
(`data/tuning/racing/fx.tres`, new `&"fx"` section). Shadow/triangle budgets
stay inside the art lints; particle counts are fx-tuning fields.

## B. Kart + characters

An original stylized kart mesh via the established Blender/palette pipeline
(stand-in tier, replaced by the operator's art ladder later). The existing
likeness-gated **Crash model seated on the player kart** (Hog Wild's seated
riding rig is the precedent); **lab assistant models drive AI karts** with
palette-recolored kart bodies per slot. No new operator art required; no new
characters invented.

## C. Smarter AI

Racing lines: per-corner apex lateral offsets derived from curvature
(outside-inside-outside) replacing constant slot offsets mid-corner — slots
still separate karts on straights. This addresses the East-turn wedge at the
root. Oscillation damping on the steering output. Better slide/boost usage
through corners. Item INTENT: hold a shield/beaker while leading, missile on
target sight, use turbo on the longest straight. Per-slot personality
scalars in AiTuning (aggression, skill jitter) so the field differentiates.

## D. More items + weighted rolls

Three additions in CTR grammar, all original: **bomb** (lobbed forward,
ballistic, area blast → spin-out), **TNT stick** (attaches to the victim,
countdown, shake-off by hopping N times — distinct from the beaker),
**triple turbo** (three stored charges, one per ITEM press). Roulette
becomes position-weighted (trailing karts roll stronger items) via
ItemTuning weight fields — the CTR rubber-band staple. AI use the new items
through the same dispatch.

## Phases and gates

T1 FX (sparks/flame/box visual) → T2 dressing/arch/flags → T3 kart+characters
→ **APK checkpoint (operator look verdict)** → T4 AI lines/damping/personality
→ T5 items+weights+AI intent → T6 integration/verification → R6 APK.
Feel/look verdicts remain the operator's on device. Pure logic (weighted
roulette, apex offset math, TNT shake-off counter) headless-tested; budgets
lint-enforced.

## Out of scope

New tracks, kart bumping physics, boost pads (debt #2 stays open), final
art (operator ladder), adventure/multiplayer.
