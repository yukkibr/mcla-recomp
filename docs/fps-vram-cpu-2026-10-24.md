# MCLA CPU / DirectX 12 / Video Memory Plan — October 24, 2026

Branch: **development**. Stable `main` remains unchanged.

## Video-memory budget — implemented

The user's RTX 5060 Ti has 8,151 MiB dedicated according to the
NVIDIA CLI. DXGI reported 7,891 MiB dedicated memory visible to the
adapter, a 7,123 MiB local budget and 0 MiB process usage *before*
the renderer was initialized; the two APIs are not interchangeable.
Windows GPU Process Memory recorded 168.9 MiB while the **intro/menu**
was running, not during city gameplay.

Existing config:
- `texture_cache_memory_limit_soft = 768` MiB
- `texture_cache_memory_limit_hard = 1024` MiB
- `d3d12_texture_resource_pool_mb = 128` MiB (separate optional DX12 pool)
- GPU buffers, render targets, shaders, screen, FSR and desktop graphics
  are **not** included in the texture-cache hard limit.

**Implemented**:
- `src/gpu_vram_budget.{h,cpp}` samples dedicated VRAM, local budget and
  the process's current local allocation via DXGI 1.4 Adapter3.
- Sampling is rate-limited to once every two seconds in the player HUD.
- DISPLAY has `VRAM TEXTURE CACHE (NEXT START)`: EXISTING, AUTO SAFE,
  1,024/1,536/2,048/3,072/4,096/5,120/6,144 MiB and MAX SAFE.
- New persisted CVar `mcla_texture_cache_budget_mb`, default -1
  (preserves existing soft/hard limits). 0=AUTO, -2=MAX SAFE.
- On startup, compute maximum texture budget as min(75% dedicated,
  75% Windows local budget, Windows budget minus 1GiB, 8GiB).
  This MAX SAFE was ~5,342 MiB on the user's card at test time.
  Windows can change budgets later; this is an initial conservative bound.
- Derive 75%-sized soft cache (up to the SDK's hard soft cap of
  4,096 MiB) from the requested hard cache.
- HUD FPS panel shows process local VRAM / Windows process budget,
  dedicated VRAM size and a small lavender usage bar.
- Mode changes require restarting MCLA; the settings menu saves
  this selector to `mcla.toml`.

**Important**: This is a configurable *texture cache target*, not a
guarantee that the whole MCLA process can never exceed that limit,
and does not preallocate the selected capacity. A higher cache is
not a guarantee of more FPS; it may reduce eviction/streaming at
the price of greater memory pressure, especially near budget.
Do not naively set the cache to the full physical VRAM.

Validation:
- First smoke revealed a real issue: the chosen 2,048 MiB budget
  was applied before the Xenos DLL had registered its CVar.
  We corrected the initialization order: load Xenos DLL first,
  set cache limits, then call Runtime::Setup.
- Repeated 2,048 MiB boot/exit smoke succeeded, EXIT=0.
  Runtime confirmed **soft=1536, hard=2048** in OnPostSetup.
- Baseline 1,024 MiB boot/exit succeeded, EXIT=0.
  Runtime confirmed **soft=768, hard=1024**.
- MAX SAFE test must confirm effective hard 5,342 MiB and smoke;
  the test may not exercise all streaming paths.

## 1 — Guest D-cache loop replacement — compiled, opt-in

LARecomp's `mc_FlushDataCache` hook at 0x821D5510 inspired the
safe change in `src/threading_perf.cpp`.
The original PPC function is only a 128-byte-stride loop over
emulated DCBF/DCBST. The generated host code treats both
instructions as no-ops but still executes the loop bookkeeping.
When CVar `mcla_fast_guest_cache_flush = true` it executes one
C++ `std::atomic_thread_fence(std::memory_order_seq_cst)` and jumps
directly to original guest BLR 0x821D5544, preserving r3.
OFF executes the original generated function unmodified.
The hook is in `config/threading_perf.toml` and included from the
manifest. Full codegen and host linking completed without failure.
The optional `mcla_cache_flush_stats` logs sampled call counts but
adds overhead; keep off during FPS benchmarking.
**No proven FPS gain or gameplay stability result yet.**
Test in same traffic/route 2–3 minutes ON, OFF, ON before
considering default ON. Monitor audio, mission transitions,
memory streaming and any new crashes.

## 2 — DX12 draw translation — existing diagnostics analyzed

The previous instrumented 80-second city sample `mcla_049.log`
showed ~37.94 guest-present requests/s (not hardware onscreen FPS).
During frame hitches, CPU thread processing a draw was dominated
by **texture requests**: 94.6ms texture request CPU in a
124.4ms swap interval at 21:59:22. Other examples had up
to 735ms CPU texture work during asset transitions, while
pipeline creation and GPU fence wait were near zero in those
specific reported events. Nested categories must not be added.

Our existing SDK `d3d12_hitch_probe` already breaks down draw,
render targets, pipeline, textures, bindings, submissions and fence.
Avoid installing another expensive per-draw timer without evidence.
Next stage: A/B cache 1024 versus 2048 (and AUTO), with *texture
diagnostics OFF*. Then isolate new-texture creation CPU cost and
invalidate/cache misses before changing shader or draw ordering.

## 3 — LARecomp native renderer — feasibility reviewed

`mzzvxm/LARecomp` public checkout holds ~116 native_gfx files
(~1.94MB in the checked out project), including its own resource
cache, barrier batcher, DX12 pipeline cache, shaders and frame
capture. It is NOT a drop-in patch to our ReXGlue Xenos backend.
LARecomp's proprietary/custom SDK rendering fixes are not fully
published. Copying modules without their dependencies would
likely break rendering correctness.
Decision: no mass merge at this time. We will port individually
only well-grounded functions with permitted reuse, ABI compatibility
and side-by-side render validation. Keep DirectX 12 default.

## 4 — SDK / upstream changes — assessed

ReXGlue 0.10.0 is still the pinned SDK family. Our patched
`graphics_system.cpp` ALREADY handles backward guest-tick jumps:
a signed behind check and max 1/4 second catch-up prevents the
infinite vblank interrupt loop discussed in LARecomp.
We therefore do NOT replace the SDK or change
`clock_no_scaling`, which may alter guest pacing.
holdmysocks's more recent changes are mainly build/setup and
game correctness fixes, not a proven FPS rewrite; review
individual patches before porting. Preserve our uncommitted
SDK-specific patches; NEVER hard reset that checkout.

## Repeatable user A/B

With MCLA closed:

```powershell
.\scripts\vram_cpu_trial.ps1 -Mode status
.\scripts\vram_cpu_trial.ps1 -Mode legacy -CacheFlush off
# Play same route 2-3min, quit
.\scripts\vram_cpu_trial.ps1 -Mode 2048 -CacheFlush off
# Drive again, compare frame times, VRAM usage and textures
.\scripts\vram_cpu_trial.ps1 -Mode legacy -CacheFlush on
# Separately test cache-flush hook against original
.\scripts\vram_cpu_trial.ps1 -Mode legacy -CacheFlush off
```

FPS UNCAPPED, TIME_CORRECTED, DX12, FidelityFX spatial FSR,
traffic density, 67ms guard and user game saves remain unchanged.
Only revert/apply experiment CVars after closing game.
No claims of 60+ sustained FPS without recorded city A/B.
