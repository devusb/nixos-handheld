# NixOS Handheld Gaming OS — Design Spec

## Overview

A Nix flake that produces flashable SD card images for Rockchip RK3326 handheld gaming devices, starting with the R36H. Runs EmulationStation + RetroArch on a minimal NixOS system with a modern mainline-based kernel.

The long-term goal is to replace the imperative, chroot-based dArkOS build pipeline with a fully declarative, reproducible NixOS configuration that provides atomic updates, rollback, and version-controlled system definitions.

## Target Hardware

### Phase 1: R36H
- **SoC**: Rockchip RK3326 — quad-core Cortex-A35 @ 1.5GHz
- **GPU**: Mali-G31 MP2 (Panfrost open-source driver via Mesa)
- **RAM**: 1GB DDR3L
- **Display**: 3.5" IPS 640x480 (MIPI DSI, various panel manufacturers)
- **Storage**: MicroSD
- **WiFi/BT**: RTL8723BS/DS (SDIO)
- **Input**: GPIO-based joypad
- **Audio**: RK817 codec
- **USB**: Dual USB-C, HDMI out

### Phase 2: RK3566 Devices
- RG353M/V, RG503, RGB30, etc.
- Leverages nabam/nixos-rockchip which already has RK3566 infrastructure

## Kernel Strategy

Use the modern mainline-based kernel from [ohjhas/linux-stable-rk3326](https://github.com/ohjhas/linux-stable-rk3326) — Linux 6.12 stable with 7 patches on top.

### What's upstream in 6.12
- Core RK3326/PX30 SoC support (clocks, pinctrl, power domains, thermal)
- Panfrost GPU driver (Mali-G31)
- Device trees for ODROID-GO2/3, RG351M/V, GameForce Chi
- RK817 codec, audio subsystem
- RTL8723BS WiFi driver

### Out-of-tree patches needed (from ohjhas repo)
- GPIO joypad drivers (odroidgo2, odroidgo3, rgb20s, xu10, gameforce)
- Device tree files for R36S/R36H/R33S, Powkiddy, MagicX devices
- Panel driver patches (elida-kd35t133, newvision-nv3051d, st7701, st7703)
- Bluetooth fixes (btrtl/btusb)
- Rockchip bus devfreq driver
- Re-introduced input-polldev (deprecated API, needed by joypad drivers)

### Nix packaging approach
Package as a custom kernel derivation: fetch linux-stable 6.12.y, apply the 7 patches as discrete `.patch` files (extracted from the ohjhas repo, not a fork dependency). This keeps patches auditable and version-controlled.

```nix
# Simplified — actual implementation will handle config, cross-compilation
linux-rk3326 = pkgs.linuxManualConfig {
  version = "6.12.74";
  src = fetchurl { /* linux-stable tarball */ };
  configfile = ./rk3326_defconfig;
  kernelPatches = [
    { name = "rk3326-joypad-drivers"; patch = ./patches/0001-joypad-drivers.patch; }
    { name = "rk3326-device-trees"; patch = ./patches/0002-device-trees.patch; }
    { name = "rk3326-panel-drivers"; patch = ./patches/0003-panel-drivers.patch; }
    { name = "rk3326-bluetooth-fixes"; patch = ./patches/0004-bluetooth.patch; }
    { name = "rk3326-devfreq"; patch = ./patches/0005-devfreq.patch; }
    { name = "rk3326-input-polldev"; patch = ./patches/0006-input-polldev.patch; }
  ];
};
```

### Known risks
- Joypad drivers use deprecated `input-polldev` API — works now, may need rewrite for future kernel versions
- The ohjhas repo is brand new (2026-02-28) with zero community adoption — we own maintenance of these patches going forward
- Panel driver patches may not cover all R36H panel variants

## Boot Flow

### Phase 1: Use existing boot blobs
1. User provides their known-working R36H boot files (idbloader.img, uboot.img, trust.img)
2. These are `dd`'d to raw sector offsets in the SD image at build time
3. U-Boot loads `boot.ini` from FAT32 boot partition (U-Boot script format, not extlinux.conf)
4. `boot.ini` loads kernel Image, uInitrd, and DTB to fixed memory addresses, then calls `booti`
5. NixOS initrd mounts rootfs, starts systemd

#### boot.ini format (U-Boot script)
```
odroidgoa-uboot-config

setenv bootargs "root=/dev/mmcblk0p2 rootwait rw console=/dev/ttyFIQ0 quiet splash"

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x04000000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image
load mmc 1:1 ${initrd_loadaddr} uInitrd
load mmc 1:1 ${dtb_loadaddr} rk3326-r36h.dtb

booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
```

### Phase 2: Build U-Boot from source
- Package U-Boot with R36H defconfig as a Nix derivation
- Generate boot blobs (idbloader, uboot, trust) reproducibly
- Migrate to extlinux.conf if U-Boot is rebuilt with syslinux distro support
- Fully reproducible boot chain

### Phase 2: Pure builds (no --impure)
- Boot blobs currently referenced via absolute paths (requires `--impure`)
- Move boot blobs to a fetchurl or flake input so the build is fully pure
- U-Boot DTB (ArkOS BSP) also needs to be either built from source or fetched as a fixed-output derivation
- Goal: `nix build .#images.r36h` with no flags produces a complete image

### Partition Layout

**MBR (MSDOS) partitioning** — not GPT. U-Boot blobs written to raw offsets before the first partition.

#### Raw bootloader offsets (dd'd before partition table)
| Blob | Sector Offset | Byte Offset | Purpose |
|------|---------------|-------------|---------|
| idbloader.img | 64 | 32 KB | Initial program loader |
| uboot.img | 16384 | 8 MB | U-Boot proper |
| trust.img | 24576 | 12 MB | ARM Trusted Firmware |

#### Partition table (first partition starts at sector 32768 / 16 MB)
| # | Label | Size | Format | Contents |
|---|-------|------|--------|----------|
| 1 | BOOT | 100 MB | FAT32 | Kernel Image, uInitrd, DTB, boot.ini |
| 2 | ROOTFS | ~4-6 GB | btrfs (compress=zlib:1) | NixOS root filesystem |
| 3 | EASYROMS | remaining | FAT32 → exFAT on first boot | Game ROMs |

#### Filesystem notes
- btrfs with `compress=zlib:1,noatime,ssd_spread` — compression saves meaningful space on the nix store
- First-boot service expands EASYROMS partition to fill SD card and reformats as exFAT
- fstab mounts: ROOTFS at `/`, BOOT at `/boot`, EASYROMS at `/roms`
- Bind mount: `/roms/tools` → `/opt/system/Tools`

Phase 2 migrates toward NixOS-idiomatic layout (potentially using NixOS generations on rootfs).

## GPU Userspace — Mesa/Panfrost

The Mali-G31 is driven by the open-source Panfrost driver (kernel + Mesa userspace). No proprietary libmali blob needed with the mainline kernel.

### NixOS configuration
```nix
hardware.graphics = {
  enable = true;
  # Mesa with Panfrost provides GLES2/GLES3 for RetroArch
};
```

### Considerations
- RetroArch cores should use GLES2 rendering paths (better performance on Mali-G31 than GLES3)
- Shader cache should be pre-warmed or disabled to avoid stutter on first launch
- Panfrost performance on Mali-G31 is adequate for 2D and light 3D (GBA, SNES, PS1) but may struggle with heavier cores (N64, PSP) compared to the proprietary Mali blob
- If Panfrost proves insufficient for specific cores, a fallback `libmali` overlay can be created (packages the proprietary blob as a Nix derivation), but this is a last resort

## Emulation Stack

### RetroArch + Cores

dArkOS ships 81 cores for RK3326, sourced from a [custom fork](https://github.com/christianhaitian/retroarch-cores) with device-specific patches. The nixpkgs RetroArch packaging includes ~91 cores, covering most of the standard ones.

#### Core availability analysis
| Category | Examples | nixpkgs? | Notes |
|----------|----------|----------|-------|
| Standard cores | mgba, snes9x, genesis-plus-gx, fceumm, pcsx-rearmed, gambatte, fbneo, mame2003-plus, flycast, mupen64plus, melonds, desmume, ppsspp, beetle-pce-fast, picodrive, nestopia | Yes | Direct use from nixpkgs |
| Custom/patched cores | flycast_rumble, mgba_rumble, pcsx_rearmed_rumble, genesis_plus_gx_EX, DoubleCherryGB | No | dArkOS-specific patches; need custom Nix derivations or skip |
| Niche cores | freej2me, fake08, xrick, dinothawr | Partial | Some in nixpkgs, others need packaging |

#### Strategy
- **M3 (Games Run)**: Use nixpkgs cores directly — covers ~60-70% of dArkOS's core list
- **M4 (Feature Parity)**: Package remaining cores as custom derivations in the flake's `pkgs/` directory, pulling from christianhaitian's fork where needed
- All cores must be validated for aarch64 builds — some nixpkgs cores may not cross-compile cleanly

```nix
retroarch.withCores (cores: with cores; [
  mgba gpsp gambatte snes9x genesis-plus-gx picodrive
  fceumm nestopia beetle-pce-fast pcsx-rearmed
  mupen64plus parallel-n64 flycast fbneo mame2003-plus
  desmume melonds ppsspp
  # ... expanded to full list per core availability audit
]);
```

### Frontend — EmulationStation

The nixpkgs `emulationstation` package is the original Aloshi version (effectively abandoned upstream). For a handheld gaming OS, we need a maintained fork.

#### Options
1. **EmulationStation-DE** (`emulationstation-de` in nixpkgs) — actively maintained, feature-rich, but has reported aarch64 build issues and heavier resource usage
2. **Custom ES fork** — dArkOS uses a patched EmulationStation build; could package as a Nix derivation
3. **Pegasus Frontend** — modern alternative, lighter, Wayland-native

#### Decision
Start with EmulationStation-DE from nixpkgs. If it's too heavy for 1GB RAM or has aarch64 build failures, fall back to packaging dArkOS's ES fork. Evaluate during M2.

#### Configuration
- System definitions from dArkOS's `es_systems.cfg.rk3326`
- 640x480, gamepad-only navigation
- ROM paths pointing to `/roms/<system>/`
- Theme optimized for small screen

### Standalone Emulators
- `ppsspp-sdl` — PSP (if RetroArch core has performance issues)
- Others added as needed based on testing

## 32-bit (armhf) Compatibility

dArkOS installs armhf (32-bit ARM) libraries and builds some components as 32-bit. This is needed because:
- Some RetroArch cores only run as 32-bit (the `retroarch32` directory in dArkOS confirms this)
- The proprietary libmali blob (if ever needed as fallback) is 32-bit
- Some standalone emulators (e.g., Drastic) are 32-bit only

### NixOS multilib strategy
```nix
# Enable 32-bit support via pkgsCross or multilib
# NixOS does not have a built-in multilib module like Debian's dpkg --add-architecture
# Options:
# 1. Use pkgs.pkgsCross.armhf-embedded for 32-bit builds
# 2. Build a minimal armhf sysroot as a derivation
# 3. Use FHS compatibility (buildFHSEnv) for 32-bit binaries
```

#### Decision
- **Phase 1 (M1-M3)**: Skip 32-bit entirely. Use only 64-bit cores and emulators.
- **Phase 2 (M4)**: Audit which cores/emulators actually need 32-bit on modern kernels. Package the necessary 32-bit libraries as a minimal sysroot derivation. Use `buildFHSEnv` or `steam-run`-style wrappers for 32-bit binaries.
- **Risk**: If critical emulators (Drastic) are 32-bit only with no 64-bit alternative, this becomes a blocker at M4. No nixpkgs binary cache exists for armhf — all 32-bit builds are from source.

## System Configuration — NixOS Modules

### Kiosk Mode (`modules/kiosk.nix`)
- No display manager, no desktop environment
- Boot directly to EmulationStation via a systemd service
- Use cage (Wayland kiosk compositor) or direct DRM/KMS framebuffer
- Auto-login as dedicated `gamer` user (no password)
- TTY available via button combo or SSH for maintenance

### Audio (`modules/audio.nix`)
- ALSA configuration for RK817 codec
- Base state from dArkOS's `asound.state.rk3326` (default: speaker output, volume 183/237)
- Profiles: speaker, headphone (jack detect), Bluetooth (if bluealsa)
- Per-emulator ALSA overrides where needed (dArkOS has custom `alsa.conf` for mednafen, gametank)
- Volume control mapped to shoulder buttons via hotkey daemon

### Input (`modules/input.nix`)
- Joypad driver loaded via kernel module
- udev rules for consistent device naming
- EmulationStation input mapping for R36H button layout

### Networking (`modules/networking.nix`)
- NetworkManager for WiFi management
- SSH server enabled for remote management
- Optional: WiFi config tool accessible from EmulationStation menu

### Storage (`modules/storage.nix`)
- Auto-mount EASYROMS partition (exFAT) at `/roms`
- Bind mount `/roms/tools` → `/opt/system/Tools`
- First-boot service: expand EASYROMS partition to fill SD card, reformat as exFAT
- USB drive auto-mount support
- NixOS store on rootfs (btrfs with compression)

### Power Management (`modules/power.nix`)
- Safe shutdown on power button
- Suspend/resume handling (backlight, WiFi module, USB controller — per dArkOS's `sleep.rk3326`)
- Battery level reporting (RK817 charger driver)
- CPU frequency governor management (default: `ondemand`, switchable to `performance` for demanding emulators)

## Flake Structure

```
nixos-handheld/
├── flake.nix                        # Entry point
├── flake.lock
├── handhelds/
│   └── r36h/
│       ├── default.nix              # Device-specific NixOS config
│       ├── hardware.nix             # Kernel, GPU, display, input
│       ├── boot.ini                 # U-Boot script for R36H
│       └── boot/                    # User-provided boot blobs (gitignored)
│           ├── idbloader.img
│           ├── uboot.img
│           └── trust.img
├── modules/
│   ├── kiosk.nix                    # Auto-launch EmulationStation
│   ├── emulation.nix                # RetroArch + cores + ES config
│   ├── audio.nix                    # ALSA profiles
│   ├── input.nix                    # Controller mapping
│   ├── networking.nix               # WiFi, SSH
│   ├── storage.nix                  # Roms partition, auto-mount, first-boot
│   └── power.nix                    # Shutdown, suspend, battery, governor
├── pkgs/
│   ├── kernel-rk3326/
│   │   ├── default.nix              # Kernel derivation
│   │   ├── rk3326_defconfig         # Kernel config
│   │   └── patches/                 # Extracted patches from ohjhas
│   │       ├── 0001-joypad-drivers.patch
│   │       ├── 0002-device-trees.patch
│   │       └── ...
│   ├── custom-cores/                # RetroArch cores not in nixpkgs
│   │   └── default.nix
│   └── emulationstation-config/
│       └── default.nix              # ES themes, system defs, input maps
├── socs/
│   └── rk3326.nix                   # RK3326 SD card image generation module
└── docs/
    └── adding-a-board.md            # How to add new device support
```

### Build Commands

```bash
# Build R36H SD card image
nix build .#images.r36h

# Future: build for RK3566 device
nix build .#images.rg353m
```

Boot blobs are placed in `handhelds/r36h/boot/` (gitignored) before building. The image builder reads them from there.

## Resource Constraints — 1GB RAM

The R36H has only 1GB RAM. Mitigations:

- **No nix-daemon on device** — images are built on a host machine, not on the handheld. Nix is not installed on the device.
- **No desktop environment** — cage or direct framebuffer, no compositor overhead
- **Minimal services** — only what's needed: systemd, NetworkManager, EmulationStation, ALSA
- **zram swap** — compressed swap in RAM for safety
- **Core selection** — heavier cores (Dolphin, etc.) excluded for RK3326; only cores that run well in 1GB
- **btrfs compression** — reduces nix store disk footprint

### Update strategy
- **Primary**: Reflash a new image (simple, safe, no on-device Nix needed)
- **Advanced**: Build closure on host, `nix copy --to ssh://device` the closure, then run `switch-to-configuration` on device. Avoids evaluation/build on the memory-constrained device.
- On-device `nixos-rebuild` is explicitly **not supported** — 1GB RAM is insufficient for Nix evaluation.

## Milestones

### M1: Boot to TTY
- Package kernel with patches as Nix derivation
- Produce SD image with existing boot blobs dd'd to correct offsets
- Generate boot.ini pointing to NixOS kernel + initrd
- Boot R36H to NixOS TTY with working display, input, and networking
- **Success criteria**: can SSH into the device, see framebuffer output, read gamepad input via `evtest`

### M2: EmulationStation Boots
- Kiosk module working (cage or direct DRM)
- Mesa/Panfrost GPU rendering functional
- EmulationStation launches with gamepad navigation
- Audio output functional (speaker)
- **Success criteria**: ES main menu displays, can navigate with joypad

### M3: Games Run
- RetroArch with initial core set (~20 cores from nixpkgs)
- ROM paths configured, at least one system playable per category (8-bit, 16-bit, PS1)
- **Success criteria**: can launch and play a GBA game via EmulationStation → RetroArch

### M4: Feature Parity
- Full core list — nixpkgs cores + custom-packaged cores (~80 total)
- 32-bit compatibility layer for cores that need it
- WiFi configuration from ES menu
- Hotkey daemon (volume, brightness, safe shutdown)
- Bluetooth audio
- Per-emulator audio/performance tuning
- First-boot partition expansion
- **Success criteria**: daily-driver capable as a gaming handheld

### M5: Multi-Device
- Add RK3566 board definitions (RG353M first)
- Factor out shared modules vs board-specific config
- **Success criteria**: same flake produces working images for R36H and RG353M

## Prior Art & Dependencies

| Resource | Role |
|----------|------|
| [ohjhas/linux-stable-rk3326](https://github.com/ohjhas/linux-stable-rk3326) | Kernel patches source |
| [nabam/nixos-rockchip](https://github.com/nabam/nixos-rockchip) | Flake structure reference, RK3566 Phase 2 starting point |
| [AeolusUX/ArkOS-R3XS](https://github.com/AeolusUX/ArkOS-R3XS) | R36H device knowledge, panel picker reference |
| [dArkOS](https://github.com/christianhaitian/arkos) | Emulation stack config, system definitions, device configs |
| [CircuiX-Sword blog post](https://jeancharles.quillet.org/posts/2025-08-13-NixOS-in-a-gameboy-shell.html) | Image size optimization reference |
| nixpkgs RetroArch/libretro | Emulation packages (~91 cores) |
| NixOS `sd-image-aarch64.nix` | Image generation base |
| upstream U-Boot `anbernic-rgxx3-rk3566_defconfig` | Phase 2 U-Boot reference |
