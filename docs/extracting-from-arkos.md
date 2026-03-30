# Extracting Required Files from ArkOS

This project requires files from a working ArkOS/ArkOS-R3XS installation. This document covers everything that needs to be extracted and how.

## What You Need

| File | Purpose | Location in repo |
|------|---------|-----------------|
| `idbloader.img` | DDR init + initial program loader | `boards/r36h/boot/` (gitignored) |
| `uboot.img` | U-Boot bootloader | `boards/r36h/boot/` (gitignored) |
| `trust.img` | ARM Trusted Firmware | `boards/r36h/boot/` (gitignored) |
| `gameconsole-r36s.dtb` | U-Boot display DTB | `boards/r36h/dtb/` (committed) |
| Panel init sequence | Display panel init | Baked into `rk3326-gameconsole-r36s-rocknix.dtb` (committed) |

The boot blobs and U-Boot DTB are firmware/bootloader files. The panel init is hardware configuration data specific to your LCD panel variant.

## Extracting Boot Blobs

You need the ArkOS **system** SD card (the one the R36H boots from, not the roms card).

The boot blobs are stored at raw sector offsets before the first partition — they are NOT files on a filesystem.

```bash
# With the ArkOS system SD card at /dev/sdX:
mkdir -p boards/r36h/boot

# idbloader — DDR init code, at sector 64
sudo dd if=/dev/sdX of=boards/r36h/boot/idbloader.img bs=512 skip=64 count=8000

# U-Boot — main bootloader, at sector 16384
sudo dd if=/dev/sdX of=boards/r36h/boot/uboot.img bs=512 skip=16384 count=8192

# ARM Trusted Firmware — secure world, at sector 24576
sudo dd if=/dev/sdX of=boards/r36h/boot/trust.img bs=512 skip=24576 count=8192
```

These files are gitignored because they are proprietary binary blobs from Rockchip's rkbin repository, redistributed in prebuilt form by ArkOS.

## Extracting the U-Boot DTB

Mount the ArkOS boot partition (the first partition, FAT32):

```bash
sudo mount /dev/sdX1 /mnt
cp /mnt/gameconsole-r36s.dtb boards/r36h/dtb/
sudo umount /mnt
```

Note: This is `gameconsole-r36s.dtb` (no `rk3326-` prefix). U-Boot looks for this specific filename for its own display initialization.

## Extracting the Panel Init Sequence

If your R36H's display doesn't work (backlight cycling, blank screen, garbled output), you may need to regenerate the Linux DTB with your panel's init sequence. See [panel-dtb.md](panel-dtb.md) for instructions.

The included `boards/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb` was generated from an ArkOS-R3XS installation and works with Panel 4 (V5) variant R36H units.

## How to identify your panel variant

The R36H ships with different LCD panels ("panel lottery"). If the included DTB doesn't work with your display:

1. Boot ArkOS on the device
2. Use the [Panel Diagnostics script](https://github.com/AeolusUX/ArkOS-R3XS) or check `dmesg | grep panel` via SSH/serial
3. Compare the panel compatible string with known variants at [ROCKNIX R36S wiki](https://rocknix.org/devices/unbranded/game-console-r35s-r36s/)
4. Use the [R36 Panel Version Checker](https://xnlfuturetechnologies.github.io/R36-Panel-Version-Checker/dtbIdentify.htm) web tool with your ArkOS DTB

## What these files correspond to on x86

On a conventional PC, all of this is handled by the motherboard manufacturer:

| ARM (what we extract) | x86 equivalent |
|---|---|
| Boot blobs (idbloader, uboot, trust) | BIOS/UEFI firmware ROM |
| U-Boot DTB | BIOS video init / ACPI tables |
| Panel init sequence | GPU VBIOS + monitor EDID |

On x86, you install Linux and the hardware identifies itself. On ARM, you have to bring the hardware description yourself.
