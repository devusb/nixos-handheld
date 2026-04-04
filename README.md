# nixos-handheld

NixOS-based gaming OS for ARM handheld devices. Currently supports the **Game Console R36H** (RK3326).

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
| `nixosModules.default` | Shared NixOS modules (retroarch, hardware, diagnostics). Reusable for other handhelds. |
| `overlays.default` | Custom package overlay (kernel, retroarch, joypad driver, panel driver, etc). |
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
- Unified gamepad (buttons + dual analog sticks as single input device)
- Audio (speaker + headphone, volume buttons)
- USB gadget ethernet + SSH (for headless development)
- NixOS generations (`nixos-rebuild boot/switch` over SSH)
- Suspend / resume (power button)
- Clean shutdown (quit RetroArch)
- GBA, GB/GBC, SNES, Genesis/Game Gear/Master System, NES, PSX, Neo Geo Pocket Color, arcade (FBNeo), DOS, NDS (slow)
- Second SD card for ROMs (exFAT, automount)
- Saves and states on roms card (survive reflash)

## What Doesn't Work

- USB host (error -71, dwc2 issue)
- WiFi (no hardware on most R36H units)
- NDS at full speed (melonds ~15fps)

## Architecture

- **Kernel**: Mainline Linux 6.19 via `linuxPackages_latest` + `structuredExtraConfig`
- **GPU**: Panfrost (open-source Mali-G31 driver via Mesa), fixed at 480MHz
- **Display**: Out-of-tree ROCKNIX generic-dsi panel driver with NV3051D init sequence
- **Input**: Out-of-tree ROCKNIX singleadc-joypad driver (ADC sticks + GPIO buttons as one device)
- **Boot**: Armbian U-Boot → boot.ini → kernel + initrd + DTB from ext4 rootfs
- **Generations**: Custom `installBootLoader` copies kernel/initrd/DTB to fixed paths
- **DTS**: Plain `.dts` file copied into kernel source via `overrideAttrs postPatch`
- **RetroArch**: Custom build (no X11/Wayland/Pulse/Qt), ODROIDGO2 brightness patch
- **Audio**: Hardware mixer at 80%, RetroArch software volume control
- **Image**: NixOS sd-image.nix with firmware partition and U-Boot blob injection

## References

- [Andre Renaud's R36S writeup](https://ignavus.net/r36s) — Mainline Linux on R36S: DTS, panel, boot flow
- [buildroot-r36s](https://github.com/AndreRenaud/buildroot-r36s) — Original R36S DTS and Buildroot system
- [nixos-r36s](https://github.com/icefirex/nixos-r36s) — NixOS on R36S, Armbian U-Boot
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — Generic MIPI DSI panel driver, singleadc-joypad driver
- [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) — Overlay + modules + legacyPackages pattern
- [circuix-sword](https://github.com/jecaro/circuix-sword) — NixOS handheld gaming (RetroArch on DRM/KMS)
- [dArkOS](https://github.com/christianhaitian/arkos) — Emulation stack and device support reference

## Documentation

- [External dependencies](docs/external-dependencies.md) — vendored files, origins, and replacement paths
