# Phase 1 baseline results (Windows, 2026-10-15)

This is a baseline *before* further graphics optimization. Do not compare
the targets as though they were the same exact scene.

## Environment

- Project binary compiled from upstream commit `c56e1d123112658ea5732e677b0cb49da2823e58`.
- Fork development tooling committed separately on `dev/phase1-foundation`.
- Intel Xeon E5-2670 v3 2.30 GHz; NVIDIA GeForce RTX 5060 Ti.
- Windows 11; ReXGlue 0.10.0; Windows Direct3D 12; Release x64.
- Captured with `scripts/benchmark_phase1.ps1 -Targets 30,60 -Seconds 75 -TailSeconds 20 -Label phase1-baseline`.
- Each test ran for 75 seconds; measurements below refer to the final
  20 seconds. The intro was set to fast; run logs and frame CSVs were created.

## Measured

| Target | Avg FPS | Median frame | P95 | P99 | Approx 1% low | Frames > 40 ms | Median GPU util | Process CPU / one core |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 30 FPS | 26.13 | 35.92 ms | 51.27 ms | 57.40 ms | 17.42 FPS | 34.61% | 50% | 365.5% |
| 60 FPS | 30.17 | 30.76 ms | 36.62 ms | 85.65 ms | 11.68 FPS | 3.15% | 44% | 326.5% |

- These are direct outputs from the collected per-frame CSV and sampled
  NVIDIA/Windows telemetry, not simulated estimates.
- The game's rendering scene varies over time. Runs at different FPS caps do
  not guarantee the same city camera/view and can differ materially in load.
- CPU percentages here count **one logical core as 100%**; for example, 326%
  represents about 3.26 cores of aggregate CPU work, not total-system CPU usage.
- The 1% low shown is the inverse P99 frametime, not a full low-FPS interval metric.
- GPU utilization below 50% *suggests* a CPU/command-translation/queue or
  synchronization limit, but it is not enough to attribute the bottleneck
  specifically to any one thread without sampling/profiling.
- A higher FPS target does not guarantee that the machine can sustain it.

## Local source files (ignored by Git)

`out/benchmarks/20261015-000351-phase1-baseline/`:

- `metadata.json`: run settings and executable/plugin hashes
- `fps-30-frames.csv`, `fps-60-frames.csv`: per-frame counters
- `fps-30-system.csv`, `fps-60-system.csv`: CPU, RAM, GPU
- `fps-30-game.log`, `fps-60-game.log`: runtime diagnostic messages
- `results.json`, `report.md`: generated results

A short 35-second verification run also passed, but is NOT used as the
baseline because it included too much startup variation.

## Before measuring a performance improvement

1. Repeat each configuration at least three times; compare medians.
2. For accurate gameplay metrics, manually use the same route, car, camera,
   traffic, weather, and game state. Record FPS, frametime, stutters and crashes.
3. Keep GPU driver, display mode, backend and application settings fixed.
4. Profile the GPU commands thread and guest frame submission/fence waits;
   compare GPU actual utilization to process CPU activity.
5. For future upscaler testing, first prove that the **internal 3D rendering
   resolution** changed and that FPS or GPU frame time actually improved.
