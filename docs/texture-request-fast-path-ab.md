# Experimental ReXGlue texture request fast path

Branch `experiment/texture-request-fast-path`, based on
`experiment/dx12-texture-hitch-decomposition`. Do **not** merge
to main until A/B city-driving and visual regression tests pass.

## Evidence motivating optimization

The actual 2026-10-16 21:22–21:24 player drive in
`mcla_023.log` produced about 10.5 million
`TextureCache::RequestTextures` calls over 15 five-second
driving windows, and ~4.96 million calls reporting changed texture
bindings. Thus the original request path is entered *very frequently*,
even if no fetch constant actually needs reprocessing.

Prior DX12 CPU hitch probe reported 596.4 ms between swaps,
with 518.7 ms processing texture requests; the newly added
stage probe showed 656.9 ms prep vs 70.3 ms residence and
32.7 ms upload *aggregated in one 5s window*. The probe
rounds individual samples to whole microseconds, so its aggregate
may undercount time across millions of sub-microsecond calls.
No inference that 10.5m calls equals unique texture creations.

## Actual optimization

SDK patch `patches/rexglue-texture-request-fast-path.patch`
is applied incrementally after the stage instrumentation, against
pinned ReXGlue v0.10.0. Shared texture cache serves both D3D12
and Vulkan, though gameplay A/B initially targets D3D12 only.

New CVar `texture_request_fast_path=false` (default OFF,
opt-in), hot reload supported but compare with game restarted.

With this CVar ON:

1. Read and consume `texture_became_outdated_` with the **same
   acquire/release atomic exchange** as the original implementation.
   When it was set, call the unchanged `ResetTextureBindings()`,
   including GPU descriptor update and sync-mask invalidation.
2. Only if `used_texture_mask & ~texture_bindings_in_sync_`
   is zero, exit. The original implementation has no visits,
   no pending loads and no binding updates in this condition.
   All changed fetch constants and watched invalidation paths
   **fall through normally**.
3. Replace the three temporary `std::vector` instances with
   three per-TextureCache scratch vectors, cleared before each
   full request. They retain capacity across calls, but not
   content. This avoids heap allocation churn while remaining
   isolated to one GPU texture cache instance. No bytes,
   keys or temporary texture pointers are used after clearing.
4. Emit a `Texture fast path: ... confirmed no-op calls bypassed`
   message after every 500,000 bypassed requests on that thread.
   This is diagnostic progress, not a claim of FPS improvement.

All texture creation, guest shared-memory residency requests,
outdated watch registration, image uploads and GPU texture
bindings retain the original implementation.

**Risk:** this is a hot path with texture invalidation from other
threads. Test camera, roads, decals, reflections, shadows, UI
and garage/interior transitions. If artifacts occur, close game
and toggle the optimization OFF, then compare/restart. It is
designed to be equivalent only if existing sync masks correctly
describe which fetch constants require refresh.

## Reversible A/B test

From the repo folder, with game closed:

    .\scripts\texture_fastpath_trial.ps1 -Mode off
    .\scripts\texture_fastpath_trial.ps1 -Mode on
    .\scripts\texture_fastpath_trial.ps1 -Mode status

Keep `dx12_texture_stage_probe=false`,
`d3d12_hitch_probe=false`, `mcla_timing_trace=false`
for **FPS comparisons**, to eliminate diagnostic overhead.
Maintain **D3D12**, 1280x720, `present_effect=fsr`,
VSync off, `mcla_fps=0`, scissor cache ON,
768/1024MB texture retention and the 67ms Gentle guard.

Warm the game and drive the SAME downtown route in both modes,
note 1) average FPS, 2) the worst guest frame time and frequency
of visible flick and 3) any rendering corruptions. Avoid interpreting
just the title screen as proof. Consider an A-B-A order to avoid
shader/asset warmup order effects.

Backup of the previous game executable, runtime DLLs, config
and pre-optimization SDK sources is in
`out/phase2-backup/pre-texture-request-fast-path/` (ignored).
No save, ISO, game binaries or SDK-local files are committed.

## Automated validation — 2026-10-16

- Full `scripts/make_pc.ps1 -FidelityFX` passed with
  `FidelityFX=ON`, expensive CSV counters OFF, Clang 20.1.8
  and no regenerated guest functions (245 unchanged).
- The first pair of title-screen tests exposed a **malformed test
  toggle script**: repeated `texture_request_fast_path` values
  ending in a literal backslash. The script was repaired to rewrite
  assignments as distinct lines, removing every duplicate. The
  earlier result is not valid for A/B benchmarking.
- The corrected `mcla.toml` now has exactly one
  `texture_request_fast_path = true` line, and malformed
  `dx12_texture_stage_probe` value was normalized to `false`.
- The final build records `Texture fast path enabled:` once
  at the first actual texture request, and bypasses print its
  accumulated no-op counter every 500,000 skipped requests.
- Final QA OFF: `out/runs/quit-qa-20261016-214504.log`
  `CLOSED=True EXIT=0`.
- Final QA ON: `out/runs/quit-qa-20261016-214433.log`
  `CLOSED=True EXIT=0`.
  Both QA sessions were in the title/initialization and did
  not reach enough in-world texture traffic to confirm the
  bypass counters. Real street driving and visual inspection
  are **required before claiming a speedup or correctness**.
- User configuration left with fast path ON for one controlled
  trial; `mcla_fps=0`, 1280x720 FSR, DX12 scissor ON,
  Gentle 67ms, texture retention 768/1024MB 90s.
  All expensive timing probes are OFF.

Do not cherry-pick or merge this branch until the optimized
mode passes road texture, vehicle, HUD, decal and camera
comparison against the OFF baseline on the same driving route.
