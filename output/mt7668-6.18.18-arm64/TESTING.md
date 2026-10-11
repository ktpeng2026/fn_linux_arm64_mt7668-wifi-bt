# MT7668 Linux 6.18.18 ARM64 deployment

## Files

- `meson-g12a-x96-max_spdif_mt7668.dtb`: MT7668 SDIO device tree, SDR50 up to 100 MHz.
- `wlan_mt76x8_sdio.ko`: Wi-Fi function 1 driver with CMD52 Driver Own fallback.
- `bt_mt7668.ko`: Bluetooth function 2 driver with CMD52 Driver/Firmware Own fallback.
- `firmware/`: Wi-Fi and Bluetooth firmware.

## Install firmware

```sh
install -d /lib/firmware/mediatek
install -m 0644 firmware/* /lib/firmware/
install -m 0644 firmware/mediatek/mt7668pr2h.bin /lib/firmware/mediatek/
```

The vendor Bluetooth module loads `mt7668_patch_e1_hdr.bin` or
`mt7668_patch_e2_hdr.bin` from `/lib/firmware`. The in-kernel `btmtksdio`
module loads `mediatek/mt7668pr2h.bin`.

## Verify the active device tree

After installing the DTB and rebooting:

```sh
tr -d '\0' </proc/device-tree/soc/mmc@ffe03000/wifi@1/compatible; echo
tr -d '\0' </proc/device-tree/soc/mmc@ffe03000/bluetooth@2/compatible; echo
od -An -tu4 -N4 --endian=big /proc/device-tree/soc/mmc@ffe03000/max-frequency
```

Expected values:

```text
mediatek,mt7668-wifi
mediatek,mt7668-bluetooth
100000000
```

## Shared power enables

- `GPIOX_6`: Wi-Fi power enable, active high; it is owned by the MMC `mmc-pwrseq-simple` node.
- `GPIOX_17`: shared Wi-Fi/Bluetooth enable, active high; it is held high by the `mt7668-enable` GPIO hog.
- GPIOX_6 alone follows the MMC power sequence and is deasserted high before the 200 ms startup delay.
- The experimental simultaneous GPIOX_17/GPIOX_6 pwrseq produced the same Driver Own failure and was reverted.
- `GPIOX_7` is the Wi-Fi-to-host wake input. `GPIOX_19` is the host-to-Bluetooth wake output and is held high.
- `GPIOX_18` is not used by this MT7668 board definition.

## Test the vendor drivers

Stop userspace Bluetooth UART attachment first. The invalid UART `hci1` is not
part of MT7668 SDIO.

```sh
systemctl stop bluetooth 2>/dev/null || true
systemctl stop hciuart 2>/dev/null || true
pkill hciattach 2>/dev/null || true
pkill btattach 2>/dev/null || true

modprobe -r btmtksdio btmtk 2>/dev/null || true
modprobe -r wlan_mt76x8_sdio 2>/dev/null || true

insmod ./wlan_mt76x8_sdio.ko
insmod ./bt_mt7668.ko
```

Check binding and logs:

```sh
for dev in /sys/bus/sdio/devices/*; do
    echo "$(basename "$dev"): $(basename "$(readlink -f "$dev/driver")")"
done
dmesg | grep -iE 'mt7668|btmtk|CMD52|driver own|firmware|wlan|bluetooth|mmc2|sdio' | tail -n 300
```

Bring Bluetooth up only after function 2 is bound to `bt_mt7668`:

```sh
hciconfig -a
hciconfig hci0 up
systemctl start bluetooth
bluetoothctl list
bluetoothctl show
```

The new Bluetooth driver prints `btmtk_sdio_write_own_cmd52` and the returned
`CHLPCR_BYTE1` value. For Driver Own, bit 0 must become set.
