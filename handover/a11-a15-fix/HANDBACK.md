# A11 / A15 gameplay-fix handback

Date: 2026-07-23

Starting revision: `e305dd1`

Final runtime-code revision: `bd78521f65b8800d22713681e6766261fe2c5c43`

## Outcome

Both assigned findings are fixed.

| Finding | Disposition | Evidence |
| --- | --- | --- |
| A11 | **FIXED** | A motionless or sub-boundary arrival is refused; the slowest permitted catch reaches the real `SecondAnchor`; a rope already caught at zero angle and zero angular velocity releases with non-zero forward velocity. |
| A15 | **FIXED** | After a real late authored rail hop misses its target, the real wall strip, real swing anchor, and third authored rail remain attachable; only the departed rail remains blocked. |

No stick-pumping was added. No authored geometry or scene changed. No existing
tuning value changed.

Gate F and Gate F2 remain human-only. Neither gate was run, judged, scored,
filled in, or inferred during this pass.

## A11 — guaranteed swing escape

The chosen mechanism uses both permitted safeguards:

1. A new minimum usable tangential catch speed refuses arrivals that would
   enter an inescapable damped swing.
2. The existing `release_boost_mps` is now also applied when an already-caught
   rope reaches zero angular velocity, so the degenerate caught state still
   has a forward escape.

This preserves the authored auto-catch/JUMP-release verb and the unforced
pendulum. The catch floor prevents the fixed point during normal entry; the
release fallback protects already-caught and restored edge states without
adding a new movement verb.

### New tuning field

- `SwingTuning.minimum_catch_speed_mps`
- Authored default: **6.5 m/s**
- Validation: greater than zero and no greater than
  `maximum_speed_mps`
- Legacy overrides: the field is backfilled through the swing migration
  cohort, preserving older operator values

`release_boost_mps` validation was also tightened to require a positive value,
because zero would reintroduce a zero-velocity release. Its authored value was
not changed.

### Worst permitted catch

`test_slowest_authored_catch_reaches_the_next_real_anchor` instantiates
`seg_swing_chain.tscn` and the real player. It catches `FirstAnchor` at the
bottom of the rope with exactly **6.5 m/s** forward tangential speed, waits
**15 physics frames**, releases, and follows the live physics/auto-catch loop.
The player reaches and catches the real **`SecondAnchor`** within the
60-frame escape window without respawning.

The boundary test separately proves that 6.49 m/s is refused and 6.5 m/s is
inclusive. The degenerate-state test proves a caught rope manually set to
`theta = 0` and `omega = 0` releases with non-zero forward velocity.

### A11 TDD evidence

Before the production fix, the new scenario run had **228 tests**, with
**225 passing and 3 failing**. The failures were the accepted zero-speed
catch, the accepted 6.49 m/s catch, and the zero-velocity release. The real
6.5 m/s escape case already reached `SecondAnchor`, which established that
6.5 m/s is viable in the authored chain rather than a synthetic threshold.

The completed A11 suite passed **230/230 tests** with **1,865 assertions**.

## A15 — missed hop no longer vetoes unrelated traversal

`_rail_hop_target` remains as intended-target metadata, but it no longer:

- filters the rail scan down to only the intended target;
- disables automatic wall-run attachment; or
- disables automatic swing catch.

`_rail_attach_blocked` is unchanged and still excludes only the rail the
player just left.

### Authored missed-hop scenario

Each of the four new tests instantiates the real player plus
`seg_grind_rails.tscn`, `seg_wall_run_canyon.tscn`, and
`seg_swing_chain.tscn`. The player enters `CenterRail` at **31.0 m**; the
first-contact rail solver snaps that entry to the **30.8 m** baked sample, so
30.8 m is the actual hop start. A real stick-right/JUMP hop targets
`RightRail`, and the live predicted arc confirms that target is beyond reach.
The automatic rail scan then executes and records the miss while the player
remains airborne.

Without clearing the missed-hop state, the four cases put the player in range
of authored traversal candidates and prove:

- `WallRunCanyon/LeftStrip` at 4.0 m auto-attaches;
- `SwingChain/FirstAnchor` auto-catches at the 6.5 m/s boundary;
- `GrindRails/LeftRail`, the third rail and not the target, attaches at
  30.8 m; and
- the departed `GrindRails/CenterRail` at 30.8 m is still refused.

Before the production change, the valid red run had **234 tests**, with
**231 passing and 3 failing**: wall, swing, and third-rail recovery. The
departed-rail protection was already green. After removing the three blanket
vetoes, all four cases passed.

## Final automated verification

Verification was rerun from the final runtime commit before export.

| Check | Result |
| --- | --- |
| GUT | **234/234 passing**, **1,939 assertions**, 20 scripts |
| Python unittest discovery | **22/22 passing** |
| Gameplay numeric-literal lint | Passed |
| Content-vocabulary tripwire | Passed |
| Traversal authoring lint | Passed |
| Exported-tuning verifier | Passed, **`EXIT=0`** |

The GUT count increased from the 224-test baseline to 234. No test was
deleted, weakened, skipped, or marked pending.

## Android APK

The successful build-only export ran after final verification and directly
from runtime commit `bd78521f65b8800d22713681e6766261fe2c5c43`.

| Field | Value |
| --- | --- |
| Command | `scripts/deploy_android.sh --build-only` |
| Path | `/root/crash-remix/build/crash-remix-debug.apk` |
| Size | **84,011,541 bytes** |
| SHA-256 | `b1d832addd289ef28ea6c70842510f65833bbedd65e80bfd0eae3eb1832e4b0f` |
| Build started | `2026-07-23T14:15:39Z` |
| Build finished | `2026-07-23T14:16:19Z` |
| Elapsed | **40 seconds** |
| Runtime commit | `bd78521f65b8800d22713681e6766261fe2c5c43` |

The APK is non-empty, identified as an Android package, and
`unzip -tq` reported no compressed-data errors. `build/` remains uncommitted.
This was a build-only export; no device install or launch was performed.

## Commits

- `0a8212f` — `Prevent inescapable low-speed swing catches`
- `bd78521` — `Keep traversal catches available after missed rail hops`

## Scope and audit notes

- The audit's A11 and A15 diagnoses were both correct; there are no audit
  disagreements for these findings.
- The other 21 Wave 2/3 findings remain open and untouched.
- F4, grind's zero side-bias, and the unrun Gate F thermal soak remain outside
  this pass.
- No manual feel assessment, device run, thermal test, Gate F, or Gate F2 was
  performed or implied.
