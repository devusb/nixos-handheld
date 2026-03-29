# R36H board definition — RK3326-based handheld gaming device
# R36H is electrically identical to R36S (landscape shell variant)
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules
    ../../images/sd-image-rk3326.nix
  ];

  # Boot blobs extracted from working R36H ArkOS SD card
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
  handheld.ubootDTB = /home/mhelton/misc/r36_boot/BOOT/gameconsole-r36s.dtb;

  # No bootloader — U-Boot + boot.ini
  boot.loader.grub.enable = false;

  # Custom kernel
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-rk3326;

  system.requiredKernelConfig = lib.mkForce [];

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
    options = [ "nofail" "noauto" "x-systemd.automount" "x-systemd.device-timeout=5" "uid=1000" "gid=100" "umask=0022" ];
  };

  # Networking
  networking.hostName = "r36h";
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.anyInterface = true;

  # SSH (for future use if we get networking)
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  users.users.root.initialPassword = "nixos";

  documentation.enable = false;

  # Debug tools
  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
    lsof
    pciutils
  ];

  system.stateVersion = "25.05";
}
