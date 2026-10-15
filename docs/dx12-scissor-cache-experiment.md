# DX12 draw submission: experimental scissor decoding cache

Branch: `experiment/dx12-scissor-cache`. Based on the verified
`fix/native-720p-preset`, texture-cache retention and Fast Runtime.

## Why test this?

Dense city scenes in past MCLA captures executed 4,000–8,000
Xenos draw calls per rendered frame. CPU profiling identified a
busy emulated game thread and a busy ReXGlue GPU Commands thread.

In the pinned ReXGlue v0.10.0, the D3D12 path already caches
the decoded *viewport* between draws when viewport state is unchanged,
but always calls `draw_util::GetScissor` on every draw. That function
decodes screen/window scissor bounds, optionally applies an offset,
clamps to guest render surface pitch, and normalizes bounds. Repeated
unchanged scissor state can be decoded once.

The versioned SDK patch is
`patches/rexglue-dx12-scissor-cache.patch`.
`scripts/make_pc.ps1 -FidelityFX` will apply it on a clean pinned SDK
installation and produce the same complete build.

## Precise cache key / correctness

The six Xenos registers used by `draw_util::GetScissor` are:
- `PA_SC_WINDOW_SCISSOR_TL`
- `PA_SC_WINDOW_SCISSOR_BR`
- `PA_SC_SCREEN_SCISSOR_TL`
- `PA_SC_SCREEN_SCISSOR_BR`
- `PA_SC_WINDOW_OFFSET`
- `RB_SURFACE_INFO` (includes the clamped render-target pitch)

Values are compared exactly; if anything changed, the original
function runs. On a hit, a stored **unscaled** rectangle is used.
Host rendering scale is applied afterward as before, so the
texture-resolution / 720p / 480p settings remain effective.
The result still passes through the original fixed-function
state updater, which generates exactly the same D3D12 commands
as before. There are no GPU resource, shader, vehicle or
simulation changes.

**Default: OFF**. It is deliberately not enabled globally until
both positive A/B performance and gameplay correctness are verified.

## Switch on/off (needs game restart)

Run from the project root in PowerShell. Or pass either option
to the game executable's normal launcher:

    --d3d12_scissor_cache=false
    --d3d12_scissor_cache=true

For a repeatable capture using the existing close QA script:

    .\scripts\test_window_close.ps1 -WarmupSeconds 45 -TimeoutSeconds 25 -ExtraArgs @('--d3d12_scissor_cache=true')

When enabled, the GPU command thread logs
`DX12 scissor cache: N hits / M recalculations (P% reuse)`
after the first 16,384 draws and then every 262,144 draws,
to avoid flooding the game log. This is a rough hit-rate measurement
and proves that the fast path is being used, NOT that it improves
FPS. Logging does not run when the option is off.

For normal gameplay without command-line arguments, use the reversible
helper after closing MCLA:

    .\scripts\scissor_cache_trial.ps1 -Mode on
    .\scripts\scissor_cache_trial.ps1 -Mode off
    .\scripts\scissor_cache_trial.ps1 -Mode status

The helper edits only the scissor CVar in ignored `mcla.toml`;
it preserves 720p, cache retention and parked vehicles.

## What should be preserved

The current user configuration is Native (1280x720 internal),
FSR1 spatial, Gentle 67ms frame guard, motion/fullscreen blur off,
0.5 parked vehicle density and the previously successful
texture retention settings:
- Soft texture memory budget 768 MB
- Hard texture memory budget 1024 MB
- Cache lifetime 90 seconds

The 64MB optional texture *resource* reuse pool is independently
disabled. QUIT GAME and gameplay timing are untouched.
Do not merge before the same route has been driven with
`d3d12_scissor_cache` both off and on and differences in
visuals, frame stability and CPU overhead are understood.

## Verified development QA (15 October 2026)

- Recompiled pinned ReXGlue v0.10.0 and the 720p FidelityFX game successfully.
- ON and OFF sessions both initialized and quit normally with exit code 0.
- With the quieter final logging, a Native 1280x720 title test confirmed
  520,023 hits and 4,265 misses at 524,288 scissor lookups, or **99.2% reuse**.
- FPS improvement **not established**; the test has an animated title camera,
  not a controlled dense-city route.
- Running MCLA's original QUIT GAME should remain unchanged; automated
  WM_CLOSE exits have passed.
- The user's local mcla.toml has the experiment enabled but it is OFF
  by default on other installs. Run the rollback script with -Mode off
  to disable the feature after closing the game.

This change is deliberately small. Even a near-100% cache hit
rate may provide negligible speedup compared with other expensive
work such as pipeline key generation, guest draw translation and
D3D12 resource creation. Do not promise or infer 30 FPS.
