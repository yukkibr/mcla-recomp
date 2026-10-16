# D3D12 scissor-cache correctness audit (experimental)

Branch: `experiment/dx12-scissor-audit`. Based on the FPS HUD and
successful 720p/scissor-cache performance experiments.

## Motivation

The user measured **40–60 guest-present FPS** over many areas with the
DX12 scissor cache enabled, with occasional dips near 29–30 FPS.
However, the chase camera or picture sometimes flickers in areas
previously affected by GPU/resource stalls. That temporal correlation
is *not proof* that cached scissor bounds are wrong.

Static inspection: ReXGlue's `draw_util::GetScissor` depends on
six Xenos registers, already part of the cache key:
`PA_SC_WINDOW_SCISSOR_TL`, `PA_SC_WINDOW_SCISSOR_BR`,
`PA_SC_SCREEN_SCISSOR_TL`, `PA_SC_SCREEN_SCISSOR_BR`,
`PA_SC_WINDOW_OFFSET`, and `RB_SURFACE_INFO`. The four returned
rect components are cached unscaled; current resolution scaling is
still applied after cache lookup. No omitted input was found in the
inspection. Nevertheless, runtime auditing can help rule out an
unexpected stale result.

## Added audit mode

Versioned incremental ReXGlue patch:
`patches/rexglue-dx12-scissor-audit.patch`.
Build script applies this AFTER the existing
`rexglue-dx12-scissor-cache.patch` on clean SDK checkouts.

- `d3d12_scissor_cache_audit = false` is the normal default.
- With the **existing scissor cache enabled**, setting
  `d3d12_scissor_cache_audit = true` recomputes one in every
  2,048 cache-hit rectangles using the original `GetScissor`.
- It compares X/Y offset and width/height exactly.
- On any discrepancy, the GPU thread logs
  `DX12 SCISSOR AUDIT MISMATCH!` and **disables caching for the
  remainder of the session**, continuing with the fresh result.
- The periodic `DX12 scissor audit: N comparisons / M mismatches`
  log confirms the audit actually ran.
- A zero-mismatch run only shows that *sampled* rectangles agree.
  It cannot rule out an unsampled race, a bug in the common path,
  or separate camera/simulation timing bugs.

All settings require game restart. Sampling adds some overhead,
so do not use audit=true as the permanent performance preset.

## Game test (FPS HUD enabled)

Drive through the same previously problematic city center route,
with the same car and similar speed.

**Run A**: the user's installation is now configured with
`d3d12_scissor_cache=true` and `d3d12_scissor_cache_audit=true`.
Simply start the game, drive the problem area, and note camera flicks,
FPS and maximum frame interval. Quit normally and let us inspect the
newest game log for `DX12 scissor audit` and `MISMATCH`.

**Run B**: close the game, then execute:

    .\scripts\scissor_cache_trial.ps1 -Mode off -Audit off

Restart, take the same route and compare. All other successful
options stay unchanged.

**Restore gameplay performance**, without the audit sampling, after
testing:

    .\scripts\scissor_cache_trial.ps1 -Mode on -Audit off

To repeat the audit:

    .\scripts\scissor_cache_trial.ps1 -Mode on -Audit on

The helper also supports `-Mode status`.
For strong causal evidence, compare ON/OFF/ON across nearly identical
routes rather than trusting a single drive or camera shot.

If flick occurs only when cache is ON (and vanishes when OFF),
investigate rendering state/cropping, even if sampled rectangles
match. If it occurs in both modes but aligns with >40–60ms
frametime spikes, investigate chase-camera smoothing vs guest
timer at fluctuating FPS, including transitions around 60Hz.
If it instead resembles world-object/geometry flashing, isolate
map occlusion and scene streaming before changing camera physics.

## SDK and game QA (15 October 2026)

- Full `make_pc.ps1 -FidelityFX` build passed, retaining the Fast Runtime
  with `REXGLUE_ENABLE_PERF_COUNTERS=OFF`.
- 34-second native 720p/FidelityFX initial/title run with
  `--d3d12_scissor_cache=true --d3d12_scissor_cache_audit=true` passed.
- At the last 3.67 million draw-state lookups, the scissor cache
  reused approximately 99.0% of scissor rectangles.
- 1,774 audit comparisons showed **0 mismatches**. This is only
  initial/title gameplay and does not cover the user's problematic
  high-speed city route.
- Window-close QA passed (`CLOSED=True EXIT=0`).
- Audit option and scissor cache option each appear exactly once
  in the local config. Original 720p, FSR, 768/1024 MB texture budget,
  90-second retention, 67 ms Gentle guard and FPS HUD are unchanged.

Do not merge to main without real driving and visual validation.
No copyrighted assets or generated binaries are committed.
