#pragma once

#include <cstdint>
#include <memory>

namespace rex::ui {
class ImGuiDialog;
class ImGuiDrawer;
}

struct MclaFpsSnapshot {
  double fps = 0.0;
  double frame_time_ms = 0.0;
  double worst_frame_ms = 0.0;
  uint64_t frame_count = 0;
};

// Observe guest present requests, without ReXGlue's expensive CSV counters.
void MclaRecordGuestPresent();
MclaFpsSnapshot MclaReadGuestFps();
std::unique_ptr<rex::ui::ImGuiDialog> MclaCreateFpsHud(rex::ui::ImGuiDrawer* drawer);
