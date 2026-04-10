# nixos-handheld

NixOS-based gaming OS for ARM handheld devices. Currently supports the **Game Console R36H** (RK3326).

Boots to [EmulationStation](https://github.com/christianhaitian/EmulationStation-fcamod) (fcamod fork, 351v branch) as a game browser, launching RetroArch cores for most systems and DraStic for Nintendo DS. No desktop environment, no compositor — everything renders directly to the DRM framebuffer via SDL2's KMSDRM backend.

## Supported Hardware

- **Game Console R36H** — Rockchip RK3326, Mali-G31 GPU, 1GB RAM, 640x480 display
  - Also known as R36S (vertical variant — same internals)
  - Display: NV3051D panel via ROCKNIX generic-dsi driver
  - Gamepad: ROCKNIX singleadc-joypad (unified buttons + dual analog sticks)
  - Audio: RK817 codec (speaker + headphone jack)

## Flake Outputs

| Output | What it does |
|---|---|
| `nixosConfigurations.r36h` | Full NixOS system configuration. Use with `nixos-rebuild boot/switch` to deploy to a running device over SSH. |
| `packages.aarch64-linux.r36h-image` | Flashable SD card image (zstd compressed). For first install. |
| `nixosModules.default` | Shared NixOS modules (emulationstation, retroarch, hardware, diagnostics). Reusable for other handhelds. |
| `overlays.default` | Custom package overlay (kernel, retroarch, emulationstation, joypad driver, panel driver, etc). |
| `legacyPackages.aarch64-linux` | Full nixpkgs set with overlay applied. |

## Flashing

After building the SD card image:

```bash
# Check lsblk first — device name varies!
zstdcat result/sd-image/*.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

## Connecting via USB

The device runs a USB gadget ethernet interface. Connect a USB cable to the device's USB-C port and configure your host:

```bash
# On your host machine, set up the USB network interface
sudo ip addr add 10.0.0.1/24 dev usb0  # interface name may vary (enp*, usb0, etc.)
sudo ip link set usb0 up

# SSH in
ssh root@10.0.0.2   # default password: nixos
```

Once connected, you can deploy changes with `nixos-rebuild switch/boot` targeting `root@10.0.0.2`.

## ROMs

Put ROMs on a separate SD card (exFAT formatted, single partition) in the R36H's second card slot. They mount at `/roms`.

The mount path is configurable via `handheld.romsDirectory` (default `/roms`); RetroArch derives its `bios`/`saves`/`states` subdirectories from it.

Create these directories on the roms card:
- `/roms/saves` — save files
- `/roms/states` — save states
- `/roms/bios` — BIOS files (e.g., `scph1001.bin` for PSX)


## Controls

- **D-pad / Left stick** — navigate EmulationStation menus
- **A** — select, **B** — back
- **Start** — open ES main menu (system info, quit, shutdown)
- **Start + Select** — open RetroArch quick menu (in-game)
- **L3 (left stick click)** — DraStic menu (in NDS games)
- **Volume Up / Down** — adjust audio volume (hardware buttons)
- **Power button (short press)** — suspend
- **Power button (long press)** — force power off

## NixOS Module Options

Both frontends are available as NixOS modules with `enable`, `package`, and `user` options:

```nix
# EmulationStation (game browser → launches RetroArch cores + DraStic)
handheld.emulationstation.enable = true;

# RetroArch kiosk mode (boots directly to RetroArch, quit = poweroff)
handheld.retroarch.enable = true;
```

Only enable one at a time. Both default to user `gamer` (uid 1000, groups: input, video, audio).

Device-specific values (ROM root, ES theme, ES config directory, DraStic state dir, systems list, diagnostics) are exposed as options so the modules are reusable for other handhelds. See `CLAUDE.md` § "Reusable module options" for the full set.

## What Works

- EmulationStation game browser with GBZ35 Mod theme
- RetroArch across + DraStic for NDS
- DraStic standalone DS emulator with R36S button mapping
- Display (640x480, Panfrost GLES, brightness control via sysfs)
- Unified gamepad (buttons + dual analog sticks as single input device)
- Audio (speaker + headphone, hardware volume buttons via triggerhappy)
- Battery level display in ES menu
- USB gadget ethernet + SSH (for headless development)
- NixOS generations (`nixos-rebuild boot/switch` over SSH)
- Suspend / resume (power button)
- Shutdown / reboot from ES menu
- Second SD card for ROMs (exFAT, automount)
- Saves and states on roms card (survive reflash)

## What Doesn't Work

- USB host (error -71, dwc2 issue)
- WiFi (no hardware on most R36H units)
- Brightness hotkeys (no button combo yet — adjust via ES Display Settings menu)

## Architecture

- **Frontend**: EmulationStation-fcamod (351v branch) with SDL2_classic KMSDRM backend
- **Emulators**: RetroArch + DraStic (NDS)
- **Kernel**: Mainline Linux 6.19 via `linuxPackages_latest` + `structuredExtraConfig`
- **GPU**: Panfrost (open-source Mali-G31 driver via Mesa)
- **Display**: Out-of-tree ROCKNIX generic-dsi panel driver with NV3051D init sequence
- **Input**: Out-of-tree ROCKNIX singleadc-joypad driver (ADC sticks + GPIO buttons as one device)
- **Boot**: Armbian U-Boot → boot.ini → kernel + initrd + DTB from ext4 rootfs
- **Generations**: Custom `installBootLoader` copies kernel/initrd/DTB to fixed paths
- **DTS**: Compiled standalone via `rk3326-dtb` package (no kernel rebuild on DTS changes)
- **Audio**: Hardware mixer at 80%, volume buttons via triggerhappy, ES volume slider
- **Image**: NixOS sd-image.nix with firmware partition and U-Boot blob injection

## References

- [Andre Renaud's R36S writeup](https://ignavus.net/r36s) — Mainline Linux on R36S: DTS, panel, boot flow
- [buildroot-r36s](https://github.com/AndreRenaud/buildroot-r36s) — Original R36S DTS and Buildroot system
- [nixos-r36s](https://github.com/icefirex/nixos-r36s) — NixOS on R36S, Armbian U-Boot
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — Generic MIPI DSI panel driver, singleadc-joypad driver
- [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) — Overlay + modules + legacyPackages pattern
- [circuix-sword](https://github.com/jecaro/circuix-sword) — NixOS handheld gaming (RetroArch on DRM/KMS)
- [dArkOS](https://github.com/christianhaitian/arkos) — Emulation stack and device support reference
- [EmulationStation-fcamod](https://github.com/christianhaitian/EmulationStation-fcamod) — ES fork with fcamod features (351v branch)

## Documentation

- [External dependencies](docs/external-dependencies.md) — vendored files, origins, and replacement paths
- [EmulationStation implementation](docs/emulationstation-implementation.md) — design decisions, package details, and module architecture
