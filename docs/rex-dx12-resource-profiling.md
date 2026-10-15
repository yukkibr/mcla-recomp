# ReXGlue DX12 resource profiling — diagnostic branch

Branch: experiment/rex-dx12-resource-profiling

## Important correction to previous analysis

The existing ReXGlue D3D12 counter named texture_cache_misses is
incremented in D3D12TextureCache::FindOrCreateTextureDescriptor
when an SRV descriptor does not already exist. This is **not**
evidence of disk streaming, texture-data cache eviction, or GPU
upload by itself. Prior reports showed correlation with slow frames;
they could not establish why the misses were occurring.

The last heavy 854x480 / spatial FSR sessions recorded:
- Uncapped: 991 frames over 50 ms after warmup; 582 with new SRV
  descriptors. P99 74.9 ms.
- Target 30 FPS: 885 frames over 50 ms after warmup; 558 with
  new SRV descriptors. P99 86.9 ms.

These were different scenes and are not controlled A/B results.

## Reproducible SDK instrumentation

A versioned patch in patches/rexglue-dx12-resource-timings.patch
adds five columns to ReXGlue REX_PERF_LOG_CSV. The older CSV format
is still supported by scripts/report_frame_spikes.py.

| Counter | Meaning |
|---|---|
| texture_descriptor_create_us | CPU microseconds for successful new SRV descriptors |
| texture_resource_create_us | CPU microseconds for successful D3D12 texture resource creation |
| texture_resident_request_us | CPU microseconds requesting batched guest memory residency |
| texture_upload_dispatch_us | CPU microseconds dispatching texture upload work, not GPU execution |
| texture_upload_requests | Pending texture-data reload requests accumulated per frame |

Only timed when the REX_PERF_LOG_CSV environment variable is
provided and ReXGlue performance counters are enabled. The patch
does not modify cache eviction limits, GPU commands or texture data.
The counters approximate host CPU setup time, not actual GPU time;
failed allocation attempts are not fully measured.

scripts/make_pc.ps1 -FidelityFX applies the patch on a clean pinned
ReXGlue SDK checkout and packages the new rexgpu-xenos.dll. No user
game data or ISO belongs in Git.

## To capture a real drive

In PowerShell, from the project root:

    .\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4 -ExtraArgs @('--mcla_fps=30')

Then close the game normally and generate the report:

    python .\scripts\report_frame_spikes.py "out\profiles\YOUR_RUN\frames.csv" --warmup 40 --slow-ms 50

The CSV remains locked by the Windows process while MCLA runs.
The capture never force-closes an active game; after the interval,
it leaves the game open and provides the command above.

Keep the currently proven 480p FSR Performance mode and Gentle
stall guard as-is while recording. Use the same vehicle, route,
time of day and camera for repeatable comparisons.

## Short smoke test results (title screen only)

The resource-instrumented build passed a 40-second 30 FPS benchmark at
480p + spatial FSR + Gentle stall guard (2026-10-15).
The resulting frame CSV included all five new columns and the report
parser passed. In the 686 frames after a 15-second warmup, nine frames
exceeded 50 ms; none had an SRV descriptor creation event. In those
nine frames, CPU request-residency and upload-dispatch measurements were
under 2 ms combined, even when the frame took 77 ms. This points away
from those measured operations as the primary cause *in that scene*,
not in dense-city gameplay. Raw run data is kept locally at:

    out/benchmarks/20261015-135402-dx12-resource-profiler-check

No improvement in performance can be inferred from this probe alone.

## What to investigate after measuring

- High texture_resource_create_us: host resource allocation / pooling.
- High texture_resident_request_us: shared memory synchronization.
- High texture_upload_dispatch_us: untile, conversion, barriers.
- All low: CPU guest draw translation, thread contention or other
  synchronization; avoid incorrectly blaming the texture cache.

This branch is instrumentation only, with **no claimed FPS gain**,
physics changes, cache policy changes or launcher work.
