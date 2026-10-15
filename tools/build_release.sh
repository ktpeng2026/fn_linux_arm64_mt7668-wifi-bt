#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KERNEL_RELEASE=${KERNEL_RELEASE:-6.18.18.c1151-trim}
KDIR=${KDIR:-$ROOT/linux-headers-$KERNEL_RELEASE}
CROSS_COMPILE=${CROSS_COMPILE-aarch64-linux-gnu-}
JOBS=${JOBS:-$(nproc)}
RELEASE="$ROOT/releases/$KERNEL_RELEASE/aarch64"
WLAN="$ROOT/MT7668-WiFi/drv_wlan/MT6632/wlan"

if [ ! -f "$KDIR/Module.symvers" ]; then
	echo "缺少目标内核 Module.symvers: $KDIR/Module.symvers" >&2
	exit 1
fi

make -C "$KDIR" M="$WLAN" ARCH=arm64 \
	CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" modules
make -C "$ROOT/MT7668-Bluetooth" KERNEL_SRC="$KDIR" \
	ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS"

for module in "$WLAN/wlan_mt76x8_sdio.ko" \
	"$ROOT/MT7668-Bluetooth/bt_mt7668.ko"; do
	case "$(modinfo -F vermagic "$module")" in
		"$KERNEL_RELEASE "*) ;;
		*) echo "vermagic 不匹配: $module" >&2; exit 1 ;;
	esac
done

mkdir -p "$RELEASE/firmware"
cp "$WLAN/wlan_mt76x8_sdio.ko" "$RELEASE/"
cp "$ROOT/MT7668-Bluetooth/bt_mt7668.ko" "$RELEASE/"
cp "$ROOT/MT7668-WiFi/7668_firmware/"*.bin \
	"$ROOT/MT7668-WiFi/7668_firmware/"*.dat \
	"$ROOT/MT7668-WiFi/7668_firmware/wifi.cfg" "$RELEASE/firmware/"
cp "$ROOT/install_mt7668.sh" "$ROOT/uninstall_mt7668.sh" "$RELEASE/"

echo "归档目录: $RELEASE"
echo "DTB 不会重新编译；请核对该目录顶层 DTB 与目标板卡是否匹配。"
