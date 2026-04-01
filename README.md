# nixos-handheld

NixOS-based gaming OS for ARM handheld devices. Currently supports the **Game Console R36H** (RK3326).

## Supported Hardware

- **Game Console R36H** — Rockchip RK3326, Mali-G31 GPU, 1GB RAM, 640x480 display
  - Also known as R36S (vertical variant — same internals)
  - Display: NV3051D panel via ROCKNIX generic-dsi driver
  - Gamepad: odroidgo3-joypad (17 buttons + dual analog sticks)
  - Audio: RK817 codec (speaker + headphone jack)

## Building

Requires an aarch64 remote builder or native aarch64 machine:

```bash
# Build on remote store (recommended)
nix build --eval-store auto --store ssh-ng://nix@your-builder \
  .#packages.aarch64-linux.r36h-image --impure

# Copy result back
nix copy --no-check-sigs --from ssh-ng://nix@your-builder \
  $(nix eval --raw .#packages.aarch64-linux.r36h-image --impure)
```

The `--impure` flag is required because boot blobs are not tracked in git (see Prerequisites below).

## Flashing

```bash
zstd -d result/sd-image/nixos-image-sd-card-*.img.zst -o nixos-r36h.img
sudo dd if=nixos-r36h.img of=/dev/sdX bs=4M status=progress conv=fsync
```

## Prerequisites — Files from a Working ArkOS/ArkOS-R3XS SD Card

The build requires U-Boot boot blobs extracted from a working ArkOS installation. These cannot be generated from source yet.

### Boot blobs

Extract from a working ArkOS SD card (the system card, not the roms card):

```bash
mkdir -p handhelds/r36h/boot
sudo dd if=/dev/sdX of=handhelds/r36h/boot/idbloader.img bs=512 skip=64 count=8000
sudo dd if=/dev/sdX of=handhelds/r36h/boot/uboot.img bs=512 skip=16384 count=8192
sudo dd if=/dev/sdX of=handhelds/r36h/boot/trust.img bs=512 skip=24576 count=8192
```

### Panel init sequence (already included)

The display panel init sequence was extracted from the ArkOS DTB using ROCKNIX's `importpanel.py` and is baked into `handhelds/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb`. No action needed unless your R36H has a different panel variant (see the [R36S panel lottery](https://rocknix.org/devices/unbranded/game-console-r35s-r36s/)).

## ROMs

Put ROMs on a separate SD card (exFAT formatted, single partition) in the R36H's second card slot. They mount at `/roms`.

Create these directories on the roms card:
- `/roms/saves` — save files
- `/roms/states` — save states
- `/roms/bios` — BIOS files (e.g., `scph1001.bin` for PSX)

## Controls

- **Start + Select** — open RetroArch quick menu
- **Volume Up / Down** — adjust audio volume
- **Power button (short press)** — suspend
- **Power button (long press)** — force power off
- **Quit RetroArch** (from main menu) — clean shutdown

## What Works

- Display (640x480, Panfrost GL, brightness control)
- RetroArch with rgui menu (direct DRM/KMS, no compositor)
- Gamepad (buttons + dual analog sticks)
- Audio (speaker + headphone, volume buttons)
- Suspend / resume (power button)
- Clean shutdown (quit RetroArch)
- GBA, GB/GBC, SNES, Genesis/Game Gear/Master System, NES, PSX, Neo Geo Pocket Color, arcade (FBNeo), DOS, NDS (slow)
- Second SD card for ROMs (exFAT, automount)
- Saves and states on roms card (survive reflash)

## What Doesn't Work

- USB host (error -71, likely kernel 6.12 dwc2 regression)
- USB gadget (g_ether loads but host doesn't see device)
- WiFi (no hardware on most R36H units)
- NDS at full speed (melonds ~15fps, needs DraStic which requires armhf)

## Architecture

- **Kernel**: Mainline stable + [ohjhas RK3326 patches](https://github.com/ohjhas/linux-stable-rk3326)
- **GPU**: Panfrost (open-source Mali-G31 driver via Mesa)
- **Display**: ROCKNIX generic-dsi panel driver with NV3051D init sequence
- **Boot**: ArkOS U-Boot blobs → boot.ini → kernel + uInitrd + DTB
- **RetroArch**: Custom build (no X11/Wayland/Pulse/Qt), ODROIDGO2 brightness patch
- **Image**: NixOS sd-image.nix with custom firmware partition and U-Boot injection
- **Structure**: overlay + modules + legacyPackages ([Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) pattern)

## Flake Outputs

- `nixosConfigurations.r36h` — full NixOS system configuration
- `nixosModules.default` — shared modules (retroarch, hardware, diagnostics)
- `overlays.default` — custom packages
- `legacyPackages.aarch64-linux` — full nixpkgs set with overlay applied
- `packages.aarch64-linux.r36h-image` — flashable SD card image

## References

- [Andre Renaud's R36S writeup](https://ignavus.net/r36s) — Mainline Linux on R36S: DTS, panel, boot flow
- [buildroot-r36s](https://github.com/AndreRenaud/buildroot-r36s) — Original R36S DTS and Buildroot system
- [nixos-r36s](https://github.com/icefirex/nixos-r36s) — NixOS on R36S, Armbian U-Boot, deploy-rs
- [ohjhas/linux-stable-rk3326](https://github.com/ohjhas/linux-stable-rk3326) — RK3326 kernel patches, GPU/CPU OPPs
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — Generic MIPI DSI panel driver
- [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) — Overlay + modules + legacyPackages pattern
- [nabam/nixos-rockchip](https://github.com/nabam/nixos-rockchip) — Rockchip NixOS SD image generation, extlinux boot
- [circuix-sword](https://github.com/jecaro/circuix-sword) — NixOS handheld gaming (RetroArch on DRM/KMS)
- [dArkOS](https://github.com/christianhaitian/arkos) — Emulation stack and device support reference

## Documentation

- [Extracting files from ArkOS](docs/extracting-from-arkos.md) — how to get the boot blobs, U-Boot DTB, and panel init
- [Generating the panel DTB](docs/panel-dtb.md) — regenerate the display DTB for a different panel variant
- [Design spec](docs/design.md)
- [M1 implementation plan](docs/m1-plan.md)
