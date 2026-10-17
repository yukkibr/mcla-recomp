// Read-only correlation between presentation stalls and guest simulation/camera.
// No guest memory writes, game pacing changes, per-frame allocations or locks.
#include "hitch_correlation.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>

#include <rex/chrono/clock.h>
#include <rex/cvar.h>
#include <rex/logging.h>

REXCVAR_DEFINE_BOOL(mcla_hitch_correlation, false, "MCLA",
                    "Correlate presentation stalls, guest frame steps and camera movement")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

namespace {
constexpr uint64_t kReportIntervalUs = UINT64_C(10000000);
constexpr uint64_t kNearbyHitchUs = UINT64_C(250000);
std::atomic<uint64_t> g_last_hitch_us{0};

struct Stats {
  std::atomic<uint64_t> presents{0};
  std::atomic<uint64_t> slow_instant_45{0};
  std::atomic<uint64_t> gaps_50{0};
  std::atomic<uint64_t> gaps_100{0};
  std::atomic<uint64_t> max_gap_us{0};
  std::atomic<uint64_t> guest_timer_calls{0};
  std::atomic<uint64_t> guest_over_40{0};
  std::atomic<uint64_t> guest_over_67{0};
  std::atomic<uint64_t> guest_clamps{0};
  std::atomic<uint64_t> guest_clipped_us{0};
  std::atomic<uint64_t> guest_peak_clipped_us{0};
  std::atomic<uint64_t> fixed_calls{0};
  std::atomic<uint64_t> fixed_clamps{0};
  std::atomic<uint64_t> fixed_clipped_us{0};
  std::atomic<uint64_t> fixed_peak_clipped_us{0};
  std::atomic<uint64_t> camera_updates{0};
  std::atomic<uint64_t> camera_long_gaps{0};
  std::atomic<uint64_t> camera_jumps{0};
  std::atomic<uint64_t> target_jumps{0};
  std::atomic<uint64_t> camera_near_hitch{0};
  std::atomic<uint64_t> target_near_hitch{0};
  std::atomic<uint64_t> collisions{0};
  std::atomic<uint64_t> published{0};
  std::atomic<uint64_t> publish_jumps{0};
  std::atomic<uint64_t> rig_deviations{0};
  std::atomic<uint64_t> publish_near_hitch{0};
  std::atomic<uint64_t> relative_samples{0};
  std::atomic<uint64_t> relative_steps_05m{0};
  std::atomic<uint64_t> relative_steps_15m{0};
  std::atomic<uint64_t> relative_steps_near_gap{0};
  std::atomic<uint64_t> relative_step_mm_sum{0};
  std::atomic<uint64_t> relative_step_max_mm{0};
} g_stats;

void Increment(std::atomic<uint64_t>& count, bool condition = true) {
  if (condition) count.fetch_add(1, std::memory_order_relaxed);
}

bool RecentlyHitch(uint64_t now_us) {
  const uint64_t at = g_last_hitch_us.load(std::memory_order_relaxed);
  // Only *after* a presentation gap; never infer that an event caused a stall.
  return at && now_us >= at && now_us - at <= kNearbyHitchUs;
}

void UpdateMax(std::atomic<uint64_t>& max_value, uint64_t value) {
  auto old = max_value.load(std::memory_order_relaxed);
  while (value > old && !max_value.compare_exchange_weak(
             old, value, std::memory_order_relaxed)) {
  }
}

void Report() {
  // Single read/reset per 10 seconds. Cross-thread atomic exchanges are
  // approximate window boundaries, not a synchronized sample snapshot.
  const auto get = [](std::atomic<uint64_t>& v) {
    return v.exchange(0, std::memory_order_relaxed);
  };
  const uint64_t presents = get(g_stats.presents);
  const uint64_t below45 = get(g_stats.slow_instant_45);
  const uint64_t gaps50 = get(g_stats.gaps_50);
  const uint64_t gaps100 = get(g_stats.gaps_100);
  const uint64_t max_gap = get(g_stats.max_gap_us);
  const uint64_t timer = get(g_stats.guest_timer_calls);
  const uint64_t over40 = get(g_stats.guest_over_40);
  const uint64_t over67 = get(g_stats.guest_over_67);
  const uint64_t clamps = get(g_stats.guest_clamps);
  const uint64_t timer_clipped_us = get(g_stats.guest_clipped_us);
  const uint64_t timer_peak_us = get(g_stats.guest_peak_clipped_us);
  const uint64_t fixed_calls = get(g_stats.fixed_calls);
  const uint64_t fixed_clamps = get(g_stats.fixed_clamps);
  const uint64_t fixed_clipped_us = get(g_stats.fixed_clipped_us);
  const uint64_t fixed_peak_us = get(g_stats.fixed_peak_clipped_us);
  const uint64_t cam = get(g_stats.camera_updates);
  const uint64_t long_cam = get(g_stats.camera_long_gaps);
  const uint64_t cam_jump = get(g_stats.camera_jumps);
  const uint64_t target_jump = get(g_stats.target_jumps);
  const uint64_t cam_near = get(g_stats.camera_near_hitch);
  const uint64_t target_near = get(g_stats.target_near_hitch);
  const uint64_t collisions = get(g_stats.collisions);
  const uint64_t published = get(g_stats.published);
  const uint64_t pub_jump = get(g_stats.publish_jumps);
  const uint64_t deviations = get(g_stats.rig_deviations);
  const uint64_t pub_near = get(g_stats.publish_near_hitch);
  const uint64_t offset_samples = get(g_stats.relative_samples);
  const uint64_t offset05 = get(g_stats.relative_steps_05m);
  const uint64_t offset15 = get(g_stats.relative_steps_15m);
  const uint64_t offset_near = get(g_stats.relative_steps_near_gap);
  const uint64_t offset_sum_mm = get(g_stats.relative_step_mm_sum);
  const uint64_t offset_max_mm = get(g_stats.relative_step_max_mm);

  REXLOG_INFO(
      "MCLA hitch correlate: present={} intervals_above_22ms={} gap50={} "
      "gap100={} max_gap_ms={:.2f} guest_calls={} guest40={} guest67={} "
      "clamps={} camera_updates={} long_camera_gaps={} camera_jumps={} "
      "target_jumps={} camera_near_gap={} target_near_gap={} "
      "collision_shifts={} matrix_publishes={} publish_jumps={} "
      "rig_deviations={} publish_near_gap={} relative_samples={} "
      "relative_above_05m={} relative_above_15m={} relative_near_gap={} "
      "relative_avg_mm={:.1f} relative_max_mm={} "
      "timer_clipped_ms={:.2f} timer_max_clip_ms={:.2f} "
      "fixed_calls={} fixed_clamps={} fixed_clipped_ms={:.2f} "
      "fixed_max_clip_ms={:.2f}",
      presents, below45, gaps50, gaps100, double(max_gap) / 1000.0,
      timer, over40, over67, clamps, cam, long_cam, cam_jump,
      target_jump, cam_near, target_near, collisions, published,
      pub_jump, deviations, pub_near, offset_samples, offset05, offset15,
      offset_near,
      offset_samples ? double(offset_sum_mm) / double(offset_samples) : 0.0,
      offset_max_mm, double(timer_clipped_us) / 1000.0,
      double(timer_peak_us) / 1000.0, fixed_calls, fixed_clamps,
      double(fixed_clipped_us) / 1000.0, double(fixed_peak_us) / 1000.0);
}
}  // namespace

bool MclaHitchCorrelationEnabled() {
  return REXCVAR_GET(mcla_hitch_correlation);
}

void MclaCorrelatePresent(uint64_t now_us, uint64_t interval_us) {
  thread_local uint64_t start_us = 0;
  if (!MclaHitchCorrelationEnabled()) {
    start_us = 0;
    return;
  }
  if (!start_us) {
    start_us = now_us;
    REXLOG_INFO("MCLA hitch correlate: read-only 10-second correlation started");
  }
  Increment(g_stats.presents);
  Increment(g_stats.slow_instant_45, interval_us > UINT64_C(22222));
  if (interval_us >= UINT64_C(50000)) {
    Increment(g_stats.gaps_50);
    if (interval_us >= UINT64_C(100000)) Increment(g_stats.gaps_100);
    g_last_hitch_us.store(now_us, std::memory_order_relaxed);
  }
  UpdateMax(g_stats.max_gap_us, interval_us);
  if (now_us - start_us >= kReportIntervalUs) {
    Report();
    start_us = now_us;
  }
}

void MclaCorrelateGuestTimer(uint64_t measured_ticks, uint64_t applied_ticks) {
  if (!MclaHitchCorrelationEnabled()) return;
  const double hz = double(rex::chrono::Clock::guest_tick_frequency());
  if (hz <= 0.0) return;
  const double ms = double(measured_ticks) * 1000.0 / hz;
  Increment(g_stats.guest_timer_calls);
  Increment(g_stats.guest_over_40, ms > 40.0);
  Increment(g_stats.guest_over_67, ms > 67.0);
  const bool clipped = measured_ticks > applied_ticks;
  Increment(g_stats.guest_clamps, clipped);
  if (clipped) {
    const auto us = static_cast<uint64_t>(
        (double(measured_ticks - applied_ticks) / hz) * 1000000.0);
    g_stats.guest_clipped_us.fetch_add(us, std::memory_order_relaxed);
    UpdateMax(g_stats.guest_peak_clipped_us, us);
  }
}

void MclaCorrelateFixedStep(double measured_s, double applied_s) {
  if (!MclaHitchCorrelationEnabled()) return;
  if (!(measured_s >= 0.0) || !(applied_s >= 0.0)) return;
  Increment(g_stats.fixed_calls);
  if (measured_s > applied_s) {
    Increment(g_stats.fixed_clamps);
    const double lost_s = measured_s - applied_s;
    // Ignore corrupt/nonphysical time deltas. Very long loading intervals
    // are reported separately from driving by the report's warmup filter.
    if (lost_s < 3600.0) {
      const auto us = static_cast<uint64_t>(lost_s * 1000000.0);
      g_stats.fixed_clipped_us.fetch_add(us, std::memory_order_relaxed);
      UpdateMax(g_stats.fixed_peak_clipped_us, us);
    }
  }
}

void MclaCorrelateCamera(uint64_t now_us, bool target_jump, bool camera_jump,
                         bool long_camera_gap, bool collision_shift) {
  if (!MclaHitchCorrelationEnabled()) return;
  Increment(g_stats.camera_updates);
  Increment(g_stats.camera_long_gaps, long_camera_gap);
  Increment(g_stats.target_jumps, target_jump);
  Increment(g_stats.camera_jumps, camera_jump);
  Increment(g_stats.collisions, collision_shift);
  if (target_jump || camera_jump) {
    const bool near = RecentlyHitch(now_us);
    Increment(g_stats.target_near_hitch, near && target_jump);
    Increment(g_stats.camera_near_hitch, near && camera_jump);
  }
}

void MclaCorrelatePublish(uint64_t now_us, bool matrix_jump, bool rig_deviation,
                          bool offset_comparable, float offset_change_m) {
  if (!MclaHitchCorrelationEnabled()) return;
  Increment(g_stats.published);
  Increment(g_stats.publish_jumps, matrix_jump);
  Increment(g_stats.rig_deviations, rig_deviation);
  Increment(g_stats.publish_near_hitch,
            matrix_jump && RecentlyHitch(now_us));
  if (offset_comparable && offset_change_m >= 0.0f &&
      offset_change_m < 1000000.0f) {
    const uint64_t mm = static_cast<uint64_t>(offset_change_m * 1000.0f);
    Increment(g_stats.relative_samples);
    Increment(g_stats.relative_steps_05m, offset_change_m > 0.5f);
    Increment(g_stats.relative_steps_15m, offset_change_m > 1.5f);
    Increment(g_stats.relative_steps_near_gap,
              offset_change_m > 1.5f && RecentlyHitch(now_us));
    g_stats.relative_step_mm_sum.fetch_add(mm, std::memory_order_relaxed);
    UpdateMax(g_stats.relative_step_max_mm, mm);
  }
}
