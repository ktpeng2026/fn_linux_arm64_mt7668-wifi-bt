# MT7668 / 6.18.18.c1151-trim / aarch64

本目录是可直接部署的归档：两个 KO、`firmware/`、安装/卸载脚本和板卡 DTB。

在目标机检查 `uname -r` 为 `6.18.18.c1151-trim`，然后运行 `sudo ./install_mt7668.sh`。DTB 不会自动安装：请先备份原 DTB，人工将本目录顶层的 `meson-g12a-x96-max_spdif_mt7668.dtb` 安装到目标机实际启动配置使用的位置，随后重启。

安装脚本会保留每台设备 `/etc/mt7668-wifi-mac` 的地址；可以通过 `sudo MT7668_WIFI_MAC=02:11:22:33:44:55 ./install_mt7668.sh` 为设备明确指定独立 MAC。完整构建与验证说明参见仓库根目录 `README.md`。
