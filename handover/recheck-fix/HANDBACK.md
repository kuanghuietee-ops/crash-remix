# Phase 0.5 recheck-fix handback

Both recheck findings are fixed. No gameplay, scene, tuning, or Android
runtime file changed.

## Finding dispositions

| Finding | Disposition | Evidence |
|---|---|---|
| R1 — exported-tuning verifier depended on unavailable `rg` | **FIXED** | `test_export_verifier_only_invokes_available_commands` and `test_export_verifier_reports_success_on_a_good_pack`; real verifier `EXIT=0`; deliberately incomplete log `EXIT=1`; commit `6152648` |
| R2 — `PhaseState` leaked set and cooldown between tests | **FIXED** | `after_each` restores the authored set, all timestamps use `_next_test_time_s`, and `test_respawn_restores_a_solid_platform_under_the_player` passes without its defensive state-normalisation guard; commit `547bb6c` |

No finding was deferred or found not applicable.

## R1 verification

The required red run used the normal system path:

`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`

Before the fix:

- the command-availability test reported exactly `['rg']`;
- the real-pack success test returned **127**;
- the runtime output did show all nine tuning paths, but no assertion had
  completed and the success line was never reached.

After replacing the four `rg -q` calls with `grep -qE`:

- both new Python tests pass;
- the real verifier prints `Exported tuning smoke passed`;
- the real verifier exits **0** after finding the fingerprint header, one bare
  64-hex fingerprint, and all nine authored tuning paths.

To prove the assertions can still fail, a temporary fake Godot executable
emitted a valid fingerprint header, a valid 64-hex line, and eight tuning
paths, deliberately omitting `res://data/tuning/phase.tres`. The verifier
exited **1**. The temporary executable was deleted and was not committed.

The earlier false-pass wording was corrected explicitly in
`handover/task15-fix/HANDBACK.md` and `handover/phase05/02-REVIEW.md`; the
historical error was not silently erased.

## R2 verification

`tests/integration/test_phase_state_integration.gd` now:

- resets the `PhaseState` autoload to the authored blue set after every test;
- clears the toggle cooldown through that same reset;
- obtains every toggle timestamp from one monotonic helper;
- removes only the redundant orange-state normalisation guard from the
  respawn integration test, preserving all of its assertions.

The complete GUT suite was run twice consecutively after this change. Both
runs produced identical results: **213/213 tests passing**, **1,256
assertions**, **20 scripts**.

## Final verification

Executed from the committed tree:

| Check | Result |
|---|---|
| GUT | **213/213 passing**, 1,256 assertions, 20 scripts |
| Python unittest discovery | **22/22 passing** |
| Gameplay numeric-literal lint | **passed** |
| Content-vocabulary tripwire | **passed** |
| Traversal authoring lint | **passed**, exit 0 with no findings |
| Exported-tuning verifier | **passed**, `EXIT=0`, success line printed |

Python increased from the 20-test baseline to 22. GUT remained at 213; no test
or assertion was removed or weakened.

## Scope and discrepancies

- Nothing under `src/`, `scenes/`, or `data/` changed.
- No APK rebuild was required because these fixes affect only repository
  verification, documentation, and test isolation.
- The audit's practical conclusion about `rg` was correct for the normal
  system environment. Codex's interactive shell additionally exposes a
  private bundled `rg` path, so the red reproduction deliberately used the
  normal system `PATH` that lacks it.
- Nothing in either finding or the ordered fix plan remained unfixable.

Gate F and Gate F2 were not run, scored, judged, filled in, or inferred.
Gate F's latency measurement, 20-minute thermal soak, and three-separate-days
criteria remain open. F4's displaced Phase 0 content remains an operator
decision.
