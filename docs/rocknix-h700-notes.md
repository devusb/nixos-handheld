# ROCKNIX H700 research notes

Source: `https://github.com/ROCKNIX/distribution` at commit `d138f63b6daeb3b45a6b821908d5fdd03a91b6f0` (cloned May 2026).

## Device tree paths

ROCKNIX H700 DTS files live under `projects/ROCKNIX/devices/H700/linux/dts/allwinner/`. Notable files:

- `sun50i-h700-anbernic-rg28xx.dts` — RG28XX overlay (17 lines)
- `sun50i-h700-anbernic-rg35xx-plus-rev6-panel.dts` — sibling device, in-tree
- `sun50i-h700-anbernic-rg35xx-plus.dts` — **NOT** in ROCKNIX's tree → it lives in mainline Linux (i.e. ROCKNIX includes it from the kernel source).

RG28XX DTS is essentially:

```dts
#include "sun50i-h700-anbernic-rg35xx-plus.dts"
/ {
    model = "Anbernic RG28XX";
    compatible = "anbernic,rg28xx", "allwinner,sun50i-h700";
    rocknix-dt-id = "sun50i-h700-anbernic-rg28xx";
};
&panel {
    compatible = "anbernic,rg28xx-panel", "panel-mipi-dpi-spi";
};
```

**Implication:** Most of the RG28XX hardware is already in mainline via the `rg35xx-plus` base DTS. Our `pkgs/h700-dtb` only needs to compile this small overlay; the heavy lifting is upstream.

## Kernel

- Linux 7.0.2 (recent mainline)
- Defconfig: `projects/ROCKNIX/devices/H700/linux/linux.aarch64.conf` (full `.config`, not a defconfig — substantial file)
- 16+ device-specific patches in `projects/ROCKNIX/devices/H700/patches/linux/`:
  - **0110-v2_20250226_kikuchan98_drm_panel_add_generic_mipi_panel_driver.patch** — adds `panel-mipi-dpi-spi` driver (out-of-tree v2; the RG28XX panel uses this)
  - 0111-rg35xx-2024-use-panel-mipi-dpi-spi-driver.patch — wires the rg35xx family to it
  - 0040-Revert-usb-musb-Fix-hardware-lockup-on-first-Rx-endp.patch — MUSB workaround
  - 0007-rg35xx-add-GPU-opp.patch — GPU operating points
  - others for HDMI, PWM, battery names, etc.

## U-Boot

`projects/ROCKNIX/devices/H700/packages/u-boot/package.mk`:

- **Built from source**, not vendored as a binary in the repo
- Mainline U-Boot `v2025.07-rc3`
- Defconfig: `anbernic_rg35xx_h700_defconfig` (shipped by mainline)
- ARM Trusted Firmware required: `sun50i_h616` platform, `bl31.bin`
- Output: `u-boot-sunxi-with-spl.bin`
- Build command involves both `ARCH=arm` (for U-Boot's host tooling) and the aarch64 cross compiler

### Bootloader install command (the dd offset)

From `projects/ROCKNIX/devices/H700/bootloader/update.sh`:

```sh
dd if=$SYSTEM_ROOT/usr/share/bootloader/u-boot-sunxi-with-spl.bin \
   of=$BOOT_DISK bs=1K seek=8 conv=fsync,notrunc
```

**Verified offset:** **8 KiB (sector 16)** — matches the standard sunxi convention I'd hypothesized in the spec.

## Boot scheme

ROCKNIX H700 does NOT use extlinux. Instead:

- A FAT boot partition mounted at `/flash`
- Fixed-name files there: `dtb.img`, kernel `Image`, `initrd`, and a compiled `boot.scr` (sourced from `projects/ROCKNIX/bootloader/` — `mkimage`-wrapped script)
- `dtb.img` is hot-swapped on each boot by `update.sh` (because ROCKNIX has multiple H700 devices sharing one image)

**Implication for Task 7 (`socs/h700.nix`):** NixOS's stock `boot.loader.generic-extlinux-compatible` may not work out of the box with ROCKNIX's U-Boot env (which expects `boot.scr`+`dtb.img` rather than `/boot/extlinux/extlinux.conf`). Two paths forward:
1. Use a from-source U-Boot built with a defconfig that prefers extlinux (mainline `anbernic_rg35xx_h700_defconfig` does support `CONFIG_DISTRO_DEFAULTS=y` per U-Boot mainline — distroboot scans for extlinux.conf as a fallback)
2. Generate a `boot.scr` from `installBootLoader` (the R36H custom-installer pattern, but emitting `boot.scr` via `mkimage` instead of `boot.ini`)

Decision: **defer this until U-Boot strategy is resolved** (see "Open decision" below).

## Panel driver

- Driver: `panel-mipi-dpi-spi` (out-of-tree, kikuchan98 v2 patchset)
- **Not** `panel-generic-dsi` (R36H's driver) — that's a different driver. RG28XX panel is initialized over SPI, not MIPI DSI command stream.
- Implication: our `pkgs/panel-generic-dsi` is **not** directly reusable. We'd need either:
  - A new `pkgs/panel-mipi-dpi-spi` out-of-tree module derivation, OR
  - Wait for the driver to land in mainline (the patchset is `v2` and explicitly marked as upstream-bound)

## Joypad driver

- Same `rocknix-joypad` repo our `pkgs/rocknix-joypad` already builds against
- Package: `projects/ROCKNIX/packages/linux-drivers/rocknix-joypad/package.mk` at upstream commit `7647fdb0fc89cd69b284903bf7707e861df5dc7e`
- H700 bindings in DTS differ from RK3326 (different ADC controller, different GPIO scheme), but the driver itself is the same kernel module — supports both via DTS

### DTS-binding correction (2026-05-25)

The plan's amendment #5 stated the mainline `sun50i-h700-anbernic-rg35xx-2024.dts` already wires the `rocknix-joypad` device. Inspection of mainline U-Boot 2026.04's vendored DTS copy proves otherwise:

- Buttons (face buttons, D-pad, L/R, start/select) are wired via a `gpio-keys` node (`gpio_keys_gamepad`) — these will work out of the box with `CONFIG_KEYBOARD_GPIO=y`, no out-of-tree driver needed.
- Joystick axes are NOT wired. There is no `joypad` node and nothing references `&axp_adc` as an `io-channels` consumer. ROCKNIX adds these bindings via their own kernel patches (`projects/ROCKNIX/devices/H700/patches/linux/` series 0030–0040), not via the upstream DTS.

For v1 this means:
- `pkgs.rocknix-joypad` still compiles against `linux-h700` and is in `boot.extraModulePackages` so it's loadable, but the kernel module will not bind to any device until the DTS overlay gains a `joypad` node.
- Hardware bring-up will need a follow-up DTS patch in `pkgs/h700-dtb/sun50i-h700-anbernic-rg28xx.dts` modelled on ROCKNIX's bindings (channel numbers per axis, GPIO references for L3/R3/menu).

## PMIC

- AXP717 — supported by mainline `axp20x` family drivers (`MFD_AXP20X_I2C`, `REGULATOR_AXP20X`, etc.)
- Power button: `axp20x-pek` (standard sunxi PMIC PEK input device) — confirmed; this is the device name we'd configure into `handheld.fakeSuspend.powerButtonDevice`

## GPU specialisation picker key — TBD

I did not exhaustively search the base DTS for `gpio-keys` / `adc-keys` nodes. The RG28XX is a horizontal handheld without dedicated volume buttons (per Anbernic product page) — most buttons route through the joypad. **Tentative conclusion:** no usable hold-button input at initrd time. Plan's Task 8 already disables the picker for v1 on this assumption.

## libmali / mali-kbase compatibility

Both RG28XX and R36H use Mali-G31 (Bifrost gen). The userspace `libmali` blob targets the architecture, not the SoC; should work unchanged. `mali-kbase` is kernel-side, parameterized on the kernel via the existing derivation — just needs to compile against `linux-h700` and bind via DTS. Not blocker-tier; verify in Task 3.

## Audio codec

`SND_SUN8I_CODEC` + `SND_SUN50I_CODEC_ANALOG` mainline drivers. ROCKNIX ships ALSA UCM patches under `projects/ROCKNIX/packages/audio/alsa-ucm-conf/patches/H700/` — worth grabbing in a follow-up if speaker/HP routing has edge cases.

---

## Open decision (blocks Task 2)

The plan's Task 2 ("Vendor U-Boot blob") assumes a prebuilt binary exists in the ROCKNIX repo. It does not — ROCKNIX builds U-Boot from source as part of their image build. To proceed we need to pick one of:

1. **Extract from a ROCKNIX release SD image.** Download the latest ROCKNIX-H700 release `.img.xz` from GitHub releases, `dd` out the first 8 MiB, vendor as `u-boot-sunxi.bin`. Keeps the plan's "vendored blob" approach intact, just changes the source. Risk: blob version drifts from whatever ROCKNIX ships in main; we should pin to a specific release tag.
2. **Build U-Boot from source now (move "from-source U-Boot" from Phase 2 to v1).** Add `pkgs/u-boot-rg28xx/` as a Nix derivation that builds mainline `u-boot` `v2025.07-rc3` (or similar) with `anbernic_rg35xx_h700_defconfig`, plus an `arm-trusted-firmware` derivation for `bl31.bin`. More upfront work but transparent and reproducible. This was originally a "post-v1" item.
3. **Build manually and vendor the resulting binary.** I run the U-Boot build out-of-band on the remote builder, commit the resulting `u-boot-sunxi-with-spl.bin` as a blob. Cheap, works, but loses reproducibility (a future me has to remember the build incantation).
