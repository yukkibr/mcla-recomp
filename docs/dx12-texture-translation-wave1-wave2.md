# DX12 Texture Translation — CPU optimization experiments

Date: October 24, 2026. Branch: development.

## Safety checkpoint
Stable branch: safety/stable-fps-2026-10-24 at
1bb25c4908825b1e36c283e3fa631682e7975624.
Additional local snapshot (binary, config, 57 modified SDK files,
4 untracked SDK files and all RexGlue patch files):
out/phase2-backup/safety-stable-fps-20261024/stable-binaries-and-custom-sdk.zip
SHA256 034d7fcda2c9acffa17bfe3768f8ca20addd6fc6a87b028c3f5b19b888d5d433.
Do not hard-reset the nested third_party/rexglue-sdk. The safety branch
alone does NOT undo its uncommitted SDK changes.

## What the existing ReXGlue path really does
The D3D12TextureCache LoadTextureDataFromResidentMemoryImpl builds texture
layouts, descriptors and resource transitions on the host CPU, then uses
DirectX 12 compute shaders for tiled/block texture conversions on GPU.
The old profiler's category "texture requests CPU" does not prove
that the CPU itself decodes each pixel or that GPU/hardware is irrelevant.

Example older mcla_049.log: 94.6ms texture request CPU was INCLUDED in
a 124.4ms GPU-thread frame interval, not additional time.
Many hundreds of thousands of calls every 5 seconds did no real work.

Higher texture cache budgets are NOT VRAM allocations or guarantees
of higher FPS. The 5.3GB DXGI-based maximum is an allowed cache ceiling.
Low live VRAM usage may simply reflect the smaller original game assets.

## Wave 1: synchronous fast texture request and 3D fetch mask
Versioned reproducible patch:
patches/rexglue-texture-translation-fastpaths.patch

- texture_request_quick_sync (restart-only, default false).
  Performs an early return before sampling, temporary vector setup,
  timers or binding resolution IF every requested fetch binding is
  synchronized and NO guest watched memory invalidation is pending.
  All actual format work, memory invalidations, and diagnostics
  fall back to the original code. Requires existing Fast Path on.
- d3d12_texture_3d_binding_mask (restart-only, default false).
  Tracks which current fetch indices genuinely refer to 3D textures,
  updating on descriptor changes. Only those slots get scanned for
  3D-as-2D wrappers. Normal per-draw resident texture transitions,
  LRU tracking, compute conversions and GPU command submission
  remain intact.

A/B control with game fully closed:
    .\scripts\texture_translation_trial.ps1 -Mode on
    .\scripts\texture_translation_trial.ps1 -Mode off
    .\scripts\texture_translation_trial.ps1 -Mode status
    .\scripts\texture_translation_trial.ps1 -Mode on -Part sync
    .\scripts\texture_translation_trial.ps1 -Mode on -Part 3d

Rebuilt SDK and game with FidelityFX ON and perf CSV OFF.
Title/intro automated QA both OFF and ON passed EXIT=0:
quit-qa-20261024-110009.log and quit-qa-20261024-110028.log.
The ON log explicitly confirmed both new switches loaded.

## Wave 2: selective memory-watch binding invalidation
Versioned reproducible patch:
patches/rexglue-texture-selective-watch-invalidation.patch

- texture_watch_selective_invalidation (restart-only, default false).
  When a guest memory watch has invalidated a texture, the original
  code performs a GLOBAL ResetTextureBindings over every fetch slot.
  New opt-in mode refreshes only bindings whose unsigned or signed
  host texture's outdated-mask is set. Missing resource pointers
  are retried to preserve the original failure recovery.
- All other full reset sites, including explicit cache eviction and
  BeginFrame, remain authoritative and untouched.
- Falls back to complete reset when render resolution is scaled,
  because scaled-resolve keys have additional dependencies.
- texture_watch_selective_stats (default false) logs the count of
  inspected/refreshed bindings once per 512 invalidation events.

Automated OFF/ON smoke tests passed (CLOSED=True, EXIT=0):
quit-qa-20261024-110840.log (OFF) and
quit-qa-20261024-110857.log (ON, debug stats enabled).
The ON run confirmed all three texture paths initialized.
It also reported thousands of watch events but ZERO valid bindings
inspected in the title/intro phase. This specifically means that
these smoke tests DID NOT exercise the targeted selective refresh
of a dirty, actively bound street texture.

This higher-risk change needs long gameplay visual QA for stale
textures, garage/mission streaming and loading transitions; the
title-screen smoke test alone is insufficient.
To compare:
    .\scripts\texture_watch_trial.ps1 -Mode on
    .\scripts\texture_watch_trial.ps1 -Mode off
    .\scripts\texture_watch_trial.ps1 -Mode status
    .\scripts\texture_watch_trial.ps1 -Mode on -Stats on

Suggested A/B in the same car, route and camera, after warmup:
  A: wave1 OFF, wave2 OFF
  B: wave1 ON, wave2 OFF
  C: wave1 ON, wave2 ON
  B: wave1 ON, wave2 OFF
2-3 minutes each. Compare FPS, frame time percentiles and hitch
frequency. No gain is considered proven without comparable CITY runs.

## Rust engine and modding ideas
Rusty MCLA is a fresh Rust engine that reads extracted Rockstar
game assets; it does not mechanically decompile XEX to Rust.
Our current ReXGlue system already recompiles PowerPC game code
into native C++ ahead of time. XEX and archives are source data,
not PowerPC code interpreted every frame.

A new engine is possible but requires reimplementing the entire
gameplay stack, physics, AI, traffic, missions, RAGE file formats,
audio and renderer: a years-scale independent project rather
than a texture speed fix.

DLC/car mods do not require a new engine. The host code can
intercept RAGE resource lookup, layer a mods directory over
the game's archive read paths, and maintain a vehicle registry,
format-safe validation, versioned manifests and optional plugins.
LARecomp already advertises a mod loader. Rusty MCLA currently
describes car mods as postponed. Review licenses before reuse.

Sources:
https://github.com/holdmysocks/rusty-mcla
https://github.com/mzzvxm/LARecomp
https://github.com/holdmysocks/mcla-recomp
