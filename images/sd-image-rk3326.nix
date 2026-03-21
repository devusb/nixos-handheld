# SD card image module for RK3326 handhelds
#
# Wraps NixOS's built-in sd-image.nix which handles rootfs population,
# activation, and nix DB correctly. We customize:
#   - U-Boot blobs dd'd to raw sector offsets
#   - FAT32 firmware partition repurposed for boot.ini + kernel + uInitrd + DTB
#   - Partition layout matching RK3326 boot expectations

{ config, lib, pkgs, ... }:

let
  cfg = config.handheld;

  idbloaderOffset = 64;    # sector 64 = 32 KB
  ubootOffset = 16384;     # sector 16384 = 8 MB
  trustOffset = 24576;      # sector 24576 = 12 MB
in
{
  imports = [
    <nixpkgs/nixos/modules/installer/sd-card/sd-image.nix>
  ];

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

    ubootDTB = lib.mkOption {
      type = lib.types.path;
      description = "Path to DTB for U-Boot's own display init (ArkOS BSP DTB)";
    };
  };

  config = {
    # uInitrd: wrap NixOS initrd in uImage format for U-Boot
    system.build.uInitrd = pkgs.runCommand "uInitrd" {
      nativeBuildInputs = [ pkgs.ubootTools ];
    } ''
      # -A arm (not arm64) — matches working ArkOS uInitrd header
      mkimage -A arm -O linux -T ramdisk -C gzip \
        -d ${config.system.build.initialRamdisk}/initrd \
        $out
    '';

    boot.initrd.compressor = "gzip";
    boot.initrd.supportedFilesystems = [ "ext4" "vfat" ];

    # sd-image.nix configuration
    sdImage = {
      # Leave room for U-Boot blobs before partition 1
      # U-Boot trust.img ends at sector 24576 + ~8192 = sector 32768 = 16 MB
      firmwarePartitionOffset = 16; # MB — start of firmware/boot partition
      firmwareSize = 100; # MB

      # Populate the firmware (boot) partition with kernel, initrd, DTB, boot.ini
      populateFirmwareCommands = ''
        cp ${config.system.build.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target} firmware/Image
        cp ${config.system.build.uInitrd} firmware/uInitrd
        cp ${config.system.build.kernel}/dtbs/rockchip/${cfg.kernelDTB} firmware/${cfg.kernelDTB}
        cp ${cfg.bootIni} firmware/boot.ini
        cp ${cfg.ubootDTB} firmware/gameconsole-r36s.dtb
      '';

      # Write U-Boot blobs to raw offsets and fix partition type
      postBuildCommands = ''
        # Write U-Boot blobs at raw sector offsets
        dd if=${cfg.bootBlobs.idbloader} of=$img bs=512 seek=${toString idbloaderOffset} conv=notrunc
        dd if=${cfg.bootBlobs.uboot} of=$img bs=512 seek=${toString ubootOffset} conv=notrunc
        dd if=${cfg.bootBlobs.trust} of=$img bs=512 seek=${toString trustOffset} conv=notrunc
      '';

      # No extlinux — we use boot.ini
      # But we still need /init symlink for the initrd to find stage-2
      populateRootCommands = ''
        mkdir -p ./files/boot
        ln -s ${config.system.build.toplevel}/init ./files/init
      '';

      compressImage = true;
    };

    # Disable GRUB — U-Boot + boot.ini handles booting
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;
  };
}
