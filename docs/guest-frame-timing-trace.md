# Guest frame-time and camera threshold trace (experimental)

This independent diagnostic experiment keeps every performance feature in
the current working MCLA Recomp build. It DOES NOT touch camera smoothing,
guest simulation physics, display sync, ReXGlue DX12 scissor decoding,
resolution, parked vehicles, or resource-cache limits.

## Why

The scissor correctness audit recorded 8,241 sampled rectangles without a
mismatch during a live driving session. The user then disabled both the
scissor cache and its audit, repeated the route, and still experienced
vehicle and chase-camera flicking with largely unchanged FPS. Scissor
cache remains useful as a low-level computation cache, but neither a
measurable FPS benefit nor a causal link to the flick is established.

The in-game FPS overlay averages **about half a second**. A half-second
reading of 33 FPS cannot rule out a single 80-200ms frame within the
window, and also cannot reveal whether guest engine delta time or camera
filter state became inconsistent.

## What this adds

A `mcla_timing_trace` CVar, default **false**. If enabled, the existing
`mcla_frame_delta` hook logs one rolling summary approximately every
5 seconds per guest timer thread:

- Count of guest timer calls;
- Average and peak **raw measured** guest frame delta in milliseconds;
- Counts of calls >40ms and >67ms and of frames where the Gentle guard
  clamped the timer value;
- Most recently observed camera framerate and number of crossings over
  the game's internal 60 FPS rounding threshold.

These are observations, not new timing policies. Runtime performance
counters remain **OFF**. This uses the existing logging system and only
runs when requested, with a tiny amount of overhead relative to the
full DX12 per-frame CSV profiler. Avoid running the diagnostic as a
permanent performance preset.

## Usage

Normal gameplay: `mcla_timing_trace = false`.

For diagnosis, close the game, and use the reversible helper:

    .\scripts\timing_trace_trial.ps1 -Mode on

Drive through a route that reproduces the flick, noting the approximate
time on screen, guest-present FPS and HUD maximum frametime. Then exit
normally and read the newest `mcla_*.log` from
`out/build/win-amd64-release/logs/` to locate
`MCLA timing trace:` entries around the moment of the problem.

To return to ordinary gameplay:

    .\scripts\timing_trace_trial.ps1 -Mode off

The helper changes only the `mcla_timing_trace` key in ignored
`mcla.toml` and refuses to run while MCLA is open. The original
configuration and binaries were backed up locally before changes.

## Interpreting the results

- Peak raw delta >67ms and guard clamps near the flick: a genuine
  simulation-time discontinuity occurred; investigate the guest tick
  accumulator and timing paths without weakening the existing safety
  clamp.
- Guest timer deltas remain 20-35ms and no clamps, but vehicles jump:
  investigate guest physics / vehicle transform interpolation or
  synchronization independently of streaming.
- Camera FPS repeatedly crosses 60 and ONLY camera flicks: potential
  smoothing-coefficient threshold issue; requires separate A/B test.
- If camera and cars flick together, a camera-only patch is unlikely
  to solve the complete issue.
- Absence of trace entries can mean no frame-timer hook ran or the CVar
  was not applied, rather than proof of stable timing.

The FPS HUD's guest-present interval is not a hardware GPU-time meter
and cannot diagnose frame-queue latency on its own. Only compare
identical driving routes and do not infer scissor FPS gain from its
98-99% calculation reuse rate.

## Local build and QA

- Full ReXGlue per-frame CSV counters remain disabled (Fast Runtime).
- The updated game built successfully with `scripts/build.ps1 -NoCodegen -FidelityFX`.
- With trace enabled, the test log `out/runs/quit-qa-20261015-235548.log`
  contained a `MCLA timing trace:` summary.
- A 7.6-second guest delta observed **during initial loading** was clamped
  safely by the 67ms Gentle guard. This is not evidence of gameplay flick;
  loading/intro frames must not be mixed with driving-frame measurements.
- Normal Windows close passed (`CLOSED=True EXIT=0`).
- Current local config preserves `d3d12_scissor_cache=true` with
  `d3d12_scissor_cache_audit=false`, Native 720p, spatial FSR,
  768/1024MB cache retention and the FPS HUD.
- A follow-up real driving session is still needed to identify the
  source of simultaneous camera and vehicle flicking.

This remains on an experimental branch; do not merge into main before
controlled driving tests.
