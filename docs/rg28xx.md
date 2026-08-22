# Anbernic RG28XX

Allwinner H700 handheld (landscape form factor). Renders through a [cage](https://github.com/cage-kiosk/cage) Wayland kiosk, which owns the panel and applies the rotation every client inherits.

Configuration: `handhelds/rg28xx/`. SoC wiring: `socs/h700.nix`.

## Hardware

- **SoC**: Allwinner H700 (H616 derivative) — quad-core Cortex-A53
- **GPU**: Mali-G31 (Panfrost, or the Mali blob)
- **Display**: 3.5" panel, native 480×640 portrait, mounted rotated and presented as 640×480 landscape
- **Storage**: two microSD slots — slot 1 NixOS boot, slot 2 ROMs (exFAT, `mmcblk1`)
- **Input**: pure-digital gamepad (`H700 Gamepad`, vid `0x484b` / pid `0x14df`) — no analog sticks
- **Audio**: sun4i / H616 audio codec — speaker + headphone jack
- **USB**: MUSB controller (not dwc2)
- **PMIC**: AXP717

## Display & rotation

The panel uses the mainline `panel-mipi-dpi-spi` driver, loading its init blob from `/lib/firmware/panels/` (`pkgs/rg28xx-panel-firmware`). cage's wlroots takes over the panel; because wlroots does not auto-honor the DRM panel-orientation property, the transform is set explicitly and applied by [kanshi](https://sr.ht/~emersion/kanshi/) inside the cage session:

```nix
handheld.compositor.enable = true;
handheld.compositor.outputTransform = "90";
```

cage runs as the `handheld-session` system service (`modules/compositor`) with `LIBSEAT_BACKEND=builtin` and `WLR_BACKENDS=drm,libinput`, launching EmulationStation as its child. SDL2 clients (ES, RetroArch with the `sdl2` driver, DraStic, SDL2 PortMaster ports) present through cage without per-app rotation patches; RetroArch is pinned to the `glcore` video driver, which presents over Wayland without grabbing DRM master.

## Controls

- **D-pad** — navigate EmulationStation menus
- **A** — select, **B** — back (Nintendo face-button layout: a=east, b=south, x=west, y=north)
- **M (Mode) button** — opens menus (ES main menu; RetroArch menu in-game)
- **Power** — suspend

The pad's SDL controller mapping is supplied via `SDL_GAMECONTROLLERCONFIG` (GUID computed from a CRC-16 of the device name) in the `handheld-session` environment, so everything using SDL gamecontroller honors it. There are no analog sticks.

## Boot

Uses NixOS's stock `generic-extlinux-compatible` — mainline U-Boot's `anbernic_rg35xx_h700_defconfig` is built with `CONFIG_DISTRO_DEFAULTS`, so U-Boot's scan finds `/boot/extlinux/extlinux.conf` on the ext4 rootfs and boots with `init=/nix/store/<toplevel>/init`. No custom boot loader. The U-Boot SPL blob is written at 8 KiB (sector 16), where the Allwinner BROM expects it.

## Input & kernel

The kernel is `pkgs/linux-h700` — mainline with the ROCKNIX H700 patch series and a custom `h700_defconfig` (Panfrost, AXP717 PMIC + battery, `panel-mipi-dpi-spi`, sun4i-codec, gpio-keys, USB gadget). The DTB is built standalone (`pkgs/h700-dtb`) from the ROCKNIX-patched `rg35xx-plus` base with the rg28xx panel compatible.

## CPU frequency

The H700 OPP table is `allwinner,sun50i-h616-operating-points`, and `cpufreq-dt-platdev` blocklists `allwinner,sun50i-h700`, so the generic DT driver never registers itself. `CONFIG_ARM_ALLWINNER_SUN50I_CPUFREQ_NVMEM` supplies the driver that reads the speed bin from the SID efuse (`cpu-speed-grade@0`, two bytes at offset 0), applies the matching `opp-supported-hw` mask, and registers `cpufreq-dt`. Without it there is no cpufreq at all and the CPU stays at the 1008 MHz rate U-Boot leaves it at.

The table spans 480–1512 MHz; which entries are usable depends on the bin. `vdd-cpu` is AXP717 `dcdc1` (0.9–1.16 V). The governor is `performance` (`modules/hardware.nix`).

```bash
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq
```

The 1512 MHz OPP is marked `turbo-mode`, so `cpufreq-dt` withholds it from the normal range and exposes it behind a switch that defaults off:

```bash
cat /sys/devices/system/cpu/cpufreq/boost                              # 0
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_boost_frequencies  # 1512000
echo 1 > /sys/devices/system/cpu/cpufreq/boost                         # raise the ceiling
```

Enabling it adds 6.8% of clock and moves the CPU rail from 1.10 V to 1.16 V, the regulator's declared maximum. Power scales roughly with V²·f, so the cost is near 19% for that 6.8%, and under the `performance` governor the turbo OPP is then held continuously rather than intermittently.

It only pays off where a single saturated thread is the limit. Dreamcast under flycast pins one core at 100% with the GPU idling at its 420 MHz floor, so clock is the only lever. It does nothing for GPU-bound titles: N64 under GLideN64 holds the 648 MHz GPU ceiling with most of the CPU idle.

Thermal throttling depends on the `cooling-maps` added in `pkgs/h700-dtb`. sun50i-h616.dtsi declares the cpu-thermal passive trips (60 C and 70 C) but binds no cooling device to them, so without the map the 110 C critical trip — a shutdown, not a throttle — is the only thermal response. The map attaches all four CPUs to both passive trips for the `step_wise` governor to act on.

```bash
cat /sys/class/thermal/thermal_zone2/type       # cpu-thermal
cat /sys/class/thermal/thermal_zone2/cdev0/type # cpufreq-cpu0
cat /sys/class/thermal/thermal_zone2/cdev0/cur_state
```

## Performance tuning

The CPU tops out at 1416 MHz (1512 with boost) and the Mali-G31 at 648 MHz. Titles are limited by one or the other, and the two cases pull in opposite directions, so identify which before changing core options.

```bash
# GPU: sitting at 648 MHz every sample means GPU-bound; ranging across the
# curve or resting at the 420 MHz floor means it is not.
for i in $(seq 1 10); do cat /sys/class/devfreq/1800000.gpu/cur_freq; sleep 0.5; done
cat /sys/class/devfreq/1800000.gpu/trans_stat

# CPU: whole-process busy for the running emulator. Over 100% spans cores;
# 400% is the ceiling.
top -b -n 2 -d 3 | head -12
```

A GPU pinned at 648 MHz alongside idle CPU cores is GPU-bound — reduce GPU work. Busy threads with the GPU at its 420 MHz floor is CPU-bound — move work onto the GPU. cage composites and rotates every frame, so GPU-bound titles pay that pass on top of their own rendering.

Core options live in `/home/gamer/.config/retroarch/config/<Core>/<Core>.opt` and are written when the core unloads. They are not managed by this repo and do not survive a reflash. `Quick Menu -> Core Options` edits them; `Quick Menu -> Controls` writes controller remaps instead.

### PSP (PPSSPP)

With `hardware_tesselation` off, PPSSPP tessellates curves on its CPU thread pool, saturating the `PoolW` workers while the GPU idles. Moving tessellation to hardware and lowering curve quality shifts that work to the idle GPU.

```
ppsspp_hardware_tesselation = "enabled"
ppsspp_spline_quality = "Low"
ppsspp_frame_duplication = "disabled"
ppsspp_texture_anisotropic_filtering = "disabled"
ppsspp_backend = "opengl"
```

### N64 (Mupen64Plus-Next / GLideN64)

`mupen64plus-rdp-plugin` offers `gliden64` and `angrylion` in this build; ParaLLEl-RDP is Vulkan-only and compiled out (`HAVE_PARALLEL_RDP=0`), and Panfrost has no Vulkan driver. GLideN64 is the fast plugin — Angrylion is a software rasterizer. Rice belongs to the separate `parallel-n64` core, which is packaged in `pkgs/parallel-n64` but not wired to the `n64` system.

These cut per-fragment shading and framebuffer readback, the dominant GPU costs:

```
mupen64plus-EnableLODEmulation = "False"
mupen64plus-EnableCopyColorToRDRAM = "Off"
mupen64plus-EnableFBEmulation = "False"
```

`EnableFBEmulation = "False"` can break framebuffer effects; re-enable it first if a game renders incorrectly. Keep `mupen64plus-EnableCopyDepthToRDRAM = "Software"` — that copy runs on the CPU, which has headroom whenever the GPU is the limit.

## Quirks & workarounds

- **Audio codec boots muted** — the sun4i / H616 codec starts with `DAC Playback Switch` off. A udev rule on `controlC*` add amixers it on (`socs/h700.nix`); without it, SDL2 audio teardown deadlocks.
- **s2idle resume wedges mmc1** — on some real-suspend resumes the sunxi-mmc controller hits `fatal err update clk timeout`, the card detaches, and `/roms` goes I/O-error. `powerManagement.resumeCommands` polls for the wedge and rebinds the `sunxi-mmc` driver to recover. `mmc1` runtime PM is pinned `on` to avoid the same timeout from autosuspend.

## What works

- Boots to EmulationStation (cage kiosk, 90° rotation) with RetroArch cores + DraStic
- Display via `panel-mipi-dpi-spi` + rotation
- Digital gamepad (SDL controller mapping), M button for menus
- Audio (sun4i-codec via PipeWire)
- PortMaster under panfrost
- USB gadget ethernet for SSH; NixOS generations over SSH

## What doesn't

- Analog sticks — the pad is digital by design
- USB host mode — MUSB host role is not yet working on mainline (parked, issue #41)
- Real suspend is survivable only via the mmc-rebind workaround above
