# ROCKNIX Single-ADC Joypad Driver Port

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace separate `adc-joystick` + `gpio-keys` with a single `rocknix-singleadc-joypad` device so RetroArch sees one unified gamepad.

**Architecture:** Port the ROCKNIX driver as an out-of-tree kernel module (same pattern as `panel-generic-dsi`). Modify DTS to use ROCKNIX bindings. Blacklist the old drivers. Strip Miyoo serial code and port from deprecated `input_polled_dev` to `input_setup_polling()`.

**Tech Stack:** Linux 6.19 kernel module (C), Nix, Device Tree

**Build:** `nix build --eval-store auto --store ssh-ng://nix@superintendent .#packages.aarch64-linux.r36h-image --impure` (aarch64 remote builder, no cross-compile)

---

## Key API Port Reference

| Old (removed in ~5.19) | New (6.19) |
|---|---|
| `#include <linux/input-polldev.h>` | `#include <linux/input.h>` |
| `struct input_polled_dev *poll_dev` | `struct input_dev *input` |
| `devm_input_allocate_polled_device(dev)` | `devm_input_allocate_device(dev)` |
| `poll_dev->private = joypad` | `input_set_drvdata(input, joypad)` |
| `poll_dev->poll = fn` | `input_setup_polling(input, fn)` |
| `poll_dev->poll_interval = N` | `input_set_poll_interval(input, N)` |
| `poll_dev->open / ->close` | `input->open / ->close` |
| `input_register_polled_device(p)` | `input_register_device(input)` |
| Callback: `void fn(struct input_polled_dev *)` | `void fn(struct input_dev *)` |
| Get private: `poll_dev->private` | `input_get_drvdata(input)` |
| Get input: `poll_dev->input` | `input` (directly) |

Also: `of_gpio_legacy.h` doesn't exist in mainline 6.19. Use `of_gpio.h` or convert to gpiod API. The `CLAMP` macro conflicts — use kernel's `clamp()` from `<linux/minmax.h>`.

---

## Tasks

### Task 1: Port the driver source

**Files:**
- Create: `pkgs/rocknix-joypad/drivers/rocknix-singleadc-joypad.c`
- Create: `pkgs/rocknix-joypad/drivers/rocknix-joypad.h` (copy as-is, just SARADC channel defines)
- Create: `pkgs/rocknix-joypad/drivers/Makefile` (`obj-m += rocknix-singleadc-joypad.o`)

Source: https://raw.githubusercontent.com/ROCKNIX/rocknix-joypad/master/rocknix-singleadc-joypad.c

- [ ] Port from `input_polled_dev` to `input_setup_polling()` per table above
- [ ] Strip all Miyoo serial code (~300 lines: `miyoo_*` structs/functions/thread/TTY, the `float`, delayed work, includes for kthread/tty/termios/uaccess/workqueue/jiffies)
- [ ] Remove `extern struct input_dev *joypad_input_g` global
- [ ] Fix `#include <linux/of_gpio_legacy.h>` — try `<linux/of_gpio.h>`, fall back to gpiod conversion if needed
- [ ] Replace `CLAMP` macro with kernel `clamp()` from `<linux/minmax.h>`
- [ ] Store `struct input_dev *input` in `struct joypad` (was accessed via `poll_dev->input`)
- [ ] `joypad_open` returns `int` (return 0) instead of `void`
- [ ] Verify: `grep -n 'input_polled_dev\|polldev\|miyoo\|MIYOO\|joypad_input_g' pkgs/rocknix-joypad/drivers/*.c` returns nothing
- [ ] Commit

### Task 2: Create Nix package

**Files:**
- Create: `pkgs/rocknix-joypad/default.nix`

- [ ] Copy pattern from `pkgs/panel-generic-dsi/default.nix`, changing pname/description/install target
- [ ] Commit

### Task 3: Modify DTS patch

**Files:**
- Modify: `pkgs/kernel-rk3326/patches/0001-add-r36s-device-tree.patch`

- [ ] Remove `joystick_mux_controller` (gpio-mux), `joystick_mux` (io-channel-mux), `analog_sticks` (adc-joystick) nodes
- [ ] Replace `builtin_gamepad: gpio-keys` with `rocknix-singleadc-joypad` node containing:
  - `joypad-name = "r36s_Gamepad"`, vendor=1, product=4488
  - `io-channels = <&saradc 1>`, `amux-count = <4>`, amux GPIO pins (A=PB3, B=PB0, EN=PB5)
  - ADC tuning: scale=2, deadzone=64, fuzz=32, flat=32, per-axis=180
  - `poll-interval = <16>`
  - All 15 gamepad button children (same GPIOs, same linux,code values — NOT volume)
- [ ] Add separate `volume_keys: gpio-keys-vol` node with just volume up/down
- [ ] Split `btn_pins` pinctrl — move volume GPIOs (PA0, PA1) to separate `vol_btn_pins`
- [ ] Update `@@` hunk line count
- [ ] Commit

### Task 4: Wire into board config

**Files:**
- Modify: `pkgs/kernel-rk3326/default.nix`
- Modify: `handhelds/r36h/default.nix`

- [ ] Remove `JOYSTICK_ADC`, `MUX_GPIO`, `IIO_MUX` from `structuredExtraConfig` (out-of-tree driver does its own mux)
- [ ] Add rocknix-joypad to `boot.extraModulePackages` (same pattern as panel-generic-dsi)
- [ ] Add `"rocknix_singleadc_joypad"` to `boot.kernelModules`
- [ ] Blacklist old drivers: add `"joydev_adc"` to `boot.blacklistedKernelModules` if needed (removing from config should suffice)
- [ ] Commit

### Task 5: Update RetroArch autoconfig

**Files:**
- Delete: `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/adc-joystick.cfg`
- Delete: `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/gpio-keys.cfg`
- Modify: `pkgs/retroarch-joypad-autoconfig/default.nix` (remove deleted file references)
- Modify: `pkgs/retroarch-joypad-autoconfig/autoconfig/udev/r36s_Gamepad.cfg` (verify/update button indices)

- [ ] Delete split config files
- [ ] Update default.nix to only install `r36s_Gamepad.cfg`
- [ ] Button index mapping will likely need empirical tuning after first boot — the cfg is a starting point
- [ ] Commit

### Task 6: Build, flash, test

- [ ] Build image
- [ ] Flash and boot
- [ ] SSH in, verify `cat /proc/bus/input/devices` shows one `r36s_Gamepad` with both EV_ABS and EV_KEY
- [ ] `evtest` — verify buttons + sticks report from same device
- [ ] Verify RetroArch autoconfigs it correctly
- [ ] If axes are swapped/inverted: adjust `amux-channel-mapping` or `invert-abs*` in DTS
- [ ] If button indices wrong: update `r36s_Gamepad.cfg` based on evtest output
- [ ] Commit fixes, rebuild if needed
