# Post-Joypad Cleanup & Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the mainline-kernel branch, merge to main via PR, reduce build times, devendor external dependencies, and prepare for emulationstation-fcamod.

**Architecture:** Sequential cleanup tasks that build on each other. Each task produces a working, testable system. Tasks 1-3 should be done in order; 4-6 can be parallelized.

**Tech Stack:** NixOS, Nix flakes, Linux kernel config, RetroArch, C (kernel modules)

**Working directory:** `/home/mhelton/code/nixos-handheld-mainline-kernel` (worktree) or `/home/mhelton/code/nixos-handheld` (main repo after merge)

**Device:** `root@10.0.0.2` via USB gadget ethernet

**Build commands:**
- Long builds: `nix build --eval-store auto --store ssh-ng://nix@superintendent .#nixosConfigurations.r36h.config.system.build.toplevel --impure`
- Deploy: `nixos-rebuild boot --target-host root@10.0.0.2 --builders "ssh-ng://nix@superintendent aarch64-linux - 4 1 big-parallel" --max-jobs 0 --flake .#r36h --impure`
- Quick config changes: use `switch` instead of `boot`

---

## Task 1: Clean up branch, update docs, merge via PR

**Prereq:** Joypad + audio + GPU confirmed working on device.

**Files:**
- Modify: `CLAUDE.md` (reflect current state)
- Modify: `docs/external-dependencies.md` (reflect current state)
- Modify: `README.md` (if needed)

- [ ] **Step 1: Review commit history**

```bash
cd ~/code/nixos-handheld-mainline-kernel
git log --oneline main..HEAD
```

Identify logical groups: kernel switch, U-Boot switch, joypad driver, audio fix, DTS refactor, etc.

- [ ] **Step 2: Interactive rebase to clean history**

Squash iteration noise (fixups, failed attempts, reverts) into logical commits. Target grouping:
- `feat: switch to mainline 6.19 kernel with Armbian U-Boot`
- `feat: installBootLoader for NixOS generation support`
- `feat: USB gadget ethernet + SSH`
- `feat: unified joypad driver (ROCKNIX singleadc-joypad)`
- `fix: ALSA volume init timing and level`
- `refactor: DTS as plain file with postPatch`
- `chore: expose out-of-tree modules via overlay`

```bash
git rebase -i main
```

- [ ] **Step 3: Update CLAUDE.md**

The current CLAUDE.md describes the old 6.12 kernel setup. Update to reflect:
- Mainline 6.19 kernel via `linuxPackages_latest`
- Armbian U-Boot (not ArkOS blobs)
- `installBootLoader` + generation support
- USB gadget ethernet + SSH access
- Unified joypad driver (rocknix-singleadc-joypad)
- DTS as plain file via `overrideAttrs postPatch` (not patch)
- Out-of-tree modules via overlay (`pkgs.panel-generic-dsi`, `pkgs.rocknix-joypad`)
- ALSA volume: 80% hardware, RetroArch software control, depends on rk817 device unit
- `nixos-rebuild switch/boot` workflow (long builds use `nix build` on remote store)
- Playback Mux: speaker driven through HP path, don't switch to SPK

- [ ] **Step 4: Update docs/external-dependencies.md**

Reflect current state:
- DTS is now a plain file (`rk3326-r36s.dts`), not a patch
- Old patches (0001, 0002, 0003) replaced by single Makefile patch + plain DTS
- Add rocknix-singleadc-joypad driver entry
- Add r36s_Gamepad.cfg autoconfig entry
- Note 0003 GPU OPP fix is baked into the DTS now

- [ ] **Step 5: Push branch, create PR**

```bash
git push origin mainline-kernel
gh pr create --base main --head mainline-kernel
```

- [ ] **Step 6: Review and merge PR**

- [ ] **Step 7: Clean up worktree**

```bash
cd ~/code/nixos-handheld
git worktree remove ~/code/nixos-handheld-mainline-kernel
```

---

## Task 2: Trim kernel defconfig

**Goal:** Cut kernel build from ~2hrs to ~15min by using a minimal config instead of full `linuxPackages_latest` defconfig.

**Files:**
- Create: `pkgs/kernel-rk3326/rk3326_defconfig` (minimal kernel config)
- Modify: `pkgs/kernel-rk3326/default.nix` (switch from `linuxPackages_latest` to custom config)

**References for minimal configs:**
- Old 6.12 `rk3326_defconfig` from ohjhas repo (in git history)
- ROCKNIX kernel config for RK3326 (in `ROCKNIX/distribution` repo)
- Andre Renaud's buildroot config (`github:AndreRenaud/buildroot-r36s`)
- Running kernel config: `ssh root@10.0.0.2 "zcat /proc/config.gz"` (full defconfig, use as reference for what's actually loaded)

- [ ] **Step 1: Gather reference configs**

Clone/fetch the reference repos and compare their RK3326 configs. Identify the minimal set needed for our hardware:
- RK3326 SoC support (clocks, pinctrl, thermal, etc.)
- Panfrost GPU (DRM_PANFROST)
- MIPI DSI display (DRM_ROCKCHIP, PHY_ROCKCHIP_INNO_DSIDPHY)
- RK817 audio codec (SND_SOC_RK817, SND_SOC_ROCKCHIP_I2S)
- USB dwc2 gadget (USB_DWC2, USB_GADGET, USB_ETH)
- SARADC + GPIO (for joypad driver)
- SD/MMC (for boot + roms card)
- ext4, exFAT, zram
- Input subsystem (evdev, joydev)

- [ ] **Step 2: Create minimal defconfig**

Start from one of the reference configs (ohjhas or ROCKNIX), update for 6.19 API changes, and trim further. Use `make olddefconfig` to fill in defaults.

- [ ] **Step 3: Update kernel build to use custom defconfig**

Modify `pkgs/kernel-rk3326/default.nix` to build from the custom defconfig instead of `linuxPackages_latest`. May need to switch from `linuxPackages_latest.kernel.override` to a custom `buildLinux` call.

- [ ] **Step 4: Build and test**

Build, deploy, verify everything still works: display, audio, joypad, USB gadget, second SD slot, suspend/resume.

- [ ] **Step 5: Commit**

---

## Task 3: Pull RetroArch settings from device

**Goal:** Move user's RetroArch config tweaks into declarative `settings.nix` so they survive reflash.

**Files:**
- Modify: `modules/retroarch/settings.nix`

- [ ] **Step 1: Pull current config from device**

```bash
ssh root@10.0.0.2 "cat /home/gamer/.config/retroarch/retroarch.cfg" > /tmp/user-retroarch.cfg
```

- [ ] **Step 2: Diff against our declarative settings**

Compare `/tmp/user-retroarch.cfg` against what `modules/retroarch/settings.nix` currently sets. Identify user changes worth keeping.

- [ ] **Step 3: Add settings to settings.nix**

Known settings to add:
- Hide date/time display (no RTC, clock is always wrong)
- Disable "Online Updater" menu item (no network)
- Any other UI/menu tweaks the user has configured

- [ ] **Step 4: Deploy and verify**

```bash
nixos-rebuild switch ...
```

Reboot, confirm RetroArch picks up the new settings.

- [ ] **Step 5: Commit**

---

## Task 4: Devendor to flake inputs

**Goal:** Replace vendored source files with flake inputs + patches. Makes provenance clear, diffs reviewable, upstream updates easy.

**Files:**
- Modify: `flake.nix` (add inputs)
- Modify: `pkgs/rocknix-joypad/default.nix` (use flake input as source)
- Modify: `pkgs/panel-generic-dsi/default.nix` (use flake input as source)
- Modify: `pkgs/kernel-rk3326/default.nix` (use flake input for DTS base)
- Create: patch files for our changes on top of upstream sources
- Delete: vendored `.c`, `.h`, `.dts` files (replaced by input + patches)

**Flake inputs to add:**
```nix
inputs.rocknix-joypad = {
  url = "github:ROCKNIX/rocknix-joypad";
  flake = false;
};

inputs.buildroot-r36s = {
  url = "github:AndreRenaud/buildroot-r36s";
  flake = false;
};
```

Panel driver is in `ROCKNIX/distribution` (huge monorepo) — may be better to keep vendoring that single unmodified file.

- [ ] **Step 1: Clone upstream repos and diff**

Compare our vendored files against upstream to understand the exact diffs:
- `rocknix-singleadc-joypad.c` vs `ROCKNIX/rocknix-joypad/rocknix-singleadc-joypad.c`
- `rk3326-r36s.dts` vs `AndreRenaud/buildroot-r36s` DTS
- `panel-generic-dsi.c` vs `ROCKNIX/distribution/.../panel-generic-dsi.c`

- [ ] **Step 2: Generate patch files from diffs**

Create clean patches that apply our changes on top of upstream.

- [ ] **Step 3: Add flake inputs**

- [ ] **Step 4: Update package derivations to use inputs + patches**

For the joypad driver:
```nix
src = inputs.rocknix-joypad;
patches = [ ./patches/0001-port-to-6.19-poll-api.patch ./patches/0002-gpiod-conversion.patch ];
```

- [ ] **Step 5: Build and test**

No functional change — verify the built modules are identical.

- [ ] **Step 6: Delete vendored source files, commit**

---

## Task 5: Build U-Boot from source

**Goal:** Eliminate the last vendored binary blob by building U-Boot from Andre Renaud's repo.

**Files:**
- Create: `pkgs/u-boot-r36s/default.nix`
- Modify: `overlay.nix` (expose package)
- Modify: `handhelds/r36h/default.nix` (use built U-Boot)
- Modify: `socs/rk3326.nix` (reference built U-Boot)
- Delete: `handhelds/r36h/blobs/u-boot-rockchip.bin`

**References:**
- [Andre Renaud's u-boot-r36s](https://github.com/AndreRenaud/u-boot-r36s)
- nixpkgs `buildUBoot` function
- Armbian U-Boot defconfig/patches

- [ ] **Step 1: Research the U-Boot build**

Check Andre's repo for defconfig, Rockchip DDR blob requirements, and build process.

- [ ] **Step 2: Create Nix package using `buildUBoot`**

- [ ] **Step 3: Audit panel firmware**

While here, check if `rg351mp-kernel.dtb` (boot logo DTB, currently non-functional) and `mipi-panel.dtbo` are still needed. The boot logo doesn't work today. The DTBO is applied by `boot.ini` to the Linux DTB — check if our `panel_description` in the DTS makes it redundant.

- [ ] **Step 4: Build, flash full image, test boot**

U-Boot changes require a full image reflash (raw sector writes).

- [ ] **Step 5: Commit**

---

## Task 6: Package emulationstation-fcamod

**Goal:** Replace raw RetroArch UI with EmulationStation as the frontend, launching RetroArch per-game.

**Files:**
- Create: `pkgs/emulationstation-fcamod/default.nix`
- Modify: `overlay.nix`
- Modify: `modules/retroarch/default.nix` (RetroArch becomes a backend, not the main service)
- Create: `modules/emulationstation/default.nix` (new systemd service)
- Create: `modules/emulationstation/settings.nix`

**References:**
- [DeepWiki: ES integration with dArkOS](https://deepwiki.com/christianhaitian/dArkOS/5.3-emulationstation-frontend)
- emulationstation-fcamod source repo

**Key considerations:**
- ES needs SDL2/SDL3, Mesa, DRM/KMS output (same as RetroArch)
- Can build and test on any machine (laptop, x86) — only DRM output needs real hardware
- ROM scanning, system configs, theme engine
- RetroArch becomes a per-game launcher, not the main UI
- ES launches RetroArch with core + ROM arguments

- [ ] **Step 1: Find and package emulationstation-fcamod**

- [ ] **Step 2: Create NixOS module for ES service**

- [ ] **Step 3: Configure ES to launch RetroArch per-game**

- [ ] **Step 4: Test on device**

- [ ] **Step 5: Commit**
