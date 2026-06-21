# Anbernic RG28XX

Allwinner H700 handheld (landscape form factor). Renders through a [cage](https://github.com/cage-kiosk/cage) Wayland kiosk, which owns the panel and applies the rotation every client inherits.

Configuration: `handhelds/rg28xx/`. SoC wiring: `socs/h700.nix`.

## Hardware

- **SoC**: Allwinner H700 (H616 derivative) — quad-core Cortex-A53
- **GPU**: Mali-G31 (Panfrost, or the Mali blob)
- **Display**: 3.5" panel, native 480×640 portrait, mounted rotated and presented as 640×480 landscape
- **Storage**: two microSD slots — slot 1 NixOS boot, slot 2 ROMs (exFAT, `mmcblk1`)
- **Input**: pure-digital gamepad (`H700 Gamepad`, vid `0x484b` / pid `0x14df`) — no analog sticks
- **Audio**: sun4i / H616 audio codec — speaker + headphone jack
- **USB**: MUSB controller (not dwc2)
- **PMIC**: AXP717

## Display & rotation

The panel uses the mainline `panel-mipi-dpi-spi` driver, loading its init blob from `/lib/firmware/panels/` (`pkgs/rg28xx-panel-firmware`). cage's wlroots takes over the panel; because wlroots does not auto-honor the DRM panel-orientation property, the transform is set explicitly and applied by [kanshi](https://sr.ht/~emersion/kanshi/) inside the cage session:

```nix
handheld.compositor.enable = true;
handheld.compositor.outputTransform = "90";
```

cage runs as the `handheld-session` system service (`modules/compositor`) with `LIBSEAT_BACKEND=builtin` and `WLR_BACKENDS=drm,libinput`, launching EmulationStation as its child. SDL2 clients (ES, RetroArch with the `sdl2` driver, DraStic, SDL2 PortMaster ports) present through cage without per-app rotation patches; RetroArch is pinned to the `glcore` video driver, which presents over Wayland without grabbing DRM master.

## Controls

- **D-pad** — navigate EmulationStation menus
- **A** — select, **B** — back (Nintendo face-button layout: a=east, b=south, x=west, y=north)
- **M (Mode) button** — opens menus (ES main menu; RetroArch menu in-game)
- **Power** — suspend

The pad's SDL controller mapping is supplied via `SDL_GAMECONTROLLERCONFIG` (GUID computed from a CRC-16 of the device name) in the `handheld-session` environment, so everything using SDL gamecontroller honors it. There are no analog sticks.

## Boot

Uses NixOS's stock `generic-extlinux-compatible` — mainline U-Boot's `anbernic_rg35xx_h700_defconfig` is built with `CONFIG_DISTRO_DEFAULTS`, so U-Boot's scan finds `/boot/extlinux/extlinux.conf` on the ext4 rootfs and boots with `init=/nix/store/<toplevel>/init`. No custom boot loader. The U-Boot SPL blob is written at 8 KiB (sector 16), where the Allwinner BROM expects it.

## Input & kernel

The kernel is `pkgs/linux-h700` — mainline with the ROCKNIX H700 patch series and a custom `h700_defconfig` (Panfrost, AXP717 PMIC + battery, `panel-mipi-dpi-spi`, sun4i-codec, gpio-keys, USB gadget). The DTB is built standalone (`pkgs/h700-dtb`) from the ROCKNIX-patched `rg35xx-plus` base with the rg28xx panel compatible.

## Quirks & workarounds

- **Audio codec boots muted** — the sun4i / H616 codec starts with `DAC Playback Switch` off. A udev rule on `controlC*` add amixers it on (`socs/h700.nix`); without it, SDL2 audio teardown deadlocks.
- **s2idle resume wedges mmc1** — on some real-suspend resumes the sunxi-mmc controller hits `fatal err update clk timeout`, the card detaches, and `/roms` goes I/O-error. `powerManagement.resumeCommands` polls for the wedge and rebinds the `sunxi-mmc` driver to recover. `mmc1` runtime PM is pinned `on` to avoid the same timeout from autosuspend.

## What works

- Boots to EmulationStation (cage kiosk, 90° rotation) with RetroArch cores + DraStic
- Display via `panel-mipi-dpi-spi` + rotation
- Digital gamepad (SDL controller mapping), M button for menus
- Audio (sun4i-codec via PipeWire)
- PortMaster under panfrost
- USB gadget ethernet for SSH; NixOS generations over SSH

## What doesn't

- Analog sticks — the pad is digital by design
- USB host mode — MUSB host role is not yet working on mainline (parked, issue #41)
- Real suspend is survivable only via the mmc-rebind workaround above
