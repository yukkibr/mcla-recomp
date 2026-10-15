#!/usr/bin/env python3
"""Analyze per-frame ReXGlue spikes, not just average FPS.

Usage: python scripts/report_frame_spikes.py out/runs/profile-...-frames.csv
The report is intentionally observational: association != proven root cause.
"""
import argparse
import csv
import math
import statistics
import sys
from pathlib import Path


def number(value):
    try:
        x = float(str(value).strip().replace(",", "."))
        return x if math.isfinite(x) else None
    except (ValueError, TypeError):
        return None


def percentile(values, p):
    a = sorted(values)
    if not a:
        return None
    index = (len(a) - 1) * p / 100
    lo, hi = math.floor(index), math.ceil(index)
    return a[lo] + (a[hi] - a[lo]) * (index - lo)


def pretty(value, places=1):
    return "-" if value is None else f"{value:,.{places}f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("frames_csv", type=Path)
    ap.add_argument("--warmup", type=float, default=30.0,
                    help="Ignore first N seconds of frames (default 30)")
    ap.add_argument("--slow-ms", type=float, default=50.0,
                    help="Spike threshold in ms (default 50)")
    ap.add_argument("--top", type=int, default=20)
    args = ap.parse_args()
    # Windows consoles may use CP1252; keep report generation functional.
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='replace')
    if not args.frames_csv.is_file():
        ap.error(f"CSV not found: {args.frames_csv}")
    source = []
    elapsed = 0.0
    with args.frames_csv.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if "frame_time_us" not in (reader.fieldnames or []):
            ap.error("Expected ReXGlue's REX_PERF_LOG_CSV frame counter format")
        for raw in reader:
            duration = number(raw.get("frame_time_us"))
            if duration is None or duration <= 0:
                continue
            elapsed += duration / 1e6
            if elapsed <= args.warmup:
                continue
            d = {k: number(v) for k, v in raw.items()}
            d["elapsed_s"] = elapsed
            d["frame_ms"] = duration / 1000
            source.append(d)
    if not source:
        ap.error("No usable frames after warmup. Try --warmup 0.")
    slow = [v for v in source if v["frame_ms"] >= args.slow_ms]
    fast = [v for v in source if v["frame_ms"] < args.slow_ms]
    slow_misses = sum((r.get("texture_cache_misses") or 0) > 0 for r in slow)
    fast_misses = sum((r.get("texture_cache_misses") or 0) > 0 for r in fast)
    slow_pipelines = sum((r.get("pipeline_cache_misses") or 0) > 0 for r in slow)
    total_seconds = sum(r["frame_ms"] for r in source) / 1000
    frames = [r["frame_ms"] for r in source]
    lines = [
        "# MCLA / ReXGlue — frame spike report",
        "",
        f"- File: {args.frames_csv.name}",
        f"- Analyzed: {pretty(total_seconds)} seconds after ignoring first {args.warmup:g}s",
        f"- Frames: {len(source):,}  •  Mean FPS: {pretty(len(source)/total_seconds)}",
        f"- Frametime: P50 {pretty(percentile(frames, 50))}ms · "
        f"P95 {pretty(percentile(frames, 95))}ms · "
        f"P99 {pretty(percentile(frames, 99))}ms · Max {pretty(max(frames))}ms",
        f"- Spikes ≥{args.slow_ms:g}ms: **{len(slow):,} ({100*len(slow)/len(source):.2f}%)**",
        f"- Slow frames with new D3D12 SRV descriptors: **{slow_misses}/{len(slow)}**" if slow
        else "- No frame exceeded the selected spike threshold.",
        f"- Normal frames with new SRV descriptors: {fast_misses}/{len(fast)}" if fast
        else "- No normal frames for comparison.",
        f"- Slow frames with pipeline cache misses: {slow_pipelines}/{len(slow)}" if slow
        else "- No slow frames with pipeline miss counters.",
        "",
        "These counters are correlations, not definitive attribution.",
        "IMPORTANT: texture_cache_misses in this D3D12 SDK counts a missing "
        "shader-resource-view (SRV) descriptor, NOT a disk or texture-data cache miss.",
        "New *_us counters measure CPU work for resource creation, "
        "shared-memory requests and GPU upload command preparation, "
        "NOT GPU execution time or disk IO.",
        "Pipeline cache hits/misses do not fully describe async shader compilation.",
        "",
        "## Counters: median normal versus slow frames",
        "",
        "| Counter | Normal | Slow |",
        "|---|---:|---:|",
    ]
    for key in ("draw_calls", "command_buffer_stalls", "texture_cache_misses",
                "texture_descriptor_create_us", "texture_resource_create_us",
                "texture_resident_request_us", "texture_upload_dispatch_us",
                "texture_upload_requests",
                "pipeline_cache_misses", "functions_dispatched", "interrupt_dispatches",
                "active_threads", "buffer_queue_depth"):
        a = [r[key] for r in fast if r.get(key) is not None]
        b = [r[key] for r in slow if r.get(key) is not None]
        if a or b:
            lines.append(f"| {key} | {pretty(statistics.median(a) if a else None, 0)} "
                         f"| {pretty(statistics.median(b) if b else None, 0)} |")
    lines.extend([
        "",
        "## Worst individual frames",
        "",
        "| Elapsed | Frame | Draws | SRV misses | SRV create ms | Resource create ms | Upload prep ms | Resident request ms | Upload requests |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ])
    for f in sorted(source, key=lambda x: x["frame_ms"], reverse=True)[:args.top]:
        def n(key):
            val = f.get(key)
            return "-" if val is None else str(int(val))
        def ms(key):
            val = f.get(key)
            return "-" if val is None else f"{val/1000:.2f}"
        lines.append(f"| {f['elapsed_s']:.1f}s | {f['frame_ms']:.1f}ms | "
                     f"{n('draw_calls')} | {n('texture_cache_misses')} | "
                     f"{ms('texture_descriptor_create_us')} | {ms('texture_resource_create_us')} | "
                     f"{ms('texture_upload_dispatch_us')} | {ms('texture_resident_request_us')} | "
                     f"{n('texture_upload_requests')} |")
    lines += ["", "## What to investigate next", ""]
    if slow and slow_misses / len(slow) >= 0.6:
        lines.append("- Many slow frames create new SRV descriptors in D3D12. This is NOT "
                     "proof of streaming misses or cache eviction. Inspect the timed "
                     "descriptor/resource/upload counters before targeting the cause.")
    if slow and slow_pipelines / len(slow) >= 0.3:
        lines.append("- Pipeline cache misses are present in many slow frames. "
                     "Compare Auto vs 4 pipeline workers and warm/cold runs.")
    lines.extend([
        "- Verify whether spikes coincide with dense city sectors or with initial area streaming.",
        "- Compare repeated drives with identical route, traffic settings, render mode and GPU backend.",
        "- Do not treat average FPS or CPU load alone as proof of an optimization.",
        "",
    ])
    report = args.frames_csv.with_name(args.frames_csv.stem + "-spikes.md")
    report.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    print(f"Saved: {report}")


if __name__ == "__main__":
    main()
