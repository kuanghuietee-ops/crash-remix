# Phase 1 — weekly device check

> **Human-only procedure.** The coding agent cannot run, judge, certify, or fill in
> any result below. Every number here comes off a real phone in the operator's hand.
> A green automated suite and a successful Android export establish only that the
> build is runnable. They establish no result on this page.

01-DESIGN's hard rule: the operator plays every build on device at least weekly.
This is that check, written down so it is the same check each time.

## Prerequisites

- A real Android phone, touch only, landscape.
- Build, install and launch the current commit with:

  ```bash
  scripts/deploy_android.sh
  ```

- If Android reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, stop. Preserve
  `user://tuning/override.tres` before uninstalling, because uninstalling deletes it.
- The performance readout sits in the top-right corner and appears in debug builds
  only. If it is not there, this is not a debug build and the numbers below cannot
  be taken.

| Item | Operator record |
|---|---|
| Date | |
| Commit | |
| APK SHA-256 | |
| Phone / Android version | |
| Tuning fingerprint | |
| `OVERRIDE ACTIVE` watermark shown? | |

## 1. Cold start and load budgets

Spec §7.1: cold start under 8 s on the reference device, hub→level under 3 s.
Time these from a fully closed app, not a resume.

| Measure | Budget | Observed | Pass / fail |
|---|---|---|---|
| Icon tap → hub interactive | < 8 s | | |
| Hub → N. Sanity Beach | < 3 s | | |
| Hub → Boulders | < 3 s | | |
| Hub → Hog Wild | < 3 s | | |
| Hub → Papu Papu | < 3 s | | |
| Retry from results | < 3 s | | |
| Retry from pause | < 3 s | | |

Watch the retry rows especially: level re-entry reloads from disk rather than
reusing the cache, and only the phone can say whether that still fits the budget.

## 2. Performance readout, per level

Spec §9.4 budgets: 60 fps typical with 1% low ≥ 50, ≤ 120 draw calls typical and
180 peak, ≤ 150k visible triangles typical and 250k peak.

Record what the readout shows after roughly thirty seconds of normal play in each
level, not at the loading screen.

| Level | FPS | 1% LOW | DRAW | PRIM | OBJ | SCALE | Pass / fail |
|---|---|---|---|---|---|---|---|
| N. Sanity Beach | | | | | | | |
| Boulders | | | | | | | |
| Hog Wild | | | | | | | |
| Papu Papu | | | | | | | |

A 1% low well below the average means hitching. Note whether it recovers within a
few seconds (a one-time cost, typically first-render shader compilation) or returns
every time a given event happens (a recurring cost).

Observed hitching, and what triggered it:

## 3. Twenty-minute thermal soak

Gate F criterion 2. Play continuously for twenty minutes without backgrounding the
app. Do not put the phone down on a cold surface or under a fan.

| Minute | FPS | 1% LOW | SCALE | Phone temperature by hand |
|---:|---|---|---|---|
| 0 | | | | |
| 5 | | | | |
| 10 | | | | |
| 15 | | | | |
| 20 | | | | |

Pass criterion: 60 fps sustained with dynamic resolution never below 0.7.

Result: **PASS / FAIL / NOT RUN**

Note whether the frame rate is capped. An uncapped display refresh above 60 will
pass the frame-rate half of this test while generating heat the budget never
assumed.

## 4. Lifecycle

| Check | Expected | Observed | Pass / fail |
|---|---|---|---|
| Pause mid-run, resume | Run continues exactly where it stopped | | |
| Background the app mid-run, return | Run resumes at the same point | | |
| Kill the app mid-run, relaunch | Offered resume at the last checkpoint | | |
| Complete a level, check the hub | Portal shows cleared | | |

## 5. Operator verdict

Anything that felt wrong but is not covered above:

Overall: **CONTINUE / FIX FIRST**

Operator name / date:
