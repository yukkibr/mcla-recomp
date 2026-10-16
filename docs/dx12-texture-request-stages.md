# Texture request stage probe and selective upstream Clang fix

Experimental branch: `experiment/dx12-texture-hitch-decomposition`.
Based on `experiment/dx12-hitch-probe`; **not merged into main**.

## Evidence from the real gameplay test at 20:32 (2026-10-16)

The user's normal downtown driving log `mcla_022.log` includes
25 GPU-thread swap intervals >=50ms and 18 guest timing summaries.
Notable real driving results:

| Time | GPU Commands swap interval | CPU inside IssueDraw | CPU inside RequestTextures |
|---|---:|---:|---:|
| 20:32:07.990 | 96.9ms | 83.5ms | 65.9ms |
| 20:32:24.523 | 88.0ms | 71.5ms | 46.8ms |
| 20:32:38.797 | 72.1ms | 58.2ms | 40.6ms |
| 20:32:45.084 | **161.8ms** | 135.3ms | **108.8ms** |

At 20:32:49 the guest timer recorded a peak raw step of **159.33ms**
and one Gentle clamp. D3D12 pipeline configuration and submission
fence checks were near zero in these slow intervals. Large draw
counts ranged from about 4,000 to 6,400 in these frames.

The evidence points to CPU texture request handling as a major
measured contributor, **not necessarily VRAM exhaustion** or
an expensive hardware GPU render. Texture request encompasses
texture lookup/creation, guest shared-memory residency, data loading
and binding updates. The outer timer alone cannot distinguish them.

## Detailed, reversible stage timing

Versioned incremental SDK patch:
`patches/rexglue-dx12-texture-stage-probe.patch`.
It modifies the original ReXGlue v0.10.0
`src/graphics/pipeline/texture/cache.cpp` *after* existing SDK patches.

New CVar `dx12_texture_stage_probe=false` by default.
When explicitly enabled, `TextureCache::RequestTextures` measures:

- **prep**: validating texture fetches, looking up / creating textures,
  deciding and preparing pending loads;
- **residency**: collecting shared-memory ranges and requesting them;
- **upload**: scheduling texture data upload / conversion work;
- **binding**: updating texture bindings after uploads.

It logs at most four detailed CPU calls >=3ms per 5s,
plus 5s aggregates including counts of pending texture loads and
resident memory ranges. The older outer `DX12 hitch probe:`
retains overall per-frame GPU Commands thread attribution.

The timers report **CPU wall time**, not actual GPU execution time.
CPU categories are independent portions of RequestTextures but
the outer draw CPU time includes the whole request and must not
be added together. No GPU synchronization, guest clock or camera
state is changed.

Extra per-call timers are only active with the CVar ON; there will
be instrumentation overhead during a diagnostic drive. Turn it off
for normal play.

## Upstream changes audited

`git fetch upstream --tags` showed our previous fork had base
`c56e1d1` and the original project's only two newer commits were:

- `bef1563`: reliable toolchain selection, fixing issue #9 where
  unrelated Clang variants on PATH lack Microsoft CRT headers.
  **Selectively ported** compiler path selection into
  `scripts/env.ps1`, `scripts/make_pc.ps1` and `scripts/build.ps1`,
  preserving FidelityFX/perf build flags.
- `54a5569`: README/docs cleanup deleting 4,500 lines of
  profiling scripts and technical documentation. **Not merged**;
  that cleanup would delete important customized fork features.

No evidence those two upstream commits fix D3D12 texture hitches;
the Clang fix is for reliability of building, not performance.

## Run and rollback

The reversible script sets the optional D3D12 per-frame,
texture request stage, and game guest timing CVars together:

    .\scripts\dx12_hitch_trial.ps1 -Mode on
    .\scripts\dx12_hitch_trial.ps1 -Mode status
    .\scripts\dx12_hitch_trial.ps1 -Mode off

Close MCLA before changing settings. Drive the same downtown route
for a few minutes, note a precise clock time when the flick happens,
and QUIT GAME. Inspect the newest log in
`out/build/win-amd64-release/logs/` for
`Texture request stage spike:`, `Texture request stages:`,
`DX12 hitch probe:`, and `MCLA timing trace:`.

Disable diagnostics after the comparison; **scissor cache stays ON**,
audit OFF, FPS unlocked, native 1280x720 + FSR, cache 768/1024MB,
90s retention and 67ms Gentle guard unchanged.

Old runnable binaries and local config preserved under ignored
`out/phase2-backup/pre-texture-stage-probe/`.

## Automated QA (2026-10-16)

- Full `scripts/make_pc.ps1 -FidelityFX` passed with **FidelityFX
  ON**, expensive **perf counters OFF**, and selected compiler
  `tools/clang+llvm-20.1.8-x86_64-pc-windows-msvc/bin/clang.exe`.
- Enabled startup: `test_window_close.ps1 -WarmupSeconds 28
  -UseConfiguredFps` produced
  `out/runs/quit-qa-20261016-205026.log`.
  Four `Texture request stages:` summaries and four limited
  `Texture request stage spike:` events were present. One
  five-second window during startup included 570.8ms of CPU prep,
  108.2ms of residence requests, and 8.3ms of uploads; this
  corresponds to startup, **not confirmed downtown stutters**.
  `CLOSED=True EXIT=0`.
- Disabled startup: `test_window_close.ps1 -WarmupSeconds 13
  -UseConfiguredFps` produced
  `out/runs/quit-qa-20261016-205056.log`.
  No texture-stage, DX12 hitch or guest timing trace lines.
  `CLOSED=True EXIT=0`.
- The user's ignored configuration was reset to all three
  diagnostics **ON** for one controlled driving test, and
  can be restored with `dx12_hitch_trial.ps1 -Mode off`.
- The original compiler-resolution change `bef1563` was ported
  selectively; upstream's destructive documentation cleanup
  `54a5569` was not merged.

## Release gate

No direct texture reloading optimization yet: first reproduce and
attribute the actual driving stalls at stage granularity, then test
one controlled performance change at a time. Do not merge before
full driving verification. No game/ISO contents, local installed
SDK artifacts or user saves may be committed.
