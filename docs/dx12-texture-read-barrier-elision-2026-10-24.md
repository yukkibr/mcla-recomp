# DX12 texture read-barrier CPU fastpath (2026-10-24)

Branch: development (safety branch unchanged).

## Latest measured gameplay
mcla_065.log, 12 x 10s windows excluding the first 20s: average
42.59 guest Presents per second and 26 frame gaps >=50ms, 4 >=100ms.
mcla_064.log: 38.79 and 20 / 4. The routes, traffic and loading differ.
Neither improvement nor regression can be assigned to the deferred
texture pool from these uncontrolled runs.

The texture resource pool probe had zero eligible recycled resources
and zero pool hits in the title/intro. We cannot infer actual driving
benefit or CPU/GPU bottleneck solely from those measurements.

## New GPU Commands thread optimization
Source: patches/rexglue-dx12-texture-read-barrier-elision.patch
CVar: d3d12_texture_read_barrier_elision (default false, restart-only).

The D3D12TextureCache::RequestTextures code calls PushTransitionBarrier
for every bound signed and unsigned texture on every draw. The called
function immediately returns false when old_state == new_state.
This patch instead checks those states at the callsite and avoids
the call entirely when it would be a no-op. Critically it still:
- Marks every bound texture as used on each draw.
- Updates the tracked D3D12 resource state.
- Emits every actual GPU resource transition barrier unchanged.
- Preserves GPU submission tracking, residency, texture conversion
  compute shaders, texture cache invalidation, descriptor handling.
- Changes no game code, simulation, physical VRAM allocation, FSR or
  render resolution.

Script (game must be closed for changes):
    .\scripts\dx12_texture_barrier_trial.ps1 -Mode status
    .\scripts\dx12_texture_barrier_trial.ps1 -Mode on
    .\scripts\dx12_texture_barrier_trial.ps1 -Mode off

Evaluate in matched 2-3 minute drives, ideally OFF/ON/OFF/ON,
after shader and resource warmup. Title-screen FPS does not count.

## Safety
Safety branch: safety/stable-fps-2026-10-24, commit 1bb25c4.
Ignored local exact binary/SDK backup:
out/phase2-backup/safety-stable-fps-20261024/
Do not reset the nested SDK. Keep development as integration branch
and main unchanged. The user-approved graphics and physics settings
stay unchanged, as does the Options -> Settings menu fallback:
mcla_options_native_submenus=false.

## QA results

- Full ReXGlue v0.10.0 and host game build: PASS, FidelityFX ON,
  ReXGlue profiling counters OFF, 245 generated code modules unchanged.
- Baseline OFF: out/runs/quit-qa-20261024-122305.log,
  CLOSED=True EXIT=0, no activation marker.
- Optimized ON: out/runs/quit-qa-20261024-122325.log,
  CLOSED=True EXIT=0, log explicitly confirms no-op read barriers skipped.
- Both boots confirmed 1280x720 native guest rendering, DXGI
  texture cache soft=4006 MiB, hard=5342 MiB.
- The two changed SDK source files were reverse patched and re-applied
  byte for byte using an isolated Git checkout; patch roundtrip PASS.
- mcla.toml now contains d3d12_texture_read_barrier_elision=true for
  the user's next city gameplay A/B. CPU/GPU speeds have NOT been
  measured in a comparable full traffic scenario, so no FPS claim yet.
