# Frame hitch vs guest clock/camera correlation (experimental)

Branch: experiment/frame-hitch-correlation (2026-10-17).
Based on experiment/texture-sampled-cpu-cost; do not merge into main
without controlled in-game checks.

## Why

User reports flicking of chase camera and other vehicles/NPCs when
FPS dips, and visual stability when FPS stays above ~45.
The earlier texture fast-path comparison (mcla_033/mcla_034)
measured ~40 FPS in both modes with rare 0.5s gaps. It cannot prove
which subsystem is responsible or which displayed frames flick.
Sparse texture request CPU samples usually cost <2 microseconds;
they do not directly explain rare 500ms guest present gaps.

## Read-only implementation

src/hitch_correlation.{h,cpp} adds a new CVar:
mcla_hitch_correlation = false (default).

This code reuses existing hooks:
- frame_timing.cpp's guest delta r8 before/after 67ms clamp;
- fps_overlay.cpp's actual guest present timestamp (steady clock);
- motion_probe.cpp's camera rig/target and camera publish
  position samples, enabled independently when correlation is on.

It never writes guest memory, alters physics, changes NPC transforms,
interpolates a camera, changes frame pacing, modifies GPU commands,
or creates new texture requests. No heap allocation or lock in
the fast path. It uses relaxed atomics and logs ONE line per
~10 seconds on the presenting thread.

"MCLA hitch correlate" fields:
- present, intervals_above_22ms (one-frame duration >22.222ms:
  approximate instantaneous <45 FPS, not a 10s average);
- gap50 / gap100 and max_gap_ms from guest present requests;
- guest_calls / guest40 / guest67 / clamps from guest timer r8;
- camera_updates / long_camera_gaps (same rig, gap 120ms-1s);
- camera_jumps and target_jumps (>6m between comparable updates
  less than 120ms apart, same rig + owner);
- camera_near_gap / target_near_gap (same-event jumps recorded within
  250ms AFTER an observed present gap >=50ms);
- collision_shifts (>5m compared to collision camera);
- matrix_publishes / publish_jumps (>6m, <120ms);
- rig_deviations (>3m vs rig updated within 50ms);
- publish_near_gap (render-source matrix jump following a gap).

Important limitations:
- These are associations in **host steady-clock time**, not
  synchronization proofs and not measurements of GPU execution.
- A position change is not necessarily a visual glitch, especially
  during collisions, high-speed driving and scene transitions.
- Long elapsed gaps cause camera position comparison to be skipped,
  by design; count those gaps separately.
- Existing camera probe may observe different rigs or no active rig
  (the title-screen smoke test has matrix publications but no
  camera-state updates). No NPC transforms are currently sampled.
- Counts across threads have approximate report boundaries.
- New hook work has a small but nonzero cost while on; it is NOT an
  FPS optimization and should be disabled after the diagnostic run.

## Test & restore

Close the game, then:

    .\scripts\frame_hitch_correlation_trial.ps1 -Mode on
    .\scripts\frame_hitch_correlation_trial.ps1 -Mode status
    # Start game, drive same dense city route 2-3 minutes.
    # Note wall-clock time of an actual flick; Quit Game.
    .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3

Disable it after collecting evidence:

    .\scripts\frame_hitch_correlation_trial.ps1 -Mode off

Only mcla_hitch_correlation changes in mcla.toml. The user's
texture_request_fast_path=true, texture_request_sample_probe=true,
mcla_fps_benchmark=true and mcla_show_fps=true are preserved, as are
DX12, FSR, scissor, resolution, texture budgets and 67ms stall guard.
The pre-change executable and ignored config are preserved under
out/phase2-backup/before-frame-hitch-correlation/.

## Local QA

- Native build: scripts/build.ps1 -NoCodegen -FidelityFX passed.
- On startup: out/runs/quit-qa-20261017-003137.log contained
  10-second summaries, three early present gaps >=100ms and three
  guest clock clamps; matrix publications were recorded.
  Camera-state updates were zero in this title-screen test, which
  is EXPECTED and not verification of city-driving camera detection.
- Closing game via WM_CLOSE: CLOSED=True EXIT=0.
- Override OFF test: out/runs/quit-qa-20261017-003333.log
  also exited 0, with NO hitch correlation lines, even while the
  installed mcla.toml has correlation enabled for the next test.
- User's Fast Path, Sampler, FPS HUD and frametime benchmark remain ON.
- Real driving/visual flick verification still required.

## Follow-up decision

If guest timer clamps and camera/publish discontinuities are
temporally associated with 50-500ms gaps, investigate the actual
stalls (streaming / draw translation / synchronization).
If camera jump events occur without preceding gaps, investigate
camera-state selection, render-source publication and interpolation
separately. In either case, do not silently change game clock,
physics or NPC AI based solely on these counters.
