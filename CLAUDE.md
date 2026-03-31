# CLAUDE.md — nixos-handheld development context

## What this is

NixOS-based gaming OS for the Game Console R36H (RK3326 ARM handheld). Boots directly to RetroArch. No desktop environment, no compositor — RetroArch renders via DRM/KMS on the bare framebuffer.

## Hardware

- **SoC**: Rockchip RK3326 — quad-core Cortex-A35 @ 1.5GHz
- **GPU**: Mali-G31 MP2 — Panfrost open-source driver via Mesa
- **RAM**: 1GB DDR3L (tight — be mindful of closure size)
- **Display**: 3.5" 640x480 MIPI DSI — NV3051D controller, panel varies by unit ("panel lottery")
- **Storage**: Two microSD slots — slot 1 is NixOS boot, slot 2 is ROMs (exFAT)
- **Input**: GPIO joypad (`r36s_Gamepad`, odroidgo3-joypad driver), volume buttons (`gpio-keys-vol`)
- **Audio**: RK817 codec, speaker + headphone jack
- **USB**: dwc2 OTG controller — currently broken for both host and gadget modes
- **WiFi**: RTL8723BS chip — unpopulated on this specific unit (no WiFi)
- **Power**: RK817 charger, power button mapped to suspend via logind

## Build commands

```bash
# Build the SD card image (requires aarch64 remote builder)
nix build --eval-store auto --store ssh-ng://nix@superintendent \
  .#packages.aarch64-linux.r36h-image --impure

# Copy result back from remote store
nix copy --no-check-sigs --from ssh-ng://nix@superintendent \
  $(nix eval --raw .#packages.aarch64-linux.r36h-image --impure)

# Decompress and flash (check lsblk first — device name varies!)
zstdcat result/sd-image/*.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

`--impure` is required because boot blobs use absolute paths (gitignored files).

### Common gotchas

- **`/dev/sda` or `/dev/sdb` becomes a regular file** after failed dd writes. Check with `ls -la /dev/sdX` — if it shows `-rw-r--r--` instead of `brw-rw----`, delete it and replug the card.
- **New files must be `git add`ed** before building — flake evaluation only sees tracked files.
- **Boot blobs are gitignored** and must exist at `boards/r36h/boot/` before building. See `docs/extracting-from-arkos.md`.
- The SD card device name changes between plugs (`sda` → `sdb` etc). Always check `lsblk` first.

## Repository structure

```
flake.nix             — nixosConfigurations.r36h, overlays.default, nixosModules.default
overlay.nix           — customizes retroarch-bare, SDL3, alsa-utils, joypad-autoconfig, parallel-n64
modules/
  default.nix         — self-applies overlay, imports all shared modules
  retroarch/
    default.nix       — RetroArch systemd service, gamer user, quit=poweroff
    settings.nix      — RetroArch --appendconfig settings (declarative, can't be overridden by user)
  hardware.nix        — GPU, backlight udev, ALSA init, power management, performance governor
  diagnostics.nix     — writes /var/log/diagnostics.txt on every boot
pkgs/
  kernel-rk3326/      — mainline Linux 6.12 + ohjhas RK3326 patches
  retroarch/          — wrapper with cores, ODROIDGO2 brightness patch, r36s_Gamepad autoconfig
boards/
  r36h/               — board-specific: boot blobs, DTBs, boot.ini, mounts
images/
  sd-image-rk3326.nix — MBR image with U-Boot blob injection at raw offsets
```

## How things work

### Boot flow

1. U-Boot (ArkOS BSP blobs at raw sector offsets) loads `boot.ini` from FAT32 firmware partition
2. `boot.ini` loads kernel Image, uInitrd, and DTB to fixed memory addresses
3. U-Boot needs `gameconsole-r36s.dtb` (no rk3326- prefix, BSP format) for its own display init
4. Linux gets `rk3326-gameconsole-r36s-rocknix.dtb` (ROCKNIX generic-dsi with panel init)
5. NixOS initrd mounts rootfs (ext4, label NIXOS_SD), hands off to stage-2 init
6. systemd starts, RetroArch service launches

### Display / Panel

The R36H ships with random LCD panels. Our DTB uses the ROCKNIX `panel-generic-dsi` driver which reads panel init bytes from a `panel_description` property in the device tree. The init sequence was extracted from a working ArkOS DTB using ROCKNIX's `importpanel.py`.

If display doesn't work on a different R36H unit, regenerate the DTB — see `docs/panel-dtb.md`.

Key discovery: U-Boot needs its own DTB (`gameconsole-r36s.dtb`, BSP format) for display init. Without it, U-Boot writes "lcd init fail, check dtb file" to `error.log` on the boot partition and the device appears dead. Always check `error.log` on the boot partition first when debugging boot issues.

### RetroArch configuration

RetroArch settings are applied via `--appendconfig` (the `retroarch-bare.wrapper` `settings` parameter). This generates a config file in the nix store that gets passed as a flag — settings cannot be overridden by the user's `~/.config/retroarch/retroarch.cfg`. This is intentional for paths like save directories.

Settings are defined in `modules/retroarch/settings.nix`. Key settings:

- `audio_driver = "alsa"` — direct ALSA, no PulseAudio/PipeWire
- `input_driver = "udev"` — reads from /dev/input directly
- `menu_driver = "rgui"` — lightest menu driver
- `system_directory = "/roms/bios"` — BIOS files on roms card
- `savefile_directory = "/roms/saves"` — saves survive reflash
- `savestate_directory = "/roms/states"` — states survive reflash
- `input_menu_toggle_gamepad_combo = "3"` — Start+Select opens quick menu

RetroArch is built without X11, Wayland, PulseAudio, PipeWire, Qt (matching circuix-sword pattern). The overlay in `overlay.nix` handles this by overriding `retroarch-bare`.

The ODROIDGO2 brightness patch (`pkgs/retroarch/odroidgo2-features.patch`) unlocks brightness control and shutdown/reboot menu items without requiring HAVE_LAKKA. Note: shutdown/reboot menu items don't actually show in rgui (only in xmb/ozone). Quit RetroArch triggers `systemctl poweroff` via `ExecStopPost`.

### Gamepad autoconfig

Button mapping is in `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/r36s_Gamepad.cfg`. Mapping was determined by remapping in RetroArch's UI, then reading the generated config from the rootfs.

Device: `r36s_Gamepad`, vendor `1`, product `4488` (0x1188).

### How to read device state without keyboard/SSH

No USB host or gadget works on this device. No WiFi. The only way to get diagnostic info:

1. **Journal on rootfs**: Mount the SD card's ext4 partition and read systemd journal:
   ```bash
   sudo mount /dev/sdX2 /mnt
   MACHINE_ID=$(ls /mnt/var/log/journal/)
   journalctl -D /mnt/var/log/journal/$MACHINE_ID --no-pager
   ```

2. **Diagnostics service**: `modules/diagnostics.nix` writes hardware info to `/var/log/diagnostics.txt` on every boot. Read it from the mounted rootfs.

3. **RetroArch verbose logs**: The service runs with `--verbose`, output goes to the journal.

4. **U-Boot error.log**: On the boot/firmware partition (FAT32, first partition):
   ```bash
   sudo mount /dev/sdX1 /mnt
   cat /mnt/error.log
   ```

5. **Roms card scripts** (for ArkOS): Can put shell scripts on the roms card that ArkOS runs from the Tools menu, writing output to the roms card. Used this to dump ArkOS dmesg for panel/hardware identification.

### How we identified the panel

1. Added a diagnostics script to ArkOS roms card that wrote `dmesg`, `/proc/device-tree/compatible`, etc. to a file
2. Found device identifies as `rockchip,rk3326-odroidgo3-linux`
3. Found ArkOS uses `panel-simple-dsi` (BSP kernel generic driver, no init commands)
4. Decompiled ArkOS DTB with `dtc` — found panel compatible `"elida,kd35t133", "simple-panel-dsi"`
5. Research found all R36S/R36H panels are NV3051D controllers — init sequences vary by panel variant
6. Used ROCKNIX's `importpanel.py` to extract the init sequence from the ArkOS DTB
7. Created custom DTB with `compatible = "rocknix,generic-dsi"` and `panel_description` property containing the extracted init

### SD card layout

MBR partitioning. U-Boot blobs at raw sector offsets before partition 1:

| Blob | Sector | Byte offset |
|------|--------|-------------|
| idbloader.img | 64 | 32 KB |
| uboot.img | 16384 | 8 MB |
| trust.img | 24576 | 12 MB |

| Partition | Label | Type | Contents |
|-----------|-------|------|----------|
| 1 | FIRMWARE | FAT32 | kernel Image, uInitrd, DTBs, boot.ini |
| 2 | NIXOS_SD | ext4 | NixOS rootfs |

Second SD card slot (roms): `mmcblk0p1`, exFAT, mounts at `/roms` via systemd automount.

### Kernel

Mainline Linux stable + 7 patches from [ohjhas/linux-stable-rk3326](https://github.com/ohjhas/linux-stable-rk3326). Patches add GPIO joypad drivers, device trees, panel drivers, Bluetooth fixes, devfreq driver, and input-polldev. Plus our `dwc2_force_mode` patch for USB host mode (didn't fix USB but kept for completeness).

Defconfig is `rk3326_defconfig` from the ohjhas repo. NixOS kernel config assertions are force-disabled (`system.requiredKernelConfig = lib.mkForce []`) because the defconfig is a fragment that `make olddefconfig` expands.

### parallel-n64 on aarch64

nixpkgs marks parallel-n64 as `badPlatforms = [ "aarch64-linux" ]` due to two build errors:
1. `nullf()` — GCC 15 rejects empty parameter list called with args. Fix: `nullf(...)`.
2. `R_AARCH64_CONDBR19` — conditional branch out of 19-bit range to `invalidate_block`. Fix: replace `b.eq invalidate_block` with `b.ne .Lskip; b invalidate_block; .Lskip:` in `linkage_aarch64.S`.

Both fixes are in `overlay.nix`. N64 emulation is marginal on this hardware — use Rice GFX plugin, HLE RSP, 320x240 native resolution.

### Closure size optimization

Current: ~4.8GB uncompressed. Main bloat sources:
- Mesa (1GB) + LLVM (586MB) — trimming Mesa to Panfrost-only would help but Mesa 26 meson options changed, needs more work
- GTK3 (312MB) — pulled in by retroarch-bare directly, can't easily remove
- linux-firmware (764MB)

Applied optimizations:
- SDL3 override: no pipewire, pulseaudio, wayland, x11, libdecor (kills GTK4/gstreamer chain)
- alsa-utils: `withPipewireLib = false`
- NixOS `profiles/minimal.nix`, disabled `all-hardware.nix` and `base.nix`
- No NetworkManager, no SSH, no DHCP

### USB status

Broken. Tried everything — `USB_ROLE_SWITCH`, `USB_DWC2_DUAL_ROLE`, `dr_mode` host/peripheral/otg, `dwc2_force_mode` kernel patch, PHY port enable/disable, `g_ether` gadget. Host mode gives error -71 (EPROTO). Gadget mode loads but host computer never sees the device.

Next things to try (from `project_usb_fixup_notes.md` in memory):
- `usbcore.old_scheme_first=1` in bootargs (dArkOSRE uses this)
- dwc2 unbind/rebind cycle
- Build dwc2 as module for runtime reset
- Try kernel 6.11 (ROCKNIX's known-working version)
- USB WiFi dongle with RTL8188EU driver

### Conventions

- Don't commit until the build succeeds
- Don't commit until tested on device if it's a functional change
- Use `lib.getExe` / `lib.getExe'` instead of `${pkg}/bin/name`
- RetroArch settings go in `modules/retroarch/settings.nix`, not inline
- Custom packages go in `pkgs/`, exposed via `overlay.nix`
- Board-specific config only in `boards/r36h/`
- Shared modules in `modules/`
- Build with remote store: `nix build --eval-store auto --store ssh-ng://nix@superintendent .#packages.aarch64-linux.r36h-image --impure`
- Copy back: `nix copy --no-check-sigs --from ssh-ng://nix@superintendent $(nix eval --raw .#packages.aarch64-linux.r36h-image --impure)`
