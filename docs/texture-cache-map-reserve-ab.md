# DX12 texture-cache hash-map reserve and miss timing (development)
Date: 2026-10-18
Branch: development, commit after smoke verification

## Motivation and previous evidence

The street log mcla_049 (around 21:59:22) measured a GPU
Commands CPU interval of 124.4ms, including 94.6ms of texture
requests. A single request cost 35.98ms, with 35.93ms
attributed to the preparation stage. Completed-resource pool
telemetry showed CreateCommittedResource much faster than
this in another route, so the expensive work could also
include texture object construction or the texture-cache
unordered_map resizing. This is a hypothesis to test,
NOT established causal attribution.

A previous experimental exact-key cache precheck yielded
99.94% exact-hit rate over ~13.25 million lookups, yet
no reproducible FPS improvement; it is currently OFF.
It also reported ~7,928 misses, not necessarily all unique
new cache entries. This suggests hash-map growth is worth
profiling; do not infer the map has exactly 7,928 textures.

## ReXGlue patch

Versioned incremental patch:
patches/rexglue-texture-cache-map-reserve.patch
Applied by scripts/make_pc.ps1 after the existing texture
request precheck SDK patch, to pinned ReXGlue 0.10.0.

Two new CVars, both OFF by default:
- texture_cache_map_reserve (integer 0..32768, requires restart).
  Reserves bucket storage in the existing texture_cache
  unordered_map at object construction. 0 is the original
  behavior. Does NOT allocate additional GPU resources,
  keep extra Texture* objects alive or affect cache eviction.
- texture_cache_map_probe (boolean, hot-reload).
  On a cache miss with successful new texture creation,
  measures CPU time in CreateTexture separately from
  unordered_map::emplace, detects bucket count changes,
  and records create/insert costs. Up to 8 slow/rehash
  events per ~10-second interval, plus one summary.
  A "rehash" is table bucket growth, not a GPU operation.

Neither change bypasses scaled-resolve key normalization,
texture watch callbacks, guest residency, shader/texture
uploads, invalidation or completion fencing. The probe
adds timing overhead when ON; disable after profiling.
Duration inside CreateTexture includes any D3D12 allocation
the function performs; times are CPU wall time, not GPU time.

## Controls and A/B

Game must be closed:
    .\scripts\texture_cache_map_trial.ps1 -Mode off -Probe on
    .\scripts\texture_cache_map_trial.ps1 -Mode 8192 -Probe on
    .\scripts\texture_cache_map_trial.ps1 -Mode 16384 -Probe on
    .\scripts\texture_cache_map_trial.ps1 -Mode status
    .\scripts\texture_cache_map_trial.ps1 -Mode off -Probe off

After a drive:
    .\scripts\texture_cache_map_report.ps1 -Recent 2
    .\scripts\texture_ab_report.ps1 -SkipFirst 3 -MaxWindows 8

Proper city A/B/A needs same saved state/area/car/time/route,
2-3min per mode with completed 10-second benchmark windows.
No speedup should be inferred from title-screen smoke tests.
Watch for missing, white, black, wrong or flickering textures,
though bucket reservation must not alter texture contents.
If no measurable rehash CPU cost or no repeatable FPS benefit,
leave reserve 0 and probe false.

## Local smoke QA (menu/intro only)

Full patched ReXGlue SDK + MCLA compiled successfully with
FidelityFX ON and performance CSV counters OFF. Two Windows
WM_CLOSE trials passed with EXIT=0:

- Reserve 16384 + probe ON: quit-qa-20261018-224312.log.
  1,089 successful texture creations reported in two 10s
  snapshots, zero hash-table rehashes, 0.01ms maximum
  unordered_map insertion, 0.98ms maximum CreateTexture CPU.
- Reserve 0 + probe ON: quit-qa-20261018-224343.log.
  826 creations in one full 10s snapshot, three rehashes,
  0.03ms maximum insertion and 1.01ms peak creation CPU.

These intro results prove that the option and diagnostic work
and the cache does rehash without a reserve. They do **not**
show a costly rehash or a repeatable FPS gain, and they do not
explain the 35.93ms texture-preparation spike observed during
street driving. The reserve is an experimental option only.

## Safety and workflow

Original SDK source, previous game EXE, DX12 DLL and TOML
under ignored out/phase2-backup/pre-texture-cache-map-reserve.
No extra Git branches created. All code changes belong to
development; main is untouched. No game assets/saves included.

Retain mcla_fps=0 (UNCAPPED), camera TIME_CORRECTED,
FidelityFX spatial FSR, Fast Path, sampler, VSync OFF,
DX12 128 MB pool, and 67ms guest step guard.
