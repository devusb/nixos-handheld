# CLAUDE.md — nixos-handheld development context

## What this is

NixOS-based gaming OS for the Game Console R36H (RK3326 ARM handheld). Boots to EmulationStation as a game browser, which launches RetroArch cores and DraStic (NDS). No desktop environment, no compositor — everything renders via DRM/KMS on the bare framebuffer using SDL2's KMSDRM backend.

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
  default.nix         — self-applies overlay, imports all shared modules (retroarch + emulationstation)
  retroarch/
    default.nix       — RetroArch module (handheld.retroarch.enable, package, user options)
    settings.nix      — RetroArch --appendconfig settings (declarative, can't be overridden by user)
  emulationstation/
    default.nix       — ES module (handheld.emulationstation.enable, package, retroarchPackage, systems, theme, drastic, ... options)
    systems.nix       — Default systems attrset (gb, gbc, gba, ..., nds) consumed by the module's submodule-typed systems option
  hardware.nix        — GPU, backlight udev, power management, flash-friendly defaults
  diagnostics.nix     — writes /var/log/diagnostics.txt on every boot
pkgs/
  linux-rk3326/       — mainline Linux 6.19 kernel config
  rk3326-dtb/         — standalone DTS compilation (no kernel rebuild on DTS changes)
    rk3326-r36s.dts   — plain DTS file for R36H/R36S
  rocknix-joypad/     — ROCKNIX singleadc-joypad out-of-tree kernel module
  panel-generic-dsi/  — ROCKNIX generic-dsi panel out-of-tree kernel module
  SDL2_classic/       — native SDL2 2.32.6 for DRM/KMS console (not sdl2-compat/SDL3)
  freeimage/          — image loading library for ES (removed from nixpkgs, includes CVE patches)
  emulationstation-fcamod/ — ES frontend (fcamod fork, 351v branch, vendored patch)
  drastic/            — DraStic NDS emulator (prebuilt aarch64 binary from ROCKNIX)
  es-theme-gbz35-mod/ — GBZ35 Mod theme for EmulationStation
  retroarch/          — retroarch-bare override (no X11/Wayland/Pulse/Qt, ODROIDGO2 brightness patch)
  retroarch-joypad-autoconfig/ — r36s_Gamepad button mapping
  alsa-utils/         — alsa-utils with pipewire disabled
  parallel-n64/       — aarch64 build fixes for parallel-n64
  sdl3/               — SDL3 stripped of desktop dependencies (closure size optimization)
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
4. systemd starts, EmulationStation service launches

### EmulationStation

ES-fcamod (351v branch) renders via SDL2_classic's KMSDRM backend with GLES1 (Panfrost). Key design decisions:

- **SDL2_classic (not sdl2-compat/SDL3)**: nixpkgs SDL2 is now sdl2-compat backed by SDL3, which breaks both ES (creates desktop GL context instead of GLES) and DraStic (segfaults with corrupted surface stride). SDL2_classic is a hand-rolled SDL2 2.32.6 build for console DRM/KMS use.
- **351v branch (not master)**: The master branch uses libgo2 for display (requires RGA kernel driver not on mainline). 351v has libgo2 code commented out and uses plain SDL2 KMSDRM.
- **Vendored patch**: `pkgs/emulationstation-fcamod/nixos-handheld.patch` contains GCC 15 fixes, GLES context profile for Panfrost, go2 include removal, analog deadzone fix, cursor reinit fix, status bar fixes, timezone crash guard, and `@placeholder@` markers for Nix store path substitution.
- **HideWindow=true**: Critical ES setting — tears down SDL/DRM before launching games so emulators get a clean DRM context.

### DraStic (Nintendo DS)

Prebuilt aarch64 binary from ROCKNIX. Uses SDL2_classic for KMSDRM rendering.

**DRM fd closing**: ES holds DRM file descriptors for its SDL2 KMSDRM context. When ES `system()`-launches a game, `fork()` copies all fds. DraStic can't initialize its own DRM context with inherited fds. The launch command in `systems.nix` closes `/dev/dri/*` fds before exec.

**Cursor fix**: DraStic enables the DRM hardware cursor plane for touch input. On exit, the cursor persisted in ES because `SDL_ShowCursor(0)` only ran on first init. Patched to run on every reinit.

State directory at `/var/lib/drastic/` with symlinked store data and writable subdirs (config, backup, cheats, savestates, profiles).

### Generations / installBootLoader

NixOS generation switching works via a custom `installBootLoader` script. Since U-Boot reads from fixed paths (not symlinks), the script copies the active generation's kernel, initrd, and DTB to `/boot/Image`, `/boot/initrd`, `/boot/dtb`. Runs automatically on `nixos-rebuild boot/switch`.

### Display / Panel

The R36H ships with random LCD panels. Our DTB uses the ROCKNIX `panel-generic-dsi` driver which reads panel init bytes from a `panel_description` property in the device tree. The init sequence was extracted from a working ArkOS DTB using ROCKNIX's `importpanel.py`.

### DTS approach

The device tree is compiled standalone via the `rk3326-dtb` package (runs cpp + dtc on the DTS using kernel source for includes). DTS changes rebuild in ~1s instead of ~5min kernel rebuild. The DTB is referenced via `hardware.deviceTree.dtbSource` in the handheld config.

### Joypad driver

The R36H uses an analog mux (GPIO-controlled 4:1 multiplexer) to read 4 analog stick axes through a single SARADC channel. The ROCKNIX `singleadc-joypad` driver handles both ADC sticks and GPIO buttons as a single input device (`r36s_Gamepad`), so RetroArch sees one unified gamepad.

The driver is an out-of-tree kernel module at `pkgs/rocknix-joypad/`, ported from the upstream ROCKNIX version:
- `input_polled_dev` → `input_setup_polling()` (API removed in ~5.19)
- Legacy integer GPIO → `gpiod` descriptor API
- Mux GPIOs use `gpiod_set_raw_value_cansleep` (not `gpiod_set_value`) — the DTS flags are GPIO_ACTIVE_LOW but mux select lines need raw physical values
- Left stick axes inverted via `invert-absx`/`invert-absy` DTS properties
- Miyoo serial code stripped (not needed for R36H)

**Analog stick note**: The R36H's cheap ADC sticks have asymmetric physical range (~1200 left vs ~1530 right out of declared 1800). ES deadzone lowered to 12000 (from 23000) to ensure all directions register.

Autoconfig: `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/r36s_Gamepad.cfg`. Device: vendor `1`, product `4488` (0x1188).

### Audio

- Hardware mixer set to 80% (-19dB) at boot via the `alsa-init` systemd service in `handhelds/r36h/default.nix`. Lives in the device-specific config because the `After=` dep names the RK817 codec device path and the card/control values are R36H-specific. RetroArch and DraStic then do software volume on top of this baseline.
- Service depends on `sys-devices-platform-rk817\x2dsound-sound-card0-controlC0.device` (not just `sound.target`) because the codec module loads late.
- Volume buttons via triggerhappy in the ES module (runs as root, uses `amixer -c 0` to target RK817 card explicitly). RetroArch also binds `VOLUMEUP`/`VOLUMEDOWN` internally via its input settings, so in-game both the triggerhappy handler and RetroArch see the events.
- Speaker is driven through the HP path — do NOT switch Playback Mux to SPK (kills audio).

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

The ODROIDGO2 brightness patch (`pkgs/retroarch/odroidgo2-features.patch`) unlocks brightness control without requiring HAVE_LAKKA. The on-exit brightness reset is disabled (would slam to max when returning to ES).

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

Main bloat sources:
- Mesa (1GB) + LLVM (586MB) — trimming Mesa to Panfrost-only would help but Mesa 26 meson options changed, needs more work
- GTK3 (312MB) — pulled in by retroarch-bare directly, can't easily remove
- VLC (~200MB) — pulled in by ES, could use `onlyLibVLC` override
- linux-firmware (764MB)

Applied optimizations:
- SDL3 override: no pipewire, pulseaudio, wayland, x11, libdecor (kills GTK4/gstreamer chain)
- SDL2_classic: console-only build (no X11/Wayland/PulseAudio/PipeWire)
- alsa-utils: `withPipewireLib = false`
- NixOS `profiles/minimal.nix`, disabled `all-hardware.nix` and `base.nix`
- No NetworkManager, no SSH (except debug), no DHCP

### USB status

Host mode broken (error -71). Gadget ethernet works (`g_ether` module, device at `10.0.0.2`).

### Reusable module options

Modules in `modules/` are written so they can be consumed by a second in-tree
handheld or a stranger's flake. Device-specific values are exposed as options;
defaults preserve R36H behavior.

- `handheld.romsDirectory` (default `/roms`) — ROM root. RetroArch derives
  `bios`/`saves`/`states` subdirectories from this; ES systems use
  `${romsDirectory}/<system>` as the default path. The module does not create
  this directory — the consumer is responsible (R36H mounts `/roms` from the
  second SD card via `fileSystems."/roms"`).
- `handheld.emulationstation.theme.{package,name}` — theme package and the
  matching theme directory name. Defaults to the bundled `gbz35_mod`.
- `handheld.emulationstation.configDirectory` — where ES reads its XML configs
  (default `/var/lib/emulationstation/.emulationstation`).
- `handheld.emulationstation.drastic.{enable,package,stateDirectory,configFile}` —
  DraStic NDS emulator wiring. `enable` defaults to true; disable on x86_64 or
  when not wanted. When disabled, the `nds` system is removed from the default
  systems attrset and the `/var/lib/drastic` tmpfiles rules are not applied.
- `handheld.emulationstation.systems` — attrset of systems keyed by short name,
  each a submodule with `fullname`, `path`, `extensions`, `platform`, `theme`,
  `command`, and `retroarchCore`. When `command` is null and `retroarchCore`
  is set, the module generates a default RetroArch command. The ES-composed
  RetroArch wrapper's cores list is *derived* from the non-null `retroarchCore`
  fields of active systems — there is no separate `retroarchCores` option, so
  the two lists cannot drift. Remove a default system with `systems.foo = lib.mkForce null`.
- `handheld.diagnostics.enable` (default false) — boot-time hardware
  diagnostics dump to `/var/log/diagnostics.txt`. R36H enables it.

The libretro `.so` filename is derived from the package via `passthru.core`:
`lib.replaceStrings ["-"] ["_"] pkg.passthru.core + "_libretro.so"`. Example:
`libretro.beetle-ngp.passthru.core = "mednafen-ngp"` → `mednafen_ngp_libretro.so`.

### Conventions

- All `callPackage`'d packages go in `overlay.nix`, referenced via `pkgs.*`
- Don't commit until tested on device if it's a functional change
- Use `lib.getExe` / `lib.getExe'` instead of `${pkg}/bin/name`
- RetroArch settings go in `modules/retroarch/settings.nix`, not inline
- Custom packages go in `pkgs/`, exposed via `overlay.nix`
- Device-specific config only in `handhelds/r36h/`
- Shared modules in `modules/`
- Modules use `mkEnableOption` + `mkIf` pattern with `package` and `user` options
- Long builds: `nix build` on remote store, then `nixos-rebuild` to deploy
- Quick config changes: `nixos-rebuild switch` directly
- Kernel/DTS changes: `nixos-rebuild boot` + reboot
- Out-of-tree module changes don't require kernel rebuild
- ES fork changes go in `devusb/EmulationStation-fcamod` nixos-handheld branch, vendored as a patch
