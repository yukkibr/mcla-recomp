# Camera relative-offset stability diagnostic — 2026-10-17

Branch: experiment/camera-relative-offset-stability.
Based on experiment/frame-hitch-correlation. No merge into main.

## Evidence from user's confirmed flick period

Session: out/build/win-amd64-release/logs/mcla_035.log.
Flicks were reported from about 00:38:50 through quitting at 00:39:37.

In the five 10-second windows ending 00:38:53 through 00:39:33:
- Average guest-present FPS: 42.42, 38.38, 40.02, 39.19, 32.94.
- 12 guest-present intervals >=50ms and 1 >=100ms.
- 6 guest delta limiter clamps >=67ms (1+1+2+2+0).
- Zero camera jump events >6m within comparable updates.
- A previous, isolated large camera/publish jump was reported in the
  window ending 00:38:13, BEFORE the user's marked flick period.
- The source matrix vs most recently updated camera rig differed by
  >3m in almost every sampled frame after ~00:38:33 (e.g. 389/389,
  399/399, 425/425, 384/384, 401/401, 392/392).
  This ALONE is not a defect: different game camera transforms and
  cine/shake stages can have an intentional fixed offset.

Older log: 9 clamp events across the last 9 windows after warmup;
do not confuse these with the 6 occurring in the marked final period.

## Change

This iteration does NOT interpolate frames or modify their times.
It only adds read-only diagnostic counters while
mcla_hitch_correlation=true:

- In camera rig post-hook, retain its identity (cs).
- In camera publish-hook, compute (published camera minus latest rig
  camera), a relative offset vector.
- Compare the vector with the previous published frame only if both
  samples refer to the same rig and are <120ms apart, and the rig
  itself was updated within 50ms.
- Count relative offset changes >0.5m and >1.5m per 10s window.
- Record average change (mm), maximum change (mm) and the number of
  >1.5m events occurring within 250ms after a >=50ms present gap.
- No game memory writes, camera transform overrides, NPC transform
  changes, graphics-setting changes, per-frame logs, new heap allocs,
  GPU sync or textures touched.

Large displacement can be normal during collisions, extremely fast
driving, camera mode changes, or intentional cinematic blending;
the counter is not a visual flick detector.

## Testing

Build with: .\scripts\build.ps1 -NoCodegen -FidelityFX.
Automated WM_CLOSE smoke test (2026-10-17):
out/runs/quit-qa-20261017-004421.log exited normally (CLOSED=True,
EXIT=0) with the new relative_* telemetry fields appearing in all
three complete windows. Camera rig was NOT active at the title
screen, so relative_samples=0 is expected and does NOT validate
actual gameplay camera measurements. Validation during driving
is still required before any behavioral change.
FPS, FSR, fast path, sampler, present telemetry, scissor cache, 67ms
Gentle guard and unlocked FPS remain as the user configured.

The improved report is backwards-compatible with logs from before
this change, where relative_* counters do not exist (shown as zero,
NOT measured zero). Only runs using the new executable can validate
the new relative-offset counters.

To test live, start the game with correlation enabled (no action
needed if already ON); drive 2-3 minutes on the same route, note
clock time of flicks, quit normally and run:

    .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3

To switch this diagnosis OFF after it has served its purpose, close
the game and run:

    .\scripts\frame_hitch_correlation_trial.ps1 -Mode off

Never declare an actual camera/publish defect without reproducing
sustained abnormal relative-offset CHANGE during reported flicks.
Further targeted vehicle/NPC transform hooks would require verified
guest pointers to avoid incorrect reads and false positives.
