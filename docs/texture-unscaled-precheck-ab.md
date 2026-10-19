# Experimental unscaled texture cache precheck
Date: 2026-10-18
Branch: experiment/rexglue-unscaled-texture-precheck

## Evidence

User mcla_049.log around 21:59:10 recorded CPU GPU-Commands
intervals of 83.8ms at 21:59:07, 60.8ms at 21:59:14,
75.3ms at 21:59:17, 124.4ms at 21:59:22, 112.8ms at
21:59:25 and 91.6ms at 21:59:29. Texture request CPU
was respectively 43.8, 31.8, 41.7, 94.6, 78.2, 57.4ms.
Fence waits were ~0. A single 35.98ms request at 21:59:21.976
cost 35.93ms in prep, not GPU upload. Between 21:59:02-32
the identity probe saw no >6m render-camera jumps.
The user experienced small flicks in this segment.

This establishes a measurable *CPU texture preparation bottleneck*
but does not establish that lookup normalization is the cause of
the single 35.93ms spike. That spike may be texture creation,
hash-map growth, allocating D3D12 resources or other work.
The optimization below is conservative and will need city A/B.

## What changed

Versioned incremental SDK patch:
patches/rexglue-texture-unscaled-precheck.patch
ReXGlue pinned v0.10.0 source:
src/graphics/pipeline/texture/cache.cpp
Run through scripts/make_pc.ps1 AFTER fastpath / sampled
texture request SDK patches and before DX12 resource pool patch.

New CVar texture_precheck_unscaled_cache=false by default, hot reload.

With opt-in ON AND internal draw resolution scaling disabled:
- perform the same textures_.find(key) before running host
  texture extent checks / oversized fallback;
- immediately return the same existing Texture* on an exact
  cache hit; existing memory-watch invalidation in
  RequestTextures still runs BEFORE FindOrCreateTexture;
- on a cache miss, run the original scaled resolve / dimension
  validation / oversized texture normalization / creation;
- do not repeat the map lookup if no normalization changed the
  key; if host size normalization changed the key, perform the
  exact original lookup on the transformed key.

With internal draw resolution scaling enabled, this CVar has
no effect. The early hit must NEVER skip checking current
guest scaled-resolve pages because the key may have changed
to or from scaled_resolve.

A first checkpoint at 5000 lookups, and then every 250000 lookups,
the GPU Commands thread logs the cumulative exact hit count (no logging per lookup).
No extra caches, asynchronous mutations, guest memory writes,
destruction policy, GPU synchronization, resolution changes,
FPS cap or physics changes.

## Test and rollback

Script (game closed):
   .\scripts\texture_unscaled_precheck_trial.ps1 -Mode on
   .\scripts\texture_unscaled_precheck_trial.ps1 -Mode off
   .\scripts\texture_unscaled_precheck_trial.ps1 -Mode status

The OFF default is the previous code path. No change is made
without opt-in. Original game exe, GPU DLL, config, SDK source
are backed up under ignored
out/phase2-backup/pre-texture-unscaled-precheck/.

A/B/A with same camera, vehicle, city route and approximately
same traffic, 2-3min:
  1. ON, inspect actual hits + missing/white/black/flickering textures.
  2. OFF, restart and same route.
  3. If differences small, ON again on a fresh restart.
  4. Compare equal 10-second guest-present windows after warmup,
     FPS/stalls/p99 and textures correctness. Never infer a
     speedup from intro/menu or different traffic.
  5. If no exact hits, clear overhead and restore OFF.
     If hitches remain, instrument CreateTexture and guest
     memory lookup separately; don't claim this precheck
     removes allocation stalls.

## Local QA (2026-10-18)

- Full pinned ReXGlue v0.10.0 SDK and game built successfully twice
  using scripts/make_pc.ps1 -FidelityFX, including the final
  reduced-frequency checkpoint version. FidelityFX ON, perf CSV OFF.
- Earlier smoke ON: out/runs/quit-qa-20261018-221037.log,
  CLOSED=True EXIT=0. After 2,220,000 exact-key lookups,
  2,219,218 cache hits (99.965%). The earlier diagnostic logged
  too frequently, so it was changed to one checkpoint after 5000
  and once per 250,000 attempts.
- Earlier smoke OFF: out/runs/quit-qa-20261018-221109.log,
  CLOSED=True EXIT=0 and no precheck diagnostic lines.
- Final reduced-frequency smoke ON:
  out/runs/quit-qa-20261018-221405.log, CLOSED=True EXIT=0.
  1,250,000 lookups, 1,249,479 exact-key cache hits (99.958%);
  only SIX checkpoint logs over the ~23s run.
- Final mode left ON for one controlled city drive.
  No historical FPS improvements should be inferred from these
  title/menu smoke checks.
- Existing camera and DX12 heavy diagnostic toggles remain OFF;
  FPS UNCAPPED, camera TIME_CORRECTED, fast path, sampler, FSR,
  128 MB DX12 pool and 67ms guard preserved.

No merge/push without city A/B tests and visual correctness checks.
