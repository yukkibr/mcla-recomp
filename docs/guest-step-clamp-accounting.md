# Guest frame-step clamp accounting — 2026-10-17

Branch: experiment/guest-step-clamp-accounting, based on
experiment/camera-relative-offset-stability. Experimental only;
do not merge to main without manual gameplay regression tests.

## Grounded findings

The user-provided mcla_036.log contained 8 post-warmup 10-second windows,
16 presents >=50ms, 2 >=100ms, 8 guest timer r8 guard clamps,
average ~41.1 requested guest presents/s; camera-to-render relative
offset change averaged 21.2mm (max 349mm; no >0.5m event).

The previous report omitted early transition windows. Inspecting the
full mcla_036.log reveals the ~00:46:25-00:46:35 window had 4 gaps
>=100ms, 8 timer clamps, one >6m rig camera jump and one 17.626m
camera-relative offset change. This can be a legal scene transition,
not proof of recurring vehicle/camera flick. Follow-on city-driving
windows did not reproduce >0.5m relative offset changes, although
frametime stalls and timer clamps continued.

## New read-only counters

The first guest hook (r8, at 0x821BDAB0) already clamps raw guest
delta to mcla_frame_stall_guard_ms. Now record:
  timer_clipped_ms: sum of measured - applied tick durations per
  10-second report window, in milliseconds
  timer_max_clip_ms: largest excess in that window.

The second guest fixed-step hook (f11, at 0x821BDB90) already clamps
the game-memory measured delta to that same guard. Now record:
  fixed_calls, fixed_clamps, fixed_clipped_ms and
  fixed_max_clip_ms, analogously.

IMPORTANT: These two hooks may process overlapping time. Do not add
the two clipped amounts as "lost game time". These measure the
difference between each input and what each individual hook passes
on; they do not measure the final physics accumulator or prove that
the simulation runs behind real time. Launch/loading deltas must be
separated from in-world driving deltas.

No change to r8, f11, update rate, camera position, NPC physics,
renderer, frame limiter, texture requests, FSR, vsync or default
settings. Counters are enabled only while mcla_hitch_correlation=true.

The existing frame_hitch_correlation_report.ps1 now shows excluded
warmup windows explicitly and displays the new per-window and total
time-step clipping, marked "--" for older logs that lack the fields.

## Controlled 67/125 A/B, optional

scripts/frame_guard_ab_trial.ps1 supports reversible guard changes
without recompilation (game MUST be closed):

    .\scripts\frame_guard_ab_trial.ps1 -Mode status
    .\scripts\frame_guard_ab_trial.ps1 -Mode 67
    # drive the same route for 2-3 min; note flicks and quit game
    .\scripts\frame_guard_ab_trial.ps1 -Mode 125
    # same route/settings; note flicks and quit game
    .\scripts\frame_hitch_correlation_report.ps1 -Recent 4 -SkipFirst 3
    .\scripts\frame_guard_ab_trial.ps1 -Mode 67

The 125ms guard allows larger guest simulation steps after stalls,
which may cause more obvious jumps. It is *not* an FPS performance
boost and is never enabled automatically by this experiment.
Observe NPC traffic, physics, camera and lap-time behavior.

The original executable and user settings were backed up under ignored
out/phase2-backup/pre-guest-step-clamp-accounting/ prior to changes.
Game stays on 67ms until user specifically tests 125ms.
Fast Path ON, Sampler ON, FPS HUD ON, FSR ON, DX12, scissor-cache
and fullscreen settings preserved.

## Release gate

- Windows FidelityFX build passes: scripts/build.ps1 -NoCodegen -FidelityFX.
- Title-screen smoke `out/runs/quit-qa-20261017-005312.log` validated
  the new counters with CLOSED=True EXIT=0. The 10-second loading
  window contained 7,784.30ms of r8 clipping (peak 7,484.95ms),
  while the f11 fixed-step path recorded just 0.17ms clipping.
  Subsequent title-screen windows recorded zero clipping in both.
  This shows that the two paths can diverge substantially during
  loading, NOT that 7.78 seconds of active driving simulation was
  lost. Real route-based samples are needed to interpret gameplay.
- The reversible A/B helper successfully switched 67 -> 125 -> 67
  and preserved all user's previous flags. Final installed guard 67ms.
- One user drive with the 67ms guard before any causal claims.
- If the duration withheld is small during an actual flick, favor
  investigating guest draw/physics transform interpolation and
  frame queue scheduling over altering the time guard.
- No copyrighted game assets, SDK-local binaries, saves or generated
  files should be committed.
