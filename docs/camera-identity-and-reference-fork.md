# Camera identity trace and reference-fork comparison
Date: 2026-10-18
Branch: experiment/camera-publish-identity-trace

## Reference fork inspected read-only

User GitHub fork: https://github.com/yukkibr/Midnight-Club-L.A-RECOMP
Upstream parent: https://github.com/luisxl15/Midnight-Club-L.A-RECOMP
At inspection, both HEADs were:
e60746a500dc1c7c29bb21186fbab25849ea4f29
(2026-08-30). No extra user commits yet. Reference cloned without
submodules under ignored out/external-reference/Midnight-Club-L.A-RECOMP/.
No content merged or copied into project source.

Our patched ReXGlue SDK is v0.10.0. The reference has customized
v0.9.0. Both run DirectX 12 on Windows, even though the older SDK
has Vulkan source code. Never replace binaries across SDK versions.

Our own game/default.xex: 9,252,864 bytes. The SHA-1 of its first
1,048,576 bytes is 2ac1e4f500e06f4267c9180a36aa1056e0303f29,
matching the reference README. Similar guest hooks are therefore
promising candidates for inspection, but need independent validation.

Useful reference ideas:
- mcla_monitor.cpp: GPU busy time, draw/upload CPU time, draw calls,
  resolves and fence waits, IssueDraw phase breakdown. Port counter
  hooks carefully to ReXGlue 0.10.0 in a later opt-in profiling branch.
- mcla_espelho_regs / mcla_estado_desenho: read-only Xenos register
  mirror for eventual native state path; not a renderer replacement.
- tools/bench.py: benchmark using a saved scene and avoiding intro
  attraction sequences, which aren't deterministic between runs.

Critical caution:
The other SDK exposes FSR2/FSR3 menu options, but its actual
d3d12_presenter.cpp passes the color image as both depth and
motion-vector input, with zero jitter and reset=true every frame.
It uses a fixed 16.666ms time step for dispatch. presenter.cpp
warns explicitly about synthetic inputs and spatial fallback.
Do NOT claim actual FSR 3.1 quality or import as real temporal
reconstruction. Native depth, motion vectors and jitter are still
required. The other project's readback_resolve shortcut also had
visual correctness regressions in its own report.

Do not compare performance figures from a GTX 1650 directly to
RTX 5060 Ti or infer causal gains from different routes.

## Original four-phase plan

1. Establish fork and reliable build/test environment: completed.
2. Spatial FSR + render resolution profiles: implemented.
3. True temporal FSR 3.1 / DLSS with motion vectors, depth,
   jitter: pending, not equivalent to experimental reference.
4. Structural Xenos/streaming/CPU/GPU synchronization optimization,
   then frame generation after correctness: in progress.

## New read-only camera identity instrument

During user test mcla_045.log (02:33-02:34), 5,689 DX12 resources
were created but no recycling occurred in the pool. At 02:33:41,
two camera matrix publish jumps occurred, with an offset step
max 12.319m and without corresponding rig camera jumps >6m.
This could be a legitimate mode change or an unexpected flick.

The existing validated camera update / camera publication midasm
hooks now optionally trace (new CVar: mcla_camera_publish_trace,
default false) the published matrix pointer and recent chase
camera rig + owner, tracking both old and new identities.
Each 10-second report counts matrix/rig/owner switches and
jumps by same/different source matrix, known stable/unpaired rig.
A stable rig requires prior observations with a known same rig
address and known same owner, not merely a stable matrix address.

Up to 6 event-level logs / 10 sec report previous/current xyz,
matrix pointers, rig IDs, owner IDs, delta time, and relative offset
changes >1.5m. Up to 12 followup records / 10 sec capture
three publications immediately after an event. No guest writes,
render command changes, physics or camera smoothing changes.

A stable rig is a stronger suspicious clue; it is NOT proof of
incorrect camera behavior without matching visual timestamps.
Source switch is not proof of a legitimate cutscene either.

Commands while the game is closed:
  .\scripts\camera_publish_trace_trial.ps1 -Mode on
  .\scripts\camera_publish_trace_trial.ps1 -Mode off
  .\scripts\camera_publish_trace_trial.ps1 -Mode status

After a real drive:
  .\scripts\camera_publish_trace_report.ps1 -Recent 2
  .\scripts\frame_hitch_correlation_report.ps1 -Recent 2 -SkipFirst 3

The user should drive 2-3 minutes, note the clock seconds of
any camera flick, and indicate intentional camera cuts, car
respawns or crashes separately. Leave FPS uncapped, VSync off,
FSR1, Fast Path+Sampler ON, DX12 pool 128MB, guest step 67ms.

## QA

Build succeeded with scripts/build.ps1 -NoCodegen -FidelityFX.
The previous mcla.exe, mcla.toml and motion_probe.cpp are backed
up under ignored out/phase2-backup/pre-camera-publish-identity-trace/.
Initial ON test 2026-10-18 20:17:30 closed EXIT=0 and observed a
menu scene transition (same source pointer, huge 3.94km step)
before a comparable known rig was established. The stable_rig
classification was then tightened to exclude this as proof of
an in-world flick. OFF smoke closed EXIT=0
(out/runs/quit-qa-20261018-201828.log).
Refined ON smoke: out/runs/quit-qa-20261018-202042.log,
CLOSED=True EXIT=0. Two 10s summaries were emitted and parsed,
no falsely classified source/rig jumps on the title screen.
A real city-drive QA is still mandatory before changing gameplay.
No merge or push.
