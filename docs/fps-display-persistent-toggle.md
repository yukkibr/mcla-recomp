# Persistent FPS HUD toggle in Display menu (2026-10-16)

Branch: `experiment/fps-display-persistent-toggle`.
Continues from `experiment/texture-request-fast-path` without
changing texture cache logic or merging into main.

## Problem reported

Player could not see FPS during the texture-fast-path A/B test.
`src/settings_menu.cpp` already contained a DISPLAY checkbox
`FPS COUNTER` for `mcla_show_fps`, and
`src/fps_overlay.cpp` already defines and renders the HUD. The
actual ignored `out/build/win-amd64-release/mcla.toml` contained
`mcla_show_fps = true` alongside **four invalid standalone
backslash lines**, left by earlier diagnostic toggle helpers.
These invalid lines could prevent TOML configuration loading.
The previous config is backed up, unmodified, under
`out/phase2-backup/pre-fps-display-persistence/mcla.toml`.

## Corrections

- Removed only the four invalid standalone backslash lines from the
  installed `mcla.toml`. All performance and visual options preserved.
- On a DISPLAY -> FPS COUNTER checkbox change, call existing
  `SaveSettingsIfChanged()` immediately after updating the CVar.
  Previously the save occurred only when leaving a custom submenu
  or clicking QUIT GAME. This also makes the setting persist if
  the player exits without explicitly closing that submenu.
- Kept the checkbox in its existing position after FPS TARGET; no
  duplicate row was introduced. OFF is the source-defined default,
  so ReXGlue may omit `mcla_show_fps = false` when saving its TOML;
  that still restores OFF correctly next startup.
- Added one-time startup log
  `MCLA FPS COUNTER startup preference: true/false`, and one-time
  HUD draw-path confirmation `MCLA FPS COUNTER HUD render path active`.
  No per-frame logging or heavy GPU/CPU timing counters required.

## Verified

- Windows `scripts/build.ps1 -NoCodegen -FidelityFX` EXIT=0.
- OFF startup `out/runs/quit-qa-20261016-215831.log`: startup
  preference false, configured FPS target 0 and 67ms guard,
  CLOSED=True EXIT=0.
- ON startup `out/runs/quit-qa-20261016-215906.log`: startup
  preference true, configured FPS target 0 and 67ms guard,
  CLOSED=True EXIT=0.
- HUD paint path `out/runs/quit-qa-20261016-220033.log`:
  ON loaded AND ImGui HUD OnDraw path confirmed active,
  CLOSED=True EXIT=0.
- The checkbox's save-on-click behaviour is verified by code
  inspection, not by automated in-menu input. Player should toggle
  ON->OFF->ON in the pause menu and confirm preference survives
  restarting the game.

## User's retained setup

`mcla_show_fps=true` in the installed `mcla.toml`. Scissor ON,
fast texture-request path ON, FPS uncapped, native 1280x720,
spatial FSR, Gentle 67ms, texture cache 768/1024MB 90 seconds;
heavy diagnostic probes OFF. No additional tool or external FPS
counter is required. No main-branch merge.
