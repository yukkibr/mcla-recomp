// Windows DXGI memory budget for the selected dedicated adapter. No GPU stalls.
#include "gpu_vram_budget.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <string>

#include <rex/cvar.h>
#include <rex/logging.h>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#endif

// -1 retains legacy ReXGlue cache settings. 0 picks a safe automatic cap.
// -2 selects the largest safe cap; a positive number asks for that MiB cap.
// This controls ONLY the texture cache, not the entire process's GPU memory.
REXCVAR_DEFINE_INT32(mcla_texture_cache_budget_mb, -1, "MCLA",
                      "Texture cache VRAM budget: -1 legacy, 0 auto, -2 max safe, or MB")
    .range(-2, 8192)
    .lifecycle(rex::cvar::Lifecycle::kRequiresRestart);

namespace {
#if defined(_WIN32)
using Microsoft::WRL::ComPtr;

ComPtr<IDXGIAdapter3> FindDedicatedAdapter() {
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return {};
  ComPtr<IDXGIAdapter3> chosen;
  SIZE_T most_dedicated = 0;
  for (UINT i = 0;; ++i) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(i, &adapter) == DXGI_ERROR_NOT_FOUND) break;
    if (!adapter) continue;
    DXGI_ADAPTER_DESC1 desc{};
    if (FAILED(adapter->GetDesc1(&desc)) || (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE))
      continue;
    ComPtr<IDXGIAdapter3> as3;
    if (FAILED(adapter.As(&as3))) continue;
    if (!chosen || desc.DedicatedVideoMemory > most_dedicated) {
      most_dedicated = desc.DedicatedVideoMemory;
      chosen = as3;
    }
  }
  return chosen;
}
#endif

MclaGpuVramSnapshot Sample() {
  MclaGpuVramSnapshot out{};
#if defined(_WIN32)
  static const auto adapter = FindDedicatedAdapter();
  if (!adapter) return out;
  DXGI_ADAPTER_DESC desc{};
  if (FAILED(adapter->GetDesc(&desc))) return out;
  DXGI_QUERY_VIDEO_MEMORY_INFO info{};
  if (FAILED(adapter->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &info)))
    return out;
  const uint64_t mib = 1024ull * 1024ull;
  out.dedicated_mib = desc.DedicatedVideoMemory / mib;
  out.budget_mib = info.Budget / mib;
  out.used_mib = info.CurrentUsage / mib;
  out.reservation_mib = info.CurrentReservation / mib;
  // Windows may allocate fewer bytes than the physical VRAM. Keep room
  // for the framebuffer, shaders, driver, desktop and other applications.
  // A larger cache cannot force the GPU to have more memory.
  const uint64_t max_safe = std::min({
      out.dedicated_mib * 3 / 4,
      out.budget_mib * 3 / 4,
      out.budget_mib > 1024 ? out.budget_mib - 1024 : uint64_t(0),
      uint64_t(8192)});
  out.safe_texture_cache_mib = uint32_t(max_safe);
  out.valid = out.dedicated_mib > 0 && out.budget_mib >= 512;
#endif
  return out;
}
}

MclaGpuVramSnapshot MclaReadGpuVram() {
  using Clock = std::chrono::steady_clock;
  static MclaGpuVramSnapshot cached{};
  static Clock::time_point previous{};
  const auto now = Clock::now();
  if (previous == Clock::time_point{} ||
      now - previous >= std::chrono::seconds(2)) {
    cached = Sample();
    previous = now;
  }
  return cached;
}

void MclaConfigureTextureCacheBudget() {
  const int requested = REXCVAR_GET(mcla_texture_cache_budget_mb);
  const auto vram = MclaReadGpuVram();
  if (!vram.valid) {
    REXLOG_WARN("MCLA VRAM: DXGI dedicated budget unavailable; retain existing texture limits");
    return;
  }
  REXLOG_INFO("MCLA VRAM DXGI: dedicated={} MiB budget={} MiB usage={} MiB "
              "reservation={} MiB safe_cache_max={} MiB",
              vram.dedicated_mib, vram.budget_mib, vram.used_mib,
              vram.reservation_mib, vram.safe_texture_cache_mib);
  if (requested == -1) {
    REXLOG_INFO("MCLA VRAM cache: LEGACY, original ReXGlue texture limits preserved");
    return;
  }
  if (vram.safe_texture_cache_mib < 512) {
    REXLOG_WARN("MCLA VRAM: insufficient safe budget to override existing texture limits");
    return;
  }
  // AUTO uses half the safe cache headroom; MAX SAFE uses the full
  // headroom. Manual requests are always bounded by that headroom.
  const uint32_t wanted = requested == -2 ? vram.safe_texture_cache_mib :
      requested == 0 ? std::min(uint32_t(2048), vram.safe_texture_cache_mib / 2) :
      uint32_t(requested);
  const uint32_t hard = std::clamp(wanted, uint32_t(512),
                                  vram.safe_texture_cache_mib);
  const uint32_t soft = std::clamp(hard * 3 / 4, uint32_t(384),
                                  uint32_t(4096));
  rex::cvar::SetFlagByName("texture_cache_memory_limit_hard", std::to_string(hard));
  rex::cvar::SetFlagByName("texture_cache_memory_limit_soft", std::to_string(
      std::min(soft, hard)));
  REXLOG_INFO("MCLA VRAM cache selection={} effective_soft={} MiB "
              "effective_hard={} MiB (other GPU allocations NOT included)",
              requested, std::min(soft, hard), hard);
}
