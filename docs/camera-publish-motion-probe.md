# Camera matrix publication diagnostic (experimental)

Branch: `experiment/camera-publish-motion-probe`. Based on the earlier
read-only `experiment/camera-target-motion-probe`.

## Observed in the player's test

The user's actual 2026-10-16 00:47:18–00:48:59 gameplay session
(`out/build/win-amd64-release/logs/mcla_019.log`) generated 13
five-second camera-state summaries:

- No >6m jumps for the same camera rig/owner after initial transition.
- During driving, max consecutive camera state steps: **3.58m**;
  target follow steps: **3.58m**.
- No active camera collision corrections >5m in the probe.
- One **17.63m** camera step at 00:47:44, when loading/entering a
  new scene while target had not moved; not directly attributable
  to the user's in-city flick.
- Previous 45 FPS pacing and disabling scissor both failed to remove
  flick. FPS restored uncapped; scissor retained.

This **does not prove** all simulated positions or render positions
are stable. It only monitors the camera rig at one update stage, and
the 6m jump threshold misses smaller relative motion discontinuities.
The user's visible flick was not timestamped or screen-captured.

## Additional, read-only hook

`config/motion_probe.toml` adds `mcla_camera_motion_publish`
at 0x8220AA88, directly following `mr r30,r4` in the game's
`sub_8220AA68`. This point was separately reverse-engineered in
LARecomp's `camera_look.cpp`.

It reads the **input camera matrix** before the cine director
adds game-specific shake, blend and post-processing. It is
**not a read-back of the final GPU framebuffer**.

When `mcla_motion_probe=true`, it samples the source position
and compares successive published inputs. It also records the
difference from the latest camera-state position, only when the
state was updated within the previous 50ms.

Log lines:
- `MCLA motion probe:` - original rig/target movement summary
- `MCLA camera publish probe:` - additional per-5s input matrix summary
- `MCLA camera publish event:` - first four suspicious events per 5s

The comparator uses *heuristic* thresholds: >6m successive publish
motion and >3m source mismatch to a recent camera rig. Cinematics,
camera modes, speed and collision may cause legitimate differences,
so a log alone is not a defect report.

## Test and rollback

The diagnostic is read-only and defaults off in new installations.
In the user's working build it is enabled until one further drive:

    .\scripts\motion_probe_trial.ps1 -Mode status
    .\scripts\motion_probe_trial.ps1 -Mode on
    .\scripts\motion_probe_trial.ps1 -Mode off

Only the `mcla_motion_probe` setting changes. The existing FSR1,
Native 720p, 768/1024MB texture retention, 90s lifetime, Gentle 67ms
frame guard, scissor cache, FPS HUD and `mcla_fps=0` stay untouched.

For the next drive, note the wall-clock time (as close as possible)
to a camera/car flick, then quit normally. Read the two corresponding
5-second summaries from the newest `mcla_*.log`, and any event lines.

- Simulation camera stable, input matrix irregular: inspect camera
  selection/publish.
- Both stable, on-screen jump: inspect later cine director blending,
  D3D12 draw/uniform publication, GPU frame/present timing.
- Both jump in step with target: inspect vehicle transform/simulation.
- Both stable with no obvious logs: probe may be observing a different
  rig or missing smaller/faster jumps.

## Build and title-screen QA (2026-10-16)

- Full `scripts/build.ps1 -FidelityFX` codegen and build passed.
- The new `sub_8220AA68` hook reported 311 then 188 published matrices
  during the title-screen validation, with 0 detected source jumps
  and 0 deviations to a recently updated rig. This does **not**
  establish behaviour in live street driving.
- `test_window_close.ps1 -UseConfiguredFps -WarmupSeconds 29`
  passed: `CLOSED=True EXIT=0`.
- The user's local ignored `mcla.toml` remains set to
  `mcla_fps=0`, `mcla_motion_probe=true`,
  `d3d12_scissor_cache=true` and `d3d12_scissor_cache_audit=false`.

Do not change physics or merge to main until real driving evidence
isolates the fault. No generated XEX/recomp code or copyrighted
assets are committed.
