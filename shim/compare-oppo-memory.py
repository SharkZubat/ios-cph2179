#!/usr/bin/env python3
"""Compare Stage 15 level-5 fixed FDT reservations with Linux System RAM."""
import argparse
import importlib.machinery
from pathlib import Path
import re


def load_decoder():
    path = Path(__file__).with_name("decode-cactus-usb.py")
    return importlib.machinery.SourceFileLoader("cactus_usb_decode", str(path)).load_module()


def parse_system_ram(path):
    pattern = re.compile(r"^\s*([0-9a-fA-F]+)-([0-9a-fA-F]+)\s+:\s+System RAM\s*$")
    result = []
    for line in path.read_text(errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            start, inclusive_end = (int(value, 16) for value in match.groups())
            if inclusive_end < start:
                raise ValueError(f"invalid System RAM interval: {line}")
            result.append((start, inclusive_end + 1))
    if not result:
        raise ValueError(f"no System RAM intervals found in {path}")
    return result


def merge(intervals):
    merged = []
    for start, end in sorted(intervals):
        if end <= start:
            continue
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def subtract(start, end, reserved):
    pieces = [(start, end)]
    for rstart, rend in reserved:
        next_pieces = []
        for pstart, pend in pieces:
            if rend <= pstart or rstart >= pend:
                next_pieces.append((pstart, pend))
            else:
                if pstart < rstart:
                    next_pieces.append((pstart, rstart))
                if rend < pend:
                    next_pieces.append((rend, pend))
        pieces = next_pieces
    return pieces


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iomem", type=Path, help="saved /proc/iomem text")
    parser.add_argument("capture", type=Path, help="raw Stage 15 level-5 CLOG capture")
    args = parser.parse_args()

    decoder = load_decoder()
    records, corrupt, noise = decoder.decode(args.capture.read_bytes())
    stage_records = [r for r in records if r["stage"] == 15]
    summaries = [r for r in stage_records if r["event"] == 0x158b]
    ranges = [r for r in stage_records if r["event"] == 0x158c]
    if len(summaries) != 1:
        raise SystemExit(f"expected one FDT reservation summary, found {len(summaries)}")

    summary = summaries[0]
    expected = summary["a"]
    indexed = {r["a"]: (r["b"], r["c"]) for r in ranges}
    if len(indexed) != len(ranges) or set(indexed) != set(range(expected)):
        raise SystemExit(f"reservation records incomplete: expected {expected}, got {len(indexed)}")
    reserved = []
    for index in range(expected):
        base, size = indexed[index]
        if not size or base + size > (1 << 64):
            raise SystemExit(f"invalid FDT reservation #{index}: base={base:#x} size={size:#x}")
        reserved.append((base, base + size))
    reserved = merge(reserved)
    banks = parse_system_ram(args.iomem)

    print(f"capture_frames={len(records)} bad_frames={corrupt} unmatched_bytes={noise}")
    print(f"FDT fixed reservation entries={expected}; initrd=[{summary['b']:#x},{summary['c']:#x})")
    print("Fixed FDT reservations (merged):")
    for start, end in reserved:
        print(f"  [{start:#010x}, {end:#010x}) size={end-start:#x}")
    print("System RAM after subtracting fixed FDT reservations:")
    for start, end in banks:
        print(f"  bank [{start:#010x}, {end:#010x})")
        for left, right in subtract(start, end, reserved):
            print(f"    candidate [{left:#010x}, {right:#010x}) size={right-left:#x}")
    print("Caveat: candidates do not account for dynamic reserved-memory nodes without reg,")
    print("LK/shim/payload occupancy, or other platform-specific carveouts.")


if __name__ == "__main__":
    main()
