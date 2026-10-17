# Experimental DX12 completed-texture reuse A/B
Date: 2026-10-17
Branch: experiment/dx12-completed-texture-reuse-ab

## Reason and baseline

User reported UNCAPPED felt visibly better than both new timer pacing
modes, so leave mcla_fps=0 and the pacing mode OFF. The two most
recent real drives (mcla_041, mcla_042) did not demonstrate a pacing
improvement. All FPS-limiting changes are out of this experiment.

Previous opt-in D3D12 CPU hitch instrumentation (mcla_022)
attributed some GPU Commands thread intervals >=50ms to the CPU
request of guest textures, e.g. a 161.8ms GPU Commands swap
interval included 108.8ms RequestTextures CPU work. This does
NOT prove resource creation specifically is the bottleneck.

The local ReXGlue v0.10.0 SDK was already patched with an opt-in
completed-GPU-submission DX12 texture resource pool:
patches/rexglue-dx12-resource-pool.patch
CVar d3d12_texture_resource_pool_mb=0 (default OFF; max 256).

A bounded pool can sometimes avoid ID3D12Device::CreateCommittedResource
when a texture of identical dimensions / format / mip count is
destroyed and recreated. The resource is only considered for reuse
if its last GPU submission index is nonzero and no longer pending
according to GetCompletedSubmission(); the existing patch adds a
state transition when required and retains a COM reference until
checkout. New guest texture data must still be uploaded. There is
no guarantee this traffic pattern happens frequently in actual
city gameplay. Pooling can cost extra memory, add CPU lookup
overhead and potentially expose render correctness bugs.

## Changes this iteration

- Expose opt-in pool via PERFORMANCE -> DX12 TEXTURE REUSE
  (NEXT START): OFF, 64 MB, 128 MB. The existing RACE SHADOWS
  toggle moved from PERFORMANCE to DISPLAY because the guest
  menu's maximum is 16 rows. Nothing removed.
  DISPLAY 13 rows, PERFORMANCE 16 rows (Windows build).
- Add scripts/dx12_texture_reuse_trial.ps1 -Mode off|64|128|status
  to switch ONLY the pool limit, refuse changes while MCLA runs,
  and save an original config backup under ignored out/.
- Add scripts/dx12_texture_reuse_report.ps1 with -LogPaths,
  -SkipFirst and -MaxWindows to compare equal 10s windows and
  show at-least observed pool reuse markers.
- No SDK logic changes made this iteration. The existing SDK
  patch is OFF by default; 64 MB has been set explicitly in
  the local game for one opt-in road test.
- FPS target remains 0 (uncapped), pacing mode OFF, FSR,
  shader settings, 67ms guest guard, and user's Fast Path,
  sparse Texture Sampler, HUD, DX12 scissor all preserved.

## Local QA

Windows FidelityFX game built successfully using
scripts/build.ps1 -NoCodegen -FidelityFX.
Reused already compiled SDK binary; no change to DLLs.

Pool=64 smoke:
  out/runs/quit-qa-20261017-015813.log
  CVar activation logged "DX12 texture resource reuse experiment: 64 MB".
  Clean Windows close CLOSED=True EXIT=0.
  Two stable title/menu FPS benchmark windows were ~41.86
  and ~41.27 guest presents/s, no >=50ms frames.
  No "successful reuses" markers in the smoke test.
  In the title/menu stage, resource recycling may not occur,
  so this does NOT validate a benefit during city driving.

Pool=OFF smoke:
  out/runs/quit-qa-20261017-015848.log
  Clean Windows close CLOSED=True EXIT=0.
  The short test did not contain enough stable 10s windows
  to make a valid A/B timing comparison.
  No positive-pool activation marker.

The script restored pool=64 for the player's next drive test.
Source and compiled artifacts backed up in ignored
out/phase2-backup/pre-dx12-completed-resource-reuse/.

## Controlled manual test — mandatory before keeping

Do not test a different FPS cap or change the render preset.
Use the same driving route/vehicle/camera with normal game graphics:

1. Close MCLA. Confirm -Mode 64. Drive 2-3 minutes including
   busy streets, decals/traffic, multiple city transitions.
   Check all textures for missing, white, black or flickering
   surfaces. Note flick occurrence and quit the game.
2. Close MCLA, use -Mode off and repeat the SAME route, quit.
3. Analyze both logs with:
       .\scripts\dx12_texture_reuse_report.ps1 -SkipFirst 4 -MaxWindows 8
         -LogPaths @('out\build\win-amd64-release\logs\mcla_0XX.log',
                     'out\build\win-amd64-release\logs\mcla_0YY.log')
4. Compare equal 10s windows, guest-present FPS, worst-frame,
   stalls >=50 / >=100ms, plus resource hit markers. The last
   power-of-two marker is a **lower bound**, not exact hit count.
5. If visual artifacts, crashes, memory pressure, no meaningful
   reuse or no improvement: leave -Mode off. Do not merge.

Never claim an A/B improvement from nonidentical driving alone.
Do not commit binaries, saves, game assets or logs. Avoid merge/push
until player confirms visuals and repeatability.
