# SD card image module for RK3326 handhelds
#
# Wraps NixOS's built-in sd-image.nix. Customizes:
#   - U-Boot blob dd'd to raw sector offset 64
#   - FAT32 firmware partition for boot.ini + panel assets
#   - Custom boot loader installer for generation support

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.handheld;

  # Boot loader installer script — called by nixos-rebuild switch/boot.
  # Copies dereferenced kernel/initrd/DTB to fixed paths in /boot
  # and updates /init symlink for the new generation.
  installBootLoader = pkgs.writeShellScript "install-boot-loader" ''
    export PATH=${pkgs.coreutils}/bin:$PATH
    system="$1"

    cp -L "$system/kernel" /boot/Image
    cp -L "$system/initrd" /boot/initrd
    cp -L "$system/dtbs/rockchip/rk3326-r36s.dtb" /boot/dtb
    ln -sfn "$system/init" /init
  '';
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  options.handheld = {
    uboot = lib.mkOption {
      type = lib.types.path;
      description = "Path to combined U-Boot blob (u-boot-rockchip.bin)";
    };

    bootIni = lib.mkOption {
      type = lib.types.path;
      description = "Path to boot.ini U-Boot script";
    };

    panChoIni = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to PanCho.ini panel chooser script";
    };

    logoEnv = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to logo.env for panel path";
    };

    panelDtbo = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to panel MIPI DTBO overlay";
    };

    panelDtb = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to panel kernel DTB for U-Boot display";
    };
  };

  config = {
    boot.initrd.supportedFilesystems = [
      "ext4"
      "vfat"
    ];

    # Custom boot loader — copies kernel/initrd/DTB to fixed paths in /boot
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;
    system.build.installBootLoader = installBootLoader;
    system.boot.loader.id = "handheld";

    sdImage = {
      firmwarePartitionOffset = 16; # MB
      firmwareSize = 100; # MB

      # Populate firmware (FAT) partition with boot.ini + panel assets
      populateFirmwareCommands = ''
        cp ${cfg.bootIni} firmware/boot.ini
        ${lib.optionalString (cfg.panChoIni != null) "cp ${cfg.panChoIni} firmware/PanCho.ini"}
        ${lib.optionalString (cfg.logoEnv != null) "cp ${cfg.logoEnv} firmware/logo.env"}
        mkdir -p firmware/ScreenFiles/Panel4
        ${lib.optionalString (
          cfg.panelDtbo != null
        ) "cp ${cfg.panelDtbo} firmware/ScreenFiles/Panel4/mipi-panel.dtbo"}
        ${lib.optionalString (
          cfg.panelDtb != null
        ) "cp ${cfg.panelDtb} firmware/ScreenFiles/Panel4/rg351mp-kernel.dtb"}
      '';

      # Write U-Boot blob + panel files with spaces in dir names
      postBuildCommands = ''
        dd if=${cfg.uboot} of=$img conv=fsync,notrunc bs=512 seek=64

        fatOffset=$((START * 512))
        export MTOOLS_SKIP_CHECK=1
        ${lib.optionalString (cfg.panelDtbo != null) ''
          mmd -i "$img@@$fatOffset" "::ScreenFiles/Panel 4"
          mcopy -i "$img@@$fatOffset" ${cfg.panelDtbo} "::ScreenFiles/Panel 4/mipi-panel.dtbo"
        ''}
        ${lib.optionalString (cfg.panelDtb != null) ''
          mcopy -i "$img@@$fatOffset" ${cfg.panelDtb} "::ScreenFiles/Panel 4/rg351mp-kernel.dtb"
        ''}
      '';

      # Populate rootfs with initial /boot contents
      populateRootCommands = ''
        mkdir -p ./files/boot

        # Dereference and copy kernel/initrd/DTB to fixed paths
        cp -L ${config.system.build.toplevel}/kernel ./files/boot/Image
        cp -L ${config.system.build.toplevel}/initrd ./files/boot/initrd
        cp -L ${config.system.build.toplevel}/dtbs/rockchip/rk3326-r36s.dtb ./files/boot/dtb

        # /init symlink for this generation
        ln -s ${config.system.build.toplevel}/init ./files/init
      '';

      compressImage = true;
    };
  };
}
