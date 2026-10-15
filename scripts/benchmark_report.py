#!/usr/bin/env python3
"""Generate repeatable title-screen baseline metrics from Phase 1 runs.

python scripts/benchmark_report.py out/benchmarks/<run-folder>
python scripts/benchmark_report.py out/benchmarks/<run-folder> --compare out/benchmarks/<previous>
"""
import argparse
import csv
import json
import math
import statistics
from pathlib import Path


def load_csv(path: Path):
    if not path.is_file():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def as_float(value):
    # PowerShell Export-Csv uses the user's numeric locale (e.g. pt-BR 1,25).
    return float(str(value).strip().replace(',', '.'))


def quantile(sorted_values, fraction):
    if not sorted_values:
        return None
    at = (len(sorted_values) - 1) * fraction
    lo, hi = math.floor(at), math.ceil(at)
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (at - lo)


def final_seconds(rows, duration_s):
    result, elapsed_us = [], 0.0
    for row in reversed(rows):
        try:
            micros = as_float(row["frame_time_us"])
        except (ValueError, TypeError, KeyError):
            continue
        if micros <= 0:
            continue
        result.append(micros)
        elapsed_us += micros
        if elapsed_us >= duration_s * 1_000_000:
            break
    return result


def median_field(rows, key):
    values = []
    for row in rows:
        try:
            value = as_float(row[key])
            if math.isfinite(value):
                values.append(value)
        except (ValueError, TypeError, KeyError):
            pass
    return round(statistics.median(values), 2) if values else None


def summary(folder: Path, tail_seconds):
    metadata = json.loads((folder / "metadata.json").read_text(encoding="utf-8-sig"))
    result = {"metadata": metadata, "targets": {}}
    for fps in metadata["targets"]:
        fps = str(fps)
        raw = load_csv(folder / f"fps-{fps}-frames.csv")
        times_us = final_seconds(raw, tail_seconds)
        if len(times_us) < 10:
            result["targets"][fps] = {"error": "Insufficient frame data", "frames": len(times_us)}
            continue
        sorted_ms = sorted(t / 1000.0 for t in times_us)
        elapsed_ms = sum(sorted_ms)
        one_percent_low = 1000.0 / quantile(sorted_ms, .99)
        system = load_csv(folder / f"fps-{fps}-system.csv")
        filtered = [row for row in system if as_float(row["elapsed_s"]) >= metadata["seconds"] - tail_seconds]
        result["targets"][fps] = {
            "frames": len(sorted_ms),
            "measured_seconds": round(elapsed_ms / 1000.0, 2),
            "average_fps": round(len(sorted_ms) * 1000 / elapsed_ms, 2),
            "median_frame_ms": round(quantile(sorted_ms, .5), 2),
            "p95_frame_ms": round(quantile(sorted_ms, .95), 2),
            "p99_frame_ms": round(quantile(sorted_ms, .99), 2),
            "one_percent_low_fps_approx": round(one_percent_low, 2),
            "max_frame_ms": round(sorted_ms[-1], 2),
            "over_40ms_pct": round(100 * sum(t > 40 for t in sorted_ms) / len(sorted_ms), 2),
            "median_draw_calls": median_field(raw[-len(times_us):], "draw_calls"),
            "median_gpu_util_pct": median_field(filtered, "gpu_util_pct"),
            "median_gpu_memory_mb": median_field(filtered, "gpu_memory_mb"),
            "median_cpu_one_core_pct": median_field(filtered, "cpu_one_core_pct"),
            "median_process_memory_mb": median_field(filtered, "process_memory_mb"),
        }
    return result


def make_markdown(result, comparison=None):
    meta = result["metadata"]
    lines = [
        "# MCLA Phase 1 - benchmark",
        "",
        f"- Commit: {meta['git_commit'][:12]} ({meta['git_branch']})",
        f"- Backend: {meta['backend']}; preset: {meta['preset']}",
        f"- CPU: {meta['processor']}",
        f"- GPU: {', '.join(g['Name'] for g in meta['gpu'])}",
        f"- Test: {meta['seconds']}s per target; final {meta['tail_seconds']}s analyzed",
        "- Scenario: automated title/menu camera, not a deterministic gameplay replay.",
        "- Run with identical resolution, driver and GPU settings for useful comparisons.",
        "",
        "| Target | Avg FPS | Median (ms) | P95 (ms) | P99 (ms) | 1% low approx | >40 ms | GPU util | CPU (one core) |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for target, data in result["targets"].items():
        if "error" in data:
            lines.append(f"| {target} | {data['error']} | | | | | | | |")
            continue
        def n(k):
            return "-" if data[k] is None else str(data[k])
        lines.append(f"| {target} | {n('average_fps')} | {n('median_frame_ms')} | "
                     f"{n('p95_frame_ms')} | {n('p99_frame_ms')} | {n('one_percent_low_fps_approx')} | "
                     f"{n('over_40ms_pct')}% | {n('median_gpu_util_pct')}% | {n('median_cpu_one_core_pct')}% |")
    if comparison:
        lines.extend(["", "## Compared with previous run", ""])
        for target, data in result["targets"].items():
            old = comparison["targets"].get(target, {})
            if "average_fps" in data and "average_fps" in old and old["average_fps"]:
                diff = 100 * (data["average_fps"] / old["average_fps"] - 1)
                lines.append(f"- {target} target: mean FPS change {diff:+.1f}% "
                             "(scene variation and noise may dominate).")
    lines.extend(["", "## Interpretation", "",
                  "1. If GPU utilization is high, render-resolution and upscaling tests are more promising.",
                  "2. If GPU utilization is low and CPU time is high, prioritize Xenos command translation and synchronization.",
                  "3. Do not mix different GPU backends in a direct A/B comparison.",
                  "4. A final gameplay benchmark should use the same route, time of day and camera.",
                  ""])
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("-TailSeconds", type=int, default=None)
    ap.add_argument("--compare", type=Path)
    args = ap.parse_args()
    meta = json.loads((args.folder / "metadata.json").read_text(encoding="utf-8-sig"))
    tail = args.TailSeconds if args.TailSeconds else int(meta["tail_seconds"])
    result = summary(args.folder, tail)
    other = summary(args.compare, tail) if args.compare else None
    (args.folder / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    text = make_markdown(result, other)
    (args.folder / "report.md").write_text(text, encoding="utf-8")
    print(text)
    print(f"Report: {args.folder / 'report.md'}")


if __name__ == "__main__":
    main()
