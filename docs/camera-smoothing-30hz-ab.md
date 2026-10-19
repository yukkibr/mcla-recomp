# Chase camera native per-frame vs time-corrected filter A/B
Date: 2026-10-18
Branch: experiment/camera-30hz-filter-ab

## Player observation and diagnosis

User observed smaller but persisting flicks, especially from
21:01:10 until end of mcla_046.log (2026-10-18, 21:01:33).
During these ~23 seconds the identity tracker saw:
- no publish jumps >6m,
- no source matrix changes and no camera owner changes,
- no relative matrix/rig offset steps >1.5m.
The camera rig changed once near the game's pause/quit sequence.
The two large identity events in the log were scene initialization
at 21:00:09, not near the user's flicks.

Guest-present log windows ending 21:01:16 and 21:01:26 measured
36.49 and 39.80 presentations/s, maximum intervals 68.45
and 114.56ms; 3 and 2 intervals >=50ms respectively.
These are presentation rate numbers, not independently measured
GPU hardware frame time or physics thread cadence. No camera 60
FPS-band crossings were recorded in those two windows.
These observations support investigating frame-rate-dependent
camera smoothing, not automatically correcting matrix positions.
Small visual jitter can exist without >6m camera changes.

## Comparison with yukkibr/Midnight-Club-L.A-RECOMP

The reference fork uses real_frame_delta (default true) to replace
the game's original 30Hz fixed-step delta through 3 timer hooks.
Our implementation in src/frame_timing.cpp already performs
these same two real-time timer corrections + safety clipping.
The reference also has cine_fps_lock=true to target 30 FPS ONLY
during cutscenes, leaving street driving uncapped. Not evidence
for driving camera flicks; don't import as a general 30fps cap.

The external project's README warns about FPS measurements from
presents versus true guest simulation. Keep them distinct.

Our current chase camera hooks at 0x82320468, 0x823204F4 convert
game-supplied per-update smoothing factors to a continuous-time
equivalent 1 - (1-k30)^(dt*30). The game halves those raw factors
when its internal measured FPS is <60. Thus at 35-45fps the
time-corrected factor per frame is smaller than the unmodified
game's original per-frame factor. This is a meaningful isolated
camera A/B hypothesis, not proof of the remaining flick's cause.

## Experiment

New CVar mcla_camera_smoothing_mode (default time_corrected):
- time_corrected: exact existing chase-camera position/look-at
  factor correction at arbitrary frame delta, for unchanged
  30Hz-equivalent response; safe baseline to restore.
- per_frame: leave the two game-supplied coefficients unchanged.
  Because the game was calibrated for a fixed update rate, this
  deliberately makes its chase-camera filtering stronger/faster
  above 30fps. It could FEEL better or worse and could add camera
  jitter. Experimental only.

The two modes do NOT change the guest engine timer, present rate,
FPS cap, 67ms guard, collision logic, vehicle/chassis physics,
ReXGlue texture/synchronization, FSR or other settings.
At the default mode, output is unchanged from previous build.
The app logs the chosen mode at startup. No callback writes guest
memory; only hooks' camera-filter floating-point registers differ.

Use reversible PowerShell helper, game CLOSED:
  .\scripts\camera_smoothing_ab_trial.ps1 -Mode per_frame
  .\scripts\camera_smoothing_ab_trial.ps1 -Mode time_corrected
  .\scripts\camera_smoothing_ab_trial.ps1 -Mode status

A/B plan: drive the same car, same camera mode, same route and
approximately same game time/traffic for 2-3min in per_frame,
then quit and test time_corrected with another restart.
Record timestamp and whether small flicks diminish, become
worse, or transform into camera lag/overshoot. Avoid cutscenes
or respawns. Benchmark measurements are supplementary to
visual differences. Test a second A (A/B/A) if ambiguous.

If per_frame looks worse, immediately restore time_corrected.
No automated intro/menu test establishes camera behavior
while driving. Do not merge experimental mode until reviewed.

## Safety and QA

Original exe, config and frame_timing.cpp backed up under ignored
out/phase2-backup/pre-camera-30hz-filter-ab.
Build: scripts/build.ps1 -NoCodegen -FidelityFX.
FidelityFX and v0.10.0 patched ReXGlue SDK preserved.
No merge/push, no user data altered.
