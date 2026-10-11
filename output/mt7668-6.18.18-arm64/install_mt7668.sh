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

rm -f /etc/modprobe.d/blacklist-mt7668-mainline-bt.conf

MAC_FILE=/etc/mt7668-wifi-mac
if [ -n "${MT7668_WIFI_MAC:-}" ]; then
	WIFI_MAC=$MT7668_WIFI_MAC
elif [ -s "$MAC_FILE" ]; then
	WIFI_MAC=$(tr -d '[:space:]' < "$MAC_FILE")
else
	seed=""
	for source in \
		/sys/firmware/devicetree/base/serial-number \
		/sys/class/dmi/id/product_uuid \
		/etc/machine-id \
		/sys/class/net/eth0/address; do
		if [ -r "$source" ]; then
			value=$(tr -d '\000\r\n ' < "$source")
			if [ -n "$value" ]; then
				seed="$seed|$value"
			fi
		fi
	done
	if [ -z "$seed" ]; then
		echo "无法取得设备唯一标识，请使用 MT7668_WIFI_MAC=xx:xx:xx:xx:xx:xx 指定 MAC" >&2
		exit 1
	fi
	hash=$(printf '%s' "$seed" | sha256sum | awk '{print $1}')
	WIFI_MAC=$(printf '02:%s:%s:%s:%s:%s' \
		"$(printf '%s' "$hash" | cut -c1-2)" \
		"$(printf '%s' "$hash" | cut -c3-4)" \
		"$(printf '%s' "$hash" | cut -c5-6)" \
		"$(printf '%s' "$hash" | cut -c7-8)" \
		"$(printf '%s' "$hash" | cut -c9-10)")
fi

if ! printf '%s\n' "$WIFI_MAC" | grep -Eiq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
	echo "无效的 Wi-Fi MAC 地址: $WIFI_MAC" >&2
	exit 1
fi

printf '%s\n' "$WIFI_MAC" > "$MAC_FILE"
chmod 0600 "$MAC_FILE"

if [ ! -f /lib/firmware/wifi.cfg ]; then
	echo "缺少 /lib/firmware/wifi.cfg" >&2
	exit 1
fi

if grep -q '^MacOverride ' /lib/firmware/wifi.cfg; then
	sed -i 's/^MacOverride .*/MacOverride 1/' /lib/firmware/wifi.cfg
else
	printf '\nMacOverride 1\n' >> /lib/firmware/wifi.cfg
fi

if grep -q '^MacAddr ' /lib/firmware/wifi.cfg; then
	sed -i "s/^MacAddr .*/MacAddr $WIFI_MAC/" /lib/firmware/wifi.cfg
else
	printf 'MacAddr %s\n' "$WIFI_MAC" >> /lib/firmware/wifi.cfg
fi

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
echo "Wi-Fi MAC: $WIFI_MAC"
echo ""
echo "重要：DTB 不会由脚本自动替换。"
echo "请人工把 $PAYLOAD_DIR/meson-g12a-x96-max_spdif_mt7668.dtb"
echo "复制到系统实际使用的 DTB 路径，并确认引导配置加载该文件。"
echo "请重启系统验证: reboot"
