# Guest frame burst / camera 60-FPS crossing correlation
Date: 2026-10-17
Branch: experiment/guest-fps-burst-camera60-correlation

## Observation and technical motivation

Player reports visually apparent camera flicks coinciding with a brief
FPS counter rise to about 90, while usual street-driving FPS is 30-45.
NPC/vehicle flick relationship remains uncertain. A brief peak on an
overlay is different from a 10s-average FPS increase.

Session mcla_037.log was recorded with frame stall guard **125 ms**
(as stated in its startup line) and FSR/DX12/uncapped guest FPS. Two
r8 timer clamp events withheld ~366.58ms, while f11 fixed-step hook
withheld ~0.62ms. This does not establish either guard as the cause.
Most post-warmup windows had no clamping despite frametime stalls.
Camera relative-step >1.5m was confined to a two-event transition
window 01:01:26-01:01:36. Elsewhere camera-relative changes did not
exceed 0.5m. The older 67ms run mcla_036 had many more clamps but
a similar visually observed flick issue.

src/frame_timing.cpp already has a camera smoothing factor path that
reads the game's reported fps and selects the (already-halved)
coefficient for rounded fps <60. The >60 branch uses half the incoming
coefficient before converting to real-time smoothing. This decision
may be legitimate, but an abrupt 40->90->40 reported camera rate
should be counted before attempting any override.

src/fps_overlay.cpp's persistent HUD displays FPS over a rolling
half-second window plus **maximum frametime (ms)** in that interval;
it has NO "maximum FPS" field. If a different FPS counter shows
"max 90", that may be instantaneous/persistent peak depending on the
counter. Thus we instrument independently.

## Change

Read-only fields added to MCLA hitch correlation's existing 10s log
lines (only while mcla_hitch_correlation=true):

- host_over60: guest inter-present intervals <16.667ms
- host_over90: guest inter-present intervals <11.111ms
- fast_after_stall: a <16.667ms interval directly after >=50ms
- camera_rate_reads: number of calls to the camera rate smoothing path
- camera_over60: calls in the game's >=60 FPS coefficient band
- camera_cross60: switches from one smoothing band to the other
- camera_cross_near_stall: above transitions within 250ms after a
  guest present gap >=50ms
- camera_peak_fps: maximum finite, plausible game-reported
  rate read by that camera hook in the 10s window

The rate reads are *calls*, not guaranteed unique frames. Host
present intervals are *requests*, not display refreshes. The 10s
aggregation cannot establish frame-level causality, but a lack of
crossings during sustained flicks would weaken the theory.

No game or camera state changed. No FPS cap, physics, AI, simulation
step, texture handling, new GPU sync, allocations or per-frame logs.
Existing SDK probes and FPS display settings are untouched.
The original executable and settings are backed up in
out/phase2-backup/pre-fps-burst-camera60/.

## QA / next street test

    .\scripts\frame_guard_ab_trial.ps1 -Mode status
    .\scripts\frame_hitch_correlation_trial.ps1 -Mode status
    # Play 2-3 minutes along the same route at 67ms; note flick times.
    .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3

Look for Host90, PostStallFast and CameraCross60 in the same 10s
window as flicks; do not infer cause without controlled reproduction.
If there are many camera crossings, an independent reversible test
of the threshold smoothing should be designed after tracing the
coefficient's actual values; DO NOT change physics/camera yet.

If no crossings but flicks remain, focus on guest simulation/present
cadence or vehicle/NPC transform publication instead. A separate
engine-level hook would be required to directly measure NPC motion.

## Local build and smoke QA

- `scripts/build.ps1 -NoCodegen -FidelityFX`: passed; linked mcla.exe.
- `scripts/test_window_close.ps1 -WarmupSeconds 27 -UseConfiguredFps`:
  CLOSED=True EXIT=0, log `out/runs/quit-qa-20261017-010922.log`.
- New log fields are emitted; in the menu, `host_over90=6471` in the
  intro/transition window (the title-screen path can run far faster
  than real driving) and `camera_rate_reads=0` because the chase
  camera is not active. This does NOT validate the camera-rate probes
  during gameplay; a city-drive run is needed.
- Updated report handles older mcla_035/036/037 records as unknown `--`
  for these new fields, rather than treating absent readings as zero.
- Final installed settings remain Fast Path ON, Sampler ON, FPS HUD ON,
  correlation ON, FSR ON, DX12, uncapped guest FPS, Gentle guard 67ms.
