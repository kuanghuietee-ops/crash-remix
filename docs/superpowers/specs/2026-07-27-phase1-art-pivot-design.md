# Phase 1 art pivot — design

**Date:** 2026-07-27
**Status:** **APPROVED by the operator 2026-07-28.** The §5 amendments have been applied
to the main design doc; the two documents now agree. Next step is `writing-plans` for
the §4 code-side pipeline.
**Relationship to the main spec:** this document *amends* §9.2, §9.3 and §12 of
`2026-07-23-crash-remix-design.md`. Those amendments are **applied** as of 2026-07-28 —
the main spec remains the source of truth and now carries the new order; this document
is the rationale record for why it changed.

---

## 1. Why this exists

Phase 1's code track ran to completion — the Island Cut's four pieces (N. Sanity Beach,
Boulders, Hog Wild, Papu Papu) are built, tested and on `wave-e-integration`. The art
track never started. Since the main spec always put Crash's 80–120 hours *inside* Phase 1
and called art the project's critical path, **this pivot is a return to the plan, not a
departure from it.** What changes is only the ordering inside the phase, and the timing
of the friends release.

The operator does all art himself in Blender, learning from zero. Nothing here is
commissioned and nothing is extracted from any shipped Crash game — with the repo now
public, that rule is the project's only real legal defence.

## 2. Decisions taken

Four forks were decided in the 2026-07-27 brainstorm. Recorded with what was rejected,
so they don't get silently re-litigated later.

**2.1 The learning order holds.** Crash is not the first thing modelled. Rigging and
weight-painting get learned on a throwaway biped first, because first-timer mistakes on
the mascot are the most expensive mistakes available.
*Rejected:* going straight at Crash; crate-then-Crash.

**2.2 The friends release waits for the art.** The Island Cut will not be handed to
anyone until Phase 1's art is done. Friends get one finished-looking thing rather than a
graybox build with a disclosure list.
*Rejected:* shipping graybox now for feel signal (the spec's original intent); splitting
so the operator plays now and friends wait.
*Consequence accepted, on the record:* nobody outside the operator's own judgement
validates the core loop for 8–12 months. See §6.1.

**2.3 The whole Island Cut gets real art**, not a character-only or single-level subset.
All four pieces, including the hog and Papu.
*Rejected:* stopping the ladder after Crash (~180–260h); Crash-and-crates only
(~140–200h).
*Note:* this does **not** invert the learning order, provided the ladder is run in
sequence — the rideable and the boss fall naturally at the end anyway.

**2.4 The likeness gate is read literally.** It blocks *all* environment and level art,
including the first jungle kit. Crash therefore moves ahead of the kit.
*Context:* §9.2 put the jungle kit at rung 2 and Crash at rung 4, while §9.3 and §12 say
the likeness gate precedes level-art production. Those cannot both hold. The operator
resolved it in favour of the gate.
*Rejected:* reading the gate as guarding only the Phase 2+ multi-kit push; holding just
the jungle kit while leaving Crash at rung 4.

## 3. The revised Phase 1 art ladder

| # | Asset | Hours | Notes |
|---|---|---|---|
| 1 | Crate family | 30–40 | Blender bootcamp: model, UV, hand-paint, break-animation. The most-seen object in the game; its break *feel* matters more than any environment |
| 2 | Lab assistant | 30–40 | First biped. Rigify, first weight-paint, first walk cycle. Deliberately low expectations. Earns its keep later as 5 costume variants on one rig |
| 3 | **Crash** | 80–120 | Orthographic reference sheets *before* modelling. PS1-era proportions with modern surfaces, matte hand-painted, explicitly not N. Sane fur. 10–12k tris, one 2048. ~20-clip set including 4–6 death gags |
| — | **LIKENESS GATE** | — | **Hard block.** Three friends, untextured model, shown cold. All three name him unprompted or the model iterates. Human-only; no agent may mark, infer or proceed past it |
| 4 | Jungle/beach kit | 40–60 | 15–20 modular pieces + trim sheet. First kit is the slow one |
| 5 | Skink, crab, plant | 36–60 | 12–20h each once fluent. Mixamo retarget for locomotion, signature attacks hand-keyed |
| 6 | Practice quadruped → hog | 35–55 | Quadruped rigs are the hardest rigging in the project. The throwaway practice one is not optional padding. *(Practice quadruped is unbudgeted in §9.5; 15–25h is an estimate, not a spec figure.)* |
| 7 | Papu Papu | 30–50 | Boss. Deliberately last, when skill has peaked |

**Total ≈ 280–425h ≈ 8–12 months at ~8 art-hours/week**, plus an unallocated share of the
project's 40–60h VFX/UI art budget.

Three gates stay in force for the whole stretch:

- **The likeness gate**, as placed above.
- **Weekly on-device play** by the operator. Never-cut in §13, and with the friends
  release deferred it is now the *only* validation signal the project has.
- **The Island Cut acceptance gate**, which moves from the start of this ladder to the
  end. `docs/qa/phase1-island-cut-acceptance.md` stands unchanged; only its timing moves.

## 4. The code-side pipeline

Built now, in parallel, because it is all valid against graybox and none of it depends on
what the art turns out to look like. Four units, each independently testable, each
slotting into machinery the repo already has.

**4.1 Import/export contract.** One documented path from `.blend` to in-game: Blender-side
conventions for units, axis, scale, naming and material slots; Godot-side import presets
committed to the repo. Exists so an asset never arrives sideways at the wrong scale.

**4.2 Budget lint.** A new script joining the existing pre-commit lint family
(`lint_gameplay_numbers`, `lint_traversal_authoring`, `lint_level_authoring`). Asserts
§9.4 per asset category — Crash 10–12k tris, enemies 3–6k, bosses 15–25k, plus texture
dimensions and ASTC format. Note the distinction: those are *per-asset* caps, whereas
§9.4's ≤120 draw calls typical / 180 peak and ≤150k visible tris typical / 250k peak are
*whole-frame* budgets, so they can only be checked in an assembled scene, not on a lone
mesh. The lint enforces the per-asset caps; the frame budgets belong to §4.4's on-device
telemetry and to the look-dev scene. A bust asset then fails at the moment it is made
rather than months later. **Every threshold lives in a `.tres`**, per repo rule 1 — no
numeric literals.

**4.3 Look-dev scene.** A bare scene that loads one asset with the shipping material and
lighting setup, deployable through the existing `scripts/deploy_android.sh`. Turns "how
does this read at phone size" from an hour into minutes. The operator will ask that
question several hundred times.

**4.4 Budget telemetry on the debug HUD.** Extends the existing tuning-fingerprint readout
with live triangle count, draw calls and texture memory, so an over-budget asset is
*visible on the device* rather than inferred from a lint.

## 5. Required amendments to the main design doc

The decisions above contradict `2026-07-23-crash-remix-design.md` as committed. Per repo
`CLAUDE.md` — if code and spec disagree, say which is wrong rather than silently picking —
the spec gets edited. **All three edits were applied on 2026-07-28**, after the operator
approved this document.

- **§9.2** — resequence the learning order: lab assistant becomes #2, Crash #3, jungle kit
  #4. Rungs 5–7 unchanged.
- **§9.3** — add one explicit sentence that the likeness gate blocks *all* environment and
  level art, including the first learning kit. This is the ambiguity that produced the
  contradiction; closing it is the whole point.
- **§12, Phase 1** — record that the Island Cut friends release moves to the end of the
  art ladder, and that Phase 2 does not open until Phase 1 art completes. The existing
  sentence "Crash himself passes the likeness gate (§9.3) before level-art production"
  becomes accurate rather than contradictory once §9.2 is resequenced.

## 6. Risks on the record

**6.1 Deferring the release removes all outside validation for 8–12 months.** This is
structurally the shape that produced the Reaper Rush failure — a large build nobody
outside the author had played. The operator chose it knowingly after the risk was raised.
The mitigation is not decorative: **weekly on-device play is now load-bearing**, and if it
lapses the project has no tripwire at all.

**6.2 A likeness-gate failure lands at ~140–200h in.** That is the expensive branch.
Orthographic reference sheets before modelling are the cheap insurance (an evening's work
against twenty hours of eyeballing), and the plan should budget for at least one iteration
rather than treating a first-try pass as the default.

**6.3 The hog's quadruped rig is the hardest single asset in the ladder.** The spec calls
quadruped rigging the hardest work in the project. Skipping the practice quadruped to save
20 hours risks the rig it was meant to protect.

**6.4 Every hour figure here is the spec's estimate, not measured velocity.** No art has
been produced yet, so the whole 280–425h range is unvalidated. **The crate is the
calibration instrument** — model it, time it honestly, and re-baseline the entire ladder
against what it actually took before trusting any date downstream of it.

**6.5 Scope-cut context.** If velocity comes in under this schedule, §13's cut ladder
applies from the top — bonus wing first. Nothing in Phase 1's art is on the cut ladder;
the likeness gate and the feel gate are explicitly never-cut.

## 7. Definition of done

Phase 1 art is complete when **all** of the following hold:

1. Every Island Cut asset is modelled, textured, in-engine, and passing the §4.2 budget lint.
2. The likeness gate has passed and is recorded — three friends named, dated, in
   `docs/qa/phase1-likeness-gate.md`.
3. The operator's own four-piece verdict on the *arted* build is recorded in
   `docs/qa/phase1-island-cut-acceptance.md`.

Then, and only then, the friends release runs and Phase 2 (Warp Room 1 — The Lost City,
Road to Nowhere, colored-gem line, bonus-wing scaffold) opens.

## 8. Resuming

Open items, in order:

1. ~~**Operator reviews this document.**~~ **Done 2026-07-28 — approved.**
2. ~~Apply the §5 amendments to the main design doc.~~ **Done 2026-07-28.**
3. `writing-plans` for the §4 code-side pipeline — that is the only track with agent work
   in it, and it should land before rung 1 so the crate is the first asset the lint sees.
4. Operator starts rung 1 (crate family) in Blender, and times it (§6.4).

Not in scope for this document, and still open independently: the ~48 uncommitted audit
and handover files in the `master` working tree, and the deferred Island Cut acceptance
paperwork.
