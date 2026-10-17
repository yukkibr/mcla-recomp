# ReXGlue texture pool lifetime and DX12 allocation telemetry
Date: 2026-10-17
Branch: experiment/rexglue-texture-pool-telemetry

## Evidence and reason

The user saw a small visual improvement with 128 MB texture reuse,
compared to 64 MB. Real driving logs mcla_043 (64MB) and mcla_044
(128MB) compared over equal 40s after warmup had guest-present
averages 39.34 and 42.04 FPS, but both had 4 >=50ms intervals
and 2 >=100ms intervals. The larger pool's worst interval
579.6ms exceeded the smaller pool's 441.2ms. The 64MB session
also involved navigating the settings menu, so these differences
are NOT proof that pool reuse accelerated rendering.

Both runs emitted one checkpoint at 1024 misses and 0 reuses.
The message is emitted *only at the 1024th miss* and does not
represent a final tally. The game's shutdown hard-exits, so the
ordinary D3D12 texture cache destructor summary is not reliable.

The primary texture cache's soft/hard limits and 90s retention
are upstream of texture object destruction. Resources cannot
enter the secondary DX12 reuse pool until their C++ D3D12Texture
destructor runs. Increasing pool MB without measuring lifetime
was premature.

## Changes to actual ReXGlue SDK

Versioned patch:
patches/rexglue-dx12-texture-pool-telemetry.patch
Built in pinned v0.10.0 local SDK source and installed by
scripts/make_pc.ps1 after the preexisting DX12 resource-pool patch.
Only this patch uses git apply --ignore-whitespace to accommodate
Windows patch context drift. Do not stage the patched SDK
checkout, generated binaries or game content.

New GPU CVar d3d12_texture_resource_pool_probe=false (default OFF).
ON provides cumulative snapshot roughly every 10s when texture
creation remains active:

- total committed DX12 resource creations, failures, total and
  peak CPU time in ID3D12Device::CreateCommittedResource;
- 8 or fewer individual >=5ms resource creation events;
- C++ texture destruction recycle callbacks and accepted pool
  stores, plus rejected-untracked, busy-GPU, oversize and other;
- pool entry count, current and peak MB, exact-description
  misses, pool evictions and actual successful reuse hits.

The probe does not change fence completion rules, COM ownership,
texture lifetimes, cache eviction, guest residency, uploads,
GPU commands, camera, physics, FPS caps or GPU synchronization.
All counters are ordinary members accessed on the texture cache's
GPU Commands owner thread. CVar OFF does not invoke timing/logging.

IMPORTANT: CreateCommittedResource duration is CPU wall time
only. It is NOT actual GPU execution time, nor all CPU draw work.

## Build, smoke and local result

Full build using scripts/make_pc.ps1 -FidelityFX succeeded.
Pinned SDK v0.10.0, FidelityFX ON, heavy CSV counters OFF.
Clang 20.1.8; mcla.exe and rexgpu-xenos.dll updated.

Probe ON with 128MB, mcla_fps=0, FSR:
out/runs/quit-qa-20261017-021653.log
CLOSED=True EXIT=0; two 10-second snapshots.
After 707 new GPU resources: 0 texture recycling callbacks,
0 stored, 0 reused. Creating the resources cost cumulative
278.63ms of CPU, 0.3941ms average, peak 0.83ms and 0 failures.
These results are intro/menu ONLY, not driving, and do not prove
that the pool never helps during gameplay.

Probe OFF:
out/runs/quit-qa-20261017-021818.log
CLOSED=True EXIT=0. No probe counters should be emitted.

Both the original local executable, DX12 DLL, SDK sources and
configuration are backed up under ignored
out/phase2-backup/pre-rexglue-texture-pool-telemetry/.

## Player driving test

The local game is left with diagnostic ON and pool 128MB for the
next test; mcla_fps=0, frame pacing OFF, Fast Path and Sampler ON,
HUD and FSR ON, VSync OFF and Gentle guard 67ms remain unchanged.
Drive 2-3 minutes in busy city sections; note flick time and
whether textures remain correct, then quit. Run:

    .\scripts\dx12_texture_pool_probe_report.ps1 -Recent 2
    .\scripts\dx12_texture_reuse_report.ps1 -Recent 2 -SkipFirst 4

Disable instrumentation after testing, when game is closed:

    .\scripts\dx12_texture_pool_probe_trial.ps1 -Mode off

Decision gate:

- recycle_attempts=0 in the city: look at main cache residency
  and eviction, not the secondary pool size.
- reject_busy high: investigate separately a bounded deferred
  COM resource queue, never reuse before GPU submission completes.
- recycled>0 and desc_misses high: test descriptor distribution
  before bucketed pooling.
- low creation cost during a flick: focus on shared-memory
  residency/command translation instead of resource creation.

No actual FPS improvement is claimed in this telemetry phase.
Any subsequent cache-policy change requires route-matched A/B/A,
visual graphics checks and reversible safeguards before merge.
No merge or push is performed here.
