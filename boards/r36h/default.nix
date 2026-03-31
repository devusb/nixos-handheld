# R36H board definition — RK3326-based handheld gaming device
# R36H is electrically identical to R36S (landscape shell variant)
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ../../modules
    ../../images/sd-image-rk3326.nix
    "${modulesPath}/profiles/minimal.nix"
  ];

  # Disable default hardware/base profiles — we specify hardware explicitly
  disabledModules = [
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
  ];

  # Boot blobs extracted from working R36H ArkOS SD card
  # Absolute paths required — files are gitignored, invisible to flake source
  # Requires --impure until we build U-Boot from source or fetchurl them
  handheld.bootBlobs = {
    idbloader = /home/mhelton/code/nixos-handheld/boards/r36h/boot/idbloader.img;
    uboot = /home/mhelton/code/nixos-handheld/boards/r36h/boot/uboot.img;
    trust = /home/mhelton/code/nixos-handheld/boards/r36h/boot/trust.img;
  };

  # Linux DTB: ROCKNIX generic-dsi with NV3051D panel init from ArkOS
  handheld.kernelDTB = "rk3326-gameconsole-r36s-rocknix.dtb";
  handheld.kernelDTBPath = ./dtb/rk3326-gameconsole-r36s-rocknix.dtb;
  handheld.bootIni = ./boot.ini;

  # U-Boot DTB: ArkOS BSP for U-Boot's own display init
  handheld.ubootDTB = ./dtb/gameconsole-r36s.dtb;

  # Custom kernel
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-rk3326;

  # Custom defconfig covers all required options via make olddefconfig,
  # but NixOS assertion checker reads the fragment directly and doesn't see them
  system.requiredKernelConfig = lib.mkForce [ ];

  # Kernel modules
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.kernelModules = [ "panfrost" ];

  # Firmware
  hardware.enableRedistributableFirmware = true;

  # Mount second SD card slot for ROMs
  fileSystems."/roms" = {
    device = "/dev/mmcblk0p1";
    fsType = "exfat";
    options = [
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "uid=${toString config.users.users.gamer.uid}"
      "gid=100"
      "umask=0022"
    ];
  };

  # Networking — no WiFi hardware on this unit
  networking.hostName = "r36h";
  networking.useDHCP = false;
  networking.firewall.enable = false;

  users.users.root.initialPassword = "nixos";

  # Kiosk mode — RetroArch owns the display
  console.enable = false;
  documentation.enable = false;

  # Debug tools
  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
    lsof
    pciutils
  ];

  system.stateVersion = "25.11";
}
