#pragma once

#include <cstdint>

// Experimental, read-only cross-thread correlation of present stalls,
// guest timer clamps and camera/publish discontinuities. No state mutation.
bool MclaHitchCorrelationEnabled();
void MclaCorrelatePresent(uint64_t now_us, uint64_t interval_us);
void MclaCorrelateGuestTimer(uint64_t measured_ticks, uint64_t applied_ticks);
void MclaCorrelateFixedStep(double measured_s, double applied_s);
void MclaCorrelateCamera(uint64_t now_us, bool target_jump, bool camera_jump,
                         bool long_camera_gap, bool collision_shift);
void MclaCorrelatePublish(uint64_t now_us, bool matrix_jump, bool rig_deviation,
                          bool offset_comparable, float offset_change_m);
