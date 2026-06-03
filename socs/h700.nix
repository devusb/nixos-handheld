# Allwinner H700 SoC platform module — SD card image wiring plus
# SoC-level runtime quirks shared by every H700 handheld.
#
# Uses NixOS's stock generic-extlinux-compatible because mainline
# U-Boot's anbernic_rg35xx_h700_defconfig is built with
# CONFIG_DISTRO_DEFAULTS (no custom installBootLoader needed).
# U-Boot SPL dd'd at 8 KiB (sector 16), where the Allwinner BROM
# expects it on H6/H616-family SoCs.

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.handheld;

  # The sun4i-codec / H616 Audio Codec boots with 'DAC Playback Switch'
  # muted; nothing in our userspace stack unmutes it on its own.
  # alsa-ucm-conf's HiFi.conf only toggles 'Speaker Switch', and
  # FixedBootSequence requires an explicit alsaucm invocation we don't
  # make. The downstream effect is that SDL2's audio teardown deadlocks
  # when it tries to drain a sink whose DAC path is half-initialized,
  # which manifested as ES's HideWindow=true launch flow never reaching
  # system() to invoke the emulator.
  #
  # ROCKNIX hits the same issue and solves it the same way: a udev
  # RUN+= on controlC* add that brute-force amixers the card's mixer
  # path into a sane state (see packages/audio/alsa-utils/scripts/
  # soundconfig + udev.d/90-alsa-restore.rules in their tree). No
  # card filter — every cset is `|| true`, so the rule is a no-op
  # against cards (USB dongles etc.) that don't carry the H616
  # controls. %n is the kernel number, i.e. "0" for controlC0.
  codecInitScript = pkgs.writeShellScript "h616-codec-init" ''
    card="$1"
    amixer=${lib.getExe' pkgs.alsa-utils "amixer"}
    "$amixer" -c "$card" cset name='DAC Playback Switch' on    >/dev/null 2>&1 || true
    "$amixer" -c "$card" cset name='DAC Playback Volume' 63    >/dev/null 2>&1 || true
    "$amixer" -c "$card" cset name='Speaker Switch' on         >/dev/null 2>&1 || true
  '';
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

    # Use lsblk PARTN rather than minor numbers — the roms card
    # (mmcblk1) can perturb minor ordering on boot.
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

    services.udev.extraRules = ''
      SUBSYSTEM=="sound", KERNEL=="controlC[0-9]*", ACTION=="add", RUN+="${codecInitScript} %n"
    '';

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
