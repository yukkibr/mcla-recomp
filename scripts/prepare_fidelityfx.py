#!/usr/bin/env python3
"""Prepare pinned FidelityFX SDK sources for a Clang/llvm-rc Windows build.

The upstream ffx_api_dll.rc ships with a UTF-16LE BOM, but the Clang
preprocessor selected by CMake's cmake_llvm_rc does not accept UTF-16 input.
Decode that resource file and re-encode as UTF-8 (no BOM) before Ninja runs.
Idempotent; never changes any game assets.
"""
from pathlib import Path
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sdk_build_dir", type=Path, help="SDK CMake build directory")
    args = parser.parse_args()
    rc = (args.sdk_build_dir / "_deps" / "fidelityfx-src" / "ffx-api" /
          "src" / "resource" / "ffx_api_dll.rc")
    if not rc.is_file():
        parser.error(f"FidelityFX resource not found: {rc}. Enable FidelityFX during configure first.")
    original = rc.read_bytes()
    if original.startswith((b"\xff\xfe", b"\xfe\xff")):
        converted = original.decode("utf-16").encode("utf-8")
        rc.write_bytes(converted)
        print(f"Fixed UTF-16 resource for Clang: {rc}")
    else:
        print(f"Resource already compatible; no changes: {rc}")


if __name__ == "__main__":
    main()
