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
#include "hitch_correlation.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <string>
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

// Camera-only A/B diagnostic: the original Xbox filter moves a fixed
// fraction each update (tuned for 30Hz); our time-corrected filter rescales
// that fraction for the real frame duration. Neither mode changes FPS,
// frame pacing, the real-time guest timer, chassis or vehicle physics.
REXCVAR_DEFINE_STRING(mcla_camera_smoothing_mode, "time_corrected", "MCLA",
                      "Camera filter A/B: time_corrected (default) or per_frame (native factor)")
    .allowed({"time_corrected", "per_frame"})
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

// Limit the maximum guest time step when a texture streaming or CPU stall
// produces a very late frame. This limits simulation jumps but cannot make
// the host render faster; smaller caps may cause brief slow-motion instead.
// 125 ms matches the previously shipped behavior (no change by default).
// OFF preserves unrestricted FPS. ADAPTIVE targets the sustainable guest
// timer rate (45-90 FPS), retaining slack and resetting on late frames.
// STEADY45 is the prior reversible 45-FPS baseline, without changing mcla_fps.
// Explicit mcla_fps targets always override these optional modes.
REXCVAR_DEFINE_STRING(mcla_frame_pacing_mode, "off", "MCLA",
                      "Guest timer frame pacing: off, adaptive, steady45")
    .allowed({"off", "adaptive", "steady45"})
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

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

// Read-only: distinguish game timer, measured physics-step timer path and
// host present-command cadence, without touching any guest transformations.
REXCVAR_DEFINE_BOOL(mcla_sim_present_sync_probe, false, "MCLA",
                    "Correlate guest timer, fixed-step path and present requests (diagnostic only)")
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

// Approximate cross-thread sequencing, not a physics transform sampler.
// Sequence numbers and timestamps are sampled only when the probe is ON.
std::atomic<uint64_t> g_sync_timer_seq{0};
std::atomic<uint64_t> g_sync_fixed_seq{0};
std::atomic<uint64_t> g_sync_timer_last_us{0};
std::atomic<uint64_t> g_sync_fixed_last_us{0};
std::atomic<uint64_t> g_sync_timer_clipped_count{0};
std::atomic<uint64_t> g_sync_timer_clipped_us{0};

void TrackSimTimer(uint64_t raw_ticks, uint64_t applied_ticks) {
  if (!REXCVAR_GET(mcla_sim_present_sync_probe)) return;
  const uint64_t now = NowMicros();
  g_sync_timer_last_us.store(now, std::memory_order_relaxed);
  g_sync_timer_seq.fetch_add(1, std::memory_order_relaxed);
  if (raw_ticks > applied_ticks) {
    const double frequency = double(rex::chrono::Clock::guest_tick_frequency());
    if (frequency > 0.0) {
      const auto lost = static_cast<uint64_t>(
          double(raw_ticks - applied_ticks) * 1000000.0 / frequency);
      g_sync_timer_clipped_us.fetch_add(lost, std::memory_order_relaxed);
      g_sync_timer_clipped_count.fetch_add(1, std::memory_order_relaxed);
    }
  }
}

void TrackSimFixedStep() {
  if (!REXCVAR_GET(mcla_sim_present_sync_probe)) return;
  g_sync_fixed_last_us.store(NowMicros(), std::memory_order_relaxed);
  g_sync_fixed_seq.fetch_add(1, std::memory_order_relaxed);
}

void TrackSimPresent() {
  struct Window {
    uint64_t start_us = 0;
    uint64_t previous_fixed = 0;
    uint64_t previous_timer = 0;
    uint64_t previous_clip_count = 0;
    uint64_t previous_clip_us = 0;
    uint32_t presents = 0;
    uint32_t no_new_fixed = 0;
    uint32_t multi_fixed = 0;
    uint32_t no_new_timer = 0;
    uint32_t age_over_50 = 0;
    uint32_t age_over_100 = 0;
    uint32_t unpaired = 0;
    uint32_t events_logged = 0;
    uint64_t age_sum_us = 0;
    uint64_t age_max_us = 0;
  };
  static thread_local Window w{};
  if (!REXCVAR_GET(mcla_sim_present_sync_probe)) {
    w = {};
    return;
  }
  const uint64_t now = NowMicros();
  const uint64_t fixed = g_sync_fixed_seq.load(std::memory_order_relaxed);
  const uint64_t timer = g_sync_timer_seq.load(std::memory_order_relaxed);
  const uint64_t fixed_at = g_sync_fixed_last_us.load(std::memory_order_relaxed);
  if (!w.start_us) {
    w.start_us = now;
    w.previous_fixed = fixed;
    w.previous_timer = timer;
    w.previous_clip_count = g_sync_timer_clipped_count.load(std::memory_order_relaxed);
    w.previous_clip_us = g_sync_timer_clipped_us.load(std::memory_order_relaxed);
    REXLOG_INFO("MCLA sim/present sync probe active: measures callbacks, not NPC positions");
    return;
  }
  const uint64_t advanced = fixed - w.previous_fixed;
  const uint64_t timer_advanced = timer - w.previous_timer;
  const bool age_known = fixed_at && now >= fixed_at && now - fixed_at < UINT64_C(10000000);
  const uint64_t age = age_known ? now - fixed_at : 0;
  ++w.presents;
  w.no_new_fixed += advanced == 0;
  w.multi_fixed += advanced > 1;
  w.no_new_timer += timer_advanced == 0;
  w.unpaired += !age_known;
  if (age_known) {
    w.age_sum_us += age;
    w.age_max_us = std::max(w.age_max_us, age);
    w.age_over_50 += age >= UINT64_C(50000);
    w.age_over_100 += age >= UINT64_C(100000);
  }
  if (age_known && age >= UINT64_C(80000) && w.events_logged < 5) {
    ++w.events_logged;
    REXLOG_INFO("MCLA sim/present sync lag: fixed_age_ms={:.2f} "
                "new_fixed={} new_timer={} total_fixed={} total_timer={}",
                double(age) / 1000.0, advanced, timer_advanced, fixed, timer);
  }
  w.previous_fixed = fixed;
  w.previous_timer = timer;
  if (now - w.start_us >= UINT64_C(10000000)) {
    const uint64_t clips = g_sync_timer_clipped_count.load(std::memory_order_relaxed);
    const uint64_t clipped_us = g_sync_timer_clipped_us.load(std::memory_order_relaxed);
    const uint64_t start_fixed = fixed;
    const uint64_t start_timer = timer;
    const auto age_mean = w.presents > w.unpaired ?
        double(w.age_sum_us) / (1000.0 * double(w.presents - w.unpaired)) : 0.0;
    REXLOG_INFO("MCLA sim/present sync: presents={} no_new_fixed={} multi_fixed={} "
                "no_new_timer={} age_mean_ms={:.2f} age_peak_ms={:.2f} "
                "age50={} age100={} unpaired={} timer_clamps={} "
                "timer_clipped_ms={:.2f} fixed_seq={} timer_seq={}",
                w.presents, w.no_new_fixed, w.multi_fixed, w.no_new_timer,
                age_mean, double(w.age_max_us) / 1000.0, w.age_over_50,
                w.age_over_100, w.unpaired, clips - w.previous_clip_count,
                double(clipped_us - w.previous_clip_us) / 1000.0,
                fixed, timer);
    w = {};
    w.start_us = now;
    w.previous_fixed = start_fixed;
    w.previous_timer = start_timer;
    w.previous_clip_count = clips;
    w.previous_clip_us = clipped_us;
  }
}

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

// A timer-hook pacer, not a GPU/Present fence. Neither adaptive pacing
// nor a fixed cap can reduce a frame's real render/streaming cost.
// The conservative adaptive ceiling is derived from the 75th percentile of
// measured *non-waiting* guest-timer intervals every two seconds.
// Crucially, a missed deadline never causes catch-up bursts.
void WaitForFrameDeadline() {
  struct Pacer {
    uint64_t next_us = 0;
    uint64_t previous_entry_us = 0;
    uint64_t previous_wait_us = 0;
    uint64_t sample_start_us = 0;
    uint64_t report_start_us = 0;
    uint64_t reported_wait_us = 0;
    uint64_t reported_late = 0;
    uint32_t samples = 0;
    uint32_t adaptive_fps = 45;
    int32_t last_explicit_fps = -999;
    std::string last_mode;
    std::array<uint32_t, 96> work_buckets{};
  };
  // Guest timer can run on additional threads; retain the original
  // single-owner rule so we never introduce competing sleepers.
  static const std::thread::id owner = std::this_thread::get_id();
  if (std::this_thread::get_id() != owner) {
    return;
  }
  static Pacer pacer;

  const int32_t explicit_fps = REXCVAR_GET(mcla_fps);
  const auto mode = REXCVAR_GET(mcla_frame_pacing_mode);
  const bool adaptive = explicit_fps == 0 && mode == "adaptive";
  const bool steady = explicit_fps == 0 && mode == "steady45";
  const bool changed = explicit_fps != pacer.last_explicit_fps ||
                       mode != pacer.last_mode;
  if (changed) {
    pacer = {};
    pacer.adaptive_fps = 45;
    pacer.last_explicit_fps = explicit_fps;
    pacer.last_mode = mode;
    if (adaptive || steady) {
      REXLOG_INFO("MCLA guest frame pacer: mode={} starting at 45 FPS "
                  "(no catch-up, explicit FPS targets override)", mode);
    }
  }

  if (explicit_fps <= 0 && !adaptive && !steady) {
    // Preserve the original user's fully uncapped code path.
    pacer.next_us = 0;
    pacer.previous_entry_us = 0;
    pacer.previous_wait_us = 0;
    return;
  }

  const uint64_t entry_us = NowMicros();
  if (adaptive) {
    if (!pacer.sample_start_us) {
      pacer.sample_start_us = entry_us;
    }
    if (pacer.previous_entry_us && entry_us > pacer.previous_entry_us) {
      const uint64_t elapsed = entry_us - pacer.previous_entry_us;
      const uint64_t busy_us = elapsed > pacer.previous_wait_us
                                   ? elapsed - pacer.previous_wait_us
                                   : elapsed;
      // Exclude scene-loading stalls and abnormal thread pauses from the
      // sustainable-rate estimate. Those still show up as long frames
      // in the existing FPS benchmark and hitch correlator.
      if (busy_us >= 1000 && busy_us <= 95000) {
        const auto bin = static_cast<size_t>(
            std::min<uint64_t>(95, (busy_us + 999) / 1000));
        ++pacer.work_buckets[bin];
        ++pacer.samples;
      }
    }
    if (entry_us - pacer.sample_start_us >= UINT64_C(2000000)) {
      if (pacer.samples >= 25) {
        const uint32_t rank = (pacer.samples * 3 + 3) / 4;
        uint32_t cumulative = 0;
        size_t p75_ms = 95;
        for (size_t i = 1; i < pacer.work_buckets.size(); ++i) {
          cumulative += pacer.work_buckets[i];
          if (cumulative >= rank) {
            p75_ms = i;
            break;
          }
        }
        // At 20ms of work, choose ~46 FPS; at 25-30ms choose 45.
        // Only gradually raise the cap when spare headroom persists.
        const int desired = std::clamp(
            static_cast<int>(1000.0 / (double(p75_ms) * 1.08)), 45, 90);
        const int delta = std::clamp(
            desired - static_cast<int>(pacer.adaptive_fps), -10, 6);
        if (delta <= -2 || delta >= 2) {
          pacer.adaptive_fps = static_cast<uint32_t>(
              std::clamp(static_cast<int>(pacer.adaptive_fps) + delta, 45, 90));
        }
      }
      pacer.work_buckets.fill(0);
      pacer.samples = 0;
      pacer.sample_start_us = entry_us;
    }
  }

  const int32_t limit = explicit_fps > 0 ? explicit_fps :
                        steady ? 45 : static_cast<int32_t>(pacer.adaptive_fps);
  const uint64_t period_us = 1'000'000ull / static_cast<uint64_t>(limit);
  if (!pacer.next_us) {
    pacer.next_us = entry_us + period_us;
    pacer.previous_entry_us = entry_us;
    pacer.previous_wait_us = 0;
    pacer.report_start_us = entry_us;
    return;
  }

  if (entry_us < pacer.next_us) {
    constexpr uint64_t kSpinMicros = 1500;
    if (pacer.next_us - entry_us > kSpinMicros + 500) {
      std::this_thread::sleep_for(
          std::chrono::microseconds(pacer.next_us - entry_us - kSpinMicros));
    }
    while (NowMicros() < pacer.next_us) {
#if defined(_WIN32)
      _mm_pause();
#else
      std::this_thread::yield();
#endif
    }
  } else if (entry_us > pacer.next_us + 1000) {
    ++pacer.reported_late;
  }

  const uint64_t after_us = NowMicros();
  const uint64_t waited_us = after_us - entry_us;
  pacer.previous_entry_us = entry_us;
  pacer.previous_wait_us = waited_us;
  pacer.reported_wait_us += waited_us;
  // Never "catch up" by issuing an immediate burst of frames.
  pacer.next_us += period_us;
  if (pacer.next_us <= after_us) {
    pacer.next_us = after_us + period_us;
  }

  if ((adaptive || steady) &&
      after_us - pacer.report_start_us >= UINT64_C(10000000)) {
    REXLOG_INFO("MCLA guest frame pacer: mode={} target={} fps "
                "waited_ms={:.1f} late_calls={} over_10s",
                mode, limit, double(pacer.reported_wait_us) / 1000.0,
                pacer.reported_late);
    pacer.report_start_us = after_us;
    pacer.reported_wait_us = 0;
    pacer.reported_late = 0;
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
  // The early OnPostSetup log can precede the effective game-config value.
  // Record the CVar once at the actual guest timer to verify A/B runs.
  static std::atomic_flag reported_effective_cap = ATOMIC_FLAG_INIT;
  if (!reported_effective_cap.test_and_set(std::memory_order_relaxed)) {
    REXLOG_INFO("MCLA effective FPS target at guest timer: {}", REXCVAR_GET(mcla_fps));
  }
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
  MclaCorrelateGuestTimer(measured_ticks, r8.u64);
  TrackSimTimer(measured_ticks, r8.u64);
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
    const double applied_delta = std::min(measured_delta, MaxGuestFrameSeconds());
    f11.f64 = applied_delta;
    MclaCorrelateFixedStep(measured_delta, applied_delta);
    TrackSimFixedStep();
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
  TrackSimPresent();
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
  MclaCorrelateCameraFps(fps);
  // Isolated test for the remaining small chase-camera flicks above 30fps:
  // leave the game's unmodified per-frame coefficient in place. This
  // purposely makes the filter stronger at >30fps, unlike the corrected
  // time-continuous formula. Do not change the other fixed-step safeguards.
  if (REXCVAR_GET(mcla_camera_smoothing_mode) == "per_frame") {
    return;
  }
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
  REXLOG_INFO("MCLA chase camera filter A/B: mode={} (does not cap FPS)",
              REXCVAR_GET(mcla_camera_smoothing_mode));
}
