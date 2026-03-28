# nixos-handheld

NixOS-based gaming OS for ARM handheld devices. Currently supports the **Game Console R36H** (RK3326).

## Supported Hardware

- **Game Console R36H** — Rockchip RK3326, Mali-G31 GPU, 1GB RAM, 640x480 display
  - Also known as R36S (vertical variant — same internals)
  - Display: NV3051D panel via ROCKNIX generic-dsi driver
  - Gamepad: odroidgo3-joypad (17 buttons + dual analog sticks)
  - Audio: RK817 codec (speaker + headphone jack)

## Building

Requires an aarch64 remote builder (e.g., Apple Silicon Mac, ARM server):

```bash
nix build .#packages.x86_64-linux.r36h-image \
  --builders 'ssh-ng://nix@your-builder aarch64-linux - - - big-parallel,kvm,nixos-test' \
  --impure --max-jobs 0
```

The image is at `result/sd-image/nixos-image-sd-card-*.img.zst`.

## Flashing

```bash
zstd -d result/sd-image/nixos-image-sd-card-*.img.zst -o nixos-r36h.img
sudo dd if=nixos-r36h.img of=/dev/sdX bs=4M status=progress conv=fsync
```

## Prerequisites — Files from a Working ArkOS/ArkOS-R3XS SD Card

The build requires boot blobs extracted from a working ArkOS installation. These cannot be generated from source yet (Phase 2 goal).

### Boot blobs

Extract from a working ArkOS SD card (the system card, not the roms card):

```bash
# With the ArkOS SD card at /dev/sdX:
mkdir -p boards/r36h/boot
sudo dd if=/dev/sdX of=boards/r36h/boot/idbloader.img bs=512 skip=64 count=8000
sudo dd if=/dev/sdX of=boards/r36h/boot/uboot.img bs=512 skip=16384 count=8192
sudo dd if=/dev/sdX of=boards/r36h/boot/trust.img bs=512 skip=24576 count=8192
```

### U-Boot DTB

Copy `gameconsole-r36s.dtb` from the ArkOS boot partition (FAT32, first partition):

```bash
# Mount the ArkOS boot partition
sudo mount /dev/sdX1 /mnt
# The file is at /mnt/gameconsole-r36s.dtb (no rk3326- prefix)
```

Update the path in `boards/r36h/default.nix` (`handheld.ubootDTB`).

### Panel init sequence (already included)

The display panel init sequence was extracted from the ArkOS DTB using ROCKNIX's `importpanel.py` and is baked into `boards/r36h/dtb/rk3326-gameconsole-r36s-rocknix.dtb`. No action needed unless your R36H has a different panel variant.

## ROMs

Put ROMs on a separate SD card (exFAT formatted, single partition) in the R36H's second card slot. They mount at `/roms`. BIOS files go in `/roms/system/`.

## What Works

- Display (640x480, Panfrost GL 3.1)
- RetroArch with rgui menu
- Gamepad (buttons + dual analog sticks)
- Audio (speaker + headphone)
- Volume buttons
- GBA (mgba), PSX (pcsx-rearmed), NDS (melonds), DOS (dosbox-pure)
- Second SD card for ROMs (exFAT)
- Start+Select opens RetroArch quick menu

## What Doesn't Work

- USB (host mode error -71, gadget mode no data)
- WiFi (no hardware on most R36H units)
- Brightness control (not configured yet)
- Sleep/suspend (not configured yet)

## Architecture

- **Kernel**: Mainline stable + ohjhas RK3326 patches
- **GPU**: Panfrost (open-source Mali-G31 driver via Mesa)
- **Display**: ROCKNIX generic-dsi panel driver with NV3051D init sequence
- **Boot**: ArkOS U-Boot blobs → boot.ini → kernel + uInitrd + DTB
- **Image**: NixOS sd-image.nix with custom firmware partition and U-Boot injection
