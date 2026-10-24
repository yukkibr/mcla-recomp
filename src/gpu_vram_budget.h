#pragma once
#include <cstdint>

struct MclaGpuVramSnapshot {
  uint64_t dedicated_mib = 0;
  uint64_t budget_mib = 0;
  uint64_t used_mib = 0;
  uint64_t reservation_mib = 0;
  uint32_t safe_texture_cache_mib = 0;
  bool valid = false;
};

// Reads DXGI adapter-local memory budget without synchronizing GPU execution.
// Cached between UI frames; excludes memory on other adapters.
MclaGpuVramSnapshot MclaReadGpuVram();
void MclaConfigureTextureCacheBudget();
