# D3D12 CPU frame-hitch attribution — optional experiment

Branch `experiment/dx12-hitch-probe`, continuing from
`experiment/camera-publish-motion-probe`.

## Evidence

The user's ~90s video of street driving shows the in-game guest-present
HUD reporting slow single intervals of **83.5 ms** and **93.8 ms**
despite half-second FPS averages remaining around 25–39.
Prior A/B tests show the flick still occurs with the DX12 scissor
cache disabled and with an actual 45 FPS cap. The previous camera-state
and matrix-publish probes showed no >6m camera jumps in a 01:00:20–30
sample, but published camera matrices can have a normal, persistent
3–7m offset from the game's rig state.

Therefore no evidence yet justifies camera motion or physics changes.
The next bottleneck to isolate is host CPU command processing vs
guest frame time vs GPU fencing/command submission.

## Instrumentation

Versioned ReXGlue SDK patch:
`patches/rexglue-dx12-hitch-probe.patch`. The build script conditionally
applies it to pinned ReXGlue v0.10.0 SDK.

New CVar `d3d12_hitch_probe=false` by default. With it enabled,
ReXGlue logs a lightweight breakdown for each **>=50ms interval
between calls to IssueSwap on the GPU Commands thread**, and once per
180 IssueSwap calls. Each line includes:

- Wall-clock **GPU Commands thread IssueSwap interval** (not GPU time);
- Draw calls issued and cumulative CPU time spent inside IssueDraw,
  plus largest single draw call;
- CPU time in render target cache update, pipeline configuration,
  texture request and descriptor/buffer binding;
- CPU time in submission-fence checks, including largest single wait;
- CPU time in EndSubmission and IssueSwap.

Timings use `std::chrono::steady_clock` and `thread_local` counters.
The probe does **not** use ReXGlue's expensive per-frame CSV counters,
GPU timestamp queries, frame capture, or forced GPU/CPU synchronization.
It does not modify game/physics state or command emission.

**Overhead warning:** when enabled, there are extra timer reads on
each draw and some function calls. Do not interpret FPS measurements
with the probe enabled as baseline speed. Timing categories **overlap**:
IssueDraw includes some pipeline, textures and binding work.
Adding all categories together is invalid. The IssueSwap phase's time
belongs to the interval after its entry, so some work is accounted
in the following row.

**Interpretation:**
- 80–120ms swap interval + large `draws cpu` or `pipeline` or
  `textures`: CPU draw/translation/resource setup hitch.
- Large `fence` or `submits`: GPU queue submission/backpressure,
  but CPU waits don't prove which individual GPU draw was slow.
- 80–120ms swap interval with low measured GPU command CPU work:
  the guest game may be failing to feed commands on time; correlate
  `MCLA timing trace:` entries. Note other GPU commands outside
  the instrumented sections are not fully counted.
- Guest >67ms sim step while GPU-thread swap interval stays normal:
  possible application scheduling or simulation time problem; record
  exact wall-clock for confirmation.

## Test, toggle and rollback

The reversible helper toggles **only** `d3d12_hitch_probe` and
`mcla_timing_trace` in ignored runtime `mcla.toml`:

    .\scripts\dx12_hitch_trial.ps1 -Mode on
    .\scripts\dx12_hitch_trial.ps1 -Mode status
    .\scripts\dx12_hitch_trial.ps1 -Mode off

Close the game before changing it; restart and drive downtown for
two to three minutes with the FPS HUD visible. When a flick occurs,
note the exact clock time, then quit via QUIT GAME. Inspect
`out/build/win-amd64-release/logs/mcla_NNN.log` for
`DX12 hitch probe:` and `MCLA timing trace:` near the event.

Restore the fast gameplay preset after testing with `-Mode off`.

Scissor cache remains enabled, audit disabled, Native 1280x720, spatial
FSR, 768/1024 MB texture cache with 90s retention, 67ms Gentle guard,
uncapped FPS and FPS HUD continue unchanged. All previous binaries and
config are locally backed up in ignored
`out/phase2-backup/pre-dx12-hitch-probe/`.

## Automated QA (2026-10-16)

- Full `scripts/make_pc.ps1 -FidelityFX` passed on Windows with
  `perf counters=OFF`, codegen unchanged and the D3D12 module rebuilt.
- Enabled startup test: `test_window_close.ps1 -UseConfiguredFps
  -WarmupSeconds 35` passed with `CLOSED=True EXIT=0`, producing
  `out/runs/quit-qa-20261016-013344.log`.
- `dx12_hitch_report.py` parsed 47 sampled intervals and highlighted
  11 at least 50ms. The largest, **525.1ms**, was **during title
  initialization**, with 480.5ms total draw-processing CPU time,
  358.9ms inside texture requests and 28.7ms inside submissions.
  Another 105ms gap had negligible measured CPU-stage time.
  **Neither example proves a cause for downtown gameplay flick.**
- Disabled startup test: `test_window_close.ps1 -UseConfiguredFps
  -WarmupSeconds 16` passed with `CLOSED=True EXIT=0`, and
  **0** `DX12 hitch probe:` and **0** `MCLA timing trace:` log lines,
  proving the CVar controls are effective.
- After QA, the user's ignored config was returned to
  `d3d12_hitch_probe=true` and `mcla_timing_trace=true` for one
  controlled driving test; default in source remains OFF.

To summarize a recorded session without installing a profiler:

    python .\scripts\dx12_hitch_report.py .\out\build\win-amd64-release\logs\mcla_NNN.log --top 15

No copyrighted source/game data or local SDK install binaries are
committed. Do not merge this diagnostics-only branch to main without
controlled driving validation.
