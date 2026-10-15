# QUIT GAME and CPU/frame-spike investigation — 2026-10-15

Development branch: `fix/quit-and-frame-spikes`, based on
`feature/phase2-render-and-quit`.

## Exit button: second correction

The earlier custom pause-menu QUIT GAME button invoked
`WindowedAppContext::RequestDeferredQuit()`. This could bypass ReXGlue's
normal window OnClosing event and hang the game during teardown.

The first attempt sent a synthetic SDL_EVENT_QUIT, but the user confirmed
the game still continued running after selecting QUIT GAME.

The second correction uses two measures:

1. Handle QUIT GAME **before** the active-submenu branch of
   `mcla_menu_click`. The old code consumed every click when a submenu state
   was active, potentially swallowing the quit action.
2. On Windows, locate the current process's actual SDL game window by PID
   and window title; post `WM_CLOSE` to it instead of faking SDL_EVENT_QUIT.
   This is the same normal close path that succeeded in
   `scripts/test_window_close.ps1`, including the guest / GPU / audio
   OnClosing callbacks. It never forcefully terminates the process.

The game still needs a **manual in-game button test**. To capture the
specific click and its result use `scripts/profile_gameplay.ps1`, open
Settings, click QUIT GAME, and inspect `out/profiles/<timestamp>/game.log`
for messages `QUIT GAME clicked` and `posted WM_CLOSE`.
If those messages are absent, the original click-to-menu-state lookup is
still failing and needs guest menu dispatch tracing, not another SDL change.

## Performance: what is actually known

The Phase 1 run on this machine's Intel Xeon E5-2670 v3 (24 logical CPUs) and
RTX 5060 Ti had **12 frames above 50 ms after warmup** on the 60-FPS target;
**9 of 12** had one or more texture cache misses. The worst frame reached
about 405 ms and recorded 654 texture cache misses. These are correlations.
A subsequent real local 4-worker title test captured 80 frames above 50ms
(after ignoring startup) and 65/80 had texture misses. The worst frame took
1.09 seconds with 1,086 texture misses. This was still a title/menu camera
session, not a controlled heavy-city race. 4 workers is *not* yet validated
as a performance improvement.

This matches prior recorded gameplay observations where texture misses
coincided with many slow frames. Enlarging the cache in an older run did NOT
reduce misses, so indiscriminately raising memory limits is not justified.
Some misses may reflect *first-time open-world streaming*, not eviction.
A 2-GB cache is not a proven fix and unnecessarily raises VRAM usage.

The ReXGlue D3D12 default
`d3d12_pipeline_creation_threads=-1` starts about 3/4 of logical CPUs,
so **18 workers** on this 24-thread machine. New menu:
`PERFORMANCE -> DX12 PIPELINE WORKERS (NEXT START)`: AUTO, 2, 4, 8.

This is a **tunable test knob** rather than a claimed performance
optimization. Fewer workers can lessen bursts of competing CPU work on cold
shader compilation, but can also delay shader/pipeline readiness.
Auto remains the default for compatibility and Vulkan is unaffected.

## Recording a real drive

Close any already-running MCLA process before starting the capture.

```powershell
cd G:\Midnight-Club-LA-Complete-Edition\mcla-recomp
.\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers auto
# Repeat the SAME route / car / conditions in another session:
.\scripts\profile_gameplay.ps1 -CaptureSeconds 300 -PipelineWorkers 4
```

The script automatically writes:
- `out/profiles/<timestamp>/frames.csv`: ReXGlue per-frame counters
- `game.log`: game log, including quit-button diagnostics if activated
- `host.csv`: per-second CPU/process RAM/thread samples
- `frames-spikes.md`: generated after the game closes; p50/p95/p99
  and top spikes, texture and pipeline miss counters

Optional `-GpuSamples` polls nvidia-smi every 4 seconds and can add
sampling overhead; leave off for performance comparisons.
The capture does not change game assets or settings. When the time ends,
the game remains running unless it already closed; quit through the game
or use Alt+F4 to close without an unsafe forced kill. Windows locks the
per-frame CSV while the game is running. If you reach the capture time
before exiting, the script prints the precise report command; run it
after closing the game. The tool never closes the game forcibly.

A/B comparisons must use equivalent scenes. Title-screen runs have moving
cameras and are NOT sufficient to claim a speed improvement. Separate
cold-shader first drives from warm repeated drives. Review the raw logs
before deciding whether to patch texture upload synchronization, pipeline
compilation, or guest GPU command translation.

## Launcher and disc import

The optional launcher / first-run disc extraction workflow is intentionally
not part of this change set. Shipping user-supplied disc extraction tooling
without distributing copyrighted game content needs a separate design and
review; no ISO, assets, extracted XEX, saves or compiled game data are pushed.
