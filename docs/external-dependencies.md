# External Dependencies

This project imports files from external sources for hardware enablement. This document tracks what was imported, where it came from, and what it does.

## Armbian U-Boot

All files in `handhelds/r36h/blobs/` and `handhelds/r36h/firmware/` originate from the Armbian project's R36S board support.

### `u-boot-rockchip.bin`

- **Location:** `handhelds/r36h/blobs/`
- **Source:** Extracted from an Armbian R36S image by the [nixos-r36s](https://github.com/icefirex/nixos-r36s) project
- **Original source:** Built by [Armbian](https://github.com/armbian/build) from mainline U-Boot + Armbian patches + Rockchip DDR/TPL binary blob
- **What it does:** Combined U-Boot bootloader. Written to raw sector 64 of the SD card. Handles DDR init, ARM trusted firmware, and the boot process. Supports ext4 filesystem reads, which enables loading kernel/initrd/DTB from the NixOS rootfs
- **Future:** Could be replaced by building U-Boot from source using nixpkgs' `buildUBoot` with Armbian's defconfig and patches

### `PanCho.ini`

- **Location:** `handhelds/r36h/firmware/`
- **Source:** Armbian R36S board support
- **What it does:** U-Boot script that runs before boot.ini. Implements a panel variant chooser — hold R1 + D-pad to select which LCD panel variant to use. Saves the selection to U-Boot environment and `logo.env`
- **Why needed:** The Armbian U-Boot is compiled to run `PanCho.ini` before `boot.ini`

### `logo.env`

- **Location:** `handhelds/r36h/firmware/`
- **Source:** Armbian convention
- **What it does:** Single line (`PanelPathSlash=ScreenFiles/Panel 4/`) telling U-Boot which panel directory to use for its own display initialization
- **Note:** Hardcoded to Panel 4, which matches the R36H unit this was developed on. Other panel variants would need a different value

### `mipi-panel.dtbo`

- **Location:** `handhelds/r36h/firmware/panel4/`
- **Source:** Armbian board support, originally from panel vendor or Armbian's hardware enablement
- **What it does:** Device tree blob overlay containing MIPI DSI init sequence for Panel 4. Applied by boot.ini at boot time (`fdt apply`) to the kernel DTB before booting Linux
- **Note:** Only used by U-Boot for display init. Linux gets panel init from the `panel_description` property in the kernel-built DTB via the panel-generic-dsi driver

### `rg351mp-kernel.dtb`

- **Location:** `handhelds/r36h/firmware/panel4/`
- **Source:** Armbian board support
- **What it does:** Device tree blob used by U-Boot for its own display initialization (splash screen). Referenced by the PanCho.ini panel path system
- **Note:** Only used by U-Boot, not by Linux

## Kernel DTS Patch

### `0001-add-r36s-device-tree.patch`

- **Location:** `pkgs/kernel-rk3326/patches/`
- **Source:** Written by Andre Renaud, included in the [nixos-r36s](https://github.com/icefirex/nixos-r36s) repository
- **What it does:** Adds `arch/arm64/boot/dts/rockchip/rk3326-r36s.dts` to the kernel source tree. This is a complete 890-line device tree describing the R36S/R36H hardware:
  - GPIO buttons via mainline `gpio-keys` driver
  - Analog sticks via mainline `adc-joystick` + `gpio-mux` + `io-channel-mux`
  - Display via MIPI DSI with `rocknix,generic-dsi` compatible and `panel_description` init sequence (Panel 4)
  - Audio via RK817 PMIC codec over I2S
  - USB via dwc2 controller
  - SD card via Designware MMC controller
  - RK817 PMIC regulators, power management, battery
- **Based on:** Mainline ODROID-GO3 DTS (`rk3326-odroid-go.dtsi`) with R36S-specific GPIO pin mappings, panel init, and analog stick calibration
- **Why not upstream:** R36S/R36H isn't an officially supported board. Would need kernel mailing list review
- **Could be replaced:** We understand the hardware well enough to write our own DTS

### `0002-r36h-enable-second-sd-slot.patch`

- **Location:** `pkgs/kernel-rk3326/patches/`
- **Source:** Written by us
- **What it does:** Enables the SDIO controller at `ff380000` as a second SD card slot. The R36S DTS disables this because the R36S only has one SD slot. The R36H (landscape variant) has two — one for NixOS, one for ROMs

## Panel Driver

### `panel-generic-dsi.c`

- **Location:** `pkgs/panel-generic-dsi/drivers/`
- **Source:** [ROCKNIX](https://github.com/ROCKNIX/distribution) project, written by Danil Zagoskin
- **What it does:** A generic MIPI DSI panel driver (670 lines of C) that reads panel init sequences from a `panel_description` device tree property at runtime. This handles the "panel lottery" — different R36H units ship with different LCD panels that need different init sequences. The init sequence is in the DTS, not hardcoded in the driver
- **Why not mainline:** Mainline Linux prefers per-panel drivers with hardcoded init sequences. The mainline `panel_newvision_nv3051d` driver exists but doesn't support our specific panel variant's init. We blacklist the mainline driver to avoid conflicts
- **Built as:** Out-of-tree kernel module, loaded early in initrd

## What we could build from source

| Dependency | Replacement path | Difficulty |
|---|---|---|
| U-Boot blob | nixpkgs `buildUBoot` + Armbian defconfig/patches | Medium — need to identify correct config and Rockchip DDR blob |
| Panel firmware assets | Would come from the U-Boot build | Tied to U-Boot |
| R36S DTS patch | Write our own R36H-specific DTS | Low — we understand the hardware |
| Panel driver | Build from ROCKNIX git, or contribute to mainline | Low — already building from source, just vendored |

## References

- [Andre Renaud's R36S writeup](https://ignavus.net/r36s) — primary source for mainline Linux on R36S: DTS creation, panel identification, boot flow. Author of the R36S DTS patch
- [Andre Renaud's buildroot-r36s](https://github.com/AndreRenaud/buildroot-r36s) — Buildroot system for R36S, original home of the DTS
- [nixos-r36s](https://github.com/icefirex/nixos-r36s) (IJsbrand Hoek) — NixOS on R36S, where we sourced the Armbian U-Boot blob, panel assets, and DTS patch
- [ohjhas/linux-stable-rk3326](https://github.com/ohjhas/linux-stable-rk3326) — RK3326 handheld kernel patches, source of GPU reset/clock-names fix and higher OPPs
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — panel-generic-dsi driver source
