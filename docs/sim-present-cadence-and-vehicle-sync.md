# Guest simulation timer / present-command cadence investigation
Date: 2026-10-18
Branch: development
Status: read-only diagnosis, NOT a change to guest simulation or graphics.

## User report and evidence

The user perceived a collision with an NPC car at a position not yet
visually shown, plus persistent small camera flicks. This could be a
simulation/render publication mismatch, but might also be texture
streaming, host GPU scheduling, collision bounds, animation, or video
presentation. This observation alone does NOT locate the cause.

City logs mcla_053.log (texture map 16384) and mcla_054.log
(texture map OFF) show no strong improvement:
- 16384: 0 hash rehashes, 0.04ms peak CPU insertion time; 6680
  new texture creations in 10 completed map telemetry windows;
  38.67 guest presents/s in a 70s segment after warmup.
- OFF: 6 hash rehashes, 0.21ms peak insertion, 6404 new textures
  in 10 completed windows; 37.27 guest presents/s in a 70s segment.
- These scene runs are not deterministically identical and do not
  support claiming an FPS gain.
- Camera matrix jumps (2 each in analyzed reports) and occasional
  guest present gaps still occur in both runs.
- Measured guest timer clipping during 70-80 second selections
  was approximately 646ms (16384) and 617ms (OFF). A single
  very large texture/streaming stall accounts for a large share;
  clipping can alter how simulated time progresses relative to
  wall time, but does not prove a particular NPC collision desync.
- The secondary fixed-step path has its own clipping records and
  overlaps with the primary timer; those two totals MUST NOT
  be added.
- CPU texture map rehash peak 0.21ms is too small to explain the
  observed ~100ms present gaps in those tests.

**Immediate rollback:** Set texture_cache_map_reserve=0 and
texture_cache_map_probe=false in the local mcla.toml. The code
and versioned patch remain available for reference, default OFF.

## Opt-in read-only trace

Adds mcla_sim_present_sync_probe=false in src/frame_timing.cpp.
When ON, timestamps guest timer callbacks, guest fixed-step path
callbacks and guest Present command hook, recording cumulative
sequences and sampling per-present:
- number of present commands with zero or multiple new fixed-step
  hook calls since previous Present;
- number of presents with no new engine timer calls;
- age of most recent fixed-step hook callback at Present time;
- count of ages >=50ms and >=100ms;
- number/amount of 67ms primary timer-clamp events, by 10s windows;
- up to five lag event samples >=80ms per 10s window.

These are CPU/host timestamps, not completion on the display.
The fixed-step **hook** does not reveal physical transform positions.
The trace cannot by itself prove that an NPC's collision transform is
ahead of its rendered model. Next stage, if timing anomalies correlate
with the user-observed collision, identify the true NPC physics and
render transform sources before any rendering interpolation changes.

Uses atomics with relaxed ordering, no GPU stalls, no guest reads
beyond preexisting timer/step hooks, no new memory or texture
invalidation policies, no NPC state writes, no FPS cap. When OFF,
only a Boolean check occurs in the two timer hooks and Present.

Commands with game closed:
   .\scripts\sim_present_sync_trial.ps1 -Mode on
   .\scripts\sim_present_sync_trial.ps1 -Mode off
   .\scripts\sim_present_sync_trial.ps1 -Mode status
After 2-3 min driving:
   .\scripts\sim_present_sync_report.ps1 -Recent 2
   .\scripts\frame_hitch_correlation_report.ps1 -Recent 2 -SkipFirst 3

Record exact clock seconds when NPC collision/hitbox mismatch is
seen and, if possible, video showing the visual car position.
Exclude intro/loading/title results from driving conclusions:
the game can issue thousands of Present requests without stepping
the physics during its splash/legal screens.

## QA

- scripts/build.ps1 -NoCodegen -FidelityFX succeeded.
- ON smoke: out/runs/quit-qa-20261018-231145.log;
  CLOSED=True EXIT=0; trace markers present, includes intro.
  First intro 10-second window had many present calls without
  timer or fixed-step hook, expected for splash screens.
- OFF smoke: out/runs/quit-qa-20261018-231215.log;
  CLOSED=True EXIT=0; ZERO sync-probe logs.
- Retain existing CPU DX12 probes OFF and no changes to FSR,
  timer delta or guest frame clamp. Need actual street driving
  before accepting any physical/render desync conclusion.

Current game user settings: FPS UNCAPPED mcla_fps=0; camera
TIME_CORRECTED, guard 67ms, FSR spatial, VSync OFF, Fast Path,
Sampler, DX12 128MB pool. Sim/present trace ON for one short
user driving test, then disable to remove profiling overhead.
Original EXE/config saved under ignored
out/phase2-backup/pre-sim-present-sync.

Everything committed/pushed directly to development branch.
Main README/code untouched. No topic branch created.
