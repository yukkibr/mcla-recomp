# Phase 1: fork workflow and Windows performance baseline

This folder contains local-only development tooling for the PC recompiler.
The game's XEX, archives, generated binaries and ISO MUST NEVER be committed,
uploaded as artifacts or included in PRs. See .gitignore.

## Repository workflow

- `origin`: https://github.com/yukkibr/mcla-recomp.git (user fork)
- `upstream`: https://github.com/holdmysocks/mcla-recomp.git (original project)
- Branch: `dev/phase1-foundation` for baseline scripts and docs.
- Stable binary snapshot: `out/phase1-backup/stable-build` (git-ignored).
- Original checkout data and Windows line-ending backups:
  `out/phase1-backup/before-git-setup`.

Recommended workflow:

```powershell
git fetch upstream
git fetch origin
git switch dev/phase1-foundation
git status
# After integrating upstream updates, rerun scripts/make_pc.ps1 and the benchmark.
```

To start a feature: `git switch -c feature/upscaling`.
Do not modify the installed `third_party/rexglue-sdk` as the only copy of a
feature: it is untracked by the parent project. Keep SDK changes as reviewable
patches under `patches/` and add them to the SDK build script.

## Prerequisites

Successful Windows x64 build via `scripts/make_pc.ps1` with its original ISO.
Python 3 for results; PowerShell 5.1 or newer; Windows 10/11; optional
`nvidia-smi` for GPU utilization/memory readings (NVIDIA only).

## Repeatable title/menu benchmark

The script launches the existing compiled executable, reads per-frame
`REX_PERF_LOG_CSV` counters and polls host process CPU/memory every second.
On NVIDIA hosts, it also polls GPU utilization and VRAM use through nvidia-smi.
Each run is stopped after a bounded number of seconds. No game data changes.

```powershell
cd G:\Midnight-Club-LA-Complete-Edition\mcla-recomp
.\scripts\benchmark_phase1.ps1 -Targets 30,60 -Seconds 80 -TailSeconds 20 -Label baseline
```

Use at least 60-80 seconds per target for title-screen steady-state.
The script uses the D3D12 backend and `mcla_intro=fast`, minimizing the
startup sequence and retaining the title logo. Frame pacing is governed by
`mcla_fps`; DO NOT count startup frames in the steady-state comparison.

Run artifacts are written ONLY to `out/benchmarks/<stamp>-<label>/`:

- `metadata.json`: commit/branch, SHA256 binary/plugin, CPU/GPU/driver, mode.
- `fps-30-frames.csv`: ReXGlue per-frame counters (if the SDK patch is active).
- `fps-30-system.csv`: CPU of the game process, GPU/VRAM where supported.
- `fps-30-game.log`: game log for warnings and crashes.
- `results.json` and `report.md`: measured steady-state summary.

Refresh a report (or compare two runs):

```powershell
python .\scripts\benchmark_report.py .\out\benchmarks\YOUR-RUN
python .\scripts\benchmark_report.py .\out\benchmarks\NEW-RUN --compare .\out\benchmarks\OLD-RUN
```

Warnings:
- The title-screen camera changes its view over time. This is a repeatable
  PROCEDURE, but not an identical rendered workload. Use multiple iterations;
  medians and percentile trends matter more than one isolated FPS value.
- Windows and in-game graphics settings, desktop resolution, GPU drivers,
  background software and backend must be held constant.
- `cpu_one_core_pct` is process usage relative to ONE logical core, not
  overall CPU usage. GPU utilization depends on nvidia-smi availability.
- `1% low approx` is 1000/p99(frame time), not a full contiguous 1%-low metric.
- Running an automated title/menu test is not a substitute for an in-race test.

## Manual gameplay benchmark checklist

For release evaluation: same car, camera, time of day, race/course, route,
traffic/ped density, settings, GPU/backend, run duration and FPS cap. Capture
three 3-minute runs with the same `REX_PERF_LOG_CSV` approach, note streaming
stalls and texture misses, and compare p95/p99 frame times and 1% lows.
Do not extrapolate menu FPS to racing physics, crashes or PS5/Vulkan.

## Priorities before Phase 2

1. Ensure baseline measurements do not crash or corrupt saves.
2. Diagnose CPU-side GPU command translation and synchronization versus
   actual host GPU saturation from telemetry.
3. Integrate spatial FidelityFX first. Current SDK build has
   `REXGLUE_ENABLE_FIDELITYFX=OFF`; existing temporal FSR 2/3 code supplies
   placeholder depth/motion inputs, so do not treat it as a validated solution.
4. Only after native render-resolution control and valid motion vectors are
   available should DLSS or newer temporal FSR be considered.
