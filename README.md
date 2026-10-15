# MT7668 Wi-Fi / Bluetooth（ARM64，Linux 6.18.18）

本仓库包含 MT7668 SDIO Wi-Fi 与蓝牙驱动，当前部署目标为 X96 Max（Amlogic G12A）和 `6.18.18.c1151-trim` ARM64 内核。原始驱动来自较旧的 Linux 内核；这里的内核兼容改动和发布文件针对上述目标内核，**不能保证其他内核或板卡可直接使用**。

| 功能 | SDIO ID | 模块 |
| --- | --- | --- |
| Wi-Fi | `037a:7608`，function 1 | `wlan_mt76x8_sdio.ko` |
| 蓝牙 | `037a:7668`，function 2 | `bt_mt7668.ko` |

## 发布文件

`output/mt7668-6.18.18-arm64/` 包含两个 KO、`firmware/`、安装与卸载脚本，以及 `meson-g12a-x96-max_spdif_mt7668.dtb`。只需将整个发布目录复制到目标机；目标机无需源码或内核头文件。源码固件主要位于 `MT7668-WiFi/7668_firmware/`，部署时以发布目录内的固件为准。

**先核实目标机** `uname -r` 为 `6.18.18.c1151-trim`。KO 的 `vermagic` 必须与正在运行的内核匹配；同为 6.18.18 的其他内核构建不一定兼容。

## 编译环境

以下以使用 APT 的 Ubuntu / Debian 开发环境为例。编译两个外置模块需要 **C 编译器、make、目标运行内核的完整构建头文件及其 `Module.symvers`**；仅安装发行版的通用 ARM64 头文件，不能替代飞牛定制内核 `6.18.18.c1151-trim` 的构建头文件。

### 目标 ARM64 机器上原生编译

```sh
sudo apt update
sudo apt install build-essential kmod
```

`build-essential` 包含本机 GCC 和 make；`kmod` 提供 `modinfo`、`depmod` 等检查工具。若需 **自己准备/构建内核头文件**（而非使用已准备好的目标头文件），还可能需要 `bc bison flex libssl-dev libelf-dev` 等内核构建依赖。先检查目标机是否已有匹配的内核构建目录：

```sh
uname -r
ls -l "/lib/modules/$(uname -r)/build/Module.symvers"
```

如 `build` 不存在，先取得与运行内核 **完全相同构建** 的头文件，并将 `KDIR` 指向该目录；不要直接安装不同版本的 `linux-headers-generic` 代替。下列命令在仓库根目录执行：

```sh
KDIR="/lib/modules/$(uname -r)/build"

make -C "$KDIR" M="$PWD/MT7668-WiFi/drv_wlan/MT6632/wlan" \
    ARCH=arm64 CROSS_COMPILE= -j"$(nproc)" modules

make -C MT7668-Bluetooth KERNEL_SRC="$KDIR" \
    ARCH=arm64 CROSS_COMPILE= -j"$(nproc)"
```

### x86_64 开发机交叉编译 ARM64 模块

```sh
sudo apt update
sudo apt install build-essential gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu kmod
```

`gcc-aarch64-linux-gnu` 提供 `aarch64-linux-gnu-gcc`，`binutils-aarch64-linux-gnu` 提供 ARM64 链接/汇编工具；内核构建系统还需要 **可在 x86_64 主机执行**的 host tools（例如 `fixdep`、`modpost`）。本仓库里的目标头文件若携带 ARM64 版本的 host tools，不能直接在 x86_64 运行，需要先替换成由主机编译的工具或取得正确准备的交叉编译头文件；不要把目标机的 host tools 直接当作 x86_64 可执行文件使用。

使用目标机对应的、包含配置与 `Module.symvers` 的头文件目录；不要使用仅修改过 `utsrelease.h` 的另一份内核源码来替代。以下命令从仓库根目录执行：

```sh
KDIR="$PWD/linux-headers-6.18.18.c1151-trim"

make -C "$KDIR" M="$PWD/MT7668-WiFi/drv_wlan/MT6632/wlan" \
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" modules

make -C MT7668-Bluetooth KERNEL_SRC="$KDIR" \
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"

modinfo -F vermagic MT7668-WiFi/drv_wlan/MT6632/wlan/wlan_mt76x8_sdio.ko
modinfo -F vermagic MT7668-Bluetooth/bt_mt7668.ko
```

若自行准备目标内核的构建目录，可补装 `bc bison flex libssl-dev libelf-dev`；这些是内核准备/构建工具，不是已准备好的外置模块在所有环境下都必须安装的依赖。Ubuntu 软件源中的交叉编译器版本未必与目标内核构建时的 GCC 版本一致。

确认输出为目标内核的 `6.18.18.c1151-trim SMP preempt mod_unload aarch64` 后，将两个新 KO 复制到发布目录；否则安装脚本会因版本不匹配而退出：

```sh
cp MT7668-WiFi/drv_wlan/MT6632/wlan/wlan_mt76x8_sdio.ko \
    output/mt7668-6.18.18-arm64/
cp MT7668-Bluetooth/bt_mt7668.ko output/mt7668-6.18.18-arm64/
```

目标内核使用 GCC 12.2 构建、本机使用 GCC 13.3 时，编译会提示 compiler differs；编译成功本身不代表运行时 ABI 完全兼容，须在目标机验证。

## 安装

将完整的 `output/mt7668-6.18.18-arm64/` 复制到目标机（包括 `firmware/` 和脚本），然后在目标机执行：

```sh
cd /mt7668-6.18.18-arm64
sudo ./install_mt7668.sh
```

脚本会检查 KO 的 `vermagic`，安装模块到 `/lib/modules/$(uname -r)/extra/mt7668/`，复制固件到 `/lib/firmware/`，运行 `depmod`，配置开机加载，屏蔽冲突的内核自带 `btmtksdio`，并尝试启用 `bluetooth.service`。当前仅屏蔽 `btmtksdio`，**不屏蔽** `btmtk`。

**DTB 必须人工处理**：发布目录内的 `meson-g12a-x96-max_spdif_mt7668.dtb` 不会由脚本自动替换。请先确认目标机实际使用的 DTB 路径和引导配置，备份原 DTB，再人工安装并确认引导器指向它。不要猜测启动分区路径或直接覆盖唯一可启动的 DTB。当前板卡的 Wi-Fi/蓝牙共用使能 GPIO，设备树必须与实际硬件一致。

完成 DTB 安装及脚本安装后重启；仅覆盖磁盘上的 KO 不会替换已经加载的内核模块。

### 每台设备的 Wi-Fi MAC

安装脚本在目标机生成并保存 `/etc/mt7668-wifi-mac`，同时将 `/lib/firmware/wifi.cfg` 中的 `MacOverride` 设为 `1`，`MacAddr` 设为该地址。重复安装默认沿用保存的地址；这是**本地管理地址**，并非从芯片读取的厂商烧录 MAC。若已有每台设备独立分配的合法 MAC，推荐安装时明确指定：

```sh
sudo MT7668_WIFI_MAC=02:11:22:33:44:55 ./install_mt7668.sh
```

未明确指定时，脚本根据可用的 DT 序列号、DMI UUID、`machine-id`、`eth0` 地址计算并持久保存一个地址。若多台设备由同一系统镜像克隆，**先检查这些标识是否真的不同**；仅凭脚本不能保证克隆设备的地址唯一。部署完成后逐台核对：

```sh
cat /etc/mt7668-wifi-mac
grep -E '^(MacOverride|MacAddr) ' /lib/firmware/wifi.cfg
cat /sys/class/net/wlan0/address
```

## 重启后验证

```sh
uname -r
lsmod | grep -E 'wlan_mt76x8_sdio|bt_mt7668|btmtksdio'
modinfo -n wlan_mt76x8_sdio
modinfo -n bt_mt7668
ip -br link
iw dev
hciconfig -a
systemctl status bluetooth --no-pager
bluetoothctl list
sudo btmgmt --index 0 info
```

预期两个自带模块已经加载、`btmtksdio` 未加载，出现 `wlan0` 和 SDIO `hci0`。`btmgmt` 的 `supported settings` 中有 `le` 表示控制器支持 BLE；蓝牙扫描与配对还依赖用户空间 BlueZ/D-Bus 服务。Wi-Fi 侧默认只需 `wlan0`，无须创建 AP/P2P 接口。

排查硬件绑定和驱动日志：

```sh
cat /sys/bus/sdio/devices/mmc2:0001:1/{vendor,device}
cat /sys/bus/sdio/devices/mmc2:0001:2/{vendor,device}
readlink -f /sys/bus/sdio/devices/mmc2:0001:1/driver
readlink -f /sys/bus/sdio/devices/mmc2:0001:2/driver
dmesg | grep -iE 'wlan|btmtk|firmware|sdio|WARNING|BUG:' | tail -n 150
```

`mmc2` 是本板卡的实际枚举示例；其他板卡上的 MMC 编号可能不同。

## 卸载与注意事项

```sh
sudo ./uninstall_mt7668.sh
sudo reboot
```

卸载脚本移除自动加载配置和两个 KO，但**不会**恢复原 DTB、删除已复制固件或删除 `/etc/mt7668-wifi-mac`。如需完全回滚，请人工恢复此前备份的 DTB 和固件配置。

本项目基于原 MT7668 驱动及社区移植工作；感谢原作者和测试者。
