# Adaptive guest timer frame pacing (experimental)
Date: 2026-10-17
Branch: experiment/adaptive-guest-frame-pacing

## Goal / test evidence

User visually confirmed fewer camera/vehicle flicks with the existing
45 FPS cap. A matched A/B of mcla_039.log (45 cap) and mcla_040.log
(uncapped), each with first 3 windows skipped and 7 compared:
- 45 cap: 38.74 average guest presents/s, 11 gaps >=50ms,
  2 gaps >=100ms, worst 520.2ms.
- Uncapped: 40.09 guest presents/s, 13 gaps >=50ms,
  3 gaps >=100ms, worst 498.9ms.
After omitting one more loading/transition window and comparing 6
windows, the 45 cap had 38.67 FPS / 9 gaps >=50ms / max 96.7ms,
versus uncapped 39.02 FPS / 10 gaps >=50ms / max 108.1ms.
Not a controlled deterministic playback; small differences
are not proof of an FPS improvement. The visual report is meaningful
but subjective.

These data favor testing pacing, not rewriting camera/vehicle physics.

## Implementation

New STRING CVar: mcla_frame_pacing_mode, allowed values:
- off: default, exact previous uncapped behavior when mcla_fps=0.
- adaptive: only when mcla_fps=0; estimate sustainable *guest timer*
  throughput using an approximately 2-second histogram of intervals
  between calls minus time deliberately held by this pacer. Take the
  75th percentile; add ~8% slack; choose a ceiling 45-90 FPS.
  Increase the ceiling by no more than 6 FPS per 2-second window or
  decrease by at most 10 FPS. Ignore invalid or >95ms sample
  intervals so title loading and large stalls do not distort the
  sustainable rate estimate. Never allocate in the hot loop.
- steady45: only when mcla_fps=0; same 45 FPS timer pacing as the
  explicit mcla_fps=45 baseline, but without changing the FPS
  TARGET menu.

Explicit positive mcla_fps targets always override the new mode.
Original timing (mcla_fps=-1) is unchanged. Both new modes use the
EXISTING first guest timer owner thread. A missed deadline is never
repaid by executing bursts of catch-up frames. The game already
latches the timer measurement before waiting; this remains unchanged
and frame time is picked up by its next measurement.

Every 10 seconds while a new mode is active, logs:
"MCLA guest frame pacer: mode=... target=... fps waited_ms=...
late_calls=... over_10s". This is guest timer pacing only and
NOT a direct GPU/physical display frametime meter. The existing
benchmark remains the comparator of guest-present intervals.

No alteration to guest physics, camera filters, traffic AI,
rendering commands, DX12 scissor, texture residency, FSR, VSync,
guest frame stall guard, FPS HUD or saved FPS TARGET preference.

## User interface

PERFORMANCE -> FRAME PACING with OFF (UNCAPPED), ADAPTIVE and STEADY 45.
To preserve the guest UI's hard 16-row limit, only the existing
SHADOWS toggle moved from PERFORMANCE to DISPLAY. SHADOWS behavior,
value and persistence remain unchanged; no features were deleted.
The FRAME PACING CVar persists using existing settings-save logic.

The player can switch modes in-game; code reads the CVar on guest
timer invocations and safely resets its scheduling state when the
mode changes. This can cause one transient timing discontinuity.
Compare separate cold-start sessions for reliable results.

Optional CLI/PowerShell toggle with the game closed:

    .\scripts\adaptive_frame_pacing_trial.ps1 -Mode off
    .\scripts\adaptive_frame_pacing_trial.ps1 -Mode adaptive
    .\scripts\adaptive_frame_pacing_trial.ps1 -Mode steady45
    .\scripts\adaptive_frame_pacing_trial.ps1 -Mode status

User's original mcla_fps=0 continues unchanged. The default CVar is
off for general users. The local ignored mcla.toml may be set to
adaptive deliberately for the user's next test.

## Validation and limitations

Compile: .\scripts\build.ps1 -NoCodegen -FidelityFX, preserving
existing DX12, FSR, HUD and other settings.

Smoke (2026-10-17), using test_window_close.ps1 -UseConfiguredFps:
- ADAPTIVE: 38s run; CLOSED=True EXIT=0;
  out/runs/quit-qa-20261017-013953.log. The real guest timer reported
  mode=adaptive, target=45, and two stable title/menu 10-second
  windows had 39.20/39.64 guest present FPS, no >=50ms stalls.
- STEADY45: 24s run; CLOSED=True EXIT=0;
  out/runs/quit-qa-20261017-014112.log. Mode=steady45,
  observed 45.00 guest present FPS in its stable 10s window.
- OFF: 19s run; CLOSED=True EXIT=0;
  out/runs/quit-qa-20261017-014137.log. No new pacer mode
  marker and effective guest FPS target remained 0.
- The local test helper switched between these modes and restored
  adaptive for the user's driving A/B; mcla_fps=0 and Gentle 67ms
  remain unchanged.
- Static menu count: DISPLAY 12 rows; PERFORMANCE 16 rows,
  within the guest menu's supported fixed row array size of 16.

These are title/menu-only automated tests, NOT validation that
city-driving stability improved. The PERFORMANCE menu selection
still requires visual in-game verification.

- If expensive frames take 30ms, a 45 FPS target CANNOT make them
  complete in 22ms; no pacer can remove streaming/CPU/GPU stalls.
- The estimator is based on the guest timer, not GPU timestamps.
- This experiment has CPU sleeping/spinning overhead similar to the
  existing fixed cap when it has spare headroom.
- Adaptive may still sacrifice peak frames above its ceiling 45-90,
  so the UI calls it an optional pacing mode, not "unlimited FPS".
- Do not merge into main before matched route/visual A/B tests.
- No game data, third-party SDK files, logs or user config are
  included in commits. Backups under ignored
  out/phase2-backup/pre-adaptive-frame-pacing/.
