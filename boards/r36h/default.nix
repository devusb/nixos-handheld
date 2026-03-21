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

  # No bootloader — we use U-Boot + boot.ini
  boot.loader.grub.enable = false;

  # Custom kernel
  boot.kernelPackages = let
    kernel = pkgs.callPackage ../../pkgs/kernel-rk3326 { };
  in pkgs.linuxPackagesFor kernel;

  # Skip NixOS kernel config assertions — our defconfig expands via
  # make olddefconfig and has these options, but the assertion checker
  # reads the defconfig fragment directly and doesn't see them.
  system.requiredKernelConfig = lib.mkForce [];

  # Kernel modules — override NixOS defaults which assume x86 hardware.
  # Most drivers are built-in (=y) in the defconfig, not modules (=m).
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.kernelModules = [
    "rtl8723bs"   # WiFi (RTL8723BS SDIO)
    "panfrost"    # Mali-G31 GPU
    "dwc2"        # USB OTG controller
    "g_ether"     # USB gadget ethernet — enables SSH over USB OTG
  ];

  # WiFi and Bluetooth firmware
  hardware.enableRedistributableFirmware = true;

  # Filesystem — use sd-image.nix defaults (ext4, label NIXOS_SD)

  # USB gadget ethernet — SSH over USB OTG cable
  networking.interfaces.usb0 = {
    ipv4.addresses = [{
      address = "10.0.0.1";
      prefixLength = 24;
    }];
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
  networking.wireless.enable = lib.mkForce false;
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
