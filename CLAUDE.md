# CLAUDE.md — nixos-handheld development context

## What this is

NixOS-based gaming OS for ARM handhelds — currently the Game Console R36H (Rockchip RK3326) and the Anbernic RG28XX (Allwinner H700). Boots to EmulationStation as a game browser, which launches RetroArch cores and DraStic (NDS). Shared modules and a package overlay drive both; per-device config lives in `handhelds/<device>/` and SoC wiring in `socs/<soc>.nix`.

Rendering is device-dependent: the R36H renders directly to DRM/KMS on the bare framebuffer via SDL2's KMSDRM backend; the RG28XX runs a cage Wayland kiosk that owns the panel (needed for rotation). Sections below are R36H-primary unless noted — RG28XX specifics live in its config, `socs/h700.nix`, and `docs/rg28xx.md`.

## Hardware — R36H (RK3326)

- **SoC**: Rockchip RK3326 — quad-core Cortex-A35 @ 1.5GHz
- **GPU**: Mali-G31 MP2 — Panfrost open-source driver via Mesa
- **RAM**: 1GB DDR3L (tight — be mindful of closure size)
- **Display**: 3.5" 640x480 MIPI DSI — NV3051D controller, panel varies by unit ("panel lottery")
- **Storage**: Two microSD slots — slot 1 is NixOS boot, slot 2 is ROMs (exFAT)
- **Input**: ROCKNIX singleadc-joypad (`r36s_Gamepad`, unified buttons + analog sticks), volume buttons (`gpio-keys-vol`)
- **Audio**: RK817 codec, speaker + headphone jack (speaker driven through HP path)
- **USB**: dwc2 OTG controller — OTG role switching via `usb-role-switch` (default: gadget/peripheral). Host mode works for USB audio dongles (Creative BT-W5 tested)
- **WiFi**: RTL8723BS chip — unpopulated on this specific unit (no WiFi)
- **Power**: RK817 charger, power button mapped to suspend via logind

## Hardware — RG28XX (H700)

- **SoC**: Allwinner H700 (H616 derivative) — quad-core Cortex-A53
- **GPU**: Mali-G31 — Panfrost (or Mali blob)
- **Display**: 3.5" panel, native 480x640 portrait, presented as 640x480 landscape via the cage transform
- **Storage**: Two microSD slots — slot 1 boot, slot 2 ROMs (exFAT, mmcblk1)
- **Input**: pure-digital `H700 Gamepad` (vid 0x484b, pid 0x14df) — no analog sticks
- **Audio**: sun4i / H616 codec — boots muted, unmuted by a udev rule
- **USB**: MUSB controller — gadget by default; host mode not working on mainline (#41)
- **PMIC**: AXP717; power button suspends via logind (real s2idle — see mmc quirk below)

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

Swap `r36h` → `rg28xx` throughout for the RG28XX image and config (`rg28xx-image`, `.#rg28xx`).

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
flake.nix             — nixosConfigurations.{r36h,rg28xx}, overlays.default, nixosModules.default, legacyPackages
overlay.nix           — callPackage wiring for all custom packages
modules/
  default.nix         — self-applies overlay, imports all shared modules (retroarch + emulationstation)
  retroarch/
    default.nix       — RetroArch module (handheld.retroarch.enable, package, user options)
    settings.nix      — RetroArch --appendconfig settings (declarative, can't be overridden by user)
  emulationstation/
    default.nix       — ES module (handheld.emulationstation.enable, package, retroarchPackage, systems, theme, drastic, ... options)
    systems.nix       — Default systems attrset (gb, gbc, gba, ..., nds) consumed by the module's submodule-typed systems option
  hardware.nix        — GPU, backlight udev, PipeWire (system-wide), USB role switch udev, power management
  diagnostics.nix     — writes /var/log/diagnostics.txt on every boot
  users.nix           — handheld.user (kiosk account, shared by all modules)
  compositor/         — cage Wayland kiosk + kanshi rotation (handheld.compositor)
  gpu/                — handheld.gpu.driver (panfrost/mali) + hold-button specialisation picker
  portmaster/         — PortMaster FHS sandbox wiring (handheld.portmaster)
pkgs/
  linux-rk3326/       — R36H mainline kernel config
  linux-h700/         — RG28XX kernel; ROCKNIX patch series, version pinned to match the rev
  rk3326-dtb/         — standalone DTS compilation (no kernel rebuild on DTS changes)
    rk3326-r36s.dts   — plain DTS file for R36H/R36S
  h700-dtb/           — standalone RG28XX DTB (ROCKNIX rg35xx-plus base + rg28xx panel)
  rg28xx-panel-firmware/ — RG28XX panel init blob (panel-mipi-dpi-spi)
  u-boot-rg28xx-rocknix/ — prebuilt ROCKNIX SPL+U-Boot blob for H700
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
  flycast2021/        — lighter Dreamcast core for weaker SoCs
  sdl3/               — SDL3 stripped of desktop dependencies (closure size optimization)
handhelds/
  r36h/               — device-specific: U-Boot blob, firmware, boot.ini, mounts
  rg28xx/             — device-specific: gamepad GUID, panel firmware, ES/DraStic configs
socs/
  rk3326.nix          — RK3326 SD image: U-Boot blob injection, custom boot loader
  h700.nix            — H700 SD image: U-Boot SPL offset, extlinux, codec/mmc quirks
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

- **PipeWire** manages audio routing — runs system-wide (`services.pipewire.systemWide = true`) to avoid user session race conditions. The `gamer` user is in the `pipewire` group.
- PipeWire auto-switches between built-in speaker (RK817 codec) and USB audio devices when plugged/unplugged.
- RetroArch, ES, and DraStic all use ALSA, which PipeWire intercepts via `pipewire-alsa`. No app-level config changes needed.
- Volume buttons via triggerhappy (runs as root, uses `wpctl set-volume @DEFAULT_AUDIO_SINK@` to target the active PipeWire sink)
- ES service requires PipeWire/WirePlumber — without this, ES starts before the ALSA sink is initialized and the volume overlay doesn't work.
- Speaker is driven through the HP path — do NOT switch Playback Mux to SPK (kills audio)
- **NixOS module bug**: `wireplumber.extraConfig` does not wire configs into the system service's `XDG_DATA_DIRS` when `systemWide = true`. Use `wireplumber.configPackages` with `pkgs.writeTextDir` instead.

### USB OTG

The dwc2 controller supports OTG role switching at runtime via the kernel's `usb-role-switch` class. The DTS sets `dr_mode = "otg"` with `role-switch-default-mode = "peripheral"` so the device boots in gadget mode (SSH works).

**Runtime switching** via sysfs:
```bash
# Switch to host (for USB peripherals)
echo "host" > /sys/class/udc/ff300000.usb/device/usb_role/ff300000.usb-role-switch/role

# Switch to gadget (for SSH via USB ethernet)
echo "device" > /sys/class/udc/ff300000.usb/device/usb_role/ff300000.usb-role-switch/role
```

A udev rule (`RUN+=chmod/chgrp`, not `MODE`/`GROUP` — sysfs attributes need explicit chmod) makes the role switch sysfs writable by the `users` group so scripts launched from ES (as `gamer`) can toggle it. The port can only be one role at a time — host mode means no SSH, gadget mode means no USB peripherals.

### RG28XX / H700 specifics

RG28XX diverges from the R36H-primary notes above. Full detail in
`docs/rg28xx.md`, `socs/h700.nix`, and `handhelds/rg28xx/`.

- **Rendering**: cage Wayland kiosk (`modules/compositor`) runs as the
  `handheld-session` service (`LIBSEAT_BACKEND=builtin`,
  `WLR_BACKENDS=drm,libinput`) and launches ES as its child. kanshi applies
  the 90° transform (`handheld.compositor.outputTransform`). RetroArch is
  pinned to `glcore` so it presents over Wayland without grabbing DRM master.
- **Boot**: stock `generic-extlinux-compatible` — no custom boot.ini or
  installBootLoader. U-Boot scans `/boot/extlinux/extlinux.conf` and boots a
  store-path `init=`; SPL at 8 KiB.
- **Kernel**: `pkgs/linux-h700` — self-sourced mainline pinned to match the
  ROCKNIX H700 patch rev. The kernel version and ROCKNIX rev move as a pair
  (their `package.mk` H700 case dictates the version). DTB via `pkgs/h700-dtb`.
- **Display**: `panel-mipi-dpi-spi` + `pkgs/rg28xx-panel-firmware` init blob.
- **Input**: digital `H700 Gamepad`, mapped via `SDL_GAMECONTROLLERCONFIG` in
  the session env; M button bound to menus. No analog sticks.
- **Audio**: sun4i / H616 codec boots muted; a udev rule amixers it on.
- **USB**: MUSB, gadget by default; host mode not working on mainline (#41).
- **mmc quirk**: real s2idle resume can wedge sunxi-mmc; `resumeCommands`
  rebind recovers it and mmc1 runtime PM is pinned `on`.

### RetroArch configuration

RetroArch settings are applied via `--appendconfig` (the `retroarch-bare.wrapper` `settings` parameter). This generates a config file in the nix store that gets passed as a flag — settings cannot be overridden by the user's `~/.config/retroarch/retroarch.cfg`. This is intentional for paths like save directories.

Settings are defined in `modules/retroarch/settings.nix`. Key settings:

- `audio_driver = "alsa"` — ALSA, routed through PipeWire via pipewire-alsa
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

Mainline Linux 6.19 via `linuxPackages_latest` with `structuredExtraConfig` for RK3326-specific modules (SARADC, GPIO, DRM, Panfrost, I2S, USB gadget, USB audio, Bluetooth). Out-of-tree modules for panel driver and joypad driver, exposed via `overlay.nix` as `pkgs.panel-generic-dsi` and `pkgs.rocknix-joypad`.

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
- `nix.registry = lib.mkForce {}` — prevents nixpkgs source (~300MB) from being copied to the device

### USB status

OTG role switching works. Boots in gadget/peripheral mode (`g_ether` module, device at `10.0.0.2`). Host mode works — USB audio dongles enumerate and are picked up by PipeWire automatically. The error -71 that was previously seen with host mode was resolved by switching from `dr_mode = "peripheral"` to `dr_mode = "otg"` with `usb-role-switch` in the DTS.

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
- Device-specific config only in `handhelds/<device>/`
- Shared modules in `modules/`
- Modules use `mkEnableOption` + `mkIf` pattern with `package` and `user` options
- Long builds: `nix build` on remote store, then `nixos-rebuild` to deploy
- Quick config changes: `nixos-rebuild switch` directly
- Kernel/DTS changes: `nixos-rebuild boot` + reboot
- Out-of-tree module changes don't require kernel rebuild
- ES fork changes go in `devusb/EmulationStation-fcamod` nixos-handheld branch, vendored as a patch
