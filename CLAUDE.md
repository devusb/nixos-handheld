# CLAUDE.md — nixos-handheld development context

## What this is

NixOS-based gaming OS for the Game Console R36H (RK3326 ARM handheld). Boots directly to RetroArch. No desktop environment, no compositor — RetroArch renders via DRM/KMS on the bare framebuffer.

## Hardware

- **SoC**: Rockchip RK3326 — quad-core Cortex-A35 @ 1.5GHz
- **GPU**: Mali-G31 MP2 — Panfrost open-source driver via Mesa
- **RAM**: 1GB DDR3L (tight — be mindful of closure size)
- **Display**: 3.5" 640x480 MIPI DSI — NV3051D controller, panel varies by unit ("panel lottery")
- **Storage**: Two microSD slots — slot 1 is NixOS boot, slot 2 is ROMs (exFAT)
- **Input**: ROCKNIX singleadc-joypad (`r36s_Gamepad`, unified buttons + analog sticks), volume buttons (`gpio-keys-vol`)
- **Audio**: RK817 codec, speaker + headphone jack (speaker driven through HP path)
- **USB**: dwc2 OTG controller — gadget ethernet works, host mode broken (error -71)
- **WiFi**: RTL8723BS chip — unpopulated on this specific unit (no WiFi)
- **Power**: RK817 charger, power button mapped to suspend via logind

## Build commands

```bash
# Build the SD card image (requires aarch64 remote builder)
nix build --eval-store auto --store ssh-ng://nix@superintendent \
  .#packages.aarch64-linux.r36h-image
# Copy result back from remote store
nix copy --no-check-sigs --from ssh-ng://nix@superintendent \
  $(nix eval --raw .#packages.aarch64-linux.r36h-image)

# Decompress and flash (check lsblk first — device name varies!)
zstdcat result/sd-image/*.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

### Deploying to a running device

```bash
# Config/module changes (no kernel rebuild needed)
nixos-rebuild switch --target-host root@10.0.0.2 \
  --builders "ssh-ng://nix@superintendent aarch64-linux - 4 1 big-parallel" \
  --max-jobs 0 --flake .#r36h

# Kernel/DTS changes (requires reboot after deploy)
nixos-rebuild boot --target-host root@10.0.0.2 \
  --builders "ssh-ng://nix@superintendent aarch64-linux - 4 1 big-parallel" \
  --max-jobs 0 --flake .#r36h
```

For long builds (kernel rebuilds), use `nix build` on the remote store first, then `nixos-rebuild` to deploy. `nixos-rebuild` with `--builders` can time out on long kernel builds.

### Common gotchas

- **`/dev/sda` or `/dev/sdb` becomes a regular file** after failed dd writes. Check with `ls -la /dev/sdX` — if it shows `-rw-r--r--` instead of `brw-rw----`, delete it and replug the card.
- **New files must be `git add`ed** before building — flake evaluation only sees tracked files.
- The SD card device name changes between plugs (`sda` → `sdb` etc). Always check `lsblk` first.

## Repository structure

```
flake.nix             — nixosConfigurations.r36h, overlays.default, nixosModules.default, legacyPackages
overlay.nix           — callPackage wiring for all custom packages
modules/
  default.nix         — self-applies overlay, imports all shared modules
  retroarch/
    default.nix       — RetroArch systemd service, gamer user, quit=poweroff
    settings.nix      — RetroArch --appendconfig settings (declarative, can't be overridden by user)
  hardware.nix        — GPU, backlight udev, ALSA init, power management, performance governor
  diagnostics.nix     — writes /var/log/diagnostics.txt on every boot
pkgs/
  kernel-rk3326/      — mainline Linux 6.19 kernel config + DTS
    default.nix       — linuxPackages_latest.kernel.override + overrideAttrs for DTS postPatch
    rk3326-r36s.dts   — plain DTS file (copied into kernel source at build time)
    patches/          — single Makefile patch to add DTS to build
  rocknix-joypad/     — ROCKNIX singleadc-joypad out-of-tree kernel module
  panel-generic-dsi/  — ROCKNIX generic-dsi panel out-of-tree kernel module
  retroarch/          — retroarch-bare override (no X11/Wayland/Pulse/Qt, ODROIDGO2 brightness patch)
    wrapper.nix       — retroarch-handheld wrapper (cores list + settings)
  retroarch-joypad-autoconfig/ — r36s_Gamepad button mapping
  alsa-utils/         — alsa-utils with pipewire disabled
  parallel-n64/       — aarch64 build fixes for parallel-n64
  sdl3/               — SDL3 stripped of desktop dependencies (DRM/KMS console build)
handhelds/
  r36h/               — device-specific: U-Boot blob, firmware, boot.ini, mounts
socs/
  rk3326.nix          — RK3326 SD image: U-Boot blob injection, partition layout
```

## How things work

### Boot flow

1. Armbian U-Boot (`u-boot-rockchip.bin` at raw sector 64) loads `boot.ini` from ext4 rootfs
2. `boot.ini` loads kernel Image, initrd, and DTB from `/boot`, applies panel DTBO via `fdt apply`
3. NixOS initrd mounts rootfs (ext4, label NIXOS_SD), hands off to stage-2 init
4. systemd starts, RetroArch service launches

### Generations / installBootLoader

NixOS generation switching works via a custom `installBootLoader` script. Since U-Boot reads from fixed paths (not symlinks), the script copies the active generation's kernel, initrd, and DTB to `/boot/Image`, `/boot/initrd`, `/boot/dtb`. Runs automatically on `nixos-rebuild boot/switch`.

### Display / Panel

The R36H ships with random LCD panels. Our DTB uses the ROCKNIX `panel-generic-dsi` driver which reads panel init bytes from a `panel_description` property in the device tree. The init sequence was extracted from a working ArkOS DTB using ROCKNIX's `importpanel.py`.

### DTS approach

The device tree is a plain `.dts` file at `pkgs/kernel-rk3326/rk3326-r36s.dts`, copied into the kernel source tree via `overrideAttrs postPatch`. A single Makefile patch adds it to the kernel build. This avoids fragile patch files with hunk counts.

### Joypad driver

The R36H uses an analog mux (GPIO-controlled 4:1 multiplexer) to read 4 analog stick axes through a single SARADC channel. The ROCKNIX `singleadc-joypad` driver handles both ADC sticks and GPIO buttons as a single input device (`r36s_Gamepad`), so RetroArch sees one unified gamepad.

The driver is an out-of-tree kernel module at `pkgs/rocknix-joypad/`, ported from the upstream ROCKNIX version:
- `input_polled_dev` → `input_setup_polling()` (API removed in ~5.19)
- Legacy integer GPIO → `gpiod` descriptor API
- Mux GPIOs use `gpiod_set_raw_value_cansleep` (not `gpiod_set_value`) — the DTS flags are GPIO_ACTIVE_LOW but mux select lines need raw physical values
- Left stick axes inverted via `invert-absx`/`invert-absy` DTS properties
- Miyoo serial code stripped (not needed for R36H)

Autoconfig: `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/r36s_Gamepad.cfg`. Device: vendor `1`, product `4488` (0x1188).

### Audio

- Hardware mixer set to 80% (-19dB) at boot via `alsa-init` systemd service
- Service depends on `sys-devices-platform-rk817\x2dsound-sound-card0-controlC0.device` (not just `sound.target`) because the codec module loads late
- RetroArch volume buttons control software `audio_volume`, not the ALSA mixer
- Speaker is driven through the HP path — do NOT switch Playback Mux to SPK (kills audio)

### RetroArch configuration

RetroArch settings are applied via `--appendconfig` (the `retroarch-bare.wrapper` `settings` parameter). This generates a config file in the nix store that gets passed as a flag — settings cannot be overridden by the user's `~/.config/retroarch/retroarch.cfg`. This is intentional for paths like save directories.

Settings are defined in `modules/retroarch/settings.nix`. Key settings:

- `audio_driver = "alsa"` — direct ALSA, no PulseAudio/PipeWire
- `input_driver = "udev"` — reads from /dev/input directly
- `menu_driver = "rgui"` — lightest menu driver
- `menu_timedate_enable = "false"` — no RTC, clock is always wrong
- `menu_show_online_updater = "false"` — no network
- `system_directory = "/roms/bios"` — BIOS files on roms card
- `savefile_directory = "/roms/saves"` — saves survive reflash
- `savestate_directory = "/roms/states"` — states survive reflash
- `input_menu_toggle_gamepad_combo = "3"` — Start+Select opens quick menu

RetroArch is built without X11, Wayland, PulseAudio, PipeWire, Qt (matching circuix-sword pattern). The build customization is in `pkgs/retroarch/default.nix`, wired through `overlay.nix`.

The ODROIDGO2 brightness patch (`pkgs/retroarch/odroidgo2-features.patch`) unlocks brightness control and shutdown/reboot menu items without requiring HAVE_LAKKA. Note: shutdown/reboot menu items don't actually show in rgui (only in xmb/ozone). Quit RetroArch triggers `systemctl poweroff` via `ExecStopPost`.

### Debugging

Device is accessible over USB gadget ethernet at `root@10.0.0.2` (password: `nixos`). Use `journalctl`, `dmesg`, `evtest`, etc. over SSH.

If USB is not available, mount the SD card's ext4 partition to read the systemd journal:
```bash
sudo mount /dev/sdX2 /mnt
MACHINE_ID=$(ls /mnt/var/log/journal/)
journalctl -D /mnt/var/log/journal/$MACHINE_ID --no-pager
```

### How we identified the panel

1. Added a diagnostics script to ArkOS roms card that wrote `dmesg`, `/proc/device-tree/compatible`, etc. to a file
2. Found device identifies as `rockchip,rk3326-odroidgo3-linux`
3. Found ArkOS uses `panel-simple-dsi` (BSP kernel generic driver, no init commands)
4. Decompiled ArkOS DTB with `dtc` — found panel compatible `"elida,kd35t133", "simple-panel-dsi"`
5. Research found all R36S/R36H panels are NV3051D controllers — init sequences vary by panel variant
6. Used ROCKNIX's `importpanel.py` to extract the init sequence from the ArkOS DTB
7. Created custom DTB with `compatible = "rocknix,generic-dsi"` and `panel_description` property containing the extracted init

### SD card layout

MBR partitioning. Armbian U-Boot blob at raw sector 64:

| Partition | Label | Type | Contents |
|-----------|-------|------|----------|
| 1 | FIRMWARE | FAT32 | Panel firmware (PanCho.ini, panel DTBs) |
| 2 | NIXOS_SD | ext4 | NixOS rootfs, kernel/initrd/DTB at /boot |

Second SD card slot (roms): `mmcblk1p1`, exFAT, mounts at `/roms` via systemd automount.

### Kernel

Mainline Linux 6.19 via `linuxPackages_latest` with `structuredExtraConfig` for RK3326-specific modules (SARADC, GPIO, DRM, Panfrost, I2S, USB gadget). Out-of-tree modules for panel driver and joypad driver, exposed via `overlay.nix` as `pkgs.panel-generic-dsi` and `pkgs.rocknix-joypad`.

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

Host mode broken (error -71). Gadget ethernet works (`g_ether` module, device at `10.0.0.2`).

### Conventions

- All `callPackage`'d packages go in `overlay.nix`, referenced via `pkgs.*`
- Don't commit until tested on device if it's a functional change
- Use `lib.getExe` / `lib.getExe'` instead of `${pkg}/bin/name`
- RetroArch settings go in `modules/retroarch/settings.nix`, not inline
- Custom packages go in `pkgs/`, exposed via `overlay.nix`
- Device-specific config only in `handhelds/r36h/`
- Shared modules in `modules/`
- Long builds: `nix build` on remote store, then `nixos-rebuild` to deploy
- Quick config changes: `nixos-rebuild switch` directly
- Kernel/DTS changes: `nixos-rebuild boot` + reboot
- Out-of-tree module changes don't require kernel rebuild
