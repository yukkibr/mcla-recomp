# CPU texture translation / retail OPTIONS integration — October 24, 2026

## User's gameplay result and measured log

Player reported an approximate 2-5 FPS benefit and improved smoothness
from the previous wave, but pronounced localized drops (~50 to 33 / 29 FPS).
Most recent manual city session:
out/build/win-amd64-release/logs/mcla_063.log.

Selected 12 ten-second windows after first two warmup windows:
~39.38 guest presents/s, 36 gaps >=50ms and 7 gaps >=100ms,
with one worst gap of 443ms. The prior differently driven test
mcla_062.log reported 39.83 guest presents/s and 26/4 gaps respectively.
The runs are not controlled A/B, and these counts do NOT demonstrate
a texture bottleneck is the sole cause of looking toward a detailed area.
The last four 10-second windows in mcla_063.log were after the
settings menu opened, dropping to ~21 FPS; they must NOT be interpreted
as free-roam driving FPS.

## Wave 3: avoid resetting ALL fetch bindings on clean frames

New ReXGlue SDK patch, opt-in restart-only:
patches/rexglue-texture-preserve-clean-frames.patch
and script:
    .\scripts\texture_frame_bindings_trial.ps1 -Mode status
    .\scripts\texture_frame_bindings_trial.ps1 -Mode on
    .\scripts\texture_frame_bindings_trial.ps1 -Mode off

Stock TextureCache::BeginFrame executes ResetTextureBindings() on EVERY
frame, even if all texture creations and resident GPU uploads
were successful. In high-draw-count game scenes that forces expensive
reconstruction of guest texture keys, cache lookups and descriptor state.

The new flag texture_preserve_clean_frame_bindings = true skips that
compulsory reset when no texture request failed since prior BeginFrame.
The code records failure on null texture creation, failure to commit
the prepared load, and failure in the residency fallback load.
On failure, NEXT BeginFrame performs original full ResetTextureBindings.
All regular guest fetch-register invalidation, watched memory changes,
cache destruction, BeginFrame error recovery and GPU resource state
transitions remain unchanged.

Built with D3D12 + FidelityFX, and profiling CSV OFF. Smoke tests:
OFF: quit-qa-20261024-113213.log, CLOSED=True EXIT=0.
ON: quit-qa-20261024-113232.log, CLOSED=True EXIT=0,
explicit 'Texture translation: retaining clean bindings across frames'.
DO NOT use the first intro/title benchmark window as city FPS.
Gameplay stability, pop-in, dynamically updated textures, night
materials, garage, mission transitions and long driving A/B MUST
still be tested; this is deliberately a reversible experimental switch.
No change to vehicle physics, clocks, 720p, FSR, uncapped FPS, vsync.

## Retail OPTIONS original menu

The preexisting custom DISPLAY, PERFORMANCE and CONTROLS menus
were formerly all appended under the original pause SettingsMenu.

A Windows ReadProcessMemory inspection of the running original retail
Xbox guest menu registry found:
- SettingsMenu (under PauseMenu)
- PM_GameOptions (under SettingsMenu, with zero children by default)
- PM_GameOptions is the retail entry used to open the game's separate
  OPTIONS screen (Game/Controller/etc.), not a normal editable Settings
  list like our native option-row submenus.

Changed src/settings_menu.cpp to attach DISPLAY/PERFORMANCE states under
the real registered PM_GameOptions state. CONTROLS and QUIT GAME remain
with SettingsMenu. Submenu parent and redirect use the selected menu's
registered parent. The original retail PM_GameOptions state remains
present. If it is unavailable, retain access to custom Settings
submenus rather than constructing an invalid replacement.

IMPORTANT: parent-level reattachment is **only a structural first step**.
The original OPTIONS screen uses a DIFFERENT list rendering/click
dispatcher from the pause Settings list, as detailed in LARecomp.
The generated app compiled, but a synthetic ESC press did NOT focus
the game window and could not exercise the nested OPTIONS screen.
As a result, visibility, activation, left/right and backing out on
the original OPTIONS screen have NOT been validated and may require
a separate native list adapter + click dispatch hook. Do not state
that the native Options UI move is fully complete without gameplay QA.

A separate reversible flag mcla_options_native_submenus (default true)
controls the attempted original OPTIONS location. With the game closed:
    .\scripts\options_menu_location_trial.ps1 -Mode options
    .\scripts\options_menu_location_trial.ps1 -Mode settings
    .\scripts\options_menu_location_trial.ps1 -Mode status
The SETTINGS mode preserves the preexisting, already working display
and performance menu paths if the retail native OPTIONS scene does not
expose the custom child states.

Original source backups:
out/phase2-backup/pre-native-options-move/
out/phase2-backup/before-texture-frame-rebind-trial/

## Safety and repo policy

Baseline safety branch at 1bb25c4:
safety/stable-fps-2026-10-24
Separate baseline SDK/binary snapshot:
out/phase2-backup/safety-stable-fps-20261024/stable-binaries-and-custom-sdk.zip
New experiment only on development, main unchanged.
Never reset nested third_party/rexglue-sdk: 57+ local modifications.

If changes cause stale textures, with MCLA closed:
    .\scripts\texture_frame_bindings_trial.ps1 -Mode off
    .\scripts\texture_watch_trial.ps1 -Mode off
    .\scripts\texture_translation_trial.ps1 -Mode off
This restores previous texture translation code paths without changing
game physics or changing the user quality/resolution preferences.
