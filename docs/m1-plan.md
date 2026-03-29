# M1: Boot R36H to NixOS TTY — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a flashable SD card image that boots NixOS to a TTY on an R36H handheld, with working display, input, and SSH.

**Architecture:** A Nix flake with a custom kernel derivation (linux-stable 6.12 + RK3326 patches), a custom SD image module that handles MBR partitioning and raw U-Boot blob injection, and a minimal NixOS configuration. User provides their existing R36H boot blobs (idbloader.img, uboot.img, trust.img) which are dd'd to raw sector offsets. U-Boot loads boot.ini from FAT32, which boots the NixOS kernel+initrd (wrapped as uInitrd).

**Tech Stack:** Nix flakes, NixOS modules, aarch64-linux (via binfmt emulation or remote builders), linux-stable 6.12.y, U-Boot (prebuilt blobs)

**Spec:** `docs/superpowers/specs/2026-03-21-nixos-handheld-gaming-os-design.md`

**Prerequisites:**
- Host machine must have aarch64-linux build support. Either:
  - `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` in host NixOS config, or
  - A remote aarch64 builder configured in `nix.buildMachines`
- This is required because `nixosSystem { system = "aarch64-linux"; }` evaluates packages natively for aarch64. Pure cross-compilation of a full NixOS system is not well-supported.

**Reference material from working R36H ArkOS-R3XS boot partition** (`/home/mhelton/misc/r36_boot/BOOT/`):

| File | Details |
|------|---------|
| `boot.ini` | U-Boot script — loads `rk3326-rg351mp-linux.dtb` (NOT a gameconsole-specific DTB) |
| `Image` | Linux kernel ARM64 boot executable, 4K pages (~10.3 MB, dated Oct 2021 — old BSP kernel) |
| `uInitrd` | u-boot legacy uImage, **Linux/ARM** (not ARM64!), RAMDisk Image (gzip), ~12.6 MB |
| `gameconsole-r36s.dtb` | Present but **unused by boot.ini** — R36H uses the RG351MP device tree |
| `rk3326-rg351mp-linux.dtb` | The DTB actually loaded by boot.ini |

**Critical values from working boot.ini:**
- `initrd_loadaddr = "0x01100000"` (NOT 0x04000000)
- `loadaddr = "0x02000000"`
- `dtb_loadaddr = "0x01f00000"`
- `root=UUID=...` (uses UUID, not LABEL)
- `fbcon=rotate:0`
- uInitrd mkimage arch flag is `ARM` not `ARM64`

---

### Task 1: Initialize the Flake Repository

**Files:**
- Create: `nixos-handheld/flake.nix`
- Create: `nixos-handheld/.gitignore`

This task creates the new repo with a minimal flake that evaluates. No board support yet — just the skeleton.

- [ ] **Step 1: Create the repo directory**

```bash
mkdir -p ~/code/nixos-handheld
cd ~/code/nixos-handheld
git init
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
result
result-*
# User-provided boot blobs (binary, not committed)
boards/*/boot/*.img
```

- [ ] **Step 3: Write minimal `flake.nix`**

```nix
{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    {
      # Placeholder — will be populated in later tasks
      packages.x86_64-linux = { };
    };
}
```

- [ ] **Step 4: Verify flake evaluates**

```bash
cd ~/code/nixos-handheld
nix flake check --no-build
```

Expected: no errors (the flake has no outputs to check yet, but it should parse and lock).

- [ ] **Step 5: Commit**

```bash
cd ~/code/nixos-handheld
git add flake.nix flake.lock .gitignore
git commit -m "init: minimal flake skeleton for nixos-handheld"
```

---

### Task 2: Extract Kernel Patches and Determine DTB Filename

**Files:**
- Create: `nixos-handheld/pkgs/kernel-rk3326/patches/0001-rk3326-handheld-support.patch` (or split patches)
- Create: `nixos-handheld/pkgs/kernel-rk3326/rk3326_defconfig`

The ohjhas repo has 7 commits on `linux-6.12.y-rk3326` on top of linux-stable. Commits 2 and 3 cancel out (add rocknix-joypad then revert it). Commit 7 is a merge commit bringing the branch up to 6.12.74. The effective patches are commits 1, 4, 5, and 6.

- [ ] **Step 1: Clone the ohjhas repo**

```bash
cd /tmp
git clone --branch linux-6.12.y-rk3326 https://github.com/ohjhas/linux-stable-rk3326.git
cd linux-stable-rk3326
```

- [ ] **Step 2: Determine the R36H DTB filename**

```bash
ls arch/arm64/boot/dts/rockchip/rk3326-*
# Look for R36S, R36H, R36, or gameconsole in the filenames
# Also check the DTS files for compatible strings mentioning R36H
grep -rl "r36" arch/arm64/boot/dts/rockchip/ || true
grep -rl "gameconsole" arch/arm64/boot/dts/rockchip/ || true
```

Record the exact DTB filename. This is critical — getting it wrong means a non-booting image with no feedback unless you have UART. Update all references in later tasks to use the correct filename.

- [ ] **Step 3: Generate the combined patch**

```bash
cd /tmp/linux-stable-rk3326

# The merge commit is 9d9b7556. Its second parent is linux 6.12.74 (444b39ef6108).
# Diff custom changes vs the 6.12.74 base:
git diff 444b39ef6108..9d9b7556 > /tmp/full-rk3326-diff.patch
```

Review the diff to understand scope:

```bash
wc -l /tmp/full-rk3326-diff.patch
# Check which files are touched
grep "^diff --git" /tmp/full-rk3326-diff.patch
```

- [ ] **Step 4: Copy patch and defconfig into the repo**

```bash
mkdir -p ~/code/nixos-handheld/pkgs/kernel-rk3326/patches
cp /tmp/full-rk3326-diff.patch ~/code/nixos-handheld/pkgs/kernel-rk3326/patches/0001-rk3326-handheld-support.patch
cp /tmp/linux-stable-rk3326/arch/arm64/configs/rk3326_defconfig ~/code/nixos-handheld/pkgs/kernel-rk3326/rk3326_defconfig
```

Optionally split the monolithic patch into logical groups using `filterdiff` (from `patchutils`). A single patch is acceptable for M1.

- [ ] **Step 5: Verify patch applies cleanly against linux-stable 6.12.74**

```bash
cd /tmp
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.74.tar.xz
tar xf linux-6.12.74.tar.xz
cd linux-6.12.74
git init && git add -A && git commit -m "base"
git apply --check ~/code/nixos-handheld/pkgs/kernel-rk3326/patches/*.patch
```

Expected: no errors. If there are failures, adjust the patches.

- [ ] **Step 6: Commit**

```bash
cd ~/code/nixos-handheld
git add pkgs/kernel-rk3326/
git commit -m "kernel: extract RK3326 patches from ohjhas/linux-stable-rk3326

Patches extracted against linux-stable 6.12.74. Source commits:
- 330814ea rk3326 bringup (DTS, panel drivers, devfreq, BT fixes)
- 765b030c enable joystick (GPIO joypad drivers)
- 98abe292 joystick needs polldev (re-introduce input-polldev)
- d5da60f7 update Makefile"
```

---

### Task 3: Package the Kernel as a Nix Derivation

**Files:**
- Create: `nixos-handheld/pkgs/kernel-rk3326/default.nix`
- Modify: `nixos-handheld/flake.nix`

- [ ] **Step 1: Write the kernel derivation**

Create `nixos-handheld/pkgs/kernel-rk3326/default.nix`:

```nix
{ lib, fetchurl, linuxKernel, ... }:

linuxKernel.manualConfig {
  version = "6.12.74";
  modDirVersion = "6.12.74";

  src = fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.74.tar.xz";
    # Get hash with: nix-prefetch-url --type sha256 --unpack <url>
    hash = ""; # TODO: fill after first build attempt — nix will tell you the expected hash
  };

  configfile = ./rk3326_defconfig;

  # Allow the build to proceed even if the defconfig doesn't cover all
  # options NixOS modules try to set. We'll refine iteratively.
  ignoreConfigErrors = true;

  kernelPatches = [
    {
      name = "rk3326-handheld-support";
      patch = ./patches/0001-rk3326-handheld-support.patch;
    }
  ];

  extraMeta = {
    platforms = [ "aarch64-linux" ];
    description = "Linux 6.12.74 with RK3326 handheld patches";
  };
}
```

Note: Using `linuxKernel.manualConfig` (not `linuxManualConfig`) because it properly supports `kernelPatches` and `ignoreConfigErrors`.

- [ ] **Step 2: Wire kernel into flake.nix as a standalone build target**

Update `nixos-handheld/flake.nix`:

```nix
{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # For building the kernel standalone (test cross-compilation)
      pkgsCross = import nixpkgs {
        system = "x86_64-linux";
        crossSystem.system = "aarch64-linux";
      };
    in
    {
      packages.x86_64-linux = {
        kernel-rk3326 = pkgsCross.callPackage ./pkgs/kernel-rk3326 { };
      };
    };
}
```

- [ ] **Step 3: Attempt to build the kernel**

```bash
cd ~/code/nixos-handheld
nix build .#packages.x86_64-linux.kernel-rk3326
```

This will fail on the first attempt. Expected iteration:
1. Missing `hash` — fill from the error message (nix prints `got: sha256-XXXX`)
2. Config errors — the defconfig may be missing options NixOS expects. With `ignoreConfigErrors = true` these should be warnings, not failures.
3. Patch apply failures — fix patches if needed.

Iterate until the kernel cross-compiles successfully.

- [ ] **Step 4: Verify kernel output**

```bash
ls -la result/
file result/Image
# Expected: "Linux kernel ARM64 boot executable Image"
```

The uncompressed `Image` file is what U-Boot's `booti` expects. Do NOT use `zImage` or `bzImage`.

- [ ] **Step 5: Commit**

```bash
cd ~/code/nixos-handheld
git add pkgs/kernel-rk3326/default.nix flake.nix flake.lock
git commit -m "kernel: add Nix derivation for linux-stable 6.12.74 + rk3326 patches"
```

---

### Task 4: Create the SD Image Module

**Files:**
- Create: `nixos-handheld/images/sd-image-rk3326.nix`

This module handles MBR partitioning, raw U-Boot blob injection, boot.ini, and rootfs population. It avoids loopback mounts (which require root and break in the Nix sandbox) by using `mkfs.btrfs --rootdir` and `mtools` for FAT32.

- [ ] **Step 1: Write the SD image module**

Create `nixos-handheld/images/sd-image-rk3326.nix`:

```nix
# SD card image module for RK3326 handhelds
#
# Produces an MBR-partitioned image with:
#   - Raw U-Boot blobs at fixed sector offsets (before partition 1)
#   - Partition 1: FAT32 "BOOT" — kernel Image, uInitrd, DTB, boot.ini
#   - Partition 2: btrfs "ROOTFS" — NixOS root filesystem
#
# No loopback mounts — sandbox-safe. Uses mtools and mkfs.btrfs --rootdir.

{ config, lib, pkgs, ... }:

let
  cfg = config.handheld;

  # Sector size is always 512 bytes
  idbloaderOffset = 64;       # sector 64 = 32 KB
  ubootOffset = 16384;        # sector 16384 = 8 MB
  trustOffset = 24576;         # sector 24576 = 12 MB
  bootPartStart = 32768;       # sector 32768 = 16 MB
  bootPartSizeMB = 100;
  rootPartSizeMB = 4096;
in
{
  options.handheld = {
    bootBlobs = {
      idbloader = lib.mkOption {
        type = lib.types.path;
        description = "Path to idbloader.img";
      };
      uboot = lib.mkOption {
        type = lib.types.path;
        description = "Path to uboot.img";
      };
      trust = lib.mkOption {
        type = lib.types.path;
        description = "Path to trust.img";
      };
    };

    kernelDTB = lib.mkOption {
      type = lib.types.str;
      description = "Device tree blob filename (e.g., rk3326-gameconsole-r36s.dtb)";
    };

    bootIni = lib.mkOption {
      type = lib.types.path;
      description = "Path to boot.ini U-Boot script";
    };
  };

  config = {
    # uInitrd: wrap NixOS initrd in uImage format for U-Boot
    boot.initrd.compressor = "gzip";
    boot.initrd.supportedFilesystems = [ "btrfs" "vfat" ];

    system.build.uInitrd = pkgs.runCommand "uInitrd" {
      nativeBuildInputs = [ pkgs.ubootTools ];
    } ''
      # Note: -A arm (not arm64) — matches working ArkOS uInitrd header
      mkimage -A arm -O linux -T ramdisk -C gzip \
        -d ${config.system.build.initialRamdisk}/initrd \
        $out
    '';

    system.build.sdImage = let
      closureInfo = pkgs.closureInfo {
        rootPaths = [ config.system.build.toplevel ];
      };
      bootPartSizeSectors = bootPartSizeMB * 1024 * 2;
      rootPartSizeSectors = rootPartSizeMB * 1024 * 2;
      rootPartStart = bootPartStart + bootPartSizeSectors;
      totalSectors = rootPartStart + rootPartSizeSectors + 1024;
    in
    pkgs.stdenvNoCC.mkDerivation {
      name = "nixos-rk3326-sd-image";

      nativeBuildInputs = with pkgs; [
        dosfstools btrfs-progs util-linux mtools coreutils zstd
      ];

      buildCommand = ''
        mkdir -p $out

        img=$out/nixos-rk3326.img

        # Create empty image
        truncate -s $((${toString totalSectors} * 512)) $img

        # Write U-Boot blobs at raw offsets
        dd if=${cfg.bootBlobs.idbloader} of=$img bs=512 seek=${toString idbloaderOffset} conv=notrunc
        dd if=${cfg.bootBlobs.uboot} of=$img bs=512 seek=${toString ubootOffset} conv=notrunc
        dd if=${cfg.bootBlobs.trust} of=$img bs=512 seek=${toString trustOffset} conv=notrunc

        # Create MBR partition table
        sfdisk $img <<PART
          label: dos
          unit: sectors

          start=${toString bootPartStart}, size=${toString bootPartSizeSectors}, type=c
          start=${toString rootPartStart}, size=${toString rootPartSizeSectors}, type=83
        PART

        # --- FAT32 boot partition (using mtools, no mount needed) ---
        truncate -s ${toString bootPartSizeMB}M boot.img
        mkfs.vfat -n BOOT boot.img

        mcopy -i boot.img ${config.system.build.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target} ::Image
        mcopy -i boot.img ${config.system.build.uInitrd} ::uInitrd
        mcopy -i boot.img ${config.system.build.kernel}/dtbs/rockchip/${cfg.kernelDTB} ::${cfg.kernelDTB}
        mcopy -i boot.img ${cfg.bootIni} ::boot.ini

        # Write boot partition into image
        dd if=boot.img of=$img bs=512 seek=${toString bootPartStart} conv=notrunc

        # --- btrfs rootfs (using mkfs.btrfs --rootdir, no mount needed) ---
        # Prepare rootfs directory structure
        rootfs_dir=$(mktemp -d)
        mkdir -p $rootfs_dir/{etc,var,tmp,run,proc,sys,dev,home,root,boot,roms}
        mkdir -p $rootfs_dir/nix/store
        mkdir -p $rootfs_dir/nix/var/nix/{profiles,db,gcroots}

        # Copy nix store closure
        for path in $(cat ${closureInfo}/store-paths); do
          cp -a $path $rootfs_dir/nix/store/
        done

        # Populate Nix database so switch-to-configuration works
        export NIX_STATE_DIR=$rootfs_dir/nix/var/nix
        # Register the closure in the Nix DB
        ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo}/registration

        # Set up system profile
        ln -sfn ${config.system.build.toplevel} $rootfs_dir/nix/var/nix/profiles/system
        ln -sfn system $rootfs_dir/nix/var/nix/profiles/system-1-link

        # NixOS marker
        touch $rootfs_dir/etc/NIXOS
        # Activation will create /etc contents on first boot via switch-to-configuration

        # Create the btrfs image from the directory
        truncate -s ${toString rootPartSizeMB}M rootfs.img
        mkfs.btrfs -L ROOTFS --rootdir $rootfs_dir -f rootfs.img

        # Write rootfs into image
        dd if=rootfs.img of=$img bs=512 seek=${toString rootPartStart} conv=notrunc

        # Compress final image
        zstd -T0 -10 $img -o $out/nixos-rk3326.img.zst
        rm $img
      '';
    };
  };
}
```

**Key design decisions:**
- **No loopback mounts** — uses `mtools` (mcopy) for FAT32 and `mkfs.btrfs --rootdir` for btrfs. Both work in the Nix sandbox without root.
- **uInitrd wrapping** — integrated here (not a separate task) since U-Boot on RK3326 always needs it.
- **Nix database** — populated via `nix-store --load-db` from closureInfo so `switch-to-configuration` works on first boot.
- **btrfs** — matches dArkOS default. No `^free-space-tree` flag since kernel 6.12 supports it natively.

- [ ] **Step 2: Verify the module syntax**

```bash
cd ~/code/nixos-handheld
nix eval --expr 'let f = import ./images/sd-image-rk3326.nix; in builtins.typeOf f'
```

Expected: `"lambda"` (valid NixOS module function).

- [ ] **Step 3: Commit**

```bash
cd ~/code/nixos-handheld
git add images/sd-image-rk3326.nix
git commit -m "images: add sandbox-safe SD card image module for RK3326

MBR partitioning with raw U-Boot blob injection. Uses mtools and
mkfs.btrfs --rootdir to avoid loopback mounts. Includes uInitrd
wrapping for U-Boot compatibility."
```

---

### Task 5: Create the R36H Board Definition and boot.ini

**Files:**
- Create: `nixos-handheld/boards/r36h/default.nix`
- Create: `nixos-handheld/boards/r36h/boot.ini`

- [ ] **Step 1: Create boot.ini**

Create `nixos-handheld/boards/r36h/boot.ini`. Values are taken directly from the working ArkOS-R3XS boot.ini, with only the `root=` parameter changed:

```
odroidgoa-uboot-config

setenv bootargs "root=/dev/mmcblk0p2 rootfstype=btrfs rootwait rw fsck.repair=yes net.ifnames=0 fbcon=rotate:0 console=/dev/ttyFIQ0 consoleblank=0 vt.global_cursor_default=0"

setenv loadaddr "0x02000000"
setenv initrd_loadaddr "0x01100000"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 ${loadaddr} Image
load mmc 1:1 ${initrd_loadaddr} uInitrd
load mmc 1:1 ${dtb_loadaddr} rk3326-rg351mp-linux.dtb

booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
```

Notes:
- **Memory addresses match the working ArkOS boot.ini exactly** — `initrd_loadaddr=0x01100000` is critical (NOT 0x04000000 which was in the spec)
- `root=/dev/mmcblk0p2` — hardcoded device path, same as working ArkOS. UUID/LABEL can be tried later.
- DTB is `rk3326-rg351mp-linux.dtb` — the R36H uses the RG351MP device tree (the `gameconsole-r36s.dtb` on the boot partition is unused)
- Removed `quiet splash plymouth.ignore-serial-consoles` — we want to see boot messages for debugging
- The ohjhas kernel's DTB for the RG351MP may have a different filename. Check after kernel build: `find result/dtbs -name "*rg351*" -o -name "*gameconsole*"`. If the ohjhas kernel only has `rk3326-odroidgo2-linux.dtb` or similar, we may need to use the DTB from the working boot partition directly instead.

- [ ] **Step 2: Create the board NixOS configuration**

Create `nixos-handheld/boards/r36h/default.nix`:

```nix
# R36H board definition — RK3326-based handheld gaming device
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../images/sd-image-rk3326.nix
  ];

  # Boot blob paths — user must place these in boards/r36h/boot/
  handheld.bootBlobs = {
    idbloader = ./boot/idbloader.img;
    uboot = ./boot/uboot.img;
    trust = ./boot/trust.img;
  };

  # R36H uses the RG351MP device tree (confirmed from working ArkOS boot.ini)
  # After kernel build, verify this DTB exists at: result/dtbs/rockchip/rk3326-rg351mp-linux.dtb
  # If the ohjhas kernel names it differently, update here or use the DTB from the working boot partition
  handheld.kernelDTB = "rk3326-rg351mp-linux.dtb";
  handheld.bootIni = ./boot.ini;

  # Custom kernel
  boot.kernelPackages = let
    kernel = pkgs.callPackage ../../pkgs/kernel-rk3326 { };
  in pkgs.linuxPackagesFor kernel;

  # Kernel modules
  boot.initrd.availableKernelModules = [
    "btrfs" "dm_mod" "sd_mod" "usb_storage" "mmc_block"
  ];
  boot.kernelModules = [
    "rtl8723bs"   # WiFi (RTL8723BS SDIO)
    "panfrost"    # Mali-G31 GPU
  ];

  # WiFi and Bluetooth firmware
  hardware.enableRedistributableFirmware = true;

  # Filesystem configuration
  fileSystems."/" = {
    device = "/dev/disk/by-label/ROOTFS";
    fsType = "btrfs";
    options = [ "compress=zlib:1" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  # Minimal system — just enough to boot and SSH in
  networking.hostName = "r36h";

  # SSH access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Set root password for serial/SSH access
  users.users.root.initialPassword = "nixos";

  # WiFi support (RTL8723BS via NetworkManager)
  networking.wireless.enable = false;
  networking.networkmanager.enable = true;

  # Hardware graphics (Panfrost for Mali-G31 via Mesa)
  hardware.graphics.enable = true;

  # Minimal system — no docs, no X11
  documentation.enable = false;

  # Basic system packages for debugging
  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest       # test gamepad input
  ];

  # zram swap — safety net for 1GB RAM
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # CPU governor — ondemand for balanced power/performance
  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "25.05";
}
```

Notes:
- Removed `nix.enable = false` — can cause assertion failures in some NixOS modules. Instead we just don't install nix tooling in `environment.systemPackages`.
- Removed `environment.noXlibs = true` — can conflict with Mesa/Panfrost which needs some X libs.
- Added `hardware.enableRedistributableFirmware = true` — needed for RTL8723BS WiFi firmware.
- Added explicit `boot.kernelModules` for WiFi and GPU.
- Added `zramSwap` for 1GB RAM safety.
- Removed `pciutils` and `i2c-tools` — not needed for M1, RK3326 doesn't have PCI.

- [ ] **Step 3: Commit**

```bash
cd ~/code/nixos-handheld
git add boards/r36h/
git commit -m "boards: add R36H board definition with boot.ini

Minimal NixOS config for boot-to-TTY with SSH, WiFi firmware,
Panfrost GPU, and zram swap. User must place boot blobs in
boards/r36h/boot/ before building."
```

---

### Task 6: Wire Everything into flake.nix and Build the Image

**Files:**
- Modify: `nixos-handheld/flake.nix`

- [ ] **Step 1: Update flake.nix**

```nix
{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.r36h = nixpkgs.lib.nixosSystem {
        # Builds for aarch64 — requires binfmt emulation or remote aarch64 builder
        system = "aarch64-linux";
        modules = [
          ./boards/r36h
        ];
      };

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        r36h-uInitrd = self.nixosConfigurations.r36h.config.system.build.uInitrd;

        # Standalone kernel build (for testing cross-compilation without full NixOS eval)
        kernel-rk3326 = let
          pkgsCross = import nixpkgs {
            inherit system;
            crossSystem.system = "aarch64-linux";
          };
        in pkgsCross.callPackage ./pkgs/kernel-rk3326 { };
      };
    };
}
```

- [ ] **Step 2: Place boot blobs**

Before building, extract boot blobs from a working R36H SD card:

```bash
mkdir -p ~/code/nixos-handheld/boards/r36h/boot

# With the R36H's SD card at /dev/sdX:
dd if=/dev/sdX of=boards/r36h/boot/idbloader.img bs=512 skip=64 count=8000
dd if=/dev/sdX of=boards/r36h/boot/uboot.img bs=512 skip=16384 count=8192
dd if=/dev/sdX of=boards/r36h/boot/trust.img bs=512 skip=24576 count=8192
```

Alternatively, if you have the dArkOS build output, copy the blobs from `sd_fuse/`.

**Verify blobs are present and non-empty:**
```bash
ls -la boards/r36h/boot/
# All three files should be present and >0 bytes
file boards/r36h/boot/*.img
```

- [ ] **Step 3: Attempt the image build**

```bash
cd ~/code/nixos-handheld
nix build .#packages.x86_64-linux.r36h-image
```

This will be iterative. Expected issues and fixes:

| Issue | Fix |
|-------|-----|
| Kernel hash missing | Fill `hash` in `pkgs/kernel-rk3326/default.nix` from error output |
| Kernel config errors | Add `structuredExtraConfig` to the kernel derivation for missing options |
| `nix-store --load-db` fails in sandbox | May need `__noChroot = true` on the image derivation, or restructure to use `pkgs.vmTools.runInLinuxVM` |
| `mkfs.btrfs --rootdir` fails | Ensure btrfs-progs version supports `--rootdir` (should on nixos-unstable) |
| DTB not found at expected path | Check `result/dtbs/rockchip/` after kernel build to find correct DTB path |

- [ ] **Step 4: Verify image structure**

Once the build succeeds:

```bash
# Check partition table
fdisk -l result/nixos-rk3326.img

# Expected:
# Disklabel type: dos
# Device          Start      End  Sectors  Size Type
# result/...p1    32768   237567   204800  100M  W95 FAT32
# result/...p2   237568  8626175  8388608    4G  Linux

# Check boot partition contents (using mtools, no mount needed)
mdir -i result/nixos-rk3326.img@@$((32768 * 512))
# Expected: Image, uInitrd, rk3326-*.dtb, boot.ini

# Verify uInitrd format
dd if=result/nixos-rk3326.img bs=512 skip=32768 count=204800 of=/tmp/boot.img 2>/dev/null
mcopy -i /tmp/boot.img ::uInitrd /tmp/uInitrd
file /tmp/uInitrd
# Expected: "u-boot legacy uImage, Linux/ARM, RAMDisk Image (gzip)"

# Verify boot.ini content
mcopy -i /tmp/boot.img ::boot.ini /tmp/boot.ini
cat /tmp/boot.ini
```

- [ ] **Step 5: Commit**

```bash
cd ~/code/nixos-handheld
git add flake.nix flake.lock
git commit -m "flake: wire up R36H NixOS config and image build"
```

---

### Task 7: Flash and Test on Hardware

This is the real test — everything before this was build-side verification.

- [ ] **Step 1: Flash the image to an SD card**

```bash
# If compressed:
zstd -d result/nixos-rk3326.img.zst -o /tmp/nixos-r36h.img
# If not compressed:
cp result/nixos-rk3326.img /tmp/nixos-r36h.img

# Flash (replace /dev/sdX with your SD card device — BE CAREFUL)
sudo dd if=/tmp/nixos-r36h.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

- [ ] **Step 2: Boot the R36H**

Insert the SD card and power on. If you have a USB-serial adapter, connect to the debug UART (`ttyFIQ0` at 115200 baud) for boot logs.

**What to look for:**
1. U-Boot output (UART) — should show it loading Image, uInitrd, DTB
2. Kernel boot messages on display or UART
3. NixOS systemd starting services
4. Login prompt

**If nothing appears on screen:**
- Panel/display driver may not match your R36H's LCD — try HDMI out
- Check UART for kernel panics
- See Task 8 troubleshooting guide

- [ ] **Step 3: Verify basic functionality**

If the device boots (via SSH, UART, or on-screen login):

```bash
ssh root@<device-ip>   # Password: nixos

# On device — verify each subsystem:
uname -a               # Should show 6.12.74 aarch64
cat /proc/cpuinfo      # Should show Cortex-A35
mount                  # Should show btrfs root with compress=zlib:1
evtest                 # Should list joypad device — test button presses
ip addr                # Should show wlan0
nmcli device wifi list # Should show available networks
aplay -l               # Should show RK817 audio device
cat /sys/class/power_supply/*/capacity 2>/dev/null  # Battery level
```

- [ ] **Step 4: Document results**

```
R36H M1 Boot Status:
- [ ] U-Boot loads boot.ini
- [ ] Kernel boots (no panic)
- [ ] Display output works
- [ ] initrd mounts rootfs successfully
- [ ] systemd starts
- [ ] Login prompt appears (UART/screen)
- [ ] SSH works
- [ ] Gamepad input detected (evtest)
- [ ] WiFi scans networks
- [ ] Audio device present (aplay -l)
```

- [ ] **Step 5: Commit any fixes**

```bash
cd ~/code/nixos-handheld
git add -A
git commit -m "fix: [describe what was fixed during hardware testing]"
```

---

### Task 8: Iterate on Boot Failures

This is a troubleshooting guide for the most likely failure modes. Not all steps will be needed — use whichever applies.

- [ ] **If U-Boot doesn't load boot.ini:**

Boot blobs may be at wrong offsets. Compare with a working dArkOS image:

```bash
# Dump header from working dArkOS SD card
dd if=/dev/sdX of=/tmp/darkos-header.bin bs=1M count=16
# Dump from our image
dd if=/tmp/nixos-r36h.img of=/tmp/nixos-header.bin bs=1M count=16

# Compare at idbloader offset (sector 64 = byte 32768)
hexdump -C -s 32768 -n 64 /tmp/darkos-header.bin
hexdump -C -s 32768 -n 64 /tmp/nixos-header.bin
# Should show similar U-Boot magic bytes
```

- [ ] **If kernel panics on rootfs mount:**

The initrd may not have btrfs support, or the root= parameter is wrong.

```bash
# Try with explicit device path instead of LABEL=
# Edit boot.ini: change root=LABEL=ROOTFS to root=/dev/mmcblk0p2
```

Also verify `boot.initrd.supportedFilesystems` includes `"btrfs"` — check by extracting the initrd:

```bash
mcopy -i /tmp/boot.img ::uInitrd /tmp/uInitrd
dd if=/tmp/uInitrd bs=64 skip=1 | gunzip | cpio -t 2>/dev/null | grep btrfs
# Should show btrfs.ko or similar
```

- [ ] **If display is blank but UART shows boot:**

Panel driver mismatch. The DTB specifies a particular LCD panel, and your R36H may have a different one.

```bash
# On a working dArkOS install, check which panel is active:
cat /sys/class/drm/*/status
cat /proc/device-tree/compatible
dmesg | grep -i panel
```

Compare with the DTS file used by the ohjhas kernel.

- [ ] **If initrd format is wrong:**

U-Boot prints "Wrong Image Type" on UART.

```bash
# Verify uInitrd header
mcopy -i /tmp/boot.img ::uInitrd /tmp/uInitrd
mkimage -l /tmp/uInitrd
# Should show: Image Type: ARM Linux RAMDisk Image (gzip compressed)
```

If it doesn't show the right format, the `mkimage` wrapping in the image module needs adjustment.

- [ ] **If kernel doesn't start at all:**

```bash
# Verify kernel format
mcopy -i /tmp/boot.img ::Image /tmp/Image
file /tmp/Image
# Must show: "Linux kernel ARM64 boot executable Image"
# NOT: "data", "gzip compressed", or "zImage"
```

---

## Summary

| Task | What it produces | Key risk |
|------|-----------------|----------|
| 1 | Flake skeleton | None |
| 2 | Kernel patches + DTB filename | Patches may not apply cleanly; DTB filename TBD |
| 3 | Kernel derivation | Config mismatches, cross-compilation issues |
| 4 | SD image module | `nix-store --load-db` sandbox behavior; btrfs --rootdir support |
| 5 | R36H board config + boot.ini | Panel/DTB compatibility |
| 6 | Buildable image | All of the above compound here |
| 7 | Hardware boot test | Panel/display compatibility, boot blob correctness |
| 8 | Troubleshooting | Reactive — varies |

**Critical path: Tasks 2→3→4→6→7.** Tasks 1 and 5 are straightforward. Task 8 is reactive.

**Expected iteration:** Multiple build-fix-rebuild cycles in Tasks 3, 4, and 6. The kernel and image builder will each need several rounds of fixing before they produce a correct output. This is normal for embedded NixOS bring-up.
