# OPPO CPH2179: live FDT reservation report

## Evidence so far

The level-4 CPH2179 trace parsed the live FDT successfully:

- `0x1588`: result `0`, total FDT bytes `0x2c393`, one memory entry.
- `0x1589`: memory entry 0 is `[0x40000000, 0x140000000)`.
- `0x158a`: level-4 diagnostic completed.

This broad 4 GiB FDT memory span is not the usable-RAM map. The saved
`OPPOA15S/iomem.txt` lists ten separate System RAM intervals. The saved live
FDT also contains fixed `/reserved-memory/*/reg` ranges and dynamic reservation
requests with `size`/`alloc-ranges` but no assigned `reg` base.

## Level 5 source change

`STAGE15_EARLY=5` retains the level-4 checks and adds:

- `0x158b`: fixed reservation count, initrd start, initrd end.
- `0x158c`: each fixed reservation as index, base, size.

The fixed ranges are the FDT reserve-map entries plus reserved-memory children
that have a concrete `reg`. Dynamic requests without a `reg` base are not
reported as allocated ranges. They remain unresolved and must not be assumed
free. This diagnostic does not read, write, relocate, or execute the XNU
payload.

## Build and capture

From `shim/`:

```sh
BOARD=oppo6765 MODE=boot STAGE15=1 STAGE15_EARLY=5 \
  EARLY_WDT=1 TAG=oppo-level5-reservations ./build.sh
```

Start `capture-cdc.py` while the handset is still in fastboot, then flash and
reboot with the established rollback procedure. Decode the capture:

```sh
python decode-cactus-usb.py /tmp/oppo-level5.bin \
  --show 120 --require-stage15-early --early-level 5
```

Compare it with the saved Linux System RAM intervals:

```sh
python compare-oppo-memory.py ../OPPOA15S/iomem.txt /tmp/oppo-level5.bin
```

The comparison prints candidate intervals after subtracting fixed FDT
reservations. They are not yet XNU-usable intervals: dynamic reservation
requests, LK/shim/payload occupancy, and any additional MediaTek carveouts still
need resolution. A strict decoder PASS also requires a clean capture containing
the early entry and USB-init records.
