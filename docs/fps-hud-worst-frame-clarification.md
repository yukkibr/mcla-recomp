# Clarify FPS HUD worst-frame measurement (2026-10-17)

Branch: fix/fps-hud-worst-frame-labels, based on
experiment/guest-fps-burst-camera60-correlation.

## Reason

The player saw quick "max ~90" spikes on the HUD during chase-camera
flicks. The old HUD rendered "FPS 40" and "25ms | max 90ms".
The "max 90" number is **90 milliseconds of worst inter-present
interval** in the previous approximately 0.5 seconds, NOT 90 FPS.
One 90ms guest-present interval corresponds to a momentary rate of
~11.1 present requests/s. A stall can cause visual hitching even
while the overlay still shows ~40 FPS averaged across 0.5 seconds.

A guest-present interval does NOT equal GPU hardware render time.
The UI could not diagnose the actual cause of the long interval.

In mcla_038.log, 16 camera 60-FPS band crossings and 79 host
>90-FPS-equivalent intervals occurred only in the post-warmup window
ending 01:13:57. The following eight 10-second windows had no camera
band crossings and no host >90-FPS-equivalent intervals, but some
had worst frames of 75-90ms with persistent perceived flicks.
This weakens the hypothesis that routine crossings of the
camera's 60-FPS threshold drive ongoing flicks.

## UI-only patch

src/fps_overlay.cpp changes the overlay to:
- FPS (0.5s avg) <value>
- Avg frame <value> ms
- Worst frame <value> ms

Widen the same translucent HUD box to 220x81 so labels fit.
Colors, placement, FPS sampling interval, counters, DX12/FSR,
simulation, physics, textures and settings remain untouched.
The user's mcla_show_fps preference persists.

## Next controlled experiment (optional, no new code needed)

The existing reversible frame-pacing helper supports a 45-FPS
cap and restoration to uncapped:

    .\scripts\frame_pacing_trial.ps1 -Mode 45
    # launch, repeat route, quit
    .\scripts\frame_pacing_trial.ps1 -Mode uncapped
    # launch, same route, quit
    .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3

A frame cap does NOT promise the hardware can maintain that rate
and does not eliminate slow frames from streaming or CPU stalls.
Look at worst-frame time, gap50/gap100 events, and actual visible
flicks, not average FPS alone. Leave uncapped as the user's
preferred default until the A/B has shown a benefit.

## QA

Build via scripts/build.ps1 -NoCodegen -FidelityFX succeeded.
Automated startup/WM_CLOSE smoke test passed: CLOSED=True EXIT=0,
log out/runs/quit-qa-20261017-011812.log. This does not replace
visual in-game verification of the enlarged FPS HUD.
Previous mcla.exe / mcla.toml were backed up into
ignored out/phase2-backup/pre-hud-frametime-labels/.
No merge to main or push to GitHub.
