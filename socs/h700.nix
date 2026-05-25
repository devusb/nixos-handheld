# SD card image module for Allwinner H700 handhelds.
#
# Sibling to socs/rk3326.nix, but takes a much simpler boot path:
# mainline U-Boot (anbernic_rg35xx_h700_defconfig) is built with
# CONFIG_DISTRO_DEFAULTS, so it scans MMC partitions for
# `extlinux/extlinux.conf` and `boot.scr`. NixOS's stock
# `boot.loader.generic-extlinux-compatible` writes the former on every
# nixos-rebuild — no custom installBootLoader needed (unlike R36H, where
# Armbian U-Boot reads fixed paths from boot.ini).
#
# Partition layout matches R36H structurally: a small FAT firmware
# partition followed by the ext4 NixOS root. The FAT partition is unused
# at runtime here — kept for symmetry and as a parking spot for any
# future per-device firmware blobs.
#
# U-Boot blob is dd'd to byte offset 8 KiB (sector 16). ROCKNIX's
# bootloader/update.sh confirms this offset; see docs/rocknix-h700-notes.md.

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.handheld;
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  options.handheld = {
    uboot = lib.mkOption {
      type = lib.types.path;
      description = "Path to combined SPL + U-Boot proper blob (u-boot-sunxi-with-spl.bin equivalent).";
    };

    ubootOffsetKB = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = ''
        Offset (in KiB) at which to dd the U-Boot blob onto the SD card.
        Allwinner BROM expects the SPL at byte 8192 (sector 16) on H6/H616-family
        SoCs including the H700. Confirmed via ROCKNIX bootloader/update.sh.
      '';
    };
  };

  config = {
    boot.initrd.supportedFilesystems = [
      "ext4"
      "vfat"
    ];

    # systemd-initrd lists efivarfs unconditionally; H700 has no EFI.
    boot.initrd.allowMissingModules = true;

    # Same expand-root fix as rk3326.nix: lsblk PARTN, not minor numbers,
    # because the roms card (mmcblk1) can perturb minor ordering on boot.
    # See https://github.com/NixOS/nixpkgs/pull/390183.
    systemd.services.expand-root-partition.script = lib.mkForce ''
      rootPart=$(${lib.getExe' pkgs.util-linux "findmnt"} -n -o SOURCE /)
      bootDevice=$(${lib.getExe' pkgs.util-linux "lsblk"} -npo PKNAME $rootPart)
      partNum=$(${lib.getExe' pkgs.util-linux "lsblk"} -no PARTN $rootPart)

      echo ",+," | ${lib.getExe' pkgs.util-linux "sfdisk"} -N$partNum --no-reread $bootDevice
      ${lib.getExe' pkgs.parted "partprobe"}
      ${lib.getExe' pkgs.e2fsprogs "resize2fs"} $rootPart
    '';

    # Distroboot — U-Boot's scan finds /boot/extlinux/extlinux.conf on
    # the ext4 rootfs partition.
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    sdImage = {
      # Default firmwarePartitionOffset = 8 MiB leaves 8160 KiB ahead of
      # the FAT partition — plenty for our 8 KiB SPL placement.
      firmwareSize = 30;

      # FAT partition is unused at runtime; leave it empty. (sd-image.nix
      # always creates two partitions, so we still need a populate hook.)
      populateFirmwareCommands = "true";

      populateRootCommands = ''
        mkdir -p ./files/boot
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
          -c ${config.system.build.toplevel} \
          -d ./files/boot
      '';

      postBuildCommands = ''
        dd if=${cfg.uboot} of=$img conv=fsync,notrunc bs=1024 \
           seek=${toString cfg.ubootOffsetKB}
      '';

      compressImage = true;
    };
  };
}
