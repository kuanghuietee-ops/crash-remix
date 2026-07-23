# Phase 0 device acceptance

This is the §11.4 tuning-loop acceptance test. It is separate from Gate F. Passing
these steps only proves the tuning pipeline; it does not prove the game feels good.

## Prerequisites

- Connect one Android 10+ arm64 phone with USB debugging authorized.
- Confirm it appears under `adb devices -l`.
- If deployment reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, stop. Do not
  uninstall the app until `user://tuning/override.tres` or the app data has been
  backed up; uninstalling deletes the override this procedure is meant to test.
- Start from a known app-data state. If an old red `OVERRIDE ACTIVE` watermark is
  present, either preserve/pull that override first or clear the app's data. Clearing
  data deletes the saved on-device tuning override:

  ```bash
  adb shell pm clear com.personal.crashremix
  ```

- If the HUD says `OVERRIDE REJECTED`, open `TUNE` and select
  `RESET TO AUTHORED`. This deletes only the invalid tuning override and keeps the
  app usable.

## A. Repo edit reaches the device

1. Run `scripts/deploy_android.sh` and record the full 64-character HUD fingerprint.
2. Play one jump and note its timing.
3. Change `gravity_mps2` in `data/tuning/move.tres` by an obvious amount.
4. Run `scripts/deploy_android.sh` again.
5. Confirm both outcomes on the phone:
   - the fingerprint differs from step 1;
   - the jump timing visibly differs.

If either stays unchanged, stop: the tuning loop has failed.

Fingerprint movement proves that loaded values changed; it does not by itself prove
that the edited property affects gameplay. The observed jump-timing change is the
separate liveness proof for `gravity_mps2`.

## B. On-device edit survives restart

1. Tap `TUNE`, change `move.gravity_mps2` again, and tap `SAVE OVERRIDE`.
2. Record the new fingerprint and confirm the red `OVERRIDE ACTIVE` watermark.
3. Force-stop and relaunch:

   ```bash
   adb shell am force-stop com.personal.crashremix
   adb shell monkey -p com.personal.crashremix \
     -c android.intent.category.LAUNCHER 1
   ```

4. Confirm the watermark, edited value, changed jump timing, and fingerprint recorded
   in B.2 all persist after restart.

## C. Pull the blessed override

Godot stores `user://tuning/override.tres` in the debug app's private files directory.
Pull it through Android's debug-only `run-as` bridge:

```bash
mkdir -p build
adb exec-out run-as com.personal.crashremix \
  cat files/tuning/override.tres > build/device-tuning-override.tres
test -s build/device-tuning-override.tres
```

Review the pulled resource before copying values into the authored files under
`data/tuning/`. Do not overwrite those source resources blindly.

Record A, B, and C as observed results. Only the operator can mark this acceptance
test complete, and only the operator can run or judge Gate F.

## Gate F watch item

Before judging feel, sanity-check the operator-selected fixed-height rule:

- Trigger a crouch high-jump and release JUMP immediately. It should retain the
  authored high-jump arc and clear the high-jump ledge.
- Trigger a slide-jump twice, once with immediate release and once with JUMP
  held. The two attempts should retain the same vertical arc and authored gap
  reach.

If either move is shortened by immediate release, stop and record a behavior
regression; do not compensate by retuning its authored height or distance.

During the separate human feel gate, deliberately short-hop off several ledges
without trying to recover. Record whether the edge-landing nudge pulls the player
back onto the platform often enough to feel sticky. This is a feel judgment, not
an automated pass condition, and no code change should be accepted from this item
without the operator's on-device observation.
