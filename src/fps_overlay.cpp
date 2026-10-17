// Lightweight, in-game FPS/frametime HUD.
// Uses the existing ReXGlue ImGui presenter (no external window or DX12 hooks).
#include "fps_overlay.h"

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
    const ImVec2 size(183.0f, 62.0f);
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
        ImGui::Text("FPS  %.1f", stats.fps);
        ImGui::TextDisabled("%.1f ms  |  max %.1f ms", stats.frame_time_ms,
                            stats.worst_frame_ms);
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
  if (last_us && now > last_us) {
    const uint64_t delta = now - last_us;
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
