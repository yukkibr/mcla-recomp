# Texture cache retention trial for high-speed city streaming

Branch: `experiment/texture-cache-retention`, built on
`experiment/rex-fast-runtime`.

## Observed behavior

After using the 854x480 Performance preset, spatial FSR, the Gentle
frame-stall guard, and switching off *both* motion blur and fullscreen
blur, driving at high speed can still cause strong temporary hitches.
The cars appear smoother but the main frame stalls persist. That
points away from motion blur as the primary bottleneck; fast movement
also streams more city objects and texture resources per second.

Previous instrumented dense-city runs proved that some of the worst
CPU stalls were spent in D3D12 `CreateCommittedResource`. They did
not prove whether these were first-time allocations or unnecessary
re-creations due to cache eviction.

## Experiment: keep completed textures for longer

The existing SDK texture cache has these CVar defaults, applied to
the texture cache's host memory budget:

| CVar | Original | Trial |
|---|---:|---:|
| `texture_cache_memory_limit_soft` | 384 MB | 768 MB |
| `texture_cache_memory_limit_hard` | 768 MB | 1024 MB |
| `texture_cache_memory_limit_soft_lifetime` | 30 seconds | 90 seconds |

No change is made to shader code, FSR, render resolution, frame timing,
motion blur, GPU memory allocator, resource-pool experiment, or QUIT GAME.
The optional prior D3D12 resource pool remains OFF (0 MB).
The user's RTX 5060 Ti has 8151 MiB of dedicated VRAM, so the trial
is deliberately moderate. The higher budget can still increase VRAM
use, and the application may allocate other resources not governed
by this cache. Abort if textures corrupt, memory usage approaches
the physical limit, crashes occur, or the performance is worse.

## Switching modes

Close the game before changing modes. In PowerShell:

```powershell
cd G:\Midnight-Club-LA-Complete-Edition\mcla-recomp
.\scripts\texture_cache_trial.ps1 -Mode status
.\scripts\texture_cache_trial.ps1 -Mode retention
```

To restore all three original cache values without touching any other
game setting:

```powershell
.\scripts\texture_cache_trial.ps1 -Mode original
```

A one-time safety copy of the untouched original `mcla.toml` is kept
locally at
`out/phase2-backup/texture-cache-retention/original-mcla.toml`.
The script removes duplicate entries for the three cache variables,
does not overwrite other settings, and requires a game restart.

## Practical A/B test

Use the same car, route, camera angle and time of day. Prefer a route
where a fast pass reliably stalls, and drive through it at a similar
speed at least twice, noting:

1. First traversal after launching the game (cold resources).
2. Second traversal of the same streets without closing the game
   (warm cache).
3. Whether severe hitches improve or worsen on the second pass.
4. Whether dedicated GPU memory increases significantly.

If cold traversal stutters but warm traversal improves, the problem
may be first-time streaming/resource creation; a larger retention
budget can only help re-visits and will not fix cold allocations.
If both are equally bad, avoid assuming cache pressure is the issue.

A fully reliable FPS benchmark needs frametime capture with the same
scene and equal instrumentation. The Fast Runtime intentionally has
the ReXGlue CSV counters compiled out. There is **no claimed FPS gain**
from this config-only experiment.

The previous smoke startup and normal WM_CLOSE test passed with the
new cache settings. The game remains installed in the usual location,
with 854x480, FSR, Gentle, QUIT GAME and the blur choices unchanged.
