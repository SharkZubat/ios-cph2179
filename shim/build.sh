#!/bin/bash
# Build the shim and wrap it in an Android boot image.
#
#   BOARD=oppo6765 ./build.sh [PAYLOAD]
#   BOARD=oppo6765 RESET_ONLY=1 AUTO_BOOT_MODE=fastboot ./build.sh
#
# PAYLOAD is a tools/mkpayload.py image.  With no payload the image is a
# diagnostic build: the shim prints CPU/FDT state, arms the top RGU watchdog,
# then resets to the bootloader.  SELFTEST=1 forces a panic before the loader.
# RESET_ONLY=1 skips console/loader work and resets after 3 s; RTC_PROBE=1
# reads RTC_PDN1 once at startup (no write).
#
# Cactus legacy defaults match the working TWRP/ALPS 0.6 layout:
#   kernel  0x40080000, ramdisk 0x51b00000, tags 0x47880000, page 2048
# The stock kernel is Image.gz + appended cactus_dtb.orig.raw; the boot.img
# dtb field is a DTBO overlay.  Preserve both.
set -euo pipefail
cd "$(dirname "$0")"

BOARD="${BOARD:-sweet}"
MODE="${MODE:-boot}"		# boot or recovery
SELFTEST="${SELFTEST:-0}"	# 1 = force an exception after watchdog arm
RESET_ONLY="${RESET_ONLY:-0}"	# 1 = skip console/loader, reset after 3 s
RTC_PROBE="${RTC_PROBE:-0}"	# 1 = read RTC_PDN1 at startup
AUTO_BOOT_MODE="${AUTO_BOOT_MODE:-off}"
EARLY_PSTORE="${EARLY_PSTORE:-0}"
EARLY_WDT="${EARLY_WDT:-0}"
ENTRY_PROBE="${ENTRY_PROBE:-0}"
TRACE_PMSG="${TRACE_PMSG:-0}"
TRACE_WDT="${TRACE_WDT:-0}"
OPPO_STOCK_BOOT="${OPPO_STOCK_BOOT:-../OPPOA15S/boot.img}"
STAGE15="${STAGE15:-0}"
STAGE15_DIAG="${STAGE15_DIAG:-0}"
STAGE15_EARLY="${STAGE15_EARLY:-0}"
PAYLOAD="${1:-}"

if [ "$STAGE15" = 1 ] && [ "$BOARD" != cactus ] && [ "$BOARD" != oppo6765 ]; then
    echo "Stage 15 requires a supported MT6765-family target" >&2; exit 1
fi
if [ "$STAGE15_DIAG" = 1 ] && [ "$STAGE15" != 1 ]; then
    echo "STAGE15_DIAG requires STAGE15=1" >&2; exit 1
fi
case "$STAGE15_EARLY" in
	0|1|2|3|4|5) ;;
	*) echo "STAGE15_EARLY must be 0..5" >&2; exit 1 ;;
esac
if [ "$STAGE15_EARLY" != 0 ] && { { [ "$BOARD" != cactus ] && [ "$BOARD" != oppo6765 ]; } || [ "$STAGE15" != 1 ]; }; then
    echo "STAGE15_EARLY requires BOARD=cactus or oppo6765 and STAGE15=1" >&2; exit 1
fi

if [ "$BOARD" = cactus ] && [ "$TRACE_PMSG" = 1 ] && [ "$EARLY_PSTORE" != 0 ]; then
	echo "error: EARLY_PSTORE writes the recovery ramoops console region; use EARLY_PSTORE=0 with TRACE_PMSG=1" >&2
	exit 1
fi
CC="${CC:-aarch64-linux-gnu-gcc}"
OBJCOPY="${OBJCOPY:-aarch64-linux-gnu-objcopy}"
READELF="${READELF:-aarch64-linux-gnu-readelf}"
NM="${NM:-aarch64-linux-gnu-nm}"

if [ "$BOARD" = cactus ]; then
	CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -fno-omit-frame-pointer -Wall -Wextra -DBOARD_OPPO6765 -DCACTUS_DEBUG=1"
	DTB="${DTB:-/home/lapdq/cactus-kernel/pack/cactus_dtb.orig.raw}"
	DTBO="${DTBO:-/home/lapdq/cactus-kernel/images/cactus_dtbo.img}"
	MBOOTIMG="${MBOOTIMG:-python3 /home/lapdq/cactus-kernel/pack/mkbootimg.py}"
	BASE=0x40078000
	KERNEL_OFFSET=0x00008000
	RAMDISK_OFFSET=0x11A88000
	SECOND_OFFSET=0x000E8000
	TAGS_OFFSET=0x07808000
	DTB_OFFSET=0x07808000
	PAGESIZE=2048
	UFS=0
elif [ "$BOARD" = oppo6765 ]; then
	CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -fno-omit-frame-pointer -Wall -Wextra -DBOARD_OPPO6765"
	DTB=""
	DTBO=""
	MBOOTIMG="${MBOOTIMG:-mkbootimg}"
	# Values reconstructed from the CPH2179 header-v2 boot.img fields.
	BASE=0x40078000
	KERNEL_OFFSET=0x00008000
	RAMDISK_OFFSET=0x11A88000
	SECOND_OFFSET=0x00E88000
	TAGS_OFFSET=0x07808000
	DTB_OFFSET=0x07808000
	PAGESIZE=2048
	UFS=0
else
	CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -fno-omit-frame-pointer -Wall -Wextra"
	DTB="${DTB:-../dtb/boot_unpacked/dtb}"
	DTBO="${DTBO:-}"
	MBOOTIMG="${MBOOTIMG:-mkbootimg}"
	BASE=0
	KERNEL_OFFSET=0x8000
	RAMDISK_OFFSET=0x1000000
	SECOND_OFFSET=0
	TAGS_OFFSET=0x100
	DTB_OFFSET=0x1f00000
	PAGESIZE=4096
	UFS=1
fi

case "${AUTO_BOOT_MODE:-off}" in
	off|0) AUTO_BOOT_TARGET=0 ;;
	fastboot|1) AUTO_BOOT_TARGET=1 ;;
	recovery|2) AUTO_BOOT_TARGET=2 ;;
	*) echo "error: invalid AUTO_BOOT_MODE: $AUTO_BOOT_MODE" >&2; exit 1 ;;
esac

CFLAGS="$CFLAGS -DSHIM_SELFTEST=$SELFTEST -DAUTO_BOOT_TARGET=$AUTO_BOOT_TARGET -DSHIM_RESET_ONLY=$RESET_ONLY -DSHIM_RTC_PROBE=$RTC_PROBE -DSHIM_EARLY_PSTORE=$EARLY_PSTORE -DSHIM_EARLY_WDT=$EARLY_WDT -DSHIM_ENTRY_PROBE=$ENTRY_PROBE -DCACTUS_PMSG_TRACE=$TRACE_PMSG -DSHIM_TRACE_WDT=$TRACE_WDT"
if [ "$STAGE15" = 1 ]; then
    CFLAGS="$CFLAGS -DSHIM_STAGE15=1 -DSHIM_STAGE15_DIAG=$STAGE15_DIAG -DCACTUS_TRACE_STAGE=15"
fi
if [ "$STAGE15_EARLY" != 0 ]; then
    CFLAGS="$CFLAGS -DSHIM_STAGE15_EARLY=$STAGE15_EARLY"
fi
if [ "$SELFTEST" = 1 ] && [ -z "${TAG:-}" ]; then
	TAG=selftest
elif [ "$ENTRY_PROBE" = 1 ] && [ -z "${TAG:-}" ]; then
	TAG=entry-probe
elif [ "$RESET_ONLY" != 0 ] && [ -z "${TAG:-}" ]; then
	if [ "$RESET_ONLY" = 1 ]; then TAG=reset; else TAG=reset$RESET_ONLY; fi
elif [ "$RTC_PROBE" = 1 ] && [ -z "${TAG:-}" ]; then
	TAG=probe
fi

OUTDIR="out/$BOARD"
mkdir -p "$OUTDIR"

STOCK_RAMDISK=""
STOCK_CMDLINE=""
if [ "$BOARD" = oppo6765 ]; then
	[ -f "$OPPO_STOCK_BOOT" ] || { echo "error: stock boot image not found: $OPPO_STOCK_BOOT" >&2; exit 1; }
	STOCK_DIR="$OUTDIR/stock-v2"
	python3 ./extract_android_boot_v2.py "$OPPO_STOCK_BOOT" "$STOCK_DIR"
	DTB="$STOCK_DIR/dt-table.img"
	STOCK_RAMDISK="$STOCK_DIR/ramdisk.gz"
	STOCK_CMDLINE="$(cat "$STOCK_DIR/cmdline.txt")"
fi

[ -f "$DTB" ] || { echo "error: DTB not found: $DTB" >&2; exit 1; }
if [ -n "$DTBO" ]; then
	[ -f "$DTBO" ] || { echo "error: DTBO not found: $DTBO" >&2; exit 1; }
fi

OBJS=()
SOURCES=(start.S shim.c console.c debug.c pmsg_trace.c watchdog.c bootmode.c mmu.c fdt.c loader.c)
if [ "$BOARD" = cactus ] || [ "$BOARD" = oppo6765 ]; then
    # Runtime memory admission is mandatory even when STAGE15=0.
    SOURCES+=(fdt_ranges.c payload_layout.c)
fi
if [ "$STAGE15" = 1 ]; then
    SOURCES+=(stage15.c cactus_trace.c cactus_usb.c)
fi
if [ "$STAGE15_EARLY" != 0 ]; then
    SOURCES+=(stage15_early.c)
fi
for f in "${SOURCES[@]}"; do
	$CC $CFLAGS -c "$f" -o "$OUTDIR/${f%.*}.o"
	OBJS+=("$OUTDIR/${f%.*}.o")
done
if [ "$UFS" = 1 ]; then
	$CC $CFLAGS -c ufs.c -o "$OUTDIR/ufs.o"
	OBJS+=("$OUTDIR/ufs.o")
fi

# The image runs wherever the bootloader puts it with no relocation pass:
# only the header's image_size (start.o, linked at 0) may be absolute.
abs=0
for o in "${OBJS[@]}"; do
	[ "${o##*/}" = start.o ] && continue
	n=$($READELF -rW "$o" | grep -c R_AARCH64_ABS64 || true)
	abs=$((abs + n))
done
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }

$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	"${OBJS[@]}" -o "$OUTDIR/shim.elf"
$OBJCOPY -O binary "$OUTDIR/shim.elf" "$OUTDIR/Image"

# The bootloader copies image_size bytes; pad so .bss/stacks exist as zeros.
hex=$($NM "$OUTDIR/shim.elf" | awk '$3=="_end"{print $1}')
size=$((16#$hex))
truncate -s "$size" "$OUTDIR/Image"

# Cactus uses its legacy appended-DTB convention. CPH2179's Android v2
# header carries the original Android DT table in the separate DTB component.
gzip -9 -c "$OUTDIR/Image" > "$OUTDIR/Image.gz"
if [ "$BOARD" = cactus ]; then
	cat "$OUTDIR/Image.gz" "$DTB" > "$OUTDIR/Image.gz-dtb"
	KERNEL_IMAGE="$OUTDIR/Image.gz-dtb"
else
	KERNEL_IMAGE="$OUTDIR/Image.gz"
fi

if [ -n "$PAYLOAD" ]; then
	[ -f "$PAYLOAD" ] || { echo "error: payload not found: $PAYLOAD" >&2; exit 1; }
	cp "$PAYLOAD" "$OUTDIR/ramdisk.bin"
	TAG="${TAG:-xnu}"
else
	if [ "$BOARD" = oppo6765 ]; then
		cp "$STOCK_RAMDISK" "$OUTDIR/ramdisk.bin"
	else
		(cd "$OUTDIR" && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
	fi
	TAG="${TAG:-diag}"
fi

if [ "$BOARD" = oppo6765 ]; then
	CMDLINE="$STOCK_CMDLINE"
else
	CMDLINE="bootopt=64S3,32N2,64N2 androidboot.selinux=permissive buildvariant=user"
fi
if [ "$MODE" = recovery ]; then
	OUT="$OUTDIR/shim-$TAG-recovery.img"
	$MBOOTIMG --header_version 1 --kernel "$OUTDIR/Image.gz-dtb" \
		--ramdisk "$OUTDIR/ramdisk.bin" \
		--base "$BASE" --kernel_offset "$KERNEL_OFFSET" \
		--ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
		--tags_offset "$TAGS_OFFSET" --pagesize "$PAGESIZE" \
		--os_version 11.0.0 --cmdline "$CMDLINE" -o "$OUT"
else
	OUT="$OUTDIR/shim-$TAG-boot.img"
	if [ "$BOARD" = oppo6765 ]; then
		$MBOOTIMG --header_version 2 --kernel "$KERNEL_IMAGE" \
			--ramdisk "$OUTDIR/ramdisk.bin" --dtb "$DTB" \
			--base "$BASE" --kernel_offset "$KERNEL_OFFSET" \
			--ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
			--tags_offset "$TAGS_OFFSET" --dtb_offset "$DTB_OFFSET" \
			--pagesize "$PAGESIZE" --os_version 10.0.0 \
			--os_patch_level 2023-02 --cmdline "$CMDLINE" -o "$OUT"
	elif [ -n "$DTBO" ]; then
		$MBOOTIMG --header_version 2 --kernel "$OUTDIR/Image.gz-dtb" \
			--ramdisk "$OUTDIR/ramdisk.bin" --dtb "$DTBO" \
			--base "$BASE" --kernel_offset "$KERNEL_OFFSET" \
			--ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
			--tags_offset "$TAGS_OFFSET" --dtb_offset "$DTB_OFFSET" \
			--pagesize "$PAGESIZE" --os_version 11.0.0 \
			--cmdline "$CMDLINE" -o "$OUT"
	else
		$MBOOTIMG --header_version 1 --kernel "$OUTDIR/Image.gz-dtb" \
			--ramdisk "$OUTDIR/ramdisk.bin" \
			--base "$BASE" --kernel_offset "$KERNEL_OFFSET" \
			--ramdisk_offset "$RAMDISK_OFFSET" --second_offset "$SECOND_OFFSET" \
			--tags_offset "$TAGS_OFFSET" --pagesize "$PAGESIZE" \
			--os_version 11.0.0 --cmdline "$CMDLINE" -o "$OUT"
	fi
fi

# Host render of the console layout (sanity check only).
HOSTDEF=""
{ [ "$BOARD" = cactus ] || [ "$BOARD" = oppo6765 ]; } && HOSTDEF="-DBOARD_OPPO6765"
gcc -O1 -Wall $HOSTDEF -o "$OUTDIR/host_test" console.c host_test.c
(cd "$OUTDIR" && ./host_test >/dev/null)

if [ "$BOARD" = oppo6765 ]; then
	ls -l "$OUTDIR/Image" "$OUTDIR/Image.gz" "$OUTDIR/ramdisk.bin" "$DTB" "$OUT"
else
	ls -l "$OUTDIR/Image" "$OUTDIR/Image.gz-dtb" "$OUTDIR/ramdisk.bin" "$OUT"
fi
if command -v sha256sum >/dev/null; then
	sha256sum "$OUT"
fi
if [ "$BOARD" = cactus ]; then
	python3 ./check_image.py "$OUT"
fi
