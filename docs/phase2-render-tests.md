# Phase 2 continuation: guest resolution, city load and clean exit

Branch: `feature/phase2-render-and-quit`. Based on
`feature/fidelityfx-upscaling`. This is experimental Windows Direct3D 12 work.

## Resolution menu (DISPLAY)

The independent settings are:

- **RENDER QUALITY**: NATIVE 720P (1280x720), QUALITY 630P (1120x630),
  BALANCED 540P (960x540), PERFORMANCE 480P (854x480).
- **UPSCALER**: NATIVE/BILINEAR, AMD CAS or AMD FSR1 spatial.
- **DRAW SCALE**: 1X native or experimental 2X supersampling.
- **FSR SOFTENING**: built-in spatial FSR sharpening control.

All resolution and presentation effect changes require a full restart.
For actual performance savings leave DRAW SCALE set to 1X, select a guest
resolution below native, and select FSR1 for better spatial reconstruction
when presenting to a larger window.

The reduction is NOT an artificial image shrink after GPU rendering:
a diagnostic ReXGlue build observed these real allocations on D3D12:

| Video mode | Guest output | First large Xenos render target |
|---|---|---|
| Original 720p | 1280x720 | 1280px wide |
| 540p | 960x540 | 960px wide |
| 480p | 854x480 | 854px wide |
| 360p trial | 640x360 | 640px wide; tested screenshots were black |

360p was excluded from the final UI because the short captures were black;
its behavior in longer gameplay was not established. The
temporary diagnostic probes have been removed from the shipped code.
The original ReXGlue SDK's 480p minimum remains intact, so the fork does
not depend on undocumented lower display modes.

Lower guest resolution *does not mean* every render stage costs less:
EDRAM allocation, draw-call translation, simulation, texture streaming
and post-processing may dominate. The 540p automated title test did
not show a reliable FPS benefit; user gameplay comparisons should
use a repeated route in heavy urban traffic.

For diagnostic command-line testing (not official AMD quality levels):

```powershell
.\out\build\win-amd64-release\mcla.exe --mcla_render_quality=balanced --present_effect=fsr --window_width=1920 --window_height=1080
```

The config `mcla_render_quality` selects the matching Xbox video mode
before the GPU initializes; each mode is saved in the existing `mcla.toml`
when selected in the in-game menu. Explicit custom Xbox video modes can
still be supplied manually when no render preset has been set.

## Dense urban areas (PERFORMANCE)

CITY PRESET combines existing game-engine controls. Selecting one changes
city detail LOD, traffic LOD/distance, pedestrians, parked vehicles,
shadows and foliage shadows. Their default values are preserved until a
preset is selected.

- CUSTOM: preserve manual settings; changing an individual relevant
  option returns to CUSTOM.
- STANDARD: restore as-shipped values.
- BALANCED: LOD 0.75, traffic 325m, pedestrians 50%, parked 50%, shadows
  retained but distant foliage shadows disabled.
- PERFORMANCE: LOD 0.5, traffic 250m, pedestrians 50%, parked 0%, main
  and foliage shadows disabled.
- MINIMUM: LOD 0.5, traffic 250m, pedestrians 0%, parked 0%, main and
  foliage shadows disabled.

These presets change gameplay visuals/population and may require a city
reload or game restart to apply fully. They can help where CPU-side guest
objects and draw submissions dominate but are not guaranteed to raise FPS.

## Exit to desktop

The pause-menu QUIT GAME item previously called
`WindowedAppContext::RequestDeferredQuit`. ReXGlue's SDL context expects
normal window-close events to execute the guest / GPU / audio shutdown
listeners first; bypassing those listeners could hang application teardown.

On Windows, the menu now queues SDL_EVENT_QUIT through SDL_PushEvent,
which routes through SDLWindowedAppContext::ProcessQuitRequest and window
closing callbacks before ending the UI loop. Other platforms retain the
previous path until a platform-specific solution is tested.

Automated QA:
```powershell
.\scripts\test_window_close.ps1 -WarmupSeconds 12 -TimeoutSeconds 25
```

Posting WM_CLOSE to the real game window exited with code 0 on the
developer's machine. It exercises the normal window close lifecycle,
not the in-game click itself. The in-game QUIT GAME button still needs
an interactive manual acceptance test, especially after long races.

## Validated so far

- FidelityFX-enabled Windows CMake/Clang build succeeded.
- Intro and title output visually checked at 720p, 630p, 540p and 480p.
- 360p displayed black and is intentionally not a released mode.
- The in-game render preset infrastructure compiled; `mcla_render_quality=quality`
  selected 1120x630 at startup and displayed the Midnight Club logo.
  The earlier 360p trial opened but produced a black screen, so the final
  Performance preset is restricted to validated 854x480.
- WM_CLOSE lifecycle test exited cleanly with code 0, including the final build.
- A temporary `mcla.toml` containing `mcla_render_quality = "balanced"`
  was loaded on startup and logged the expected 960x540 mode; the user's
  original configuration was restored immediately after testing.
- FSR1 alone is spatial, not FSR4/DLSS. No temporal or frame-generation
  modes were added.

Release gate still pending: run real city/race scenarios for all presets,
verify manual QUIT GAME button, test save/load game and examine 1% low
framerates across repeated routes.
