#!/usr/bin/env bash
# Build a CPH2179 boot-v2 shim that records entry and returns to fastboot.
# It preserves the stock ramdisk and Android DT table and never enters XNU.
set -euo pipefail
cd "$(dirname "$0")"

BOARD=oppo6765 \
MODE=boot \
RESET_ONLY=1 \
AUTO_BOOT_MODE=fastboot \
TAG=diag \
exec ./build.sh
