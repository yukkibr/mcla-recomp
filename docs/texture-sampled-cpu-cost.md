# ReXGlue texture request CPU sampling (2026-10-17)

Branch: experiment/texture-sampled-cpu-cost, based on the reversible
fast path + persistent FPS display + frametime A/B branch.
Keep this experimental work out of main.

## User street tests inspected

- OFF mcla_030.log: 7 ten-second windows after three warmup windows;
  weighted 40.01 guest presents/s, highest per-window p99 bucket
  48 ms, maximum interval 492.2 ms, 12 frames >=50 ms, 2 >=100 ms.
- ON mcla_031.log: 8 such windows; weighted 39.84 guest presents/s,
  highest per-window p99 bucket 48 ms, maximum interval 592.5 ms,
  13 frames >=50 ms, 2 >=100 ms. 5 million synchronized requests
  were bypassed over the full run.
- Different window counts and no deterministic playback:
  neither the small FPS difference nor the isolated max stalls
  prove gain or regression from the fast path.
- Both modes showed the same invalid texture-fetch warning
  and normal QUIT GAME. DX12 scissor cache: ~99% reuse.
- Heavy texture-stage probe OFF: the precise CPU reason for
  remaining frame stalls is NOT identified from these logs.

## New opt-in profiler

Patch: patches/rexglue-texture-sampled-cpu-cost.patch, applied
after the fastpath patch in scripts/make_pc.ps1. No change to
texture invalidation, binding, memory ownership, residency, GPU
commands, texture upload or texture cache policy.

New GPU CVar texture_request_sample_probe=false (default OFF).
When enabled and the expensive dx12_texture_stage_probe is OFF,
the instrumentation:

- counts all calls as synchronized bypass, synchronized original
  request, or request doing active texture work;
- times only 1 in every 257 calls using steady_clock;
- records averaged sampled CPU cost: bypass, synchronized original
  no-op, and active prep/residency/upload/binding phases;
- reports a bounded one-line summary every ~10 seconds.

Fixed thread-local memory, no per-request heap allocation, GPU
query or new synchronization. Sparse samples can miss rare
stutters and may alias with repeating draw patterns. These are
estimates for diagnosis, NOT exact totals. Turn this OFF for normal
performance comparisons.

## Diagnostic loop (close game before changing config)

    .\scripts\texture_fastpath_trial.ps1 -Mode off -Sampler on
    # Drive a 1-2 minute city route, then quit game
    .\scripts\texture_fastpath_trial.ps1 -Mode on -Sampler on
    # Drive the SAME route, then quit game
    .\scripts\texture_cpu_sample_report.ps1 -Recent 6
    .\scripts\texture_ab_report.ps1 -Recent 6 -SkipFirst 3

Disable sample profiler when done:

    .\scripts\texture_fastpath_trial.ps1 -Mode on -Sampler off
    .\scripts\texture_fastpath_trial.ps1 -Mode status

-Frametime and -Sampler independently default to keep.
The existing DISPLAY FPS HUD, FidelityFX, DX12, scissor-cache,
guest frame pacing and cache budgets are untouched.

Backups of the pre-patch SDK source, local config and old runtime
DLLs are in ignored out/phase2-backup/pre-texture-sampled-cpu-cost/.

## Local build and smoke QA (2026-10-17)

- Windows make_pc.ps1 -FidelityFX passed; Clang 20.1.8,
  FidelityFX ON, heavy CSV counters OFF, 245 generated functions unchanged.
- ON smoke run out/runs/quit-qa-20261017-000718.log:
  CLOSED=True, EXIT=0, 3 texture sample windows.
- OFF smoke run out/runs/quit-qa-20261017-000843.log:
  CLOSED=True, EXIT=0, 3 texture sample windows.
- ON sampled bypass mean ~0.07 microseconds per call;
  OFF synchronized original no-op mean ~0.20 microseconds per call.
  Difference ~0.13 microseconds is illustrative, not a causal
  gameplay speedup. These are startup/menu windows with differing
  ratios of unchanged fetches, not matched downtown driving.
- Active CPU prep/residency/upload/binding averages were measured
  successfully; no sampled full request exceeded 3ms in these
  short warmup tests. Rare unobserved outliers are still possible.
- Final installed settings: fastpath ON, frametime logging ON,
  texture request sparse CPU sampler OFF. FPS DISPLAY toggle kept.

## Release gate

Before any subsequent optimization, identify the dominant
active request stage; require like-for-like driving A/B/A,
road/vehicles/decals/UI inspection and shutdown test.
Do not commit game assets, compiled builds, SDK-local sources,
user settings or saves.
