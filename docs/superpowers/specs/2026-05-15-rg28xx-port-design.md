# Design: Anbernic RG28XX port

**Date:** 2026-05-15
**Status:** Design (pre-implementation)
**Branch:** `feature/nixos-handheld-rg28xx`

## Summary

Add support for the Anbernic RG28XX (Allwinner H700) as a second device alongside the existing R36H (Rockchip RK3326). The work is a speculative full port — hardware is not in hand at design time — so the spec calls out every assumption that must be verified against ROCKNIX sources or the actual device before flashing.

The existing `socs/` / `handhelds/` / `modules/` separation already supports adding a second SoC family with minimal refactoring; most of the work is new SoC-specific packages and a new device directory.

## Hardware (per ROCKNIX)

- **SoC**: Allwinner H700 — quad Cortex-A53 @ 1.4 GHz (overclockable 1.5 GHz)
- **GPU**: Mali-G31 MP2 — Panfrost open-source driver via Mesa (same as R36H)
- **RAM**: 1 GB LPDDR4
- **Display**: 2.8" 640×480 IPS (orientation TBD — likely landscape-native given the horizontal form factor)
- **Storage**: Two microSD slots (system + ROMs) — same dual-card layout as R36H
- **Input**: Standard gamepad layout (D-Pad, A/B/X/Y, L1/R1/L2/R2, Start/Select/Menu) plus dual analog sticks
- **Audio**: Codec not specified by ROCKNIX docs — verify
- **PMIC**: Not specified — H700 reference designs use AXP717 or AXP313, verify
- **USB**: H700 supports USB-OTG via MUSB controller
- **WiFi/BT**: **None** (no wireless hardware on this device)
- **LED**: Multi-color status LED (out of scope for v1)
- **Suspend**: H700 mainline does not support real S3; ROCKNIX implements "fake suspend"

## Decisions (settled during brainstorming)

| Topic | Decision |
| --- | --- |
| Scope | Full speculative port — refactor + RG28XX-specific code now |
| ROM storage | Dual-card layout (same as R36H); ROMs on second SD as exFAT |
| U-Boot | Vendored ROCKNIX H700 blob for v1; design for easy swap to from-source later |
| Kernel package | Separate `pkgs/linux-h700` (no shared `linux-handheld` base — YAGNI) |
| DTS build | Standalone `pkgs/h700-dtb` package (mirrors `pkgs/rk3326-dtb`) |
| Refactor scope | Minimal — `modules/` are already SoC-agnostic; add a new `socs/h700.nix` |

## Architecture

### Repo additions

```
flake.nix                         — add nixosConfigurations.rg28xx + packages.aarch64-linux.rg28xx-image + check
socs/h700.nix                     — Allwinner H700 SD image module (counterpart to rk3326.nix)
modules/fake-suspend.nix          — opt-in NixOS module providing handheld.fakeSuspend.* options; disabled by default, enabled in RG28XX
handhelds/rg28xx/
  default.nix                     — device-level NixOS config
  blobs/u-boot-sunxi.bin          — vendored ROCKNIX H700 SPL+U-Boot combined blob
  extlinux.conf                   — distroboot template (only if custom installBootLoader is chosen; omitted if stock generic-extlinux-compatible suffices)
  es_input.cfg                    — ES gamepad input config
  drastic.cfg                     — DraStic config
pkgs/
  linux-h700/                     — kernel package (linuxManualConfig + static h700_defconfig)
  h700-dtb/                       — standalone DTS build for sun50i-h700-anbernic-rg28xx.dts (skip if mainline already ships this DTS; see verification #3)
  u-boot-rg28xx/                  — wraps the vendored blob; design for easy from-source swap
  (panel + joypad drivers)        — reuse existing or add new; see "Open questions"
```

### Shared modules (unchanged)

`modules/hardware.nix`, `modules/diagnostics.nix`, `modules/options.nix`, `modules/retroarch/*`, `modules/emulationstation/*` already operate on SoC-agnostic abstractions (PipeWire system-wide, backlight udev by subsystem, USB role-switch udev by subsystem, `handheld.romsDirectory`, etc.). No changes required for the port itself; small additions may be needed if H700 hardware behaves differently than expected (e.g., USB role-switch under MUSB).

### `socs/h700.nix`

Mirrors `socs/rk3326.nix`. Differences:

- **U-Boot raw offset**: SPL at sector 16 (8 KiB) on most Allwinner SoCs, with U-Boot proper following — but **this is not verified for H700/ROCKNIX**. Implementation must verify by examining the ROCKNIX blob (`eGON.BT0` magic in `hexdump`) and ROCKNIX's image build script before committing the `dd` invocation.
- **Boot loader**: Allwinner U-Boot typically uses distroboot — either `/boot/extlinux/extlinux.conf` (syslinux-style) or a compiled `boot.scr` (`mkimage`-wrapped script). Determine which from the ROCKNIX U-Boot env.
- **`installBootLoader`**: copies `kernel`/`initrd`/`dtb` from the active generation to fixed paths (same trick as R36H) and rewrites `extlinux.conf` (or `boot.scr`) accordingly. Inherits the kernel cmdline from NixOS `boot.kernelParams`.

  *Alternative considered:* NixOS ships `boot.loader.generic-extlinux-compatible` which handles distroboot natively (including generation-aware menu entries). If ROCKNIX's H700 U-Boot does proper distroboot scanning of the firmware/rootfs partitions, the stock module may be a better fit than a hand-rolled installer. R36H needed a custom installer because Armbian U-Boot reads fixed paths only — that constraint does not necessarily apply on Allwinner. Decision deferred to implementation, after we examine the ROCKNIX U-Boot environment. If the stock module fits, we use it (less code to maintain); if not, we fall back to a custom installer matching the R36H pattern.
- **Partition layout**: same two-partition MBR (FAT32 firmware + ext4 NixOS rootfs) for parity with R36H.

### `handhelds/rg28xx/default.nix`

Structurally identical to `handhelds/r36h/default.nix`. Differences:

- `boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-h700`
- DTB: `hardware.deviceTree.{dtbSource = "${pkgs.h700-dtb}"; name = "sun50i-h700-anbernic-rg28xx.dtb";}` (mainline naming)
- No `panChoIni` / `logoEnv` / `panelDtbo` (R36H's panel lottery is a Rockchip workaround; RG28XX ships a single fixed DTB)
- `boot.kernelModules`: drops `rockchip_saradc`, adds `sun4i_gpadc_iio`, `axp20x_*`, sunxi audio modules — exact list determined in implementation
- `boot.initrd.kernelModules`: drops `rockchipdrm`, adds `sun4i_drm`, `sun8i_mixer`, `panfrost` (panfrost stays), panel driver
- `networking.hostName = "rg28xx"`
- USB gadget ethernet at `10.0.0.2` — same plan as R36H, contingent on MUSB role-switch behaving the same way (verify)
- `SDL_GAMECONTROLLERCONFIG`: different vendor/product IDs (TBD from `evtest` on a working unit)
- `handheld.emulationstation.enable = true` + ES input/DraStic config files
- `/roms` mount stays `/dev/mmcblk1p1` exFAT, same automount
- `handheld.fakeSuspend.enable = true` (see "Fake suspend" below)
- `services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore"` (the fake-suspend module owns the power button — overrides the default in `modules/hardware.nix`)

### Fake suspend (`modules/fake-suspend.nix`)

H700 mainline has no working suspend-to-RAM. ROCKNIX implements a *userspace-only* "fake suspend" — the device appears suspended but is actually still running with display off, audio muted, inputs grabbed, and CPU governor pinned to powersave. We mirror this design.

**Why not systemd-suspend hooks**: systemd-suspend (even with `SuspendState=freeze`) freezes user-process cgroups. ROCKNIX's design keeps the running game *executing* through the suspend cycle so that resume is instant. That semantic is not reachable through `systemd-suspend` — it requires bypassing systemd's sleep machinery entirely.

**Module shape (`handheld.fakeSuspend.*` options):**

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Master switch. RG28XX sets `true`; R36H leaves at `false` (uses real suspend via logind). |
| `powerButtonDevice` | `"axp20x-pek"` | Substring match against `/sys/class/input/event*/device/name` to locate the power-button input device. AXP-PMIC-based devices (H700) use `axp20x-pek`; other SoCs would override. |
| `lidSwitchDevice` | `null` | Optional lid switch (`gpio-keys-lid`). RG28XX has none; left null. |
| `inputWhitelist` | `[ "axp20x-pek" ]` (+ lid if set) | Input device names that remain active during fake-suspend (everything else gets `evtest --grab`'d). |
| `shutdownDelay` | `900` (seconds) | Time before auto-shutdown if not resumed. `0` disables auto-shutdown. |
| `parkCores` | `true` | Whether to offline all CPUs except CPU0 during fake-suspend. |
| `cpuGovernorSuspended` | `"powersave"` | Governor applied to all CPUs during fake-suspend. |
| `gpuGovernorSuspended` | `"powersave"` | Governor applied to the GPU devfreq node during fake-suspend. |

**Components installed when enabled:**

1. **`handheld-fake-suspend`** (shell script in nixpkgs `writeShellApplication`) — adapted from ROCKNIX's `rocknix-fake-suspend`, stripped of ROCKNIX-specific helpers and adjusted for our environment:
   - PulseAudio `pactl` calls work unchanged (we run PipeWire with pipewire-pulse — `pactl` is provided by it).
   - The `swaymsg`/`weston-dpms` DPMS path is removed — we have no compositor; always use `/sys/class/backlight/*/bl_power`.
   - `ledcontrol` calls are gated behind an option (default off for v1; RG28XX LED is out of scope).
   - ROCKNIX's `get_setting`/`set_setting` are replaced with reading a small state file under `/run/handheld-fake-suspend/`.
   - The ES HTTP API check (`http://localhost:1234/runningGame`) is kept; ES-fcamod exposes the same endpoint.
   - Suspend actions: `bl_power` off, `pactl` mute, governors → powersave, optional core parking, grab all non-whitelisted inputs via `evtest --grab` (matches ROCKNIX exactly).
   - Resume actions: reverse, plus `killall handheld-fake-suspend` to cancel the shutdown countdown.

2. **`handheld-power-button.service`** — systemd service that runs an event-loop reading the power-button device (located by name match at start) and invokes `handheld-fake-suspend power` on each `KEY_POWER` release. Requires `evtest` and `coreutils`; runs as root because it needs to write `/sys/devices/system/cpu/cpu*/online` and `/sys/class/backlight/*/bl_power`.

3. **Logind override**: when `enable = true`, the module sets `services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore"` so logind doesn't compete for power-button events.

4. **Required packages added to `environment.systemPackages`**: `evtest`, `pulseaudio` (for `pactl`), `util-linux`.

**State files**: `/run/handheld-fake-suspend/active`, `/run/handheld-fake-suspend/shutdown-delay.<pid>` — tmpfs, cleared on resume / boot.

**Verification items (added to the list below):** power button event device name and code (`evtest` on a live unit), confirmation that the AXP power-button driver emits `KEY_POWER` (rather than `KEY_POWEROFF` or similar), and confirmation that `evtest --grab` on all other input devices doesn't interfere with ES/RetroArch's own input pipeline on resume.

### Packages

#### `pkgs/linux-h700`

Same mechanism as `pkgs/linux-rk3326`: a `linuxManualConfig` derivation fed a `.config` produced by `runCommand`, which copies a static `h700_defconfig` file into `arch/arm64/configs/`, runs `make h700_defconfig`, and emits the resulting `.config`. `features = {}` passthru to skip nixpkgs assertions. `allowImportFromDerivation = true`.

The `h700_defconfig` file is the unit of work — it starts as a copy of mainline `defconfig` and enables (subject to revision during impl):

- **SoC family**: `CONFIG_ARCH_SUNXI=y`; H700 is supported in mainline under the H616 family (exact selectable Kconfig symbol verified during impl)
- **Clocks/Reset**: `CONFIG_SUN50I_H616_CCU`, `CONFIG_SUN50I_H616_R_CCU` (verify exact symbol names against mainline)
- **PMIC**: `CONFIG_MFD_AXP20X_I2C=y`, `CONFIG_AXP20X_POWER=y`, `CONFIG_AXP20X_ADC=y`, `CONFIG_REGULATOR_AXP20X=y` — verify whether AXP717 needs out-of-tree support
- **ADC**: `CONFIG_IIO=y`, `CONFIG_SUN4I_GPADC=y`
- **MMC**: `CONFIG_MMC_SUNXI=y`
- **Audio**: `CONFIG_SND_SUN4I_CODEC=y`, `CONFIG_SND_SUN8I_CODEC_ANALOG=y`, `CONFIG_SND_SUN50I_CODEC_ANALOG=y`
- **DRM**: `CONFIG_DRM_SUN4I=y`, `CONFIG_DRM_SUN8I_MIXER=y`, `CONFIG_DRM_PANFROST=y`
- **USB**: `CONFIG_USB_MUSB_SUNXI=m`, `CONFIG_USB_GADGET=y`, `CONFIG_USB_ETH=m`

We use a static defconfig file rather than nixpkgs' `structuredExtraConfig` because the existing repo pattern does, and because diffing a checked-in defconfig is more legible than a Nix attrset over hundreds of options.

Starting kernel version: `linuxPackages_latest` (matches R36H). Fall back to a pinned version if anything is broken.

#### `pkgs/h700-dtb`

Standalone DTS compile package, identical mechanism to `pkgs/rk3326-dtb` (cpp + dtc, kernel source for headers only). Source DTS: `sun50i-h700-anbernic-rg28xx.dts`, ported from ROCKNIX with header paths adapted to mainline.

Panel rotation handled in the DTS via `rotation = <0|90|180|270>;` on the panel node if the physical mounting differs from the reported orientation.

#### `pkgs/u-boot-rg28xx`

Thin derivation that wraps the vendored ROCKNIX H700 U-Boot blob as a Nix store path. Designed so a future swap to a from-source build (mainline U-Boot with a `rg28xx_defconfig`) is a single-file change inside this directory.

#### Panel and joypad drivers

Two outcomes possible, each preferred in order:

1. **Reuse `pkgs/panel-generic-dsi` and `pkgs/rocknix-joypad`** — works if ROCKNIX's RG28XX builds use the same two out-of-tree drivers, just bound differently in DTS. This is the assumed default.
2. **Add new package(s)** — only if ROCKNIX uses a different driver for either subsystem (e.g., a dedicated panel driver, or `gpio-keys` + IIO sticks + a userspace daemon for the joypad).

Decision deferred to implementation, when we examine ROCKNIX's H700 kernel module sources.

## Boot flow

R36H (today):
1. Armbian U-Boot from raw sector 64 → loads `boot.ini`
2. `boot.ini` loads kernel/initrd/dtb from ext4 `/boot`, applies panel DTBO
3. NixOS initrd → stage-2 → systemd → EmulationStation

RG28XX (planned):
1. Allwinner U-Boot SPL from raw sector 16 (verify) → U-Boot proper from sector 16384 (combined blob)
2. U-Boot distroboot scans ext4 partitions for `/boot/extlinux/extlinux.conf` (or `boot.scr`)
3. Loads kernel/initrd/dtb listed in extlinux entry; no DTBO apply step
4. NixOS initrd → stage-2 → systemd → EmulationStation

`installBootLoader` generates `extlinux.conf` from the active generation, substituting the system path into the `init=` argument and propagating `boot.kernelParams` to `APPEND`.

## Verification (must be done before flashing)

This is a speculative design. The following items will block a working boot and must be verified against ROCKNIX sources or hardware before declaring v1 done:

1. **U-Boot SPL/proper offsets** — `hexdump` ROCKNIX SD image for `eGON.BT0` magic; consult ROCKNIX image build script
2. **Boot loader spec format and module choice** — `extlinux.conf` vs. compiled `boot.scr`; determined by ROCKNIX U-Boot environment. Also decides whether NixOS' stock `boot.loader.generic-extlinux-compatible` suffices or whether we need a custom `installBootLoader` like R36H.
3. **DTS source of truth** — pull RG28XX DTS from ROCKNIX, port to mainline header paths, diff against any mainline-submitted DTS for the device
4. **Panel driver choice** — reuse `panel-generic-dsi` or add a new driver
5. **Panel orientation** — 640×480 is reported, but verify whether the panel is natively landscape or a portrait panel mounted sideways (determines DTS `rotation`)
6. **Joypad driver choice** — `singleadc-joypad` reuse vs. new approach
7. **Joypad vendor/product IDs + device name** — needed for `SDL_GAMECONTROLLERCONFIG` and `retroarch-joypad-autoconfig`
8. **PMIC mainline support** — AXP717 vs. AXP313; mainline driver coverage
9. **Kernel version compatibility** — does `linuxPackages_latest` boot cleanly, or pin a known-good version
10. **USB OTG role-switch under MUSB** — confirm the kernel `usb-role-switch` class exposes the same sysfs path so existing udev rules apply unchanged
11. **Power button input device** — verify name (expected `axp20x-pek`) and that it emits `KEY_POWER` via `evtest`; required by the fake-suspend module to locate the right device and event code
12. **Backlight `bl_power` path** — verify a `/sys/class/backlight/*/bl_power` node exists for the RG28XX panel (the fake-suspend module writes `4` to blank, `0` to restore)

## Items not verifiable pre-hardware

- Panel rotation property (likely none, but the physical mount could surprise us)
- ADC stick deadzones (R36H needed ES deadzone lowered to 12000 due to asymmetric sticks)
- Audio routing (different codec; may need ALSA UCM tweaks similar to R36H's "drive speaker through HP path" quirk)
- Power consumption / thermals under load
- Suspend behavior (see "Fake suspend" risk below)

## Risk register

| Risk | Mitigation |
| --- | --- |
| ROCKNIX is the **sole** mainline+Panfrost reference for this device. Anbernic publishes no kernel/U-Boot source; Knulli reuses stock binaries rather than running mainline; the decompiled BSP DTS is per sunxi "full of nonsense" and unreliable as a cross-check. The DTS, panel init, and joypad bindings we use will essentially come from ROCKNIX | Treat the ROCKNIX RG28XX kernel tree as the canonical reference. Pin to commits we've reviewed rather than tracking their main blindly |
| Mainline H700 less mature than RK3326 — some peripherals may misbehave on `linuxPackages_latest` | Be ready to pin to a known-good kernel version; treat version as a tunable, not a default |
| GPU performance under Panfrost vs. stock libmali | Expected to be comparable or better for the RetroArch workload — confirmed on R36H with the same Mali-G31 chip ("Mali faster for PortMaster, worse for RetroArch"). PortMaster-style native ARM games would be the place stock could win, and even there it's a small delta on a weak GPU. No turnkey libmali fallback: the Anbernic BSP is closed-source so reusing their userspace would require extracting binaries from a stock SD image (Knulli-style), out of scope for v1 |
| RG28XX panel needs a custom init sequence not in `panel-generic-dsi` | Onboard the same way as R36H: extract init from ROCKNIX DTS, port to `panel_description` format |
| H700 has no real suspend-to-RAM | We do not attempt kernel suspend. We implement fake suspend as a userspace overlay (see "Fake suspend" section). Risk reduces to: getting the power-button input device name and `KEY_POWER` event right, and ensuring `evtest --grab` of non-whitelisted inputs doesn't interfere with ES/RetroArch's own input handling on resume |
| MUSB OTG role-switch may not expose the same sysfs path as dwc2 | Verify in implementation; udev rule in `modules/hardware.nix` may need a small generalization if the path differs |
| Closure size regression | None expected — same arch, same Mesa, no extra firmware blobs (no WiFi). Track via existing checks |

## Out of scope for v1

- Addressable LED control (RG28XX has a multi-color status LED) — defer to a follow-up
- From-source U-Boot build — vendored blob now, design allows easy swap later
- Real suspend-to-RAM — depends on upstream mainline H700 work
- WiFi/BT — device has no wireless hardware

## Open follow-ups (post-v1)

- Build U-Boot from mainline source with `rg28xx_defconfig` — replaces the vendored blob with a transparent, reproducible derivation
- LED control via sysfs or a small helper
- If kernel package duplication between `linux-rk3326` and `linux-h700` becomes painful, factor out shared `structuredExtraConfig` into a common base
- Whether to add a SoC-agnostic `linux-handheld` package that takes a per-SoC overlay (deferred per YAGNI; revisit only if the duplication smells)

## Why this design

- **Reuses the existing `socs/` / `handhelds/` / `modules/` split** instead of inventing a new structure. The current repo already separates SoC-level concerns from device-level concerns; the RG28XX port is the test case that proves the split was the right call.
- **YAGNI on kernel/u-boot abstractions.** Adding shared `linux-handheld` or a from-source U-Boot derivation before either is needed would be speculative refactoring. We add them when concrete duplication or transparency needs arise.
- **Vendored U-Boot blob first** matches the existing R36H pattern, unblocks bring-up, and keeps the from-source migration as an isolated future change.
- **Calls out unknowns explicitly.** Because the port is speculative, every assumption that could break boot is in the Verification section, not buried in narrative.
