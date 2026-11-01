#!/usr/bin/env bash
# Build a CPH2179 boot-v2 probe with early USB CDC records.
# Arm the known MT6765 RGU watchdog for 30 s before C; the probe should finish
# its 18 s capture window before the watchdog returns the device to boot flow.
set -euo pipefail
cd "$(dirname "$0")"

BOARD=oppo6765 \
MODE=boot \
STAGE15=1 \
STAGE15_EARLY=1 \
EARLY_WDT=0 \
TAG=usb-probe \
exec ./build.sh
