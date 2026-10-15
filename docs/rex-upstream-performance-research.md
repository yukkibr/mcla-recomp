# Performance research: official ReXGlue development and LARecomp

Compared on October 15, 2026, using read-only local checkouts in the
ignored directory `out/references/`.

- Official SDK: https://github.com/rexglue/rexglue-sdk/tree/development
  (commit bd833a2, checked out separately).
- LARecomp: https://github.com/mzzvxm/LARecomp/tree/main
  (commit 23b91be, checked out separately).
- Our pinned, locally patched SDK: v0.10.0 / f5337cd.

## Findings

**1. The development SDK does not remove the D3D12 allocation bottleneck.**
The DX12 texture creation in
`src/graphics/d3d12/texture_cache.cpp` still uses
`ID3D12Device::CreateCommittedResource` at each uncached texture
resource creation. The development checkout did not expose a D3D12MA
allocator or a compatible resource pool for that code path.
Upgrading the SDK wholesale would introduce a substantial risk of
regressions against our game-specific patches, without a proven
fix for the measured stalls. Do not switch the pinned SDK yet.

**2. LARecomp contains a DIFFERENT native graphics architecture.**
Its `src/native_gfx/` has its own texture and buffer region caching,
fence-retirement, invalidation and upload code. That is not a small
patch we can safely paste into the ReXGlue Xenos D3D12 texture cache.
It could inspire a future alternative graphics backend, but a port
would require substantial testing and is not part of this experiment.

**3. LARecomp documents a long-session vblank issue.**
The authors report an unsigned underflow in the SDK vblank catch-up
loop, causing interrupt storms after several minutes. Their temporary
workaround is `--clock_no_scaling=true`. The CVar is present in our
SDK and in the development checkout. Whether the issue also causes our
individual 50-600ms frame spikes is NOT established. Switching the
guest clock alters timing behavior, so it should be a separate
30-minute A/B test, not a new default without evidence.

**4. The original project reports significant profiling overhead.**
LARecomp documents thousands of high-frequency PM4 timer queries and
substantial CPU time in its earlier SDK/compiler configuration. Our
ReXGlue SDK v0.10.0 has `REXGLUE_ENABLE_PERF_COUNTERS=ON` in the
Release CMake cache. Although the implementation is not identical,
ReXGlue's per-frame and per-command atomic counters are compiled into
Release when this option is ON. Profiling itself may add work to the
already busy CPU thread. This is a concrete, reversible build-mode
experiment and does not affect the game simulation or shader output.

**5. D3D12 primary buffer submission is already enabled.**
Our SDK defines `d3d12_submit_on_primary_buffer_end=true` by
default, the same value LARecomp recommends. No change is needed.

## New build modes

Default fast playable build, with ReXGlue per-frame counters compiled
out (but retaining FidelityFX and the existing MCLA settings):

    .\scripts\make_pc.ps1 -FidelityFX

Full ReXGlue CSV diagnostic build, which restores all counters:

    .\scripts\make_pc.ps1 -FidelityFX -ProfileCounters

The build script stores the installed perf-mode stamp in the SDK
install directory and rebuilds when the setting switches. Both
modes retain all existing project patches and the SDK pinned commit.

When the fast build is active, `scripts/profile_gameplay.ps1`
refuses to create empty/misleading ReXGlue frame CSVs and instructs
you how to enable the diagnostic build first.

## Validation limits

The original 480p + FSR frame captures were made with the profiler
compiled in, so their FPS numbers cannot directly predict the
fast build's effect. Title-screen benchmarks vary with moving
cameras and shaders; do not claim the LARecomp authors' FPS
numbers as our own. Have the player repeat the SAME heavy-traffic
route after building the fast mode, compare subjective hitching,
input/camera stability and overlay frame rate. A fully controlled
frametime comparison will require a low-overhead external capture
such as PresentMon/ETW because ReXGlue CSV counters are intentionally
absent in the fast build.

## Texture resource pool experiment

Our earlier experimental 64MB resource pool logged 1,024 misses
and zero confirmed reuses in the initial scene. Its heavy-city run
averaged 21.9 FPS versus 24.6 in a non-identical prior run; this
does not establish a causal regression or a benefit. Leave
`d3d12_texture_resource_pool_mb=0` until a positive hit rate
and controlled reduction in creation time are demonstrated.

No copyrighted game data, ISO, compiled XEX or binaries belong in
this repository.
