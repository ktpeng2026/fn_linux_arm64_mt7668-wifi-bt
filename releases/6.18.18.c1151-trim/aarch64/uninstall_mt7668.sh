#!/bin/sh
set -eu

KERNEL_RELEASE="${KERNEL_RELEASE:-$(uname -r)}"
MODULE_DIR="/lib/modules/$KERNEL_RELEASE/extra/mt7668"

if [ "$(id -u)" -ne 0 ]; then
	echo "请使用 root 执行: sudo $0" >&2
	exit 1
fi

rm -f /etc/modules-load.d/mt7668.conf
rm -f /etc/modprobe.d/mt7668.conf
rm -rf "$MODULE_DIR"
depmod -a "$KERNEL_RELEASE"

echo "MT7668 自动加载配置和 KO 已移除；固件文件予以保留。"
echo "请重启系统恢复内核默认驱动。"
