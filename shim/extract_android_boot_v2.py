#!/usr/bin/env python3
"""Extract the ramdisk and DT table from a legacy Android boot-v2 image."""

import argparse
import json
import struct
from pathlib import Path


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def u64(data: bytes, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def align(value: int, page: int) -> int:
    return (value + page - 1) & ~(page - 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("boot_image", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    data = args.boot_image.read_bytes()
    if data[:8] != b"ANDROID!":
        raise SystemExit("input is not an Android boot image")
    version = u32(data, 40)
    page = u32(data, 36)
    if version != 2 or page != 2048:
        raise SystemExit(f"expected boot header v2/page 2048; got v{version}/page {page}")
    if len(data) < 1660:
        raise SystemExit("truncated v2 header")

    kernel_size = u32(data, 8)
    ramdisk_size = u32(data, 16)
    second_size = u32(data, 24)
    recovery_size = u32(data, 1632)
    recovery_offset = u64(data, 1636)
    header_size = u32(data, 1644)
    dtb_size = u32(data, 1648)
    dtb_addr = u64(data, 1652)
    if header_size != 1660 or not dtb_size:
        raise SystemExit(f"unexpected v2 header_size={header_size}, dtb_size={dtb_size}")

    kernel_offset = page
    ramdisk_offset = kernel_offset + align(kernel_size, page)
    second_offset = ramdisk_offset + align(ramdisk_size, page)
    if recovery_size:
        if recovery_offset < second_offset:
            raise SystemExit("recovery DTBO offset overlaps earlier boot components")
        dtb_offset = recovery_offset + align(recovery_size, page)
    else:
        dtb_offset = second_offset + align(second_size, page)
    end = dtb_offset + dtb_size
    if end > len(data):
        raise SystemExit(f"DT table ends at {end:#x}, beyond image size {len(data):#x}")
    if data[dtb_offset:dtb_offset + 4] not in (b"\xd7\xb7\xab\x1e", b"\xd0\x0d\xfe\xed"):
        raise SystemExit(f"unexpected DT payload magic at {dtb_offset:#x}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    ramdisk = data[ramdisk_offset:ramdisk_offset + ramdisk_size]
    dt_table = data[dtb_offset:end]
    (args.output_dir / "ramdisk.gz").write_bytes(ramdisk)
    (args.output_dir / "dt-table.img").write_bytes(dt_table)

    cmdline = (data[64:64 + 512].rstrip(b"\0") +
               data[608:608 + 1024].rstrip(b"\0"))
    cmdline = cmdline.decode("ascii", errors="replace")
    metadata = {
        "header_version": version,
        "page_size": page,
        "header_size": header_size,
        "kernel_addr": u32(data, 12),
        "ramdisk_addr": u32(data, 20),
        "second_addr": u32(data, 28),
        "tags_addr": u32(data, 32),
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "second_size": second_size,
        "recovery_dtbo_size": recovery_size,
        "recovery_dtbo_offset": recovery_offset,
        "dtb_size": dtb_size,
        "dtb_addr": dtb_addr,
        "dtb_offset": dtb_offset,
        "dtb_magic": dt_table[:4].hex(),
        "cmdline": cmdline,
    }
    (args.output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (args.output_dir / "cmdline.txt").write_text(cmdline + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
