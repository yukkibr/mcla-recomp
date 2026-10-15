# Phase 2: experimental FidelityFX presentation (Windows D3D12)

This branch adds opt-in AMD FidelityFX support to the pinned ReXGlue SDK and
exposes spatial presentation effects through the existing in-game DISPLAY menu.
The default remains native bilinear: existing users are not forced to enable
FidelityFX. No Xbox 360 game data is checked into the repository.

## Building

Build once from your own extracted game and installed toolchain:

```powershell
.\scripts\make_pc.ps1 -FidelityFX
```

On a clean checkout, add `-Iso PATH_TO_YOUR_OWN_DISC.iso`.
The switch configures ReXGlue v0.10.0 with
`REXGLUE_ENABLE_FIDELITYFX=ON` and `REXGLUE_FIDELITYFX_BACKEND=dx12`.
The pinned third-party FidelityFX SDK comes from ReXGlue's existing FetchContent.
Its vendor `ffx_api_dll.rc` file is UTF-16; the script uses
`scripts/prepare_fidelityfx.py` to convert it into UTF-8 for Clang 20.
The installer copies `amd_fidelityfx_dx12.dll` into the game's build folder.
Mode is persisted under the SDK install prefix; enabling/disabling it causes
the installer to rebuild the SDK instead of silently keeping stale binaries.
The project CMake build flag `MCLA_ENABLE_FIDELITYFX_MENU` follows the same
switch; without it the FSR/CAS controls are omitted from the in-game UI.
If compiling the game manually, use `scripts/build.ps1 -FidelityFX` as well.

Using `make_pc.ps1` without `-FidelityFX` reverts the optional
SDK integration to OFF, so the in-game FSR/CAS menu choices will NOT work
unless this switch was used at build time.

## In-game DISPLAY menu (Windows)

- DRAW SCALE (NEXT START): 1X (original) or experimental 2X. This scales
  the actual Xenos draw targets UP (roughly 720p -> 1440p at 2X); GPU cost
  and VRAM usage may increase. It is not a way to render below 720p.
- UPSCALER (NEXT START): NATIVE (BILINEAR), AMD CAS, AMD FSR 1.
- FSR SOFTENING (NEXT START): 0.0, 0.2 (ReXGlue default), 0.5, 1.0, 2.0.
  Larger values mean less RCAS sharpening.
- These use ReXGlue's existing `present_effect` and
  `present_fsr_sharpness_reduction` CVars. Settings save to `mcla.toml`.
  **Restart the game** after changing the present effect.
- The new rows are excluded from the PS5 menu.

Equivalent command-line usage (D3D12 only):

```powershell
.\out\build\win-amd64-release\mcla.exe --mcla_gpu_backend=d3d12 --present_effect=fsr --window_width=1920 --window_height=1080
```

For A/B comparison, use `--present_effect=bilinear` with the exact
same window width and height. For spatial sharpening only use `cas`.

## Important limits and known issues

1. This is **spatial FSR 1**, not temporal FSR 3.1, FSR 4.1 or DLSS.
   The experimental ReXGlue FSR2/3 code synthesizes depth/motion inputs;
   do not enable it or market it as high-fidelity temporal reconstruction.
2. The game commonly outputs a 1280x720 guest frontbuffer; the spatial effect
   sharpens/upscales the final output when the window/display is larger.
   This change **does not lower the 3D internal render resolution**. It does
   not promise higher FPS (the Phase 1 tests were likely CPU/translation limited).
3. ReXGlue's `resolution_scale` currently accepts integers 1..8 **only for
   increasing draw resolution**, not percentages below 100%. The menu exposes
   1X and experimental 2X; a short startup smoke test at 2X succeeded, but
   full gameplay, HUD/post-processing and race handling remain unverified.
   Do not create a fake Quality/Balanced/Performance menu until a correct
   fractional 3D renderer is available (render targets, viewport/resolve
   coordinates, and post-processing). Temporal FSR2/3 quality modes do not
   mean FSR1 will render the original game at those scales.
4. Test title screen, gameplay, UI/HUD, shadows, bloom, garage and rain.
   For performance compare the same actual in-race route and camera.
5. Windows D3D12 has been targeted here; Vulkan/PS5 FSR runtime parity is
   intentionally not claimed.
6. If FidelityFX fails at launch or looks broken, remove the
   `present_effect` entry from `mcla.toml` or launch with
   `--present_effect=bilinear`. Preserve the stable binaries in
   `out/phase1-backup/stable-build`.

## Benchmarking an A/B pair

```powershell
.\scripts\benchmark_phase1.ps1 -Targets 30 -Seconds 70 -TailSeconds 20 -Label native1080 -ExtraArgs @('--window_width=1920','--window_height=1080','--present_effect=bilinear')
.\scripts\benchmark_phase1.ps1 -Targets 30 -Seconds 70 -TailSeconds 20 -Label fsr1080 -ExtraArgs @('--window_width=1920','--window_height=1080','--present_effect=fsr')
```

Benchmark artifacts and disc data stay ignored by Git. The title camera is
not a deterministic workload; interpret any small FPS difference cautiously.

## First smoke and title-screen benchmark results (2026-10-15)

- D3D12, window 1920x1080, native 1X draw scale; RTX 5060 Ti and Xeon E5-2670 v3.
- Both bilinear and FSR1 launched and remained active; FSR1 also produced
  two screenshots during a 50-second run. No spontaneous exit was observed.
- Target 30 FPS, 55-second runs, final 20 seconds summarized:

| Presenter | Mean FPS | Median frametime | P95 | P99 | Median GPU utilization |
|---|---:|---:|---:|---:|---:|
| Bilinear | 25.79 | 35.44 ms | 54.09 ms | 63.83 ms | 52% |
| FSR1 | 29.78 | 33.19 ms | 36.99 ms | 46.39 ms | 48% |

**These FPS differences are NOT a causal performance improvement result.**
The title camera and frame workload are different across runs; FSR1 does not
reduce native render resolution, and the earlier Phase 1 profile suggests a
CPU/command-translation limit. Repeat controlled gameplay tests before making
any performance claim. Raw data remains only on the local machine under
`out/benchmarks/20261015-002543-phase2-bilinear-1080p` and
`out/benchmarks/20261015-002703-phase2-fsr1-1080p`.
