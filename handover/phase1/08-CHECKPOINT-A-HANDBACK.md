# Phase 1 — CHECKPOINT A handback

**Date:** 2026-07-25 · **Commit:** `1f3fd41` · **Branch:** `master` (local only, never pushed)

This is the mandatory full-stop handback required by `02-PLAN.md` after Task 16. It uses that
plan's handback template. **No human gate has been run, judged, or inferred by any agent.**

---

## Handback report

```
Phase 1 Wave A slice built (audit-fix pass complete).

GUT: 454 tests / 4,293 asserts (baseline at this session's start: 415 / 4,032).
Python: 70 tests (baseline: 47).
Lints green: gameplay-numbers EXIT=0 / content-vocabulary EXIT=0 /
  traversal-authoring EXIT=0 / level-authoring EXIT=0.
Export tuning smoke: EXIT=0 — sections: move, input, camera, depth, wall_run,
  grind, swing, phase, economy; level metas: n_sanity_beach.
  Runtime tuning fingerprint: 73d460e53326e1429f2b30f3a9f7cdee5ec18b2535d63cf6c0925039e1f4d3c0
APK: sha256 3b48ea704d50b2fa5db7755511b6f02aa7e5d68c2a9e8f2bb48980a0e6f5f6a8
  built from commit 1f3fd4156d74552bd324b53193f0ef5349acee65 with a clean tree.

Graybox/placeholder disclosure — what a friend would actually see:
  every mesh is procedural graybox; assets/models, assets/textures and
  assets/audio contain only .gitkeep, so there is NO art and NO audio at all;
  the level is undressed; audio slots are silent; there is no hog, no Papu, and
  no boss. Nothing is extracted from any shipped Crash game.

Checkpoint coverage: the full run loop is exercised end to end through the real
  scene — real spawn on authored floor, real player body entering the Finish
  area, real deaths, real checkpoints, real crate breaks, real results and
  profile write. ENEMIES ARE NOT PRESENT — NOT TESTED (Checkpoint A is
  enemy-free by design; enemies are Task 17 / Wave B).
  H15 soft-ghost-marker phone verdict: NOT RUN — operator's call on device.

Human gates: Gate F2 WAIVED BY OPERATOR — NOT PASSED (the underlying QA result
  record is untouched and remains separate); likeness gate NOT RUN; Island Cut
  acceptance NOT RUN. No gate was run, judged, scored, or inferred by any agent.

Operator decisions consumed: Q1–Q14 as ruled on 2026-07-24 (all recommended
  defaults accepted, recorded in 01-DESIGN.md §1).

[proposed] numbers changed from 01-DESIGN §4.2: ONE.
  economy.checkpoint_respawn_offset = Vector3(0, -0.45, 2) — NEW FIELD, not a
  changed value. This number already existed and already governed play; it was
  authored inside scenes/props/crate_checkpoint.tscn as a Marker3D position,
  where the numeric lint could not see it and the on-device drawer could not
  tune it (finding D9). The value is preserved EXACTLY. No feel value was
  altered: move/input/camera/depth/wall_run/grind/swing/phase are byte-identical.

Spec ambiguities newly found: ONE, needing an operator ruling — see D13 below.

Not tested: feel, thermals, load-time budgets, battery, touch ergonomics, and
  everything else only a phone can answer. Additionally NOT verified on device:
  the level-load time change described under "Read this before you play".
```

---

## Read this before you play

Three things you should know that a bare green report would hide.

### 1. The suite is NOT deterministically green

Measured on an idle box at this commit: **2 red runs out of 25**, and **4 out of 24** before
the fix. It is better, it is not fixed, and per `CLAUDE.md` rule 4 it must not be described as
green.

What fails is never an assertion. The game logic passes every time — 454/454 whenever the run
completes. What fails is GUT's "unexpected engine errors" capture catching renderer noise
(`Parameter "m" is null`, `unimplemented base type encountered in renderer scene cull`) while a
scene tears down. Three genuinely real races were found and fixed in the threaded level loader
(finding N2): a duplicate in-flight load request after quit→re-enter, sub-threaded loading
racing the main thread on the same meshes, and a shared resource cache letting one load overlap
another tree's teardown. Those were real bugs reachable in production, not just in tests.

**This could have been made "green" in thirty seconds** by telling GUT to ignore those engine
errors. That would weaken the harness for all 454 tests to silence four lines, so it was not
done. Two other candidate fixes were tried, measured, and rejected — both are recorded as
negative results in the ledger so nobody repeats them.

**Recommended next step (your call, not done):** run the three integration suites that drive the
whole `main.tscn` in their own Godot process, separate from the rest. That removes the
cross-test resource sharing without silencing anything or weakening a single assertion.

### 2. Level re-entry may now be slower on device

The N2 fix switched level loading to `CACHE_MODE_REPLACE`, so re-entering a level reloads it
from disk instead of reusing the cache. Suite wall-clock did not move (61.5s vs 63.3s average),
but §7.1 budgets hub→level at under 3 seconds and **only the phone can answer whether that still
holds**. Please watch it when you play, especially on retry-from-pause and retry-from-results.

### 3. One question needs your ruling — D13

Landing on top of a standard crate currently does nothing. That matches 02-PLAN Task 6, which
lists the breaking verbs as spin / jump-under / slam / slide. 01-DESIGN §4.5 is silent on it.
Real Crash canon makes landing on top one of the two foundational ways to break a crate.

So the code is not wrong against the plan — the plan may be wrong against canon. **Restore canon
parity (landing on top also breaks a standard crate), or keep it as the bounce crate's
distinguishing interaction?** Nothing was changed either way.

---

## What this session did

Resumed the Phase 1 Wave A audit-fix run from finding D9 and worked it to completion:
**59 commits**, one finding each, failing test first.

| Outcome | Count | |
|---|---|---|
| FIXED | 45 | each with a named test |
| REJECTED | 3 | finding verified NOT real by reading the audited commit |
| DEFERRED | 4 | with the reason and what would unblock it |
| NOT APPLICABLE | 2 | phantom rows whose claim was unrecoverable |
| Still open | 0 | |

Full per-finding detail with evidence: `handover/phase1/06-FIX-LEDGER.md`.

### Four findings were raised by auditing the fixes, not by the original audit

- **N1** — the D9 fix added a tuning field with a sentinel default of `Vector3(-999999,…)` and
  left it the only 1 of 20 economy fields with no validation. A leaked sentinel would respawn the
  player 999 km under the world on every checkpoint: an unrecoverable death loop, i.e. the
  original audit's P0-2 reintroduced through tuning. Fixed with a cross-field invariant against
  the already-tuned fall floor.
- **N2** — the suite was never deterministically green. See above.
- **N3** — the G13 fix left an armed tripwire: a real segment file would fail the lint the moment
  Task 17 revived it. Classified deliberately instead of left to detonate.
- **I15–I19** — the audit's P3 list ended with the bare line "I15–I21 hub/UI minors" and the raw
  notes behind it were gone. Rather than guess or drop them, the lane was re-audited from
  scratch: five real findings, verified by headless probe. **I15 was above P3** — the hub never
  actually paused, so the player, input router and touch controls kept running underneath the
  level-list modal. I20/I21 are closed honestly as unrecoverable rather than padded.

### Three original findings were wrong

`I9` claimed `ResultsScreen.present()` was an empty stub — it has a real body and real coverage
at the audited commit. `E10` claimed an unguarded null dereference with no reachable call path.
`C17` was a duplicate of `J4`. All three were rejected with evidence rather than "fixed" with
ceremony.

---

## Verification commands

```bash
cd /root/crash-remix
scripts/run_gut.sh                                    # 454/454, 4,293 asserts (see caveat 1)
python3 scripts/lint_gameplay_numbers.py              # EXIT=0
python3 scripts/check_content_vocabulary.py           # EXIT=0
python3 scripts/lint_traversal_authoring.py           # EXIT=0
python3 scripts/lint_level_authoring.py               # EXIT=0
python3 -m unittest discover -s tests -p 'test_*.py'  # 70/70
bash scripts/verify_exported_tuning.sh                # EXIT=0
git diff --check                                      # EXIT=0
```

---

## The stop

**Task 17 and Wave B have NOT been started, and must not be until you say so.** Wave B has zero
commits. This checkpoint exists so the first slice stays narrow: you play the beach on the phone
and confirm the loop feels right before content multiplies across two more levels and a boss.

Install: `build/crash-remix-debug.apk` (sha256 above).
</content>

---

# ADDENDUM — independent recheck, and the build that supersedes the one above

**Date:** 2026-07-25 (later same day) · **Commit:** `4f5bab9`

Everything above this line was written at commit `1f3fd41` and is preserved unaltered as the
record of that moment. **The APK named above is superseded — do not install it.** The operator
then asked for a fresh-eyes recheck of *both* fix lanes before playing, which is what produced
everything below.

## What the recheck was

Eight independent agents over the full 99-file, +9,759/−699 diff of both lanes — the earlier
agent's 70 commits and this session's 60 — under one rule: **check into the code, do not believe
the surface.** Every claim was executed, not read. Findings in
`docs/audits/2026-07-25-phase1-recheck/`.

It found **17 issues, two of them P1**, in work that had already been reported clean.

## The two P1s

**R1 was mine, and it was a partial fix wearing a complete one's clothes.** The N1 guard I had
personally approved bounded one axis of three: `.x` and `.z` of the checkpoint respawn offset
were unbounded and reachable from the on-device drawer's ±1,000,000 spinboxes. Two agents found
it independently. `Vector3(1000000, -7.99, 1000000)` passed validation — P0-2's unrecoverable
death loop, sideways instead of downward. The guard-the-guard test could not catch it because it
demanded only *a* bad value per field *name*.

**R2 was a duplicated parser nobody had looked at.** `lint_traversal_authoring.py` carries its
own copy of the scene parser and had received *neither* fix applied to its twin — still blind to
Godot's `transform =` save format, still silently dropping unclassifiable sections. Dormant only
because wall-run content happens to be `position =`-only today.

## What held up

The two P0s that nearly shipped were re-broken and re-caught. `P1-11`'s twelve cells — a table
of tests the original audit had *already proven vacuous* — were each re-mutated to their literal
original shape, and **all twelve now genuinely catch their bug**. All three `REJECTED` rows hold
when re-read at `5e49d77`. All five `DEFERRED` rows are genuinely deferred. A sweep of all 155
exported tuning fields found exactly one with no runtime consumer, and it is legitimately
lint-only.

## Loop closure

Ten fixes were made in response, then **audited by a further fresh-eyes pass** — each re-broken,
its named test confirmed RED, the file restored byte-identical. All ten hold: no regressions, no
vacuous tests, no scope creep. That extra pass exists because R1 is proof that a fix reviewed
only by the session that commissioned it is not reviewed.

Eleven P3-class items remain, each deferred in writing with its specific unblocker. Zero open.

## Superseding verification

```
GUT: 464 tests / 4,471 asserts (was 454 / 4,293; 415 / 4,032 at session start).
Python: 75 tests (was 47).
Lints: gameplay-numbers / content-vocabulary / traversal-authoring / level-authoring — all EXIT=0.
Export tuning smoke: EXIT=0.
git diff --check: EXIT=0.

APK: sha256 8ab0c8c20f8d8c4199b28a99ccdf4ddfed4fdc4da281348fcc2f424b012c56af
  built from commit 080546b with a clean tree.
```

**Suite nondeterminism (N2) improved again:** 0 red in 14 consecutive full-suite runs, against
2-in-25 before the recheck fixes and 4-in-24 originally. Still not claimed as proven
deterministic — 14 clean runs is evidence, not proof, and the row stays DEFERRED with its
recommended structural fix recorded.

## The repo is now public

By operator decision on 2026-07-25 this repo has a public remote,
`https://github.com/kuanghuietee-ops/crash-remix`, with the APK attached to release
`v0.1.0-checkpoint-a`. `CLAUDE.md` was corrected to describe that reality rather than the
"stays local / never distributed" rules it superseded. History was scanned before publication:
no `.env`, no tokens, no private keys across 206 commits.

## What is still NOT established

- **Feel, thermals, load-time budgets, touch ergonomics** — only the phone answers these.
  `CACHE_MODE_REPLACE` (the N2 fix) reloads a level from disk on re-entry, so watch the
  §7.1 sub-3s hub→level budget on retry.
- **One continuous witnessed spawn-to-Finish playthrough.** The real player was proven to walk
  into the real Finish and complete with a real profile write; the one required jump has a 2.5×
  margin (2.0 m gap vs 5.57 m range); all seven segment floors connect. But no agent watched a
  single unbroken run from spawn to exit. That is precisely what you are about to do.
- Gate F2 remains **WAIVED BY OPERATOR — NOT PASSED**. Likeness gate and Island Cut acceptance
  **NOT RUN**. No gate has been run, judged, scored or inferred by any agent.
