# R36H board definition — RK3326-based handheld gaming device
# R36H is electrically identical to R36S (landscape shell variant)
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../images/sd-image-rk3326.nix
  ];

  # Boot blobs extracted from working R36H ArkOS SD card
  handheld.bootBlobs = {
    idbloader = /home/mhelton/code/nixos-handheld/boards/r36h/boot/idbloader.img;
    uboot = /home/mhelton/code/nixos-handheld/boards/r36h/boot/uboot.img;
    trust = /home/mhelton/code/nixos-handheld/boards/r36h/boot/trust.img;
  };

  # R36H uses the gameconsole-r36s device tree (same hardware)
  handheld.kernelDTB = "rk3326-gameconsole-r36s.dtb";
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

  # Minimal system — no docs
  documentation.enable = false;

  # Basic system packages for debugging
  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
  ];

  # zram swap — safety net for 1GB RAM
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # CPU governor
  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "25.05";
}
