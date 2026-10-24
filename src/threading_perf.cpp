// Optional MCLA PowerPC data-cache flush loop bypass on coherent x86-64.
// Reference: mzzvxm/LARecomp src/mc_engine/threading.cpp, 0x821D5510.
// Native DCBF/DCBST from guest are already host no-ops in ReXGlue codegen.
#include "generated/default/mcla_init.h"

#include <atomic>
#include <chrono>
#include <cstdint>

#include <rex/cvar.h>
#include <rex/logging.h>

REXCVAR_DEFINE_BOOL(mcla_fast_guest_cache_flush, false, "MCLA",
                    "Replace emulated D-cache line flush loop with a host memory fence")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);
REXCVAR_DEFINE_BOOL(mcla_cache_flush_stats, false, "MCLA",
                    "Log optional 10s counts of data cache flush hook calls")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

// Called only with the generated guest function at 0x821D5510. The jump
// destination 0x821D5544 is the function's BLR, NOT another function.
bool mcla_fast_guest_cache_flush() {
  if (!REXCVAR_GET(mcla_fast_guest_cache_flush)) return false;

  // Full ordering, stronger than needed for many data-cache flush uses;
  // no alignment or block-size assumptions; r3 stays unchanged.
  std::atomic_thread_fence(std::memory_order_seq_cst);

  if (REXCVAR_GET(mcla_cache_flush_stats)) {
    static thread_local uint64_t count = 0;
    static thread_local auto window = std::chrono::steady_clock::now();
    ++count;
    const auto now = std::chrono::steady_clock::now();
    if (now - window >= std::chrono::seconds(10)) {
      REXLOG_INFO("MCLA native cache-flush fence: {} calls per {:.2f} seconds",
                  count, std::chrono::duration<double>(now - window).count());
      count = 0;
      window = now;
    }
  }
  return true;
}
