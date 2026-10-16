# Experimental camera-target motion probe

Branch: `experiment/camera-target-motion-probe`, based on the 45 FPS pacing A/B.
The user confirmed the cap did not reduce camera or vehicle flicking. The
default local gameplay FPS was restored to **uncapped** (`mcla_fps=0`).
DX12 scissor cache, Native 720p, FSR1, 768/1024 MB texture retention,
90-second cache lifetime, Gentle 67ms guard, parked cars and FPS HUD
are unchanged.

## Why investigate the camera's follow target?

The previous read-only guest timing trace recorded genuine 72-590ms
frame intervals and clamped simulation-time spikes during city driving,
while 5-second average FPS still appeared near 35-45. Scissor OFF did
not remove the flick, and a real 45 FPS cap was ineffective.

The existing two gameplay timer paths already share the same max 67ms
step. Therefore rewriting guest clock/physics without identifying the
fault would be speculative and risky.

## Code/source location

Original LARecomp project reverse-engineered `sub_8231CE30`
(the common `mcTrackCS` / `vehTrackCS` camera-state update) and its
matrix and target offsets in `src/mc_engine/camera_look.cpp`.

The read-only hook in `config/motion_probe.toml` samples at
**0x8231CEE0**, after the game has computed the desired camera
position and run its optional collision passes.

It reads, without writing:
- Camera owner pointer at `cs+192`, to detect rig/follow-target swaps.
- Camera matrix position at `cs+64` (`cs+16` matrix row 3).
- Second matrix position at `cs+128` (`cs+80` matrix row 3),
  **only when** the game's collision type and `cs+156` collided flag
  indicate that alternate matrix is active. Inactive camera matrices
  were observed to contain misleading values during the title intro.
- Camera follow target `cs+320`.

The target is **not independently confirmed as the vehicle's root
physics transform**. If both target and camera jump, this is a reason
to inspect the vehicle/physics state next, not proof of a bad car
interpolation routine.

## Switches

The CVar `mcla_motion_probe` defaults to `false` and is not part
of normal build options. For a short A/B diagnostic:

    .\scripts\motion_probe_trial.ps1 -Mode on
    .\scripts\motion_probe_trial.ps1 -Mode status
    .\scripts\motion_probe_trial.ps1 -Mode off

Close the game before switching, then restart. The helper updates
only this key, preserving all performance and control settings.
The untouched configuration and game binary are backed up under
`out/phase2-backup/pre-camera-target-probe/` (ignored, never committed).

## Logs and interpretation

Game logs are stored at
`out/build/win-amd64-release/logs/mcla_NNN.log`.
The probe emits one `MCLA motion probe:` summary every ~5s on the
camera update thread plus at most four event lines per window.

A jump is merely flagged when successive updates of the same rig
and same owner less than 120ms apart have a target or camera
displacement of more than 6m. It also records >5m differences
between the two camera-state positions. **Those thresholds are
heuristics**, not physics validity conditions. Crashes, fast camera
motion, teleports, rig switching and some legitimate collision
changes can produce large values.

- Target + camera jump together: investigate target/car transforms.
- Camera position jump while target stable: investigate camera's
  interpolation and collision branches.
- Large collision position differences: inspect collision update
  before changing any vehicle physics.
- Flick visible with all these fields steady: likely **rendering
  or present timing**, not a simulated camera position discontinuity.

Capture the user's *approximate clock time* at the on-screen flick
to relate it to the 5-second summary. The sampling log is not a
frame-accurate video capture and cannot identify the event visually.

## Validation and release gate

Compiled successfully via `scripts/build.ps1 -FidelityFX` and
recompiled once more after guarding the alternate matrix with the
collision flag. `scripts/test_window_close.ps1 -UseConfiguredFps
-WarmupSeconds 27` passed with native 720p, **uncapped FPS**,
probe enabled and `CLOSED=True EXIT=0`.

The automated title-screen camera showed one 17.63m camera movement
while the target was unchanged, which is consistent with a title or
camera transition and **not** evidence of the user's in-city flick.
The initial 1km false collision shift disappeared after checking the
active collision matrix flag. The final diagnostic log
`out/runs/quit-qa-20261016-004432.log` shows one 5s summary,
`target jumps=0`, `camera jumps=1`, `collision shifts=0`.

New generated code artifacts are not committed. Actual driving in the
problem location remains the release gate. Never merge to main without
a successful visual regression test.
