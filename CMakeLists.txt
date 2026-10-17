# mcla - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(mcla LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(MCLA_SOURCES
    src/main.cpp
    src/mcla_app.cpp
    src/crash_trace.cpp
    src/audio_fallback.cpp
    src/frame_timing.cpp
    src/motion_probe.cpp
    src/hitch_correlation.cpp
    src/fps_overlay.cpp
    src/render_perf.cpp
    src/perf_options.cpp
    src/warp_fix.cpp
    src/button_prompts.cpp
    src/settings_menu.cpp
    src/sampling_profiler.cpp
    src/code_pointer_scan.cpp
)

if(WIN32)
    add_executable(mcla WIN32 ${MCLA_SOURCES})
else()
    add_executable(mcla ${MCLA_SOURCES})
endif()

rexglue_setup_target(mcla)

# The presenter effects are only offered in-game when the SDK was built with
# optional FidelityFX. The default/PS5 build must not show unusable choices.
option(MCLA_ENABLE_FIDELITYFX_MENU "Expose built FidelityFX controls in the MCLA menu" OFF)
if(WIN32 AND MCLA_ENABLE_FIDELITYFX_MENU)
    target_compile_definitions(mcla PRIVATE MCLA_FIDELITYFX_MENU=1)
endif()

# The fast SDK build compiles out rex::perf::GetSnapshotCounter entirely.
# Guard the game's development-only A/B draw counter on this build mode.
option(MCLA_REX_PERF_COUNTERS "SDK has the ReXGlue performance snapshot API" OFF)
if(MCLA_REX_PERF_COUNTERS)
    target_compile_definitions(mcla PRIVATE MCLA_HAS_REX_PERF_COUNTERS=1)
endif()

if(WIN32)
    # timeBeginPeriod for the frame limiter.
    target_link_libraries(mcla PRIVATE winmm)
endif()
