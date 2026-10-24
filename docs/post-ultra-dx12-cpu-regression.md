# Post-ULTRA DX12 CPU overhead investigation
Date: October 24, 2026
Branch: development

## Immediate rollback

The user reported the ULTRA PERFORMANCE preset was worse than the
previous configuration. We restored exactly the pre-ULTRA mcla.toml:
scripts/ultra_performance_profile.ps1 -Mode restore

The original preferences remain in the ignored folder
out/phase2-backup/pre-ultra-performance-profile/mcla.toml,
including DX12, native 720p, FSR spatial, uncapped FPS, the
67ms timer guard, camera time_corrected, 0.5 pedestrian and
parked-car density and MAX SAFE texture-cache budget.
The unvalidated guest cache-flush experiment is OFF by default.

## Observations

- mcla_059.log: 2026-10-24 10:05-10:09, native 1280x720,
  texture cache 768/1024 MiB. Four 10-second windows after
  two warmup windows: 41.75 guest presents/sec, 13
  gaps >=50ms, 3 gaps >=100ms, max P99 bucket 86ms.
- mcla_060.log: 2026-10-24 10:09-10:12, native 1280x720,
  texture cache 4006/5342 MiB: 33.72 guest presents/sec,
  12 gaps >=50ms, 4 gaps >=100ms, max P99 bucket 89ms.
- mcla_061.log: 2026-10-24 10:20-10:21, ULTRA 854x480,
  cache 4006/5342 MiB and guest cache-flush hook ON:
  34.82 guest presents/sec, 34 gaps >=50ms and 9
  >=100ms, worst P99 bucket 137ms.

These are not identical routes; cannot isolate exact
cause from logs alone. However lowering the render
resolution did not produce a sustained improvement and
the user reported worse gameplay. No claim that high
VRAM cache alone was responsible; the user's restored
baseline already selected MAX SAFE.

## New ReXGlue DX12 optimized diagnostic-off path

Versioned SDK patch:
patches/rexglue-dx12-scissor-quiet-fastpath.patch

Existing D3D12 scissor cache: same cache key, same
cached rectangles, same GPU commands, same fallbacks.
Previously the render thread counted each hit or miss
and periodically logged the cumulative stats.

New restart-only CVar:
d3d12_scissor_cache_stats = false (default).

When stats OFF, avoid per-draw hit/miss counters, their
sampling and logs. The audit CVar remains independent
and samples cache results on every 2048th cache hit,
including when stats are OFF. When statistics ON,
original diagnostics work for A/B.

The stats and audit preferences are read once when the
D3D12 command processor is constructed, instead of
re-reading the audit flag on each draw. Stats OFF is a
conservative CPU overhead reduction on an extremely hot
render path; there is NO proven gameplay FPS gain yet.

Reversible script (only with game closed):
    .\scripts\scissor_metrics_trial.ps1 -Mode status
    .\scripts\scissor_metrics_trial.ps1 -Mode on
    .\scripts\scissor_metrics_trial.ps1 -Mode off

The complete SDK and game were rebuilt using FidelityFX
ON and SDK profiling CSV counters OFF, without replacing
any guest physics, guest timer, game assets or save files.
Smoke QA on 2026-10-24:
- STATS OFF: out/runs/quit-qa-20261024-103258.log,
  CLOSED=True EXIT=0, zero scissor-cache stats log messages.
- STATS ON: out/runs/quit-qa-20261024-103319.log,
  CLOSED=True EXIT=0, seven scissor-cache stats messages.
- Both modes use identical cache/graphics behavior; completed
  title-screen tests are NOT comparable street FPS benchmarks.
- After QA, restored the user's original pre-ULTRA TOML exactly.
  d3d12_scissor_cache=true; stats omitted (SDK default false).

## Safety and integration

Make_pc.ps1 applies the new incremental SDK patch
immediately after the already versioned scissor audit
patch on fresh SDK installations. All pre-existing
local patches in third_party/rexglue-sdk are preserved.
Previous SDK source files and binaries stored under
ignored out/phase2-backup/pre-scissor-stats-off/sdk/.

Main unchanged. One integration branch only:
development. The opt-in ULTRA preset remains available
as an A/B tool, but is not active after rollback.
