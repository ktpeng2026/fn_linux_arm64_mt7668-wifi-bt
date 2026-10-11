#!/bin/sh
set -eu

KERNEL_RELEASE="${KERNEL_RELEASE:-$(uname -r)}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${PAYLOAD_DIR:-}" ]; then
	PAYLOAD_DIR=$PAYLOAD_DIR
elif [ -f "$SCRIPT_DIR/wlan_mt76x8_sdio.ko" ] &&
	[ -f "$SCRIPT_DIR/bt_mt7668.ko" ]; then
	PAYLOAD_DIR=$SCRIPT_DIR
else
	PAYLOAD_DIR="$SCRIPT_DIR/output/mt7668-6.18.18-arm64"
fi
MODULE_DIR="/lib/modules/$KERNEL_RELEASE/extra/mt7668"

if [ "$(id -u)" -ne 0 ]; then
	echo "请使用 root 执行: sudo $0" >&2
	exit 1
fi

for file in wlan_mt76x8_sdio.ko bt_mt7668.ko; do
	if [ ! -f "$PAYLOAD_DIR/$file" ]; then
		echo "缺少文件: $PAYLOAD_DIR/$file" >&2
		exit 1
	fi
done

if [ ! -d "$PAYLOAD_DIR/firmware" ]; then
	echo "缺少固件目录: $PAYLOAD_DIR/firmware" >&2
	exit 1
fi

for module in wlan_mt76x8_sdio.ko bt_mt7668.ko; do
	vermagic=$(modinfo -F vermagic "$PAYLOAD_DIR/$module")
	case "$vermagic" in
		"$KERNEL_RELEASE "*) ;;
		*)
			echo "$module vermagic 不匹配: $vermagic" >&2
			echo "当前内核: $KERNEL_RELEASE" >&2
			exit 1
			;;
	esac
done

install -d -m 0755 "$MODULE_DIR"
install -m 0644 "$PAYLOAD_DIR/wlan_mt76x8_sdio.ko" "$MODULE_DIR/"
install -m 0644 "$PAYLOAD_DIR/bt_mt7668.ko" "$MODULE_DIR/"

find "$PAYLOAD_DIR/firmware" -type d -print | while IFS= read -r directory; do
	relative=${directory#"$PAYLOAD_DIR/firmware"}
	install -d -m 0755 "/lib/firmware$relative"
done

find "$PAYLOAD_DIR/firmware" -type f -print | while IFS= read -r firmware; do
	relative=${firmware#"$PAYLOAD_DIR/firmware"}
	install -m 0644 "$firmware" "/lib/firmware$relative"
done

cat > /etc/modprobe.d/mt7668.conf <<'EOF'
# The in-tree btmtksdio driver also matches SDIO 037a:7668.
# Use the vendor MT7668 driver for this board instead.
blacklist btmtksdio
softdep wlan_mt76x8_sdio pre: cfg80211
softdep bt_mt7668 pre: bluetooth
EOF

cat > /etc/modules-load.d/mt7668.conf <<'EOF'
wlan_mt76x8_sdio
bt_mt7668
EOF

depmod -a "$KERNEL_RELEASE"

if command -v systemctl >/dev/null 2>&1; then
	systemctl enable bluetooth.service >/dev/null 2>&1 || true
fi

echo "MT7668 驱动安装完成。"
echo "模块目录: $MODULE_DIR"
echo "请重启系统验证: reboot"
