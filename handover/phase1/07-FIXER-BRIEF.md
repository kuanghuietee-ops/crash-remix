# Fixer brief — Phase 1 Wave A audit-fix run

Every fix subagent reads this file first. It is the contract. Nothing in it is
optional, and none of it may be "simplified" for expedience.

## Where you are

Repo `/root/crash-remix`, branch `master`. The audit being worked is
`docs/audits/2026-07-24-phase1-wave-a-audit.md`. The remaining work and its live
status is `handover/phase1/06-FIX-LEDGER.md`. All P0 and P1 findings are already
fixed and committed; you are working P2 and P3 remainders.

Read before touching anything: `/root/CLAUDE.md`, `/root/crash-remix/CLAUDE.md`,
the audit section for your finding, and `handover/phase1/06-FIX-LEDGER.md`.

## The loop, per finding

1. **Verify the finding is real** by reading the actual code. Do not fix from the
   audit's description alone. If it is not real, stop and report `REJECTED` with
   the evidence that refutes it. A rejection is a good outcome; an invented fix is
   not.
2. **Write the failing test first.** Run it. Capture the red output verbatim —
   the command and the failure text go in your report. A fix with no recorded red
   step will be rejected on audit and you will be asked to redo it.
3. **Make the smallest fix that makes it green.**
4. **Grep every call site** of any function signature you changed, and list what
   you found in your report.
5. **Run the full verification block** (below) and report the counts.
6. **Commit that one finding alone**, explicit paths only.
7. Update your finding's row in `06-FIX-LEDGER.md` to its terminal status with the
   evidence (test name for FIXED, reason + unblocker for DEFERRED, the refutation
   for REJECTED). Commit the ledger edit with the fix.

One finding per commit. Never batch two findings into one commit.

## Verification block

```bash
cd /root/crash-remix
scripts/run_gut.sh
python3 scripts/lint_gameplay_numbers.py
python3 scripts/check_content_vocabulary.py
python3 scripts/lint_traversal_authoring.py
python3 scripts/lint_level_authoring.py
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
```

Baseline to beat, established 2026-07-24 at `975df4e`: GUT 415/415 (4,032 asserts),
Python 47/47, every lint EXIT=0. Test counts go **up** or stay level, never down.

## Hard rules

- **Never weaken a test, a lint, an assertion, or a guard** to make something pass.
  If a test blocks a correct fix, the test is a finding of its own — report it, do
  not edit it into agreement.
- **No gameplay numbers in `src/gameplay/**`** beyond `0`, `1`, `-1`. New numbers go
  into a typed resource under `data/tuning/` and must have a real runtime consumer.
  A field with no consumer is the exact failure this project exists to prevent.
- **Never mark or infer a human gate pass.** Do not touch `docs/qa/phase05-gate-f2.md`
  or any gate record. Gate F2 is **WAIVED BY OPERATOR — NOT PASSED**.
- **Do not start Task 17 or Wave B.** Work stops at Checkpoint A.
- **This tree is shared with another agent.** Run `git status --porcelain` before
  every commit and stage only paths you personally changed. Never `git add -A`,
  `git add .`, or `git commit -a`. Never `git checkout -- <path>`, `git restore`,
  `git reset --hard`, or `git clean -f` — copy a file aside instead. No push, no
  remotes.
- **Preserve pre-existing modified and untracked files**, especially `CLAUDE.md`,
  `docs/superpowers/specs/2026-07-23-crash-remix-design.md`, and everything under
  `docs/audits/`, `docs/qa/` and `handover/`.
- **Never write to live state from a test.** The `LivePollution` tripwire is
  fail-closed by design; if you trip it, fix the caller, never the tripwire.
- Tests: no shared GUT helpers across files, `wait_physics_frames` not
  `wait_frames`, restore any autoload state in `after_each`, and deep-copy tuning
  resources properly (`duplicate(true)` alone does **not** isolate catalog
  sub-resources in Godot 4.7.1 — see P1-12; use the established helper).

## Your report back

Plain text, per finding:

- finding id and verdict (`FIXED` / `REJECTED` / `DEFERRED`)
- the red evidence: the exact command and the failure output before the fix
- what you changed and why, in one short paragraph
- the green evidence: full verification block results with counts
- files changed, and the commit sha
- call sites grepped for any changed signature
- anything adjacent you noticed but did not fix — say it, do not silently ship it

Do not claim anything works that you did not run. "Should work" is not a status.
</content>
