# Collision versus visual vehicle position: 23:20 test
Date: 2026-10-18
Branch: development

## User observation
Around 23:20 (seconds unknown), the user collided with an
ambient vehicle where its visible model did not yet appear
positioned. Small camera flicks persist. No incident video
or individual NPC physics/render transforms were captured,
so a physics-vs-graphics mismatch is NOT yet proven.

mcla_055.log is the matching run, ended 23:20:35.
Configuration: FPS UNCAPPED, spatial FSR, TIME_CORRECTED
chase camera, 67ms guard, reduced city/traffic profile.

## Timestamp-based findings
Completed windows ended at 23:20:02, 23:20:12, 23:20:22
and had 347, 388, 371 Present requests respectively.
Each had zero reports of no new fixed-step hooks, zero
of multiple fixed steps, and zero without a new timer hook.
The last fixed-step callback was on average ~9-10ms earlier,
with maxima of ~14-20ms. Thus guest Present is not simply
outrunning the monitored simulation timer callbacks here.

Completed windows ending at 23:20:12, 23:20:22, 23:20:32:
- FPS: 38.78, 37.03, 32.94 guest presents/second.
- Peak gaps: 96.9, 106.6, 90.2ms.
- Time suppressed by the 67ms timer guard: 37.44, 39.53,
  23.34ms in those windows (never sum with secondary hook).
- Large published-camera matrix jumps: 0, then 2, then 2;
  chase rig position didn't show equivalent >6m movements.

Four matrix jumps between approximately 23:20:12-32 could
be relevant; the identity/owner probe was OFF and exact user
collision seconds are unavailable. Not proof of an NPC
collision desync, not proof of jitter causality.

The timer guard can briefly slow simulated time compared
with host after long streaming hitches. Avoid changes to
physics/guards until actual physical and visual positions
have been compared. The guest hook does not measure GPU
display completion, NPC transforms, or physics hitboxes.

Turn off sim/present sync trace after this session:
    .\scripts\sim_present_sync_trial.ps1 -Mode off
Texture map reserve and its probe are also OFF (no visible
difference, and map rehash CPU cost <0.21ms in city run).

## New traffic *visual LOD only* A/B experiment

Existing performance profile uses:
    mcla_city_lod=0.5
    mcla_traffic_lod=0.5
    mcla_traffic_distance=250
    mcla_pedestrians=0.5
    mcla_parked_cars=0.5
Traffic LOD changes when the render model becomes less
detailed; the traffic-distance and density parameters
are separate. It is possible, but NOT confirmed, that
visual LOD/culling affects the apparent car position.

scripts/traffic_visual_lod_trial.ps1 changes ONLY
mcla_traffic_lod to 1.0 (normal 100% visual detail).
It does not change spawn distance/traffic quantity,
frame limiting, simulation delta, camera smoothness,
collision, FSR, shaders or GPU synchronization.
It retains the original configuration as backup in
ignored out/phase2-backup/pre-traffic-visual-lod-ab/.

Game closed:
    .\scripts\traffic_visual_lod_trial.ps1 -Mode normal
    .\scripts\traffic_visual_lod_trial.ps1 -Mode status
    .\scripts\traffic_visual_lod_trial.ps1 -Mode restore

Drive 2-3min same car/route/camera in the 1.0 test,
then restore original 0.5 and repeat. Track the second
of any invisible/late visible NPC collision or car pop.
The experiment may lower FPS due to greater detail; if
no difference, restore 0.5. Keep other configuration
unchanged. Boot/exit QA is not validation of gameplay
collision correctness.

If mismatch persists, next phase needs direct per-NPC
physics/collision transform and render transform pairing
with entity identity and sequence number, or investigate
DX12 queued frame age. Do not interpolate or change guest
vehicle state without measuring both.

## Smoke QA
With normal visual LOD: quit-qa-20261018-232445.log,
CLOSED=True EXIT=0. OFF smoke also performed; verify log
before calling QA complete. Code committed directly to
development, never main. No game saves or assets included.
