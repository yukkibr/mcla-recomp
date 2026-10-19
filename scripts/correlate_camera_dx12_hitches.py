#!/usr/bin/env python3
"""Correlate guest-present hitches, DX12 GPU-Commands CPU stalls and camera events.

This is a read-only offline report. DX12 probe timings are CPU wall time, NOT GPU
execution time. Guest-present timestamps are a different clocking hook than the
GPU Commands swap event; a matching 10s window is association, NOT proof.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
import re

DATE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]")
BENCH = re.compile(
    r"MCLA FPS benchmark: fps=(?P<fps>[\d.]+) avg_ms=[\d.]+ "
    r"p99_bucket_ms=(?P<p99>\d+) max_ms=(?P<max>[\d.]+) "
    r"stalls50=(?P<s50>\d+) stalls100=(?P<s100>\d+) "
    r"frames=(?P<frames>\d+) seconds=(?P<seconds>[\d.]+)"
)
DX12 = re.compile(
    r"DX12 hitch probe: GPU-thread swap interval (?P<gap>[\d.]+)ms"
    r" \| draws (?P<draws>\d+) cpu (?P<draw>[\d.]+)ms"
    r" \(max single (?P<maxdraw>[\d.]+)ms\), rt (?P<rt>[\d.]+)ms,"
    r" pipeline (?P<pipeline>[\d.]+)ms, texture (?P<texture>[\d.]+)ms,"
    r" bindings (?P<bindings>[\d.]+)ms, fence (?P<fence>[\d.]+)ms"
    r" \(max (?P<maxfence>[\d.]+)ms\), submits (?P<submits>\d+)"
    r" cpu (?P<submission>[\d.]+)ms, swap (?P<swap>[\d.]+)ms"
)
STAGE = re.compile(
    r"Texture request stages: (?P<calls>\d+) calls, prep (?P<prep>[\d.]+)ms,"
    r" residency (?P<residency>[\d.]+)ms, upload (?P<upload>[\d.]+)ms,"
    r" binding (?P<binding>[\d.]+)ms, pending loads (?P<loads>\d+),"
    r" ranges (?P<ranges>\d+), changed (?P<changed>\d+),"
    r" calls over 3ms (?P<slow>\d+), peak (?P<peak>[\d.]+)ms"
)
SPIKE = re.compile(
    r"Texture request stage spike: total (?P<total>[\d.]+)ms,"
    r" prep (?P<prep>[\d.]+)ms, residency (?P<residency>[\d.]+)ms,"
    r" upload (?P<upload>[\d.]+)ms, binding (?P<binding>[\d.]+)ms"
)
CAMERA = re.compile(r"MCLA camera identity event: .*?stable_rig=(?P<stable>true|false)"
                    r".*?publish_step_m=(?P<step>[\d.]+)"
                    r" relative_step_m=(?P<offset>[\d.]+)")
CAMERA_MODE = re.compile(r"MCLA chase camera filter A/B: mode=(\w+)")
CLAMP = re.compile(r"MCLA timing trace: .*?guard clamps (?P<clamps>\d+)")

@dataclass
class Point:
    time: datetime
    metrics: dict[str, str]

def load(path: Path) -> tuple[dict[str, list[Point]], str, bool]:
    out: dict[str, list[Point]] = {n: [] for n in
                                   ("bench", "dx12", "stage", "spike", "camera", "clamp")}
    mode = "unknown"
    configured_probe = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        ts = DATE.match(line)
        if not ts:
            continue
        when = datetime.strptime(ts.group(1), "%Y-%m-%d %H:%M:%S.%f")
        cm = CAMERA_MODE.search(line)
        if cm:
            mode = cm.group(1)
        if "DX12 hitch probe:" in line:
            configured_probe = True
        for kind, pattern in (("bench", BENCH), ("dx12", DX12),
                              ("stage", STAGE), ("spike", SPIKE),
                              ("camera", CAMERA), ("clamp", CLAMP)):
            match = pattern.search(line)
            if match:
                out[kind].append(Point(when, match.groupdict()))
    return out, mode, configured_probe

def m(p: Point, key: str) -> float:
    return float(p.metrics[key])

def inside(p: Point, a: datetime, b: datetime) -> bool:
    return a < p.time <= b

def biggest(points: list[Point], key: str) -> Point | None:
    return max(points, key=lambda p: m(p, key)) if points else None

def diagnosis(event: Point) -> str:
    gap = m(event, "gap")
    draw = m(event, "draw")
    tex = m(event, "texture")
    other = (("render targets", m(event, "rt")),
             ("pipeline", m(event, "pipeline")),
             ("GPU fence wait (CPU)", m(event, "fence")),
             ("submission CPU", m(event, "submission")))
    if tex >= 5 and tex >= 0.5 * draw and draw >= 0.5 * gap:
        return "texture-request CPU (associated)"
    name, cost = max(other, key=lambda item: item[1])
    if cost >= 5 and cost >= 0.5 * gap:
        return name + " (associated)"
    if draw >= 0.6 * gap:
        return "draw CPU, stage uncertain"
    return "unattributed CPU interval"

def report(path: Path, args: argparse.Namespace) -> None:
    events, mode, probe = load(path)
    windows = events["bench"][args.skip_warmup:]
    if args.max_windows:
        windows = windows[:args.max_windows]
    print(f"\n=== {path.name} | camera={mode} | full 10s windows={len(windows)} ===")
    print(f"DX12 hitch records={len(events['dx12'])}, texture stage reports="
          f"{len(events['stage'])}, camera identity events={len(events['camera'])}")
    if not probe:
        print("WARNING: No DX12 CPU probe events in this log; this is NOT proof of zero CPU hitches.")
    if not windows:
        print("No completed guest benchmark windows remain; showing DX12-only records if present.")
        filtered = events["dx12"]
        if args.around and filtered:
            target = filtered[0].time.replace(
                hour=int(args.around[:2]), minute=int(args.around[3:5]),
                second=int(args.around[6:8]), microsecond=0)
            margin = timedelta(seconds=args.margin)
            filtered = [e for e in filtered if abs(e.time - target) <= margin]
        for e in sorted(filtered, key=lambda x: m(x, "gap"), reverse=True)[:args.top]:
            print(f"  {e.time:%H:%M:%S.%f}"[:-3]
                  + f" GPU-Commands interval {m(e,'gap'):.1f}ms; "
                    f"draw CPU {m(e,'draw'):.1f}ms, "
                    f"texture CPU {m(e,'texture'):.1f}ms; {diagnosis(e)}")
        print("No guest-present FPS comparison possible for this historical log.")
        return
    if args.around:
        # User-supplied HH:MM:SS is interpreted on the same calendar date as this log.
        target = windows[0].time.replace(
            hour=int(args.around[:2]), minute=int(args.around[3:5]),
            second=int(args.around[6:8]), microsecond=0)
        margin = timedelta(seconds=args.margin)
        windows = [w for w in windows
                   if (w.time > target - margin and
                       w.time - timedelta(seconds=m(w, "seconds")) < target + margin)]
        if not windows:
            print("No benchmark windows overlap requested time.")
            return
    print("Window end            fps  p99  worst  gap50  gap100  DX12>50 "
          "DX12 max  Texture max  Camera events")
    for w in windows:
        start = w.time - timedelta(seconds=m(w, "seconds"))
        d = [e for e in events["dx12"] if inside(e, start, w.time)]
        s = [e for e in events["spike"] if inside(e, start, w.time)]
        c = [e for e in events["camera"] if inside(e, start, w.time)]
        w_d = biggest(d, "gap")
        w_s = biggest(s, "total")
        print(f"{w.time:%H:%M:%S}          {m(w,'fps'):5.1f}  {m(w,'p99'):3.0f}  "
              f"{m(w,'max'):5.1f}  {m(w,'s50'):5.0f}  {m(w,'s100'):6.0f}  "
              f"{sum(m(x,'gap') >= 50 for x in d):7}  "
              f"{m(w_d,'gap') if w_d else 0:8.1f}  "
              f"{m(w_s,'total') if w_s else 0:11.1f}  {len(c):13}")
    start = windows[0].time - timedelta(seconds=m(windows[0], "seconds"))
    end = windows[-1].time
    d = [e for e in events["dx12"] if inside(e, start, end)]
    c = [e for e in events["camera"] if inside(e, start, end)]
    s = [e for e in events["stage"] if inside(e, start, end)]
    print(f"\nDX12 GPU-Commands CPU intervals >= {args.min_dx12:g}ms "
          "(the DX12 probe logs these events selectively):")
    slow = [e for e in d if m(e, "gap") >= args.min_dx12]
    if slow:
        print("Timestamp             gap    draw    texture   rt   pipeline   fence   submit  likely CPU contributor")
        for e in sorted(slow, key=lambda e: m(e, "gap"), reverse=True)[:args.top]:
            print(f"{e.time:%H:%M:%S.%f}"[:-3] + "  "
                  f"{m(e,'gap'):6.1f} {m(e,'draw'):7.1f} {m(e,'texture'):9.1f} "
                  f"{m(e,'rt'):5.1f} {m(e,'pipeline'):8.1f} {m(e,'fence'):7.1f} "
                  f"{m(e,'submission'):7.1f}  {diagnosis(e)}")
    else:
        print("(None recorded in selected windows.)")
    print(f"\nTexture request stage aggregates: {len(s)} five-second summaries in selected windows")
    if s:
        count = sum(m(e, "calls") for e in s)
        total = {key: sum(m(e, key) for e in s) for key in
                 ("prep", "residency", "upload", "binding")}
        print(f"  {int(count)} sampled requests; CPU sums (ms): "
              + ", ".join(f"{k} {v:.1f}" for k, v in total.items()))
        print(f"  slow calls >=3ms: {int(sum(m(e,'slow') for e in s))}; "
              f"largest call: {max(m(e,'peak') for e in s):.2f}ms")
    if c:
        print(f"\nCamera identity events: {len(c)}")
        for event in c[:args.top]:
            print(f"  {event.time:%H:%M:%S.%f}"[:-3] +
                  f" stable_rig={event.metrics['stable']} step={m(event,'step'):.2f}m"
                  f" offset_step={m(event,'offset'):.2f}m")
    else:
        print("\nNo camera identity events in these windows; small visual jitter is still possible.")
    total_frames = sum(m(w, "frames") for w in windows)
    duration = sum(m(w, "seconds") for w in windows)
    print(f"\nGuest presents: {total_frames:.0f} over {duration:.1f}s, "
          f"{total_frames/duration:.2f} avg requests/s. "
          f"Stalls >=50ms: {sum(m(w,'s50') for w in windows):.0f}.")
    print("Interpretation: timing records from different host threads and their "
          "10s windows provide association, NOT exact frame-level causality.")
    print("DX12 times are CPU wall times, not GPU execution; nested categories "
          "(draw/texture/rt/pipeline) MUST NOT be added.")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+")
    parser.add_argument("--skip-warmup", type=int, default=3)
    parser.add_argument("--max-windows", type=int, default=0)
    parser.add_argument("--top", type=int, default=12)
    parser.add_argument("--min-dx12", type=float, default=50)
    parser.add_argument("--around", help="HH:MM:SS timestamp of visually observed flick")
    parser.add_argument("--margin", type=float, default=15.0)
    args = parser.parse_args()
    for path in args.logs:
        if not path.is_file():
            parser.error(f"log does not exist: {path}")
        report(path, args)

if __name__ == "__main__":
    main()
