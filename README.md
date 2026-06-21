# nixos-handheld

NixOS-based gaming OS for ARM handheld devices. Boots to [EmulationStation](https://github.com/christianhaitian/EmulationStation-fcamod) (fcamod fork, 351v branch) as a game browser, launching RetroArch cores for most systems and DraStic for Nintendo DS.

Shared NixOS modules and a custom package overlay drive every device. Per-device configuration lives under `handhelds/<device>/` and SoC wiring under `socs/`. How frames reach the panel depends on the device — some render directly to the DRM framebuffer via SDL2's KMSDRM backend, others through a [cage](https://github.com/cage-kiosk/cage) Wayland kiosk.

## Supported Devices

| Device | SoC | Display | Input |
|---|---|---|---|
| [Game Console R36H](docs/r36h.md) | Rockchip RK3326 | 640×480 NV3051D, bare DRM/KMS | Unified pad + dual analog sticks |
| [Anbernic RG28XX](docs/rg28xx.md) | Allwinner H700 | 480×640 panel rotated to 640×480 landscape via cage | Pure-digital pad |

Both use the Mali-G31 GPU (Panfrost by default, optional Mali blob).

## Flake Outputs

| Output | What it does |
|---|---|
| `nixosConfigurations.{r36h,rg28xx}` | Full NixOS system configuration. Use with `nixos-rebuild boot/switch` to deploy to a running device over SSH. |
| `packages.aarch64-linux.{r36h,rg28xx}-image` | Flashable SD card image (zstd compressed). For first install. |
| `legacyPackages.aarch64-linux.nixos-{r36h,rg28xx}` | `system.build.toplevel` for each device. |
| `nixosModules.default` | Shared NixOS modules (emulationstation, retroarch, compositor, gpu, portmaster, hardware, diagnostics). Reusable for other handhelds. |
| `overlays.default` | Custom package overlay (per-SoC kernels, retroarch, emulationstation, joypad/panel drivers, etc). |
| `legacyPackages.aarch64-linux` | Full nixpkgs set with the overlay applied. |

## Building & Flashing

```bash
# Build the SD card image for your device (requires an aarch64 builder)
nix build .#packages.aarch64-linux.rg28xx-image    # or r36h-image

# Check lsblk first — the device name varies between plugs!
zstdcat result/sd-image/*.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

## Connecting via USB

Devices boot in USB gadget (peripheral) mode with a USB ethernet interface at `10.0.0.2`:

```bash
# On your host machine
sudo ip addr add 10.0.0.1/24 dev usb0   # host interface name varies (enp*, usb0, ...)
sudo ip link set usb0 up

ssh root@10.0.0.2                        # default password: nixos
```

Then deploy changes with `nixos-rebuild switch/boot` targeting `root@10.0.0.2`. USB controller behavior (OTG role switching, host mode) differs per device — see the device pages.

## ROMs

Put ROMs on a separate SD card (exFAT formatted, single partition) in the device's second card slot. They mount at `/roms`.

The mount path is set by `handheld.romsDirectory` (default `/roms`); RetroArch derives its `bios`/`saves`/`states` subdirectories from it. Create on the roms card:

- `/roms/saves` — save files
- `/roms/states` — save states
- `/roms/bios` — BIOS files (e.g. `scph1001.bin` for PSX)

## Frontends & Module Options

Both frontends are NixOS modules with `enable`, `package`, and `user` options:

```nix
# EmulationStation (game browser → launches RetroArch cores + DraStic)
handheld.emulationstation.enable = true;

# RetroArch kiosk mode (boots directly to RetroArch, quit = poweroff)
handheld.retroarch.enable = true;
```

Enable one at a time. The kiosk account defaults to `gamer` (uid 1000, groups: input, video, audio, pipewire) via `handheld.user`. Device-specific values (ROM root, ES theme, ES config directory, DraStic state dir, systems list, compositor transform, diagnostics) are exposed as options so the modules are reusable for other handhelds. See `CLAUDE.md` § "Reusable module options" for the full set.

## GPU Modes (Panfrost vs Mali)

Two GPU stacks share a single set of generations:

- **Panfrost** (default) — open-source Mali-G31 driver via Mesa. Better for RetroArch cores.
- **Mali** — ARM proprietary blob (`mali_kbase` kernel module + `libmali` userspace, unfree). Better for native PortMaster ports.

`handheld.gpu.driver` sets the default. Mali is a NixOS specialisation of the panfrost base; `handheld.gpu.specialisation.{enable,picker.enable}` adds a hold-button initrd picker that repoints the boot closure to the alternate specialisation before `find-nixos-closure` runs. The picker is enabled on R36H (hold Volume Down at power-on) — see its page.

## PortMaster

`handheld.portmaster.enable = true` wires a `buildFHSEnv` bwrap sandbox (`pkgs/portmaster-fhs`) that provides the standard Linux library layout PortMaster's prebuilt binaries expect (`/usr/lib`, `/lib64`, dynamic loader). Launch scripts (`/roms/ports/*.sh`) call `portmaster-launch`, which enters the sandbox and exports `CFW_NAME=NixOS` so PortMaster's launchers source `/roms/ports/PortMaster/mod_NixOS.txt` for control wiring. Runs in both GPU modes; faster on mali. Control wiring is device-specific.

## Architecture (shared)

- **Frontend**: EmulationStation-fcamod (351v branch) on SDL2_classic
- **Emulators**: RetroArch + DraStic (NDS)
- **GPU**: Panfrost (Mesa) or the Mali blob (libmali + mali_kbase)
- **Kernel**: per-SoC package (`pkgs/linux-rk3326`, `pkgs/linux-h700`) with `structuredExtraConfig` / a custom defconfig
- **Image**: NixOS `sd-image.nix` with a U-Boot blob injected at a SoC-specific offset and a firmware partition
- **Modules / overlay**: shared modules in `modules/`; custom packages in `pkgs/` exposed via `overlay.nix`

Per-device boot, panel, input, and USB details are on the device pages.

## References

- [Andre Renaud's R36S writeup](https://ignavus.net/r36s) — Mainline Linux on R36S: DTS, panel, boot flow
- [buildroot-r36s](https://github.com/AndreRenaud/buildroot-r36s) — Original R36S DTS and Buildroot system
- [nixos-r36s](https://github.com/icefirex/nixos-r36s) — NixOS on R36S, Armbian U-Boot
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — Panel/joypad drivers, H700 kernel patches and quirks
- [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS) — Overlay + modules + legacyPackages pattern
- [circuix-sword](https://github.com/jecaro/circuix-sword) — NixOS handheld gaming (RetroArch on DRM/KMS)
- [dArkOS](https://github.com/christianhaitian/arkos) — Emulation stack and device support reference
- [EmulationStation-fcamod](https://github.com/christianhaitian/EmulationStation-fcamod) — ES fork with fcamod features (351v branch)

## Documentation

- [Game Console R36H](docs/r36h.md) — RK3326 hardware, boot, panel, input, GPU picker, USB OTG
- [Anbernic RG28XX](docs/rg28xx.md) — H700 hardware, cage compositor, extlinux boot, panel, input, quirks
- [External dependencies](docs/external-dependencies.md) — vendored files, origins, and replacement paths
