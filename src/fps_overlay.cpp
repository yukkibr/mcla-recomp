// Lightweight, in-game FPS/frametime HUD.
// Uses the existing ReXGlue ImGui presenter (no external window or DX12 hooks).
#include "fps_overlay.h"
#include "hitch_correlation.h"

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>

#include <imgui.h>
#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/ui/imgui_dialog.h>
#include <rex/ui/imgui_drawer.h>

REXCVAR_DEFINE_BOOL(mcla_show_fps, false, "MCLA",
                    "Display guest present FPS, average frametime and peak frametime");

// Opt-in 10-second samples for real A/B tests. Does not touch GPU timing,
// resource uploads or the existing FPS overlay.
REXCVAR_DEFINE_BOOL(mcla_fps_benchmark, false, "MCLA",
                    "Log 10-second guest present FPS, p99 frametime and stalls");

namespace {
std::atomic<uint32_t> g_fps_hundredths{0};
std::atomic<uint32_t> g_frame_ms_hundredths{0};
std::atomic<uint32_t> g_peak_ms_hundredths{0};
std::atomic<uint64_t> g_frames{0};

uint64_t NowMicros() {
  return uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(
                      std::chrono::steady_clock::now().time_since_epoch())
                      .count());
}

// One fixed-size histogram per presenting thread; no per-frame allocations,
// sorting or GPU queries. Bucket 256 means 256 ms or more.
struct BenchmarkWindow {
  uint64_t start_us = 0;
  uint64_t previous_us = 0;
  uint64_t accumulated_us = 0;
  uint64_t maximum_us = 0;
  uint32_t frames = 0;
  uint32_t stalls_50 = 0;
  uint32_t stalls_100 = 0;
  std::array<uint32_t, 257> histogram{};

  void Reset(uint64_t now_us) {
    start_us = now_us;
    previous_us = now_us;
    accumulated_us = 0;
    maximum_us = 0;
    frames = 0;
    stalls_50 = 0;
    stalls_100 = 0;
    histogram.fill(0);
  }
};

void RecordBenchmarkGuestPresent(uint64_t now_us) {
  thread_local BenchmarkWindow window;
  thread_local bool active = false;
  if (!REXCVAR_GET(mcla_fps_benchmark)) {
    active = false;
    return;
  }
  if (!active) {
    active = true;
    window.Reset(now_us);
    REXLOG_INFO("MCLA FPS benchmark: 10-second guest-present sampling enabled");
    return;
  }
  if (now_us <= window.previous_us) {
    window.Reset(now_us);
    return;
  }

  const uint64_t interval_us = now_us - window.previous_us;
  window.previous_us = now_us;
  window.accumulated_us += interval_us;
  if (interval_us > window.maximum_us) {
    window.maximum_us = interval_us;
  }
  ++window.frames;
  if (interval_us >= 50000) ++window.stalls_50;
  if (interval_us >= 100000) ++window.stalls_100;
  const auto bucket = static_cast<size_t>(
      interval_us >= 256000 ? 256 : interval_us / 1000);
  ++window.histogram[bucket];

  const uint64_t elapsed_us = now_us - window.start_us;
  if (elapsed_us < 10000000) {
    return;
  }

  // 99th percentile of inter-present interval, quantized to 1 ms. A bucket
  // of 256 represents >=256 ms; use maximum_us for exact longest stall.
  const uint32_t rank =
      static_cast<uint32_t>((uint64_t(window.frames) * 99 + 99) / 100);
  uint32_t cumulative = 0;
  size_t p99_bucket = 256;
  for (size_t i = 0; i < window.histogram.size(); ++i) {
    cumulative += window.histogram[i];
    if (cumulative >= rank) {
      p99_bucket = i;
      break;
    }
  }

  REXLOG_INFO(
      "MCLA FPS benchmark: fps={:.2f} avg_ms={:.2f} p99_bucket_ms={} "
      "max_ms={:.2f} stalls50={} stalls100={} frames={} seconds={:.2f}",
      double(window.frames) * 1000000.0 / double(window.accumulated_us),
      double(window.accumulated_us) / (1000.0 * double(window.frames)),
      p99_bucket, double(window.maximum_us) / 1000.0, window.stalls_50,
      window.stalls_100, window.frames, double(elapsed_us) / 1000000.0);
  window.Reset(now_us);
}

class MclaFpsHud final : public rex::ui::ImGuiDialog {
 public:
  explicit MclaFpsHud(rex::ui::ImGuiDrawer* drawer) : ImGuiDialog(drawer) {}

 protected:
  void OnDraw(ImGuiIO& io) override {
    if (!REXCVAR_GET(mcla_show_fps)) {
      return;
    }
    // Verify that the HUD is actually reaching the ImGui paint path, not
    // merely that the saved CVar was loaded. Log once, not on every frame.
    static bool draw_reported = false;
    if (!draw_reported) {
      REXLOG_INFO("MCLA FPS COUNTER HUD render path active");
      draw_reported = true;
    }
    const auto stats = MclaReadGuestFps();
    const ImVec2 size(220.0f, 81.0f);
    ImGui::SetNextWindowPos(ImVec2(io.DisplaySize.x - size.x - 12.0f, 12.0f),
                            ImGuiCond_Always);
    ImGui::SetNextWindowSize(size, ImGuiCond_Always);
    ImGui::SetNextWindowBgAlpha(0.66f);
    const ImGuiWindowFlags flags =
        ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoInputs |
        ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoSavedSettings;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.07f, 0.04f, 0.14f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(0.46f, 0.29f, 0.68f, 0.85f));
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.93f, 0.91f, 0.98f, 1.0f));
    if (ImGui::Begin("##mcla_fps_hud", nullptr, flags)) {
      if (stats.frame_count == 0) {
        ImGui::TextUnformatted("FPS  --");
        ImGui::TextDisabled("Measuring frames...");
      } else {
        ImGui::Text("FPS (0.5s avg)  %.1f", stats.fps);
        ImGui::TextDisabled("Avg frame  %.1f ms", stats.frame_time_ms);
        // A 90ms worst frame is a hitch (~11 FPS for that frame), not 90 FPS.
        ImGui::TextDisabled("Worst frame  %.1f ms", stats.worst_frame_ms);
      }
    }
    ImGui::End();
    ImGui::PopStyleColor(3);
    ImGui::PopStyleVar();
  }
};
}  // namespace

void MclaRecordGuestPresent() {
  // The hook runs on the guest command thread, once per requested present.
  // All UI-visible state is atomic: no locks on the hot path.
  thread_local uint64_t last_us = 0;
  thread_local uint64_t window_start_us = 0;
  thread_local uint64_t peak_delta_us = 0;
  thread_local uint32_t count = 0;

  const uint64_t now = NowMicros();
  RecordBenchmarkGuestPresent(now);
  if (last_us && now > last_us) {
    const uint64_t delta = now - last_us;
    MclaCorrelatePresent(now, delta);
    if (delta > peak_delta_us) {
      peak_delta_us = delta;
    }
  }
  last_us = now;
  if (!window_start_us) {
    window_start_us = now;
    return;
  }
  ++count;
  const uint64_t elapsed = now - window_start_us;
  if (elapsed < 500000) {
    return;
  }
  if (elapsed && count) {
    g_fps_hundredths.store(uint32_t(count * 100000000ull / elapsed),
                            std::memory_order_relaxed);
    g_frame_ms_hundredths.store(uint32_t(elapsed / (10ull * count)),
                                 std::memory_order_relaxed);
    g_peak_ms_hundredths.store(uint32_t(peak_delta_us / 10),
                                std::memory_order_relaxed);
    g_frames.fetch_add(count, std::memory_order_relaxed);
  }
  count = 0;
  peak_delta_us = 0;
  window_start_us = now;
}

MclaFpsSnapshot MclaReadGuestFps() {
  MclaFpsSnapshot out;
  out.frame_count = g_frames.load(std::memory_order_relaxed);
  out.fps = g_fps_hundredths.load(std::memory_order_relaxed) / 100.0;
  out.frame_time_ms = g_frame_ms_hundredths.load(std::memory_order_relaxed) / 100.0;
  out.worst_frame_ms = g_peak_ms_hundredths.load(std::memory_order_relaxed) / 100.0;
  return out;
}

std::unique_ptr<rex::ui::ImGuiDialog> MclaCreateFpsHud(rex::ui::ImGuiDrawer* drawer) {
  return std::make_unique<MclaFpsHud>(drawer);
}
