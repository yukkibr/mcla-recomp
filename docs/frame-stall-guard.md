# Experimental frame stall guard — 2026-10-15

Branch: `experiment/frame-stall-guard` (based on `fix/quit-and-frame-spikes`).

## Why this exists

The user reported vehicle snapping back and forth and chase-camera
jumps only when the game's FPS is unstable; at stable FPS, neither
problem appears.

Two actual gameplay captures were inspected (different routes/scenes,
so these are NOT controlled A/B measurements):

| Metric | Uncapped, Oct 15 12:46 | Target 30 FPS, Oct 15 13:03 |
|---|---:|---:|
| Mean FPS after warmup | 32.2 | 24.9 |
| P95 frametime | 53.0 ms | 56.9 ms |
| P99 frametime | 74.9 ms | 86.9 ms |
| Worst frame | 647.0 ms | 214.2 ms |
| Frames over 50 ms | 991 (6.82%) | 885 (13.23%) |
| Slow frames with newly created SRV descriptors | 582 / 991 | 558 / 885 |

The capped run confirms the remaining performance problem: in dense
scenes it cannot sustain 30 FPS. New SRV descriptor creation is associated
with many spikes, but it is not proof of texture upload or disk streaming.
Some of the worst frames have no descriptor misses at all. ReXGlue CPU draw
translation and resource synchronization still require direct measurements.

## Important frame-timing detail

`mcla_frame_delta` previously capped the timer's `r8` guest tick value
to 125 ms. The independent `mcla_fixed_step_path` hook subsequently
published the measured unscaled delta from guest memory to `f11`
**without a matching clamp**. This could send a large post-stall
time step to that gameplay path.

The patch applies a common maximum to:
- `r8` measured guest tick delta
- `f11` in the second fixed-step update path
- chase-camera position / look-at smoothing
- chassis ground-depth smoothing

All are the existing hooks from `config/frame_timing.toml`. The
original `mcla_fps=-1` fixed-step compatibility path remains unchanged.

## New option

In DISPLAY -> FRAME STALL GUARD:

| Mode | Maximum step | Behavior |
|---|---|---|
| ORIGINAL (default) | 125 ms | Keeps the prior timer setting; new consistency check on the second path |
| GENTLE | 67 ms | Cuts the largest simulation steps; recommended first experimental test |
| STRONG | 50 ms | More aggressive and may cause perceptible temporary slowdown |

For a one-time test, without changing `mcla.toml`:

```powershell
.\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4 -ExtraArgs @('--mcla_fps=30','--mcla_frame_stall_guard_ms=67')
```

Or select GENTLE from DISPLAY. Changing it back to ORIGINAL restores the
125 ms limit. Nothing changes the underlying streaming work or increases
the raw rendering frame rate.

**Critical tradeoff:** the time cut off a large delta is not simulated.
This may smooth the camera/car after a streaming hitch at the cost of
brief slow motion. Using the measured 30 FPS CSV frame times as a rough
upper-bound proxy (the actual guest delta may differ), a 309-second
capture included approximately:

- 125 ms cap: 24 frames over cap, total excess ~1.76 s
- 67 ms cap: 164 frames over cap, total excess ~5.80 s
- 50 ms cap: 907 frames over cap, total excess ~12.25 s

This is not equivalent to measured physics slowdown; it illustrates why
smaller caps are NOT automatically superior. Test lap time, collisions,
car behavior, NPC traffic and camera after repeated dense-city stalls.

## Verification and remaining work

- Build Windows D3D12 with `scripts/make_pc.ps1 -FidelityFX`.
- Smoke test game launch with `--mcla_fps=30 --mcla_frame_stall_guard_ms=67`;
  verify initial log shows 67 ms and quit closes cleanly.
- Do manual gameplay tests in the same location, with Original and Gentle.
- Profile ReXGlue's texture uploads and CPU/GPU synchronization to
  reduce the stalls rather than merely absorbing their visual effects.
- Do not merge a behavioral timing change into the main branch without
  manual regression testing of missions, garage, collisions and saves.

The first-run launcher and user ISO workflow are explicitly out of scope.
