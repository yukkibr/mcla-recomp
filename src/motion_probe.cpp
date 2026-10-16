// Read-only camera/target motion probe for rare vehicle + camera flick.
// Only enabled with --mcla_motion_probe=true. No guest state is modified.
#include "generated/default/mcla_init.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/runtime.h>

REXCVAR_DEFINE_BOOL(mcla_motion_probe, false, "MCLA",
                    "Sample camera target, camera position and collision corrections to locate visual jumps")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

namespace {
struct Vec3 {
  float x, y, z;
};
struct State {
  uint32_t cs = 0;
  uint32_t owner = 0;
  Vec3 previous_target{};
  Vec3 previous_camera{};
  uint64_t last_us = 0;
  uint64_t last_seen_us = 0;
};
struct Summary {
  uint64_t start_us = 0;
  uint32_t samples = 0;
  uint32_t target_jumps = 0;
  uint32_t camera_jumps = 0;
  uint32_t collision_shifts = 0;
  float peak_target_step = 0.0f;
  float peak_camera_step = 0.0f;
  float peak_collision_shift = 0.0f;
  uint32_t distinct_states = 0;
  uint32_t event_logs = 0;
  uint32_t publish_samples = 0;
  uint32_t publish_jumps = 0;
  uint32_t source_mismatches = 0;
  float peak_publish_step = 0.0f;
  float peak_source_difference = 0.0f;
};
thread_local std::array<State, 8> g_states{};
thread_local Summary g_summary{};

// Camera matrix handed to the cine director for rendering, independently of
// the simulation camera state's pre-publish update.
thread_local Vec3 g_last_rig_camera{};
thread_local uint64_t g_last_rig_time_us = 0;
thread_local Vec3 g_last_published_camera{};
thread_local uint64_t g_last_publish_time_us = 0;
thread_local uint32_t g_publish_event_logs = 0;

uint64_t NowUs() {
  return uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now().time_since_epoch()).count());
}
bool PlausibleAddress(uint32_t ea, uint32_t bytes) {
  // The validated guest game arena spans low address 0x82000000... and high
  // dynamic pointers 0xB... ; reject null/overflow before host reads.
  return ea >= 0x10000u && uint64_t(ea) + bytes <= UINT64_C(0x100000000);
}
uint32_t ReadU32(uint32_t ea) {
  const uint8_t* p = rex::Runtime::instance()->virtual_membase() + ea;
  return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 |
         uint32_t(p[2]) << 8 | uint32_t(p[3]);
}
float ReadFloat(uint32_t ea) {
  const uint32_t bits = ReadU32(ea);
  float value;
  std::memcpy(&value, &bits, sizeof(value));
  return value;
}
Vec3 ReadPos(uint32_t ea) {
  return {ReadFloat(ea), ReadFloat(ea + 4), ReadFloat(ea + 8)};
}
bool Finite(Vec3 a) {
  return std::isfinite(a.x) && std::isfinite(a.y) &&
         std::isfinite(a.z) && std::fabs(a.x) < 1000000.0f &&
         std::fabs(a.y) < 1000000.0f && std::fabs(a.z) < 1000000.0f;
}
float Distance(Vec3 a, Vec3 b) {
  const float dx=a.x-b.x,dy=a.y-b.y,dz=a.z-b.z;
  return std::sqrt(dx*dx + dy*dy + dz*dz);
}
void FlushIfDue(uint64_t now) {
  if (!g_summary.start_us) {
    g_summary.start_us = now;
    return;
  }
  if (now - g_summary.start_us < UINT64_C(5000000)) {
    return;
  }
  if (g_summary.samples) {
    REXLOG_INFO(
      "MCLA motion probe: {} camera updates, {} distinct rigs, target jumps {}, "
      "camera jumps {}, collision shifts {}, peak target {:.2f}m, "
      "peak camera {:.2f}m, peak collision {:.2f}m (last 5s)",
      g_summary.samples, g_summary.distinct_states, g_summary.target_jumps,
      g_summary.camera_jumps, g_summary.collision_shifts,
      g_summary.peak_target_step, g_summary.peak_camera_step,
      g_summary.peak_collision_shift);
  }
  if (g_summary.publish_samples) {
    REXLOG_INFO(
      "MCLA camera publish probe: {} matrix publishes, jumps {}, "
      "nearby-rig deviations {}, peak publish {:.2f}m, "
      "peak distance to rig {:.2f}m (last 5s)",
      g_summary.publish_samples, g_summary.publish_jumps,
      g_summary.source_mismatches, g_summary.peak_publish_step,
      g_summary.peak_source_difference);
  }
  g_summary = {};
  g_publish_event_logs = 0;
  g_summary.start_us = now;
}
State& FindState(uint32_t cs, uint64_t now) {
  for (auto& s : g_states) {
    if (s.cs == cs) {
      return s;
    }
  }
  State* oldest = &g_states[0];
  for (auto& s : g_states) {
    if (!s.cs) {
      oldest = &s;
      break;
    }
    if (s.last_seen_us < oldest->last_seen_us) {
      oldest = &s;
    }
  }
  *oldest = {};
  oldest->cs = cs;
  oldest->last_seen_us = now;
  ++g_summary.distinct_states;
  return *oldest;
}
} // namespace

// sub_8231CE30 @0x8231CEE0, AFTER the optional camera collision passes.
// Compare the updated rig target and final camera positions across ticks.
void mcla_camera_motion_post(PPCRegister& r31) {
  if (!REXCVAR_GET(mcla_motion_probe)) {
    return;
  }
  const uint32_t cs = r31.u32;
  if (!PlausibleAddress(cs, 512)) {
    return;
  }
  auto* runtime = rex::Runtime::instance();
  if (!runtime || !runtime->virtual_membase()) {
    return;
  }
  const uint32_t owner = ReadU32(cs + 192);
  if (!owner) {
    return; // Ignore inactive camera states.
  }
  const Vec3 camera = ReadPos(cs + 64);       // Camera matrix at cs+16, row 3.
  const Vec3 target = ReadPos(cs + 320);      // Camera target/follow point.
  if (!Finite(camera) || !Finite(target)) {
    return;
  }
  // The alternative cs+80 camera matrix is ONLY selected when cs+156 says
  // collision was resolved this frame. Without that flag, it may contain
  // an unrelated/stale pose from initialization and produce false 1km deltas.
  const uint32_t collision_type = ReadU32(cs + 464);
  const bool collision_active = collision_type != 0 &&
      *(runtime->virtual_membase() + cs + 156) != 0;
  Vec3 collided{};
  if (collision_active) {
    collided = ReadPos(cs + 128);
  }

  const uint64_t now = NowUs();
  FlushIfDue(now);
  State& state = FindState(cs, now);
  // Switching follow objects, camera modes, entering cutscenes or after a
  // multi-second pause is NOT counted as a movement discontinuity.
  const bool comparable = state.owner == owner && state.last_us &&
      now > state.last_us && now - state.last_us < UINT64_C(120000);
  const float target_step = comparable ? Distance(target, state.previous_target) : 0.0f;
  const float camera_step = comparable ? Distance(camera, state.previous_camera) : 0.0f;
  const float collision_shift =
      collision_active && Finite(collided) ? Distance(camera, collided) : 0.0f;
  ++g_summary.samples;
  g_summary.peak_target_step = std::max(g_summary.peak_target_step, target_step);
  g_summary.peak_camera_step = std::max(g_summary.peak_camera_step, camera_step);
  g_summary.peak_collision_shift = std::max(g_summary.peak_collision_shift,
                                             collision_shift);
  // These thresholds are diagnostics, not a judgment that such a camera
  // motion is necessarily invalid. Fast turns, crashes and cinematic rigs
  // can legitimately trigger them.
  const bool jump_target = comparable && target_step > 6.0f;
  const bool jump_camera = comparable && camera_step > 6.0f;
  const bool collision = collision_shift > 5.0f;
  g_summary.target_jumps += jump_target;
  g_summary.camera_jumps += jump_camera;
  g_summary.collision_shifts += collision;
  if ((jump_target || jump_camera || collision) && g_summary.event_logs < 4) {
    const float delta_ms = comparable ? float(now-state.last_us)/1000.0f : 0.0f;
    REXLOG_INFO(
      "MCLA motion event: rig=0x{:08X} owner=0x{:08X} dt={:.1f}ms "
      "target_step={:.2f}m camera_step={:.2f}m collision_shift={:.2f}m",
      cs, owner, delta_ms, target_step, camera_step, collision_shift);
    ++g_summary.event_logs;
  }
  state.owner = owner;
  state.previous_target = target;
  state.previous_camera = camera;
  state.last_us = now;
  state.last_seen_us = now;
  // A candidate for matching the camera passed to the render pipeline.
  g_last_rig_camera = camera;
  g_last_rig_time_us = now;
}

// sub_8220AA68 @0x8220AA88: r30 points to the matrix passed from the
// game's camera state into the cine director/presentation pipeline.
// Read only. This probe deliberately does NOT alter the camera matrix.
void mcla_camera_motion_publish(PPCRegister& r30) {
  if (!REXCVAR_GET(mcla_motion_probe)) {
    return;
  }
  const uint32_t matrix = r30.u32;
  if (!PlausibleAddress(matrix, 64)) {
    return;
  }
  auto* runtime = rex::Runtime::instance();
  if (!runtime || !runtime->virtual_membase()) {
    return;
  }
  const Vec3 published = ReadPos(matrix + 48);
  if (!Finite(published)) {
    return;
  }
  const uint64_t now = NowUs();
  FlushIfDue(now);
  const bool comparable = g_last_publish_time_us &&
      now > g_last_publish_time_us &&
      now - g_last_publish_time_us < UINT64_C(120000);
  const float published_step = comparable ?
      Distance(published, g_last_published_camera) : 0.0f;
  // A match to the most recently updated rig is not guaranteed:
  // different active rigs, shake and cinematic systems may be involved.
  const bool recent_rig = g_last_rig_time_us &&
      now >= g_last_rig_time_us &&
      now - g_last_rig_time_us < UINT64_C(50000);
  const float rig_difference = recent_rig ?
      Distance(published, g_last_rig_camera) : 0.0f;

  ++g_summary.publish_samples;
  const bool jump = comparable && published_step > 6.0f;
  const bool deviation = recent_rig && rig_difference > 3.0f;
  g_summary.publish_jumps += jump;
  g_summary.source_mismatches += deviation;
  g_summary.peak_publish_step = std::max(
      g_summary.peak_publish_step, published_step);
  g_summary.peak_source_difference = std::max(
      g_summary.peak_source_difference, rig_difference);
  if ((jump || deviation) && g_publish_event_logs < 4) {
    REXLOG_INFO(
      "MCLA camera publish event: matrix=0x{:08X}, delta {:.1f}ms, "
      "step {:.2f}m, to last updated rig {:.2f}m, recent rig {}",
      matrix, comparable ? double(now-g_last_publish_time_us)/1000.0 : 0.0,
      published_step, rig_difference, recent_rig);
    ++g_publish_event_logs;
  }
  g_last_published_camera = published;
  g_last_publish_time_us = now;
}
