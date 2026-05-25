# RG28XX hardware bring-up checklist

Run this when the device arrives. The v1 image is speculative — every item
below is either deferred from the plan because hardware was unavailable,
or is a known unknown carried in `docs/rocknix-h700-notes.md`. Tick each
box, file a follow-up issue for anything that doesn't pass, and only call
v1 done when section 10 (closure size) has been compared head-to-head with
the R36H image.

## 1. Pre-flash sanity

- [ ] `head -c 8 $(nix eval --raw .#legacyPackages.aarch64-linux.u-boot-rg28xx)/u-boot-sunxi-with-spl.bin | od -c` shows `eGON` at byte offset 4 (first 4 bytes are the ARM jump instruction; `eGON.BT0` follows)
- [ ] U-Boot SPL placement vs a stock ROCKNIX RG28XX SD image: mount it,
      `cmp -n 8192 <our-blob> <(dd if=/dev/sdX bs=1024 count=8 skip=8)` — confirms our blob lands at the same 8 KiB offset and is byte-compatible enough to chain-load.

## 2. Flash and first boot

- [ ] Build: `nix build --eval-store auto --store ssh-ng://nix@superintendent .#packages.aarch64-linux.rg28xx-image`
- [ ] Copy back: `nix copy --no-check-sigs --from ssh-ng://nix@superintendent $(nix eval --raw .#packages.aarch64-linux.rg28xx-image)`
- [ ] Flash: `zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync && sync`
- [ ] Power on. Does U-Boot text appear over the (presumably uninitialised) panel? If the panel is dark, that's expected for v1 — see section 3.
- [ ] Does the kernel reach `multi-user.target` (USB gadget enumerates → `10.0.0.2` answers ping over `usb0`)?
- [ ] If boot hangs: serial console on the UART pads. Kernel param `console=ttyS0,115200` is already wired in by `sd-image-aarch64.nix`.

## 3. Display / panel driver

- [ ] Mainline status of kikuchan98's `panel-mipi-dpi-spi` v2 patchset — has it landed? `git log -n1 drivers/gpu/drm/panel/panel-mipi-dpi-spi.c` in the kernel tree we're pinned to. If yes, just enable `CONFIG_DRM_PANEL_MIPI_DPI_SPI=y` in `pkgs/linux-h700/h700_defconfig` and add `&panel` back to `pkgs/h700-dtb/sun50i-h700-anbernic-rg28xx.dts`.
- [ ] If still out-of-tree, add `pkgs/panel-mipi-dpi-spi/` mirroring `pkgs/panel-generic-dsi`. Cite the kikuchan98 v2 patchset in the package description.
- [ ] Native resolution 640×480 reported by `modetest -M sun4i-drm`
- [ ] Backlight: `echo 4 > /sys/class/backlight/*/bl_power` blanks; `echo 0` restores. Needed by `handheld-fake-suspend`.

## 4. Input

> **Important deviation from the original plan.** The plan's amendment #5
> claimed the mainline `sun50i-h700-anbernic-rg35xx-2024.dts` already
> wires `rocknix-joypad`. It does not — only `gpio-keys` is bound. So
> on v1, buttons should work but joystick axes WILL NOT until a DTS
> overlay adds a `joypad` node with `io-channels = <&axp_adc N>`
> references (look in `projects/ROCKNIX/devices/H700/patches/linux/`
> for the shape — patch numbering shifts between ROCKNIX tags).
> `pkgs.rocknix-joypad` is still wired into `extraModulePackages` so the
> module compiles against `linux-h700`; it just won't bind to anything
> until the DTS gains the joypad node.

- [ ] Confirm gpio-keys path: `evtest` enumerates the gpio-keys device; press each face button + D-pad + L/R + start/select and record the KEY_* codes (they should match the BTN_* constants in `rg35xx-2024.dts`'s `gpio-keys-gamepad` node).
- [ ] Joystick axes — currently unwired. Add `joypad` node + ADC channel refs to `pkgs/h700-dtb/sun50i-h700-anbernic-rg28xx.dts`; rebuild DTB; verify `evtest` shows ABS_X/ABS_Y events on stick movement. Resulting device name will be whatever the DTS labels it; capture it.
- [ ] Update `handhelds/rg28xx/es_input.cfg`'s `deviceName=` to match the actual device name.
- [ ] Replay each button while watching `evtest`; record button IDs in `es_input.cfg`.
- [ ] Update `systemd.services.emulationstation.environment.SDL_GAMECONTROLLERCONFIG` in `handhelds/rg28xx/default.nix` with the real vendor/product GUID and per-button map (see R36H's value for shape).
- [ ] Power button: `evtest` on `/dev/input/by-path/*axp20x-pek*` shows `KEY_POWER` press/release. Confirms `handheld.fakeSuspend.powerButtonDevice = "axp20x-pek"` is correct.
- [ ] Add a `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/<RG28XX-name>.cfg` mirroring the R36H entry so RetroArch picks up the mapping without ES setting `SDL_GAMECONTROLLERCONFIG`.

## 5. Fake suspend

- [ ] `systemctl status handheld-power-button` is active after boot.
- [ ] Single press of power button: backlight blanks (`cat /sys/class/backlight/*/bl_power` → `4`), `pactl get-sink-mute @DEFAULT_SINK@` → `Mute: yes`, and `/run/handheld-fake-suspend/fake-suspend-active` exists.
- [ ] Game (e.g. a quick RetroArch session) keeps running through the cycle — DraStic specifically, since it's the picky one.
- [ ] Second press: state reverses; flag file gone.
- [ ] Wait past `handheld.fakeSuspend.shutdownDelay` (default 900 s): device powers off cleanly (`shutdown -h now` semantics, no kernel panic).

## 6. Audio

- [ ] Speaker plays through PipeWire (`paplay /etc/test.wav` or similar). Verify the sun4i-codec card enumerates: `pactl list short sinks`.
- [ ] Headphone-jack insertion auto-switches the active sink. (RG28XX has analog mux'd HP detect on `pio PI3` per the rg35xx-plus base DTS.)
- [ ] If volume buttons exist on RG28XX (research has them as unconfirmed), wire `triggerhappy` rules mirroring R36H. If not, document "no volume buttons; use ES menu or wpctl over SSH."

## 7. USB

- [ ] Gadget mode (default after boot): `ssh root@10.0.0.2` works.
- [ ] H700 uses MUSB, not DWC2 like R36H. The `usb-role-switch` sysfs path differs — capture it (`ls /sys/class/udc/`) and document in CLAUDE.md.
- [ ] Manual host-mode switch via sysfs role write — test with a USB audio dongle (Creative BT-W5 known-working on R36H).

## 8. ROMs

- [ ] Insert exFAT-formatted second SD; verify `/roms` automount triggers on first access (`ls /roms` should mount on demand).
- [ ] ES scans systems from `/roms/<system>/` directories (gb, gbc, gba, snes, etc.) and populates the carousel.

## 9. Emulation parity check vs R36H

A35→A53 (R36H→RG28XX) is a wider OoO core with slightly better IPC, but
clock and cache sizes are comparable. Expect parity within 10%.

- [ ] GBA (gpSP): full speed, no audio underruns.
- [ ] PSX (mednafen-psx-hw): full speed.
- [ ] SNES, GBC, GB: full speed (these were always headroom on R36H).
- [ ] N64 (parallel-n64 Rice + HLE): basic title (Mario 64) reaches main screen.
- [ ] NDS (DraStic): the picky one. Same DraStic build, same SDL2_classic.
      Expect full speed on commercial NDS titles. If not, check whether
      DraStic's KMSDRM path picks the right CRTC on H700 (the `&panel`
      story may bite here).

## 10. GPU stack

- [ ] Default panfrost: `dmesg | grep -i panfrost` shows successful probe and Mali-G31 detected.
- [ ] If picker hardware is identified (Task 1.8 left this open): flip
      `handheld.gpu.specialisation.{enable,picker.enable} = true;` and
      override `eventDeviceName` / `key` in `handhelds/rg28xx/default.nix`.
- [ ] mali-kbase build against `linux-h700`: `pkgs.mali-kbase.override { kernel = pkgs.linux-h700; }` builds — `nix build .#legacyPackages.aarch64-linux.mali-kbase` to confirm. Then load the resulting module and check `dmesg | grep -i mali_kbase` for successful probe against the H700 IOMMU.
- [ ] libmali userspace under the mali specialisation: launch a PortMaster
      port that runs on libmali R36H-side and confirm parity.

## 11. PortMaster

- [ ] `PortMaster Launch` entry appears in the ES `ports` system.
- [ ] At least one prebuilt port (suggest a simple SDL2 title like *Cave Story*) launches and runs under panfrost.

## 12. Closure size

- [ ] `du -sh result/sd-image/*.img.zst` for both r36h-image and rg28xx-image — RG28XX should be within ±10% of R36H. Material drift would suggest a closure-bloat regression (Mesa/LLVM/GTK chain pulled in by something we missed disabling). If it does drift, run `nix path-info -rsSh .#nixosConfigurations.rg28xx.config.system.build.toplevel | sort -k2 -h | tail -30`.
