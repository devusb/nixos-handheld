# SD card image module for RK3326 handhelds
#
# Produces an MBR-partitioned image with:
#   - Raw U-Boot blobs at fixed sector offsets (before partition 1)
#   - Partition 1: FAT32 "BOOT" — kernel Image, uInitrd, DTB, boot.ini
#   - Partition 2: btrfs "ROOTFS" — NixOS root filesystem
#
# Sandbox-safe: uses mtools and mkfs.btrfs --rootdir (no loopback mounts).

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
    # Note: -A arm (not arm64) matches working ArkOS uInitrd header
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
        dosfstools btrfs-progs util-linux mtools coreutils zstd nix
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
        rootfs_dir=$(mktemp -d)
        mkdir -p $rootfs_dir/{etc,var,tmp,run,proc,sys,dev,home,root,boot,roms}
        mkdir -p $rootfs_dir/nix/store
        mkdir -p $rootfs_dir/nix/var/nix/{profiles,db,gcroots}

        # Copy nix store closure
        for path in $(cat ${closureInfo}/store-paths); do
          cp -a $path $rootfs_dir/nix/store/
        done

        # Populate Nix database
        export NIX_STATE_DIR=$rootfs_dir/nix/var/nix
        nix-store --load-db < ${closureInfo}/registration

        # Set up system profile
        ln -sfn ${config.system.build.toplevel} $rootfs_dir/nix/var/nix/profiles/system
        ln -sfn system $rootfs_dir/nix/var/nix/profiles/system-1-link

        # NixOS marker
        touch $rootfs_dir/etc/NIXOS

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
