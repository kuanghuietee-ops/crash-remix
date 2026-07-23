# Phase 0.5 — Gate F2 device procedure

> **Human-only gate.** The coding agent cannot run, judge, certify, or fill in any
> result below. Gate F2 must be played on a real phone by thumb. Criterion 4 also
> requires the same zero-instruction blind-transfer friend who completed Gate F
> criterion 5; another observer cannot substitute for that person.

Automated tests and a successful Android export only establish that the build is
runnable. They do not establish any Gate F2 result.

## Prerequisites

- Use a real Android phone and touch controls only; do not use a keyboard or gamepad.
- Keep the phone in landscape orientation.
- Build, install, and launch the current commit with:

  ```bash
  scripts/deploy_android.sh
  ```

- If Android reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, stop. Preserve
  `user://tuning/override.tres` before uninstalling because uninstalling deletes it.
- Record the build and device before testing:

  | Item | Operator record |
  |---|---|
  | Date | |
  | Commit | |
  | Phone / Android version | |
  | Tuning fingerprint | |
  | Authored tuning or override fingerprint | |

The route is wall-run canyon → three grind rails → swing chain → phase gauntlet.
The thin green bands between segments are bare debug respawn points. They only move
the fall-respawn location forward; they are not progression checkpoints.

## 1. Wall-run attach and detach

Count exactly five attempts in the wall-run canyon. An attempt succeeds only when the
player attaches to a wall strip, detaches, and lands on the exit pad.

| Attempt | Success / fail | Observation |
|---:|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |

**Pass criterion:** wall-run attach→detach onto a pad, **≥4/5**.

Recorded result: ___ / 5. Result: **PASS / FAIL / NOT RUN**

Relaunch the build after a successful attempt when needed to return to the start of
the wall-run segment. Do not silently discard or repeat a scored attempt.

## 2. Three-rail hop sequence

Starting from the debug respawn after the wall-run, try to complete the authored
three-rail hop sequence cleanly. Count each fall or unintended rail exit as an
attempt. Record the first clean attempt; stop after attempt five if none is clean.

| Attempt | Clean / not clean | Observation |
|---:|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |

**Pass criterion:** a 3-rail hop sequence, clean **by attempt five**.

First clean attempt: ___. Result: **PASS / FAIL / NOT RUN**

## 3. Phase toggle in mid-jump

Reach the phase gauntlet through the swing chain and activate the debug respawn before
the phase platforms. Score ten consecutive required mid-air transfers. A transfer
succeeds only when PHASE is pressed after takeoff and the player lands safely on the
next platform that the toggle makes solid.

| Attempt | Success / fail | Observation |
|---:|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| 6 | | |
| 7 | | |
| 8 | | |
| 9 | | |
| 10 | | |

**Pass criterion:** phase-toggle mid-jump gauntlet, **≥8/10**.

Recorded result: ___ / 10. Result: **PASS / FAIL / NOT RUN**

## 4. Blind-transfer camera check

This check belongs to the same friend who cleared Gate F's tutorial strip with zero
instruction. Do not teach the wall-run, explain the camera behavior, or replace the
friend with an observer who already knows the implementation.

1. Relaunch so the friend starts at the wall-run canyon.
2. Hand over the phone with no gameplay instruction.
3. Let the friend encounter and perform the wall-run.
4. After the attempt, ask directly: **“Did the camera disorient you at any point
   during the wall-run?”**
5. Record the answer verbatim. Do not infer an answer from whether the friend
   completed the jump.

Friend's answer:

>

**Pass criterion:** the camera **never disorients the blind-transfer friend** during
a wall-run — **asked, not assumed**.

Result: **PASS / FAIL / NOT RUN / COULD NOT JUDGE**

If the designated friend does not encounter or perform a wall-run, record
`COULD NOT JUDGE`; Gate F2 is not passed.

## Gate decision

| Criterion | Required result | Operator result |
|---|---|---|
| Wall-run | ≥4/5 | |
| Three-rail hop | Clean by attempt five | |
| Phase toggle | ≥8/10 | |
| Blind-transfer camera | Never disorients; explicitly asked | |

Gate F2 is passed only when the operator records all four criteria as passing.
Anything else is **failed or still open**, never an inferred pass.

Operator decision: **PASS / FAIL / OPEN**

Operator name / date: ______________________________

Notes and tuning changes proposed after the run:

- _Operator notes go here._
