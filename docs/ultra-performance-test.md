# ULTRA PERFORMANCE — opt-in benchmark preset

Use only with MCLA closed. This profile is a gameplay/performance experiment,
not proof of higher FPS. It changes visual fidelity and traffic density.

```powershell
.\scripts\ultra_performance_profile.ps1 -Mode on
.\scripts\ultra_performance_profile.ps1 -Mode status
.\scripts\ultra_performance_profile.ps1 -Mode restore
```

The ON command creates an exact config snapshot only on the first run:
`out/phase2-backup/pre-ultra-performance-profile/mcla.toml`.
RESTORE copies that snapshot byte for byte; the backup is deliberately kept
so it cannot be accidentally overwritten by a second ON.

- GPU: DirectX 12, uncapped, VSync OFF, 480p native game rendering with
  FidelityFX spatial FSR presentation, 1x draw resolution.
- CPU: guest data-cache flush fence experimental hook ON, single-tile
  rendering and GPU wait yield ON; d3d12 pipeline workers 8.
- Graphics: MSAA/shadows/race shadows/motion blur/DOF/full-screen blur OFF;
  city/traffic LOD 0.5, no pedestrian and parked vehicle density, moving
  traffic removal threshold unchanged at 250m.
- Resource work: ReXGlue fast texture request bypass and D3D12 scissor cache ON,
  existing DX12 texture reuse pool 128 MiB maintained; texture cache MAX SAFE
  (clamped by Windows DXGI on startup). Never allocates the requested
  cache size in advance. FPS counter/10s benchmark ON.
- Rejected or non-beneficial experiments (unscaled texture precheck, map reserve)
  stay OFF. CPU-intensive diagnostics and probes remain OFF.
- Maintains 67ms guest timer guard and TIME_CORRECTED camera to avoid
  changing physics/timer behavior.
- Pressing restore requires the game to be fully closed.
- The active user mcla.toml is ignored by Git and not included in commits.

## Smoke test 2026-10-24

`out/runs/quit-qa-20261024-101701.log`:
- `CLOSED=True EXIT=0`
- `MCLA guest render mode: performance (854x480)`
- `MCLA VRAM effective ReXGlue texture limits: soft=4006 hard=5342 MiB`
- DX12 texture resource reuse pool 128 MiB
- Scissor cache 98.6% hits after 2 million lookups
- Texture fast path bypassed 1 million no-op calls
- FPS HUD preference true

Numbers from title-screen smoke test are NOT representative of city FPS.
For a gameplay test use the same vehicle, route, camera and time spent
driving; report sustained FPS, 1% lows, stalls, texture pop-in and crashes.
The guest FPS overlay counts Present requests, not completed GPU displays.

No additional feature toggles or new branches needed. `main` unchanged.
