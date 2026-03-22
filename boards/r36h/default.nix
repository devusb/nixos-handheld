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

  # Linux DTB: ROCKNIX generic-dsi with NV3051D panel init from ArkOS
  handheld.kernelDTB = "rk3326-gameconsole-r36s-rocknix.dtb";
  handheld.kernelDTBPath = ./dtb/rk3326-gameconsole-r36s-rocknix.dtb;
  handheld.bootIni = ./boot.ini;

  # U-Boot DTB: ArkOS BSP for U-Boot's own display init
  handheld.ubootDTB = /home/mhelton/misc/r36_boot/BOOT/gameconsole-r36s.dtb;

  # No bootloader — U-Boot + boot.ini
  boot.loader.grub.enable = false;

  # Custom kernel
  boot.kernelPackages = let
    kernel = pkgs.callPackage ../../pkgs/kernel-rk3326 { };
  in pkgs.linuxPackagesFor kernel;

  system.requiredKernelConfig = lib.mkForce [];

  # Kernel modules — only what this hardware needs
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.kernelModules = [
    "rtl8723bs"
    "panfrost"
  ];

  # WiFi and Bluetooth firmware
  hardware.enableRedistributableFirmware = true;

  # Auto-login on tty1 (no keyboard available, gamepad only)
  services.getty.autologinUser = "root";

  # Minimal system
  networking.hostName = "r36h";

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root.initialPassword = "nixos";

  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  hardware.graphics.enable = true;
  networking.firewall.enable = false;
  documentation.enable = false;

  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "25.05";
}
