# DX12 resource recycling and original Options menu recovery
Date: 2026-10-24. Branch: development. Safety: safety/stable-fps-2026-10-24.

## Reported improvement and logs
The player reports steadier motion but severe location-dependent drops.
The last manually driven log, mcla_064.log, in 12 comparable-length
10-second windows following two warmup windows, reported 38.79 guest
Present requests/s, 20 >=50ms stalls and 4 >=100ms stalls. The prior
mcla_063.log had 39.38 Present requests/s and 36 / 7 stalls respectively.
The routes are uncontrolled and menu time may affect samples. This
supports further investigation but NOT a claim of measured FPS gain.

## Original Options menu regression fixed via fallback
The previous patch attached DISPLAY and PERFORMANCE as children of
PM_GameOptions, a retail state under SettingsMenu. However the retail
Game Options screen is a separate movie/list dispatcher; it ignores
these child states. In mcla_064.log the states and rows were created
correctly under PM_GameOptions but never displayed. CONTROLS remained
accessible in Settings.

The user's mcla.toml is now explicitly:
    mcla_options_native_submenus = false

The source DEFAULT was also changed to false so future installs keep
the already verified Settings location. The experimental original
OPTIONS attach code is retained, NOT considered an implemented UI
migration. Do not present it as fully working. Completing this
requires intercepting and extending the actual native Options list
(its widget and click dispatch, not the SCXML PM_GameOptions children).
The LARecomp original reference has an opt-in Game Options PM_Graphics
intercept at address 0x826686D4 that opens an external overlay. That
intercept REPLACES a stock option rather than adding native DISPLAY
and PERFORMANCE buttons, so it is NOT a correct substitute.
The new original OPTIONS list adapter is deferred until we can
inspect the native screen layout and its controls in actual gameplay.

User fallback:
    .\scripts\options_menu_location_trial.ps1 -Mode settings
The code default itself now preserves that fallback without user steps.

## DX12 GPU-safe deferred texture resource reuse
Opt-in source patch:
  patches/rexglue-dx12-deferred-gpu-texture-reuse.patch
Run:
    .\scripts\dx12_deferred_texture_pool_trial.ps1 -Mode status
    .\scripts\dx12_deferred_texture_pool_trial.ps1 -Mode on
    .\scripts\dx12_deferred_texture_pool_trial.ps1 -Mode off

Previously, the D3D12 resource pool kept textures only when their
last GPU submission had *already* completed when destructed.
If a resource was destroyed while GPU commands still used it, the
pool immediately rejected it, releasing its recycling opportunity.
It is now optionally retained in the existing bounded pool with the
last GPU-use submission index, so it can become eligible later
without another CreateCommittedResource call.

Correctness/limits:
- A pool entry can be reused only after its last_usage_submission_index
  <= GetCompletedSubmission() (checked right before selecting it).
- In-flight resources keep an owning COM reference in PooledResource.
- The existing 128MiB resource pool cap includes retained pending
  resources. The over-budget path only evicts resources that have
  finished; if all eligible candidates are busy, reject the incoming
  object without modifying the pool. Never evict pending submissions
  from the pool just to admit another texture.
- Unknown/untracked submission IDs still prevent recycling.
- GPU barriers on reuse still use the previous known state and the
  destination COPY_DEST state.
- The change does NOT force VRAM allocations, wait on fences, change
  guest frame time, physics, shader conversion or guest texture content.
- CVar d3d12_texture_deferred_recycle defaults to false in SDK. The
  user testing config currently has it set to true for an A/B drive.

Measured initialization:
- Probe with original pool: mcla title/intro ~1471 committed
  resources, 583ms cumulative resource allocation, zero recycle
  attempts, zero reuses (first 30s).
- New pool enabled with probe: ~520 initial resource creations,
  ~206ms cumulative allocation, zero recycle attempts and zero
  deferred resources retained in first 15s; difference is due to
  sampling duration, not a proved speed improvement.
- Off smoke: quit-qa-20261024-120625.log, CLOSED=True EXIT=0.
- On smoke: quit-qa-20261024-120645.log, CLOSED=True EXIT=0;
  "DX12 deferred GPU-safe texture resource recycling ON; budget=128 MiB".
- Both D3D12 builds succeeded, FidelityFX ON, CSV profiling OFF.
- Device: RTX 5060 Ti, DX12 default, FSR, 1280x720 guest render,
  uncapped FPS; mcla.toml other preferences remain unchanged.

Need 2-3 minute city driving A/B before concluding if reclaimed resources
materially reduce texture allocation hitches; zero reuses in title/intro
cannot establish improvement. If VRAM usage, flickering, crashes or FPS
regresses, turn deferred pool OFF only.

All work on development; original main and stable safety branch unchanged.
Original ReXGlue SDK local patches MUST NOT be reset.
