# Experimental 45 FPS pacing A/B for simultaneous vehicle/camera flick

Based on `experiment/guest-frame-timing-trace`; branch
`experiment/frame-pacing-45-flick-ab`.

## Evidence motivating this experiment

User report: with scissor OFF the camera and vehicles still flicked, and
the FPS was similar. With scissor ON, an observed improvement of roughly
7–10 FPS is plausible but has not been established from controlled
frametime recordings.

The live `mcla_017.log` recorded raw guest timer interval spikes of
85, 89, 147, 176 and even 590ms after the title loaded, while 5-second
mean intervals were typically 20–33ms. The 67ms Gentle guard activates
on these large intervals. Average HUD FPS moving by ~4 cannot disprove
a rare single-frame freeze.

## Source-code review

- `mcla_frame_delta` clamps raw timer r8 ticks to 67ms.
- `mcla_fixed_step_path` clamps the alternative fixed-step path f11
  to the SAME upper bound when measured delta is valid.
- Chase-camera position and look-at smoothing and the chassis
  ground-depth filter use this 67ms upper bound too.
- The game's own camera smoothing changes its tune factor at a
  rounded **60 FPS** threshold. The compensation code uses a
  matching threshold, and recorded some crossings early in one
  session, but 0 crossings in later intervals despite remaining
  guest-timing peaks.

Thus **no proof of a mismatch or scissor-render bug** emerged from
this review. In particular, a camera-only workaround would not
address vehicle flick, and changing physics without a verified cause
is too risky.

## Controlled experiment

The game is usually uncapped (`mcla_fps=0`) and commonly fluctuates
between 40–60 FPS. A **45 FPS cap** is a *diagnostic* to stabilize
frame pacing and keep chase-camera frame-rate estimation mostly
below the 60 FPS threshold. It intentionally trades some peak FPS
for potential consistency; **it is not a performance optimization**.
It cannot prevent an 80–590ms streaming/resource stall and cannot
guarantee to fix flick.

The Display → FPS TARGET menu now includes 45 between 30 and 60.
The script changes exactly ONE ignored `mcla.toml` value:

    .\scripts\frame_pacing_trial.ps1 -Mode 45

Run the same car, camera and downtown route, note whether visual
flick is reduced and whether it still correlates with the HUD
`max ... ms` readout.

Restore the previous uncapped mode:

    .\scripts\frame_pacing_trial.ps1 -Mode uncapped

Check configuration:

    .\scripts\frame_pacing_trial.ps1 -Mode status

The script refuses to modify the game while it is running and keeps
a backup in `out/phase2-backup/before-45fps-pacing-ab/mcla.toml`.
Native 1280x720, FSR, 67ms Gentle guard, 768/1024MB texture-cache
retention, parked cars 0.5, FPS HUD and DX12 scissor cache remain
unchanged. Scissor audit and detailed timing trace remain OFF
for normal gameplay.

If the 45 FPS cap does NOT materially improve stability, return to
uncapped. Further investigation should focus on the underlying
long-frame guest simulation and physics step/vehicle transform changes,
not an arbitrary camera clamp.

## Release gate

Compile the Windows FidelityFX game, smoke test both capped and
uncapped native output plus normal WM_CLOSE, then test actual driving.

**Important QA correction:** `scripts/test_window_close.ps1` historically
injected `--mcla_fps=30` into *every* smoke test. It therefore hid
configuration-based pacing and logged 30 FPS even with mcla.toml set to
45 or 0. The new `-UseConfiguredFps` switch omits that hard-coded
argument and tests the actual chosen mcla.toml value:

    .\scripts\test_window_close.ps1 -UseConfiguredFps -WarmupSeconds 14

The game's `mcla_frame_delta` now prints the first effective
`mcla_fps` that its limiter observes in the same session. An early
`ConfigureFrameTiming` log by itself is not sufficient to validate a
user's persisted configuration.

Do not merge this experiment to main without realistic manual tests.
