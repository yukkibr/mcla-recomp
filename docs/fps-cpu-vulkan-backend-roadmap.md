# FPS roadmap: CPU overhead and DX12 versus Vulkan

Date: 2026-10-18
Branch: development. Keep main stable and do not create topic branches.

## Why focus shifted from camera/collision to FPS

The user asked to defer the remaining native-game camera/physics
anomalies and concentrate on sustained FPS and smooth performance.
Recent DX12 gameplay logs show roughly 37-42 guest presents/s with
occasional larger spikes. The target of 60 fps requires ~16.67ms
per frame; 40fps takes 25ms. This is ~33% less frame time, not a
tiny cache optimization.

Hardware: Xeon E5-2670 v3 at 2.30 GHz (12 cores / 24 logical threads)
and GeForce RTX 5060 Ti with 8GB VRAM. Xeon single-core performance
is likely an important constraint given thousands of translated
Xenos draw calls per guest frame. Still need backend-specific real
GPU present time to prove CPU/GPU bottleneck.

Older, highly instrumented 2026-10-15 frame profiles reported
4,000-8,000 draw calls on many frames, GPU resource creation spikes
during loading and very few pipeline cache misses. Those profiles
had high profiling overhead and are NOT directly comparable with
today's fast build FPS.

Do not keep tuning negligible costs (unscaled precheck/map buckets)
without reproducible evidence. Current unscaled precheck and
map reserve defaults should remain OFF; existing texture Fast
Path, scissor cache and single-tile rendering remain ON.

## Concrete Vulkan feasibility discovered

The existing pinned patched ReXGlue 0.10.0 build ALREADY includes
Vulkan on Windows (scripts/make_pc.ps1 configures
- DREXGLUE_USE_VULKAN=ON). RTX 5060 Ti supports Vulkan API 1.4.

First smoke:
out/runs/quit-qa-20261018-233628.log
- Vulkan instance and NVIDIA Vulkan device initialized;
- VulkanPresenter created its 1280x720 swapchain;
- game remained alive 22 seconds and closed normally, EXIT=0;
- no SDK replacement, no user game assets modified.
- Vulkan emitted "Skipping Vulkan frame presentation due to async
  placeholder draw usage in this frame" during shader warmup.
- Guest-present benchmark reported ~431.8/s during title/loading.
  THIS IS NOT ACTUAL DISPLAY FPS or evidence of Vulkan gains.
  Vulkan can skip presenting unfinished frames, and game may
  issue many guest Present calls without normal simulation.
- Vulkan backend also has spatial FSR shaders in its presenter,
  although visual equivalence to DX12 during CITY gameplay is
  not yet validated.

DX12 is still the default and still the safe fallback.

## Reversible backend trial

Use scripts/gpu_backend_trial.ps1. It only sets a command-line
override for this process; user TOML isn't changed, and the
same settings carry across API backends.

1. DX12 (A): .\scripts\gpu_backend_trial.ps1 -Backend d3d12
2. Vulkan (B): .\scripts\gpu_backend_trial.ps1 -Backend vulkan
3. DX12 (A): .\scripts\gpu_backend_trial.ps1 -Backend d3d12

Close the game completely between trials. Use the same car,
traffic/profile, same area and same camera, and 2-3 minutes
per attempt after shader/scene warmup. Note rendered image
fidelity, black/missing textures, reflections, cut scenes,
hitches, FPS at identical landmarks.

IMPORTANT: guest-present FPS is not actual onscreen Vulkan
FPS if there are skip/placeholder warnings. External GPU frame
presentation monitor (such as PresentMon or NVIDIA frame-rate
overlay if available) should be used for cross-API FPS claims.
Track FPS percentiles and visually displayed motion as primary
checks, not the 400+ startup guest-present number.

If Vulkan has serious graphical artifacts or missing/incorrect
draws, stop and use DX12 again. Never switch main/default
backend until city validation on both.

## Next structural CPU performance work

1. Build reliable frame presentation timing (GPU and CPU) for
   DX12/Vulkan so skipped guest frames cannot inflate FPS.
2. Inspect draw-state and binding translation overhead in
   ReXGlue. Avoid repeated per-draw state decoding and
   map/hash work only after measuring the relevant CPU scopes.
   Preserve exact draw order and guest render semantics.
3. Tune pipeline worker scheduling versus game/render threads
   on this Xeon, comparing workers 4/8/auto with matched
   city recordings. Current workers = 8; don't change
   without evidence. Async compilation reduces early stalls
   but may produce temporary Vulkan placeholder skips.
4. Compare Vulkan and DX12 sustained GPU frames and correctness.
   If Vulkan is materially faster and visually correct, make
   a user-selectable restart-only backend preference in the UI.
5. Optimize new-texture upload/preparation when it dominates a
   measured fraction of gameplay frame time. Keep memory
   watches, GPU fences and resource validity intact.
6. FSR3.1/DLSS temporal require real depth and motion vectors;
   not a near-term substitute for true rendering optimization.

No physics timing, camera, vehicle transforms, shadow quality,
resolution, fast-path validity, or core Xenos emulation changed
in this backend comparison.

## QA

- GPU backend script is syntax validated by Windows PowerShell.
- Vulkan backend launch/swapchain/exit smoke was successful.
- The existing test_window_close.ps1 now accepts Backend=...
  default remains d3d12. DX12 regression smoke succeeded at
  out/runs/quit-qa-20261018-234005.log, CLOSED=True EXIT=0.
- Build remains ReXGlue 0.10.0 FidelityFX ON, no profiling CSV.
- Git changes only in scripts/docs directly on development.
