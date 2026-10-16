#!/usr/bin/env python3
"""Summarize opt-in DX12 GPU-command-thread hitch diagnostics from a game log."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import statistics

PATTERN = re.compile(
    r"DX12 hitch probe: GPU-thread swap interval (?P<gap>[\d.]+)ms"
    r" \| draws (?P<draws>\d+) cpu (?P<draw>[\d.]+)ms"
    r" \(max single (?P<maxdraw>[\d.]+)ms\), rt (?P<rt>[\d.]+)ms,"
    r" pipeline (?P<pipeline>[\d.]+)ms, texture (?P<texture>[\d.]+)ms,"
    r" bindings (?P<bindings>[\d.]+)ms, fence (?P<fence>[\d.]+)ms"
    r" \(max (?P<maxfence>[\d.]+)ms\), submits (?P<submits>\d+)"
    r" cpu (?P<submission>[\d.]+)ms, swap (?P<swap>[\d.]+)ms"
)
DATE = re.compile(r"^\[(.*?)\]")
TIMING = re.compile(r"MCLA timing trace:")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="mcla_NNN.log or quit-qa log")
    parser.add_argument("--top", type=int, default=12)
    parser.add_argument("--min-ms", type=float, default=50.0)
    args = parser.parse_args()
    rows = []
    timer_count = 0
    for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        if TIMING.search(line):
            timer_count += 1
        result = PATTERN.search(line)
        if not result:
            continue
        record = {k: float(v) for k, v in result.groupdict().items()}
        stamp = DATE.search(line)
        record["time"] = stamp.group(1) if stamp else "?"
        rows.append(record)
    if not rows:
        raise SystemExit("No DX12 hitch probe lines found. Was d3d12_hitch_probe enabled?")
    slow = [row for row in rows if row["gap"] >= args.min_ms]
    print(f"Log: {args.log}")
    print(f"Recorded GPU-thread intervals: {len(rows)}; >= {args.min_ms:g}ms: {len(slow)}")
    print(f"Guest timing trace summaries: {timer_count}")
    print(f"Max logged swap interval: {max(x['gap'] for x in rows):.1f}ms")
    if slow:
        print("Top slow GPU Commands thread intervals:")
        print("Timestamp                 gap    draw    texture    RT   pipeline  bindings  fence  submit")
        for record in sorted(slow, key=lambda x: x["gap"], reverse=True)[: max(0, args.top)]:
            print(
                f"{record['time']:25} {record['gap']:6.1f} {record['draw']:7.1f}"
                f" {record['texture']:10.1f} {record['rt']:5.1f}"
                f" {record['pipeline']:9.1f} {record['bindings']:9.1f}"
                f" {record['fence']:6.1f} {record['submission']:7.1f}"
            )
        print("Category times overlap: draw includes pipeline, textures, RT and bindings.")
        print("These are CPU wall-times on the GPU Commands thread, NOT GPU execution times.")
    else:
        print("No logged interval exceeded the selected threshold.")


if __name__ == "__main__":
    main()
