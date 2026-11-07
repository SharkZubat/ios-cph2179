# oppo6765 port plan

This document records the plan for adapting the Cactarwin/XNU work to the OPPO
A15s. **`oppo6765` is the project codename**; it does not claim that the OPPO
board is identical to Redmi 6A `cactus`.

## Device identity

- Product/model: OPPO A15s, `CPH2179`.
- Android device string: `OP4F2F`.
- Project codename: `oppo6765`.
- Platform/SoC family: MediaTek MT6765; the live tree reports `MT6765V/CB`.
- Stock software evidence: Android 10, Linux 4.9.190+, 4 GB LPDDR4X,
  720 x 1600 display. See the local device inventory; do not copy device dumps
  or identifiers containing serial/calibration data into this repository.

## What the live device tree currently indicates

These are observations from `device/oppo_lfdt.dts`, not yet a complete XNU
platform configuration:

- Eight Cortex-A53 CPU nodes, with MPIDR values `0..3` and `0x100..0x103`.
- DRAM node starts at `0x40000000` and declares a 4 GiB range. The tree also
  contains many MediaTek reserved-memory regions; the declared DRAM range is
  not a safe allocation map by itself.
- GICv3 distributor at `0x0c000000`, redistributor region at `0x0c100000`.
- ARMv8 architectural timer at 13 MHz; the virtual timer is listed as PPI
  11 (architectural INTID 27).
- Android boot image is header v2 with a device-tree handoff. The exact LK
  entry state, memory reservations, and DTB/DTBO selection still need to be
  confirmed from the boot path used for an XNU payload.

## Cactus work that must be revalidated

The Cactus board config contains fixed framebuffer addresses and dimensions,
GIC setup, CPU topology, timer assumptions, and 4 KiB hardware / 16 KiB XNU
software-page settings. Some architectural facts may be shared by these MTK
devices, but none of the board addresses, memory layout, reserved regions,
panel settings, or bootloader assumptions should be inherited without OPPO
evidence. The Cactus Stage 79 PID1 and virtual-RAMDisk work is later-stage XNU
work; it does not establish that the OPPO shim or board initialization works.

## First implementation milestone

Produce an OPPO handoff profile and a small, recoverable shim diagnostic before
adding an `OPPO6765` XNU machine configuration:

1. Decode the stock boot image and selected DTB/DTBO. Record the actual entry
   exception level, registers/arguments, kernel and initrd placement, FDT
   address, and all reserved ranges. Check arithmetic and overlap offline.
2. Compare the live FDT's CPU, GIC, timer, memory, and reserved-memory data
   with the Cactus config. Mark each setting as verified for OPPO, different,
   or unknown; do not infer board identity from the shared MT6765 label.
3. Make a minimal shim-only entry/return diagnostic that confirms the OPPO
   bootloader handoff without jumping into XNU. Keep the existing Android and
   recovery paths intact while validating how to recover from a failed boot.
4. Only then add an isolated `OPPO6765` machine configuration and test an
   instrumented XNU entry with a one-core baseline. Add VM, interrupt, timer,
   storage, and display support as separate measured milestones.

## Safety and evidence rules

- Do not use a Cactus image or write a Cactus framebuffer/GIC/memory constant
  onto the OPPO.
- The local device notes report that `fastboot boot` does not boot the supplied
  image and may reboot after about 20 seconds. Do not perform a hardware trial
  until the image path and reliable recovery procedure are confirmed.
- Keep raw partition images, DT dumps with identifiers, calibration partitions,
  and generated firmware out of Git.
- Label results as built, shim-entered, XNU-entered, or XNU-progressed. A
  successful build or a visible bootloader logo is not proof of XNU execution.
