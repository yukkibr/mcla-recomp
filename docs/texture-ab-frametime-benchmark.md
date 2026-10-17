# Texture fast path A/B: lightweight guest-present benchmark

Branch: `experiment/texture-ab-frametime-benchmark` (continues the
FPS HUD toggle and reversible ReXGlue texture request fast path).
This experiment has **not** been merged into `main`.

## Why

The player's 2026-10-16 run `mcla_028.log` (23:04:45 to 23:41:15)
showed **100,500,000** texture no-op bypasses with fast path ON.
`mcla_029.log` (23:43:06 to 23:44:46) had no fast path activation,
consistent with fast path OFF. The runs have different durations,
and neither had recorded frametime series. Bypass count proves work
was avoided, **not** increased real-world FPS or texture correctness.

## Change

New opt-in CVar `mcla_fps_benchmark=false` in `src/fps_overlay.cpp`.
A 257-bin thread-local frametime histogram reuses the existing guest
present timestamp (steady clock). No heap allocation per frame; no
GPU queries, texture-cache mutation, heavy CSV capture, host OS hooks,
or new rendering overlays. Every ten seconds while enabled, one
structured log line reports:

- `fps`: count of guest present intervals / sum of interval time
- `avg_ms`: mean interval between guest present requests
- `p99_bucket_ms`: 1 ms histogram bucket of 99th percentile
  (256 = 256 ms or worse; see exact `max_ms`)
- `max_ms`: longest interval in the window
- `stalls50`, `stalls100`: counts at least 50 / 100 ms
- `frames` and `seconds`: window sample sizes

**Caveat:** guest-present FPS can be extremely high in title/menus,
so never compare those windows against street-driving FPS. A gap
from pausing, switching windows or loading scenes also counts as a
long frame. Compare the same driving route, graphics settings and
camera conditions. First three 10-second windows are excluded by
the default report to reduce startup warmup bias; do not treat
this as an automated "driving only" detector.

## Test commands (close game before changing the configuration)

    .\scripts\texture_fastpath_trial.ps1 -Mode off -Frametime on
    # drive the same route, exit game
    .\scripts\texture_fastpath_trial.ps1 -Mode on -Frametime on
    # drive the same route, exit game
    .\scripts\texture_fastpath_trial.ps1 -Mode status
    .\scripts\texture_ab_report.ps1 -Recent 6 -SkipFirst 3

`-Frametime keep` (default) leaves the benchmark setting intact,
so the original `-Mode off/on/status` commands still work.
`-Frametime off` turns off new periodic benchmark logs.
`mcla_show_fps` is a separate persistent DISPLAY setting and
remains ON; the in-game FPS HUD stays unaffected.

The report displays each run separately: weighted FPS, highest
window p99 bucket, worst frame, stutter totals and largest
confirmed fast-path bypass count. No automatic claim of
optimization benefit is made from mismatched driving conditions.

## Build and smoke tests

- `scripts/build.ps1 -NoCodegen -FidelityFX` (Clang 20.1.8),
  FidelityFX retained; linked `mcla.exe` successfully.
- Opt-in ON smoke: `out/runs/quit-qa-20261016-235220.log` had
  10-second benchmark lines, texture fast path ON marker,
  normal WM_CLOSE and exit code zero.
- Opt-in OFF smoke: `out/runs/quit-qa-20261016-235402.log` had
  benchmark lines, no fast-path activation marker, normal WM_CLOSE
  and exit code zero. This is a smoke check, not a matched gameplay run.
- The installed settings are restored to `texture_request_fast_path=true`
  with `mcla_fps_benchmark=true` for next route-based comparisons.
- Original executable and user settings backed up in ignored
  `out/phase2-backup/pre-texture-ab-benchmark/`.
- These smoke tests do not measure in-world FPS and do not
  validate absence of flicker/texture corruption.

Keep DX12, native 1280x720, FSR, VSync OFF, scissor cache ON,
67 ms Gentle guard, and texture cache 768/1024 MB/90s for A/B.
Keep heavy timing probes OFF. Do not commit game, extracted XEX,
ISO, SDK-local binaries, user saves or generated runtime logs.
