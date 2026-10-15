# Experimental D3D12 texture resource reuse pool

Branch: experiment/dx12-texture-resource-pool, based on the verified
DX12 CPU resource profiler.

## Why

The October 15 dense-city capture is in
out/profiles/20261015-163412 (ignored from Git).
Its 7,109 analyzed frames averaged 24.6 FPS. Among 48 frames
over 100 ms, 47 recorded host D3D12 texture resource creation.
The cumulative host creation time was 43.9% of the combined duration
of those 48 slow frames. The worst frame was 592.4 ms and spent
441.9 ms inside D3D12 CreateCommittedResource.
Other bottlenecks remain; results cannot guarantee higher FPS.

## Implementation

The pinned ReXGlue SDK patch is:
patches/rexglue-dx12-resource-pool.patch.

It creates an optional limited pool of already released D3D12
textures and checks all resource descriptor properties before
reusing a resource. A resource is admitted only when:
- It has a tracked nonzero last-use submission.
- The last-use submission is no newer than the GPU completed fence.
- Its size fits the requested pool budget.

All D3D12 SRV descriptors are released from the original texture,
and a new Texture wrapper gets its own descriptors. The original
guest texture pixels are not reused: new texture contents are
uploaded. When a reused resource has a different D3D12 state, the
normal command processor records a barrier before the upload.
ClearCache and cache destruction empty the pool.

This is a **bounded cache of GPU resource allocations**, separate from
ReXGlue texture pixel caching. Holding pooled committed resources may
temporarily increase dedicated GPU memory consumption by up to the
configured budget. Does not touch the physics, guest frame timer,
render quality, spatial FSR or QUIT GAME behavior.

## Activation

The new experimental SDK option is an integer in MB:
d3d12_texture_resource_pool_mb. Default: 0 (OFF).
SDK supports 0 through 256; first controlled test: 64 MB.
The option must be selected before launching, and requires restart.

Start a comparison without editing mcla.toml:

    .\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4 -ExtraArgs @('--mcla_fps=30','--d3d12_texture_resource_pool_mb=0')

    .\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4 -ExtraArgs @('--mcla_fps=30','--d3d12_texture_resource_pool_mb=64')

Use exactly the same car, route, camera, traffic preset, resolution,
and restart the game for each run. Let each run finish, quit normally,
then generate reports with scripts/report_frame_spikes.py.

Success criteria: lower creation time, fewer >100ms and >50ms frames,
improved P99/1%-low, no corrupted/missing textures, no out-of-memory.
Worse frametime, new glitches, crash or VRAM pressure: use 0 / OFF
immediately. Do not claim performance wins based on menu-camera smoke tests.

## Build and rollback

The project applies the patch automatically in scripts/make_pc.ps1
on a clean SDK checkout; existing SDK and rendering patches are
applied first. Build normally:

    .\scripts\make_pc.ps1 -FidelityFX

The working previous binary and configuration are backed up under:
out/phase2-backup/pre-resource-pool.

## Local validation

The patched SDK and full FidelityFX-enabled game build compiled.
The startup smoke ran with the pool disabled and with a 64 MB pool.
A 64 MB session successfully displayed the title / city scene and
closed normally via WM_CLOSE with exit code 0 after 52 seconds.

The opt-in log recorded 1,024 lookup misses and zero reuses in the
title screen run. **No improvement has been established** in this
scenario; there may be too few safely retired, matching resources
to reuse. Do not turn the pool on permanently based on this test.
It is provided strictly for a controlled heavy-city A/B trial.

Still outstanding: warm and cold driving on the same route with
0 MB versus 64 MB; monitor pool reuse logs, resource-create CPU
time and VRAM usage. If reuses stay at zero, or graphics glitch,
revert to 0 and do not merge the feature as a performance fix.
