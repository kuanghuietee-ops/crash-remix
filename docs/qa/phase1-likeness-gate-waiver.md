# Phase 1 — likeness gate operator waiver

Date: 28 July 2026
Operator: Tee Kuang Huie
Branch: `worktree-environment-package`

## Decision

**WAIVED BY OPERATOR FOR THE N. SANITY BEACH TEXTURE PASS ONLY — NOT PASSED**

The operator was shown that the likeness gate is unrun and that design doc §9.2/§9.3
make it a hard block on all environment and level art, including the first kit. The
operator was offered three courses — run the gate first, waive it and proceed, or leave
new art alone — and explicitly chose to waive and proceed, accepting the risk.

This waiver changes the entry condition for one package of environment art only. It does
not certify the likeness gate, rewrite its criteria, or convert an unrun gate into a
pass. No friend has been shown the model.

## Evidence preserved

`docs/qa/phase1-likeness-gate.md` remains the authoritative likeness-gate record and is
unchanged by this waiver. Its unresolved evidence is that **the gate has not been run at
all**:

- no date, model file, commit or triangle count recorded;
- none of the three friend rows filled in — no friend has been shown the model cold;
- the result line still reads PASS / FAIL / NOT RUN with nothing selected;
- the iteration table is empty, so no round has been attempted.

## Risk accepted

The operator accepts that the beach/jungle kit is being textured around a Crash model
that no outside observer has yet identified unprompted. If the model later fails the
likeness gate and its proportions change, the environment art textured under this waiver
may need rework to sit correctly against a revised mascot — including its palette,
scale relationships and the trim sheet's shared bands.

This is the specific failure §9.3 exists to prevent, stated plainly rather than softened:
the gate is the mechanism that stops environment work being built around a mascot that
reads as "off-brand orange thing", and it is being bypassed rather than satisfied.

## Scope boundary

This waiver unlocks only:

- an original, self-made texture atlas and trim sheet for the existing 25-piece
  beach/jungle kit under `assets/models/kits/`;
- the material, UV and `.import` changes needed to put those textures on that kit;
- the `kit_piece` triangle band in `data/tuning/art_budget.tres`, whose values
  (100–2,000) the operator chose after being shown the measured range of 100–1,564;
- tests, lints and budget checks covering the above.

It does **not** unlock any further environment kit, the temple-ruins or any other §9.4
kit, enemies, rideables, bosses, Phase 2 content, baked lighting as a separate package,
the Island Cut acceptance gate, or Gate F and Gate F2. Those remain in force. A later
operator decision is required before any of them begins.

## Agent boundary

This document transcribes the operator's explicit decision, taken in the session of
28 July 2026. No agent ran, judged, passed, or certified the likeness gate, and no agent
edited `docs/qa/phase1-likeness-gate.md` to manufacture a pass — it remains blank,
which is the honest record of an unrun gate.
