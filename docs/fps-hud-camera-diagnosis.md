# MCLA FPS HUD and camera regression isolation

Branch: `experiment/fps-hud-camera-diagnosis`, based on the successful
Native 720p, texture-cache retention and experimental DX12 scissor cache.

## Lightweight in-game FPS HUD

**DISPLAY → FPS COUNTER → ON/OFF** controls `mcla_show_fps`.
On Windows, a small Midnight Purple ImGui HUD appears in the
top-right corner. It shows:

- `FPS`: guest present requests per second, averaged over ~500 ms.
- `ms`: mean guest-present interval in the same window.
- `max ... ms`: largest single interval recorded in that window.

The HUD uses the existing ReXGlue ImGui presentation system; no
external FPS application, window injection, gameplay assets, expensive
`REXGLUE_ENABLE_PERF_COUNTERS`, or special GPU SDK build is needed.
A single steady_clock timestamp is taken per guest present; values
are published using atomics for the UI thread.

**Measurement limitation:** these are *guest-present intervals*,
not precise GPU frame execution, desktop compositor or monitor scanout.
If a guest present is delayed by frame pacing, CPU or GPU backpressure,
the interval includes that delay; it cannot identify root cause alone.

The SDK's built-in **F3 debug overlay** now also receives these
frame statistics, which it previously lacked for this game.
The menu toggle is saved to the normal ignored `mcla.toml`.
The HUD defaults OFF in public builds but may be turned on in
the user's local install. Built-in UI FPS tracking is optional.

## Investigating the renewed camera flicker

The user reports that vehicles and FPS have improved significantly,
but camera movement/image flicker recurs specifically in locations
that formerly produced slow frames. This is an observation, not proof
of an SDK scissor-cache regression.

Keep all these constant: guest render 1280x720, FSR, Gentle 67ms frame
guard, texture-cache retention soft 768/hard 1024/lifetime 90,
0.5 parked cars, frame pacing and the same car/camera mode.

**A/B experiment:** close the game, then switch ONLY the scissor
decoding cache:

    .\scripts\scissor_cache_trial.ps1 -Mode on
    .\scripts\scissor_cache_trial.ps1 -Mode off

Run the same route at the same speed for both modes. With FPS HUD on,
note whether the camera misbehaves when `max ... ms` jumps,
whether visual *flashing* occurs without any frametime spike, and
whether the camera regresses only with cache ON. These outcomes point
to different causes:

- Camera changes direction/jumps with 40–100 ms intervals in BOTH
  modes: suspect game chase-camera time step / smoothing after spikes.
- Rapid flickering/cropping ONLY with scissor cache ON, at stable
  framerate: suspect incorrectly cached GPU state; disable the
  experiment and inspect differences before optimizing further.
- Camera appears to teleport or vibrate in both modes despite stable
  intervals: requires separate game-camera state instrumentation.
- Only graphics objects/light or geometry blink: not necessarily
  a camera positioning bug.

The previous optional `mcla_frame_stall_guard_ms=67` still clamps
the *guest* time step; this HUD does not change that value or alter
camera, vehicle, physics, or quit-game behavior.

Do not claim the camera issue fixed until controlled gameplay validates
a specific cause. Preserve rollback binaries/config under
`out/phase2-backup/before-fps-hud`.
