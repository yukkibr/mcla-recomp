// Frame pacing and frame-rate targets.
//
// The game was built for a locked 30 FPS: its timer replaces the measured
// frame time with a fixed 33.3 ms step, so any frame that runs long plays in
// slow motion, and with vsync a 35 ms frame waits until 50 ms. Here the timer
// is given the real elapsed time instead, vsync is turned off, and a host
// limiter sleeps to a wall-clock deadline. A late frame then costs only its
// overrun, and the simulation advances by real time at any frame rate.
//
// Hook addresses and the timer analysis come from LARecomp (see
// config/frame_timing.toml).

#include "generated/default/mcla_init.h"

#include "mcla_app.h"
#include "fps_overlay.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <thread>

#include <rex/chrono/clock.h>
#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/runtime.h>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <timeapi.h>
#include <immintrin.h>
#endif

REXCVAR_DEFINE_INT32(mcla_fps, 30, "MCLA",
                     "Frame-rate target: 30, 60 or 120. 0 runs uncapped. "
                     "-1 restores the game's original fixed 30 Hz timing")
    .range(-1, 240);

// Limit the maximum guest time step when a texture streaming or CPU stall
// produces a very late frame. This limits simulation jumps but cannot make
// the host render faster; smaller caps may cause brief slow-motion instead.
// 125 ms matches the previously shipped behavior (no change by default).
REXCVAR_DEFINE_INT32(mcla_frame_stall_guard_ms, 125, "MCLA",
                     "Maximum real frame time advanced in one guest simulation "
                     "step after a hitch (50, 67, 125 ms)")
    .range(33, 125);

// Off by default: skipping here also skips whatever puts the game logo on the
// title screen (only "PRESS START" remains). Tested with and without the
// render-pass mask change; the logo is missing either way.
// Read-only, opt-in frame time diagnostics. Does not change frame pacing,
// guest simulation deltas or the existing camera / vehicle smoothing hooks.
REXCVAR_DEFINE_BOOL(mcla_timing_trace, false, "MCLA",
                    "Log guest frame delta and camera FPS threshold transitions (5s summaries)")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

REXCVAR_DEFINE_BOOL(mcla_skip_intro, false, "MCLA",
                    "Skip the intro movies. Side effect: the title screen loses its logo");

// The legal screens and logos at start-up. "skip" is mcla_skip_intro by
// another name, so that the settings menu can offer all three in one row.
REXCVAR_DEFINE_STRING(mcla_intro, "normal", "MCLA",
                      "Start-up legal screens and logos: normal (original speed), fast (as "
                      "fast as the host presents), skip (the title screen loses its logo)");

namespace {

// The engine timer object lives at a fixed guest address (sub_821BDA90).
constexpr uint32_t kGuestFrameDelta = 0x827D7508;  // seconds, time-scaled
constexpr uint32_t kGuestFrameRate = 0x827D750C;   // 1 / delta

// The previous 125 ms hard limit is still the default. Alternative limits
// are opt-in for users who see camera / physics jumps after large CPU stalls.
double MaxGuestFrameSeconds() {
  return static_cast<double>(REXCVAR_GET(mcla_frame_stall_guard_ms)) / 1000.0;
}

// Set when the frame limiter has run; see PaceUnlimitedSwap.
std::atomic<bool> g_limiter_ran_since_swap{false};

bool OriginalTiming() {
  return REXCVAR_GET(mcla_fps) < 0;
}

uint64_t NowMicros() {
  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(
                                   std::chrono::steady_clock::now().time_since_epoch())
                                   .count());
}

// Only read when diagnostics are explicitly enabled; no GPU or CSV counters.
std::atomic<uint32_t> g_camera_fps_hundredths{0};
std::atomic<uint64_t> g_camera_60fps_crossings{0};

void TraceCameraRate(float fps) {
  if (!REXCVAR_GET(mcla_timing_trace) || !std::isfinite(fps) || fps < 0.0f) {
    return;
  }
  // The original chase camera changes its per-frame tune coefficient when
  // round(1 / dt) crosses 60 FPS. Observe, do not override that decision.
  static thread_local int previous_band = -1;
  const int band = static_cast<int>(fps + 0.5f) >= 60 ? 1 : 0;
  if (previous_band != -1 && previous_band != band) {
    g_camera_60fps_crossings.fetch_add(1, std::memory_order_relaxed);
  }
  previous_band = band;
  g_camera_fps_hundredths.store(
      static_cast<uint32_t>(std::min(fps, 1000.0f) * 100.0f),
      std::memory_order_relaxed);
}

void TraceGuestFrameDelta(uint64_t measured_ticks, uint64_t applied_ticks) {
  if (!REXCVAR_GET(mcla_timing_trace)) {
    return;
  }
  // MCLA can invoke its guest timer from more than one thread. Keep separate
  // rolling summaries instead of introducing locks or thread contention.
  struct Summary {
    uint64_t window_start_us = 0;
    uint64_t samples = 0;
    double sum_ms = 0.0;
    double peak_ms = 0.0;
    uint64_t over_40ms = 0;
    uint64_t over_67ms = 0;
    uint64_t clamped = 0;
    uint64_t previous_cam_crossings = 0;
  };
  static thread_local Summary summary{};
  const uint64_t now_us = NowMicros();
  if (!summary.window_start_us) {
    summary.window_start_us = now_us;
    summary.previous_cam_crossings =
        g_camera_60fps_crossings.load(std::memory_order_relaxed);
  }
  const double clock_hz =
      static_cast<double>(rex::chrono::Clock::guest_tick_frequency());
  if (clock_hz <= 0.0) {
    return;
  }
  const double ms = static_cast<double>(measured_ticks) * 1000.0 / clock_hz;
  ++summary.samples;
  summary.sum_ms += ms;
  summary.peak_ms = std::max(summary.peak_ms, ms);
  summary.over_40ms += ms > 40.0;
  summary.over_67ms += ms > 67.0;
  summary.clamped += measured_ticks > applied_ticks;
  if (now_us - summary.window_start_us >= UINT64_C(5000000)) {
    const uint64_t crossings =
        g_camera_60fps_crossings.load(std::memory_order_relaxed);
    REXLOG_INFO(
        "MCLA timing trace: {} timer calls, raw dt mean {:.2f}ms peak {:.2f}ms, "
        ">40ms {}, >67ms {}, guard clamps {}, camera {:.1f} FPS, "
        "60-FPS crossings {} (last 5s)",
        summary.samples, summary.sum_ms / static_cast<double>(summary.samples),
        summary.peak_ms, summary.over_40ms, summary.over_67ms,
        summary.clamped,
        g_camera_fps_hundredths.load(std::memory_order_relaxed) / 100.0,
        crossings - summary.previous_cam_crossings);
    summary = {};
  }
}

// Sleeps until the next frame deadline. The deadline advances by one period
// per frame; a frame that is already late resets it, so lateness is not
// repaid by running the following frames faster.
void WaitForFrameDeadline() {
  static uint64_t next_us = 0;
  // The timer function has callers on other threads; pace only the first one.
  static const std::thread::id owner = std::this_thread::get_id();
  if (std::this_thread::get_id() != owner) {
    return;
  }

  const int32_t fps = REXCVAR_GET(mcla_fps);
  if (fps <= 0) {
    next_us = 0;
    return;
  }
  const uint64_t period_us = 1'000'000ull / static_cast<uint64_t>(fps);

  uint64_t now = NowMicros();
  if (next_us == 0) {
    next_us = now + period_us;
    return;
  }
  if (now < next_us) {
    // Sleep most of the way, then spin the last stretch: sleeps overshoot by
    // up to a millisecond or two, which is a large share of an 8.3 ms frame.
    constexpr uint64_t kSpinMicros = 1500;
    if (next_us - now > kSpinMicros + 500) {
      std::this_thread::sleep_for(std::chrono::microseconds(next_us - now - kSpinMicros));
    }
    while (NowMicros() < next_us) {
#if defined(_WIN32)
      _mm_pause();
#else
      std::this_thread::yield();
#endif
    }
  }
  now = NowMicros();
  next_us += period_us;
  if (next_us < now) {
    next_us = now + period_us;
  }
}

float ReadGuestFloat(uint32_t address) {
  const uint8_t* p = rex::Runtime::instance()->virtual_membase() + address;
  uint32_t bits = (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
  float value;
  std::memcpy(&value, &bits, sizeof value);
  return value;
}

}  // namespace

void MclaTickButtonPrompts();
void MclaTickPerfOptions();

void mcla_frame_delta(PPCRegister& r8) {
  MclaTickButtonPrompts();
  MclaTickPerfOptions();
  if (OriginalTiming()) {
    return;
  }
  WaitForFrameDeadline();
  g_limiter_ran_since_swap.store(true, std::memory_order_relaxed);
  // r8 was computed before the wait. Whatever the wait added is picked up by
  // the next frame's measurement, so no time is lost, only shifted one frame.
  const uint64_t max_ticks = static_cast<uint64_t>(
      MaxGuestFrameSeconds() * static_cast<double>(rex::chrono::Clock::guest_tick_frequency()));
  const uint64_t measured_ticks = r8.u64;
  if (r8.u64 > max_ticks) {
    r8.u64 = max_ticks;
  }
  TraceGuestFrameDelta(measured_ticks, r8.u64);
}

bool mcla_use_real_delta() {
  return !OriginalTiming();
}

void mcla_fixed_step_path(PPCRegister& r3, PPCRegister& f11) {
  if (OriginalTiming()) {
    return;
  }
  // The second fixed-step path reads the measured delta from guest memory.
  // Clamp this path too, otherwise large streaming stalls may reach the
  // physics / camera simulation even when the earlier r8 hook was clamped.
  const double measured_delta = static_cast<double>(ReadGuestFloat(r3.u32 + 0x58));
  if (std::isfinite(measured_delta) && measured_delta >= 0.0) {
    f11.f64 = std::min(measured_delta, MaxGuestFrameSeconds());
  }
}

// Loops that never reach the engine timer (the publisher logos at start-up,
// loading screens) were paced on the console only by the present interval of
// two vblanks, which is removed here, so they ran as fast as the host could
// present: the logo sequence was over in about a second. A swap that follows
// another with no pass through the frame limiter in between is held to the
// original 30 per second.

static void PaceUnlimitedSwap() {
  static std::atomic<uint64_t> last_swap_us{0};
  constexpr uint64_t kPeriodMicros = 1'000'000ull / 30;
  const bool limited = g_limiter_ran_since_swap.exchange(false, std::memory_order_relaxed) ||
                       REXCVAR_GET(mcla_intro) != "normal";
  const uint64_t last = last_swap_us.load(std::memory_order_relaxed);
  uint64_t now = NowMicros();
  if (!limited && last && now - last < kPeriodMicros) {
    std::this_thread::sleep_for(std::chrono::microseconds(kPeriodMicros - (now - last)));
    now = NowMicros();
  }
  last_swap_us.store(now, std::memory_order_relaxed);
}

bool mcla_present_interval(PPCRegister& r11) {
  // Actual guest present requests, not target FPS and not an SDK profiler.
  MclaRecordGuestPresent();
  if (OriginalTiming()) {
    return false;
  }
  PaceUnlimitedSwap();
  r11.u64 = 1;
  return true;
}

// A filter written as "move a fraction k toward the target every frame" is
// only right at the frame rate it was tuned for. The same filter over an
// arbitrary step dt is 1 - (1 - k)^(dt * 30), where k is the 30 FPS fraction.
static double PerFrameToContinuous(double k30, double dt) {
  return 1.0 - std::pow(1.0 - k30, dt * 30.0);
}

static void RescaleCameraFactor(PPCRegister& reg) {
  if (OriginalTiming()) {
    return;
  }
  const double dt = std::min(static_cast<double>(ReadGuestFloat(kGuestFrameDelta)),
                             MaxGuestFrameSeconds());
  const double raw = reg.f64;
  if (raw <= 0.0 || raw >= 1.0 || dt <= 0.0) {
    return;
  }
  // The game halves the tune value itself when its integer frame rate is
  // below 60 (0x82320454..0x82320464), so the value arriving here is already
  // the 30 FPS factor in that case and the raw tune value otherwise.
  const float fps = ReadGuestFloat(kGuestFrameRate);
  TraceCameraRate(fps);
  const bool already_halved = static_cast<int>(fps + 0.5f) < 60;
  reg.f64 = PerFrameToContinuous(already_halved ? raw : 0.5 * raw, dt);
}

void mcla_camera_pos_smoothing(PPCRegister& f13) {
  RescaleCameraFactor(f13);
}

void mcla_camera_lookat_smoothing(PPCRegister& f0) {
  RescaleCameraFactor(f0);
}

void mcla_chassis_depth_smoothing(PPCRegister& f0) {
  if (OriginalTiming()) {
    return;
  }
  const double dt = std::min(static_cast<double>(ReadGuestFloat(kGuestFrameDelta)),
                             MaxGuestFrameSeconds());
  if (dt > 0.0) {
    f0.f64 = PerFrameToContinuous(0.10, dt);
  }
}

static bool SkipIntro() {
  return REXCVAR_GET(mcla_skip_intro) || REXCVAR_GET(mcla_intro) == "skip";
}

bool mcla_hook_skip_intro() {
  return SkipIntro();
}

void mcla_skip_intro_render_pass_mask(PPCRegister& r4) {
  if (SkipIntro()) {
    r4.u32 = 0xFEFFFFFFu;
  }
}

void MclaApp::ConfigureFrameTiming() {
  if (OriginalTiming()) {
    REXLOG_INFO("frame timing: original fixed 30 Hz step, vsync left as configured");
    return;
  }
  // Pacing is done by the limiter. With vsync on, a frame that misses a
  // display interval would wait for the next one.
  if (rex::cvar::GetFlagSource("vsync") == rex::cvar::Source::kDefault) {
    rex::cvar::SetFlagByName("vsync", "false");
  }
#ifdef _WIN32
  // Default Windows timer granularity is 15.6 ms; sleeps need 1 ms.
  timeBeginPeriod(1);
#endif
  REXLOG_INFO("frame timing: real frame delta, target {} FPS, vsync {}, "
              "max guest step {} ms",
              REXCVAR_GET(mcla_fps), rex::cvar::GetFlagByName("vsync"),
              REXCVAR_GET(mcla_frame_stall_guard_ms));
}
