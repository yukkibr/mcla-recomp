# Matched CPU DX12, texture stage and camera-identity trace (experiment)
Date: 2026-10-18
Branch: experiment/camera-hitch-dx12-stage-correlation

## Why

The player prefers time_corrected chase-camera smoothing with uncapped FPS.
Latest matched 70s A/B: per_frame had ~40.44 FPS and 2 stable-rig large
published camera jumps, while time_corrected had ~40.51 FPS and zero
such jumps. Occasional small flicks and host frame gaps persist.
Do not infer a sustainable FPS gain from the camera filter change.

The external fork yukkibr/Midnight-Club-L.A-RECOMP has fine GPU/CPU
profiling in modified ReXGlue 0.9.0. Instead of copying its incompatible
SDK profiling code, use the existing probes in our patched 0.10.0:
d3d12_hitch_probe, dx12_texture_stage_probe, mcla_timing_trace,
mcla_hitch_correlation, and camera publish identity.

Historical mcla_022.log: a 161.8ms GPU Commands CPU swap interval had
135.3ms drawing, including 108.8ms of texture requests and zero
measured GPU fence CPU wait. Nested CPU timings must never be added.
This history is NOT direct evidence of the cause of the new small flicks.

## New offline report

scripts/correlate_camera_dx12_hitches.py correlates complete 10s guest
present benchmark windows with timestamped GPU Commands CPU intervals,
texture request stage spikes, 5s texture stage aggregates and camera
identity jumps. It ranks long CPU intervals and labels likely
contributors as temporal associations, NOT causal proof.
Handles historical logs missing benchmark or DX12 probe events.

No SDK source, rendering code, camera logic, guest physics or FPS
limiter has been modified. No full SDK/profile CSV build necessary.

The existing script toggles three diagnostic CVars (default OFF):
    .\scripts\dx12_hitch_trial.ps1 -Mode on
    .\scripts\dx12_hitch_trial.ps1 -Mode status
    .\scripts\dx12_hitch_trial.ps1 -Mode off

With diagnostics ON, drive 2-3 min downtown, note an exact clock time
when the small flick occurs and close MCLA. From the repo root run:
    python .\scripts\correlate_camera_dx12_hitches.py .\out\build\win-amd64-release\logs\mcla_0XX.log --skip-warmup 3 --top 10 --around HH:MM:SS --margin 20

Cross-check:
    python .\scripts\dx12_hitch_report.py <LOG>
    .\scripts\frame_hitch_correlation_report.ps1 -Recent 2 -SkipFirst 3

Then turn the CPU-stage probes OFF. They add measurement overhead
while enabled, so do not use in normal gameplay or infer an FPS
increase from the test.

## Preserved configuration

FPS UNCAPPED mcla_fps=0; time_corrected camera filter; FidelityFX
FSR; Fast Path and Sampler; DX12 128MB pool; 67ms Gentle guard;
VSync OFF; HUD ON; camera identity tracker still ON.

Current config backed up in ignored
out/phase2-backup/pre-camera-hitch-dx12-stage/.
No merge or push; no game data, SDK binaries or save files changed.
Automated smoke should verify probes ON and OFF and clean WM_CLOSE.
