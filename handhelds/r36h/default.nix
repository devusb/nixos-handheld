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
    ../../socs/rk3326.nix
    "${modulesPath}/profiles/minimal.nix"
  ];

  # Disable default hardware/base profiles — we specify hardware explicitly
  disabledModules = [
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
  ];

  # Armbian U-Boot with ext4 support
  handheld.uboot = ./blobs/u-boot-rockchip.bin;
  handheld.bootIni = ./boot.ini;
  handheld.panChoIni = ./firmware/PanCho.ini;
  handheld.logoEnv = ./firmware/logo.env;
  handheld.panelDtbo = ./firmware/panel4/mipi-panel.dtbo;
  handheld.panelDtb = ./firmware/panel4/rg351mp-kernel.dtb;

  # Linux DTB: built from kernel source with R36S DTS patch
  hardware.deviceTree = {
    enable = true;
    filter = "*rk3326-r36s.dtb";
    name = "rockchip/rk3326-r36s.dtb";
  };

  # Mainline kernel with RK3326 driver config
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-rk3326;

  # Out-of-tree ROCKNIX generic-dsi panel driver
  boot.extraModulePackages = [
    (pkgs.callPackage ../../pkgs/panel-generic-dsi {
      kernel = config.boot.kernelPackages.kernel;
    })
  ];

  # Blacklist mainline NV3051D driver (lacks R36H-specific init sequence)
  boot.blacklistedKernelModules = [ "panel_newvision_nv3051d" ];

  # Load display modules early so DRM framebuffer is ready before stage-1
  boot.initrd.kernelModules = [
    "rockchipdrm"
    "panel_generic_dsi"
    "phy_rockchip_inno_dsidphy"
  ];

  boot.kernelModules = [ "panfrost" "g_ether" ];
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  # USB gadget ethernet
  networking.interfaces.usb0 = {
    ipv4.addresses = [{
      address = "10.0.0.2";
      prefixLength = 24;
    }];
  };

  # Firmware
  hardware.enableRedistributableFirmware = true;

  # Mount second SD card slot for ROMs
  fileSystems."/roms" = {
    device = "/dev/mmcblk1p1";
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

  # zram swap — critical with only 1GB RAM
  zramSwap.enable = true;

  # Networking — no WiFi hardware, USB gadget ethernet only
  networking.hostName = "r36h";
  networking.useDHCP = false;
  networking.firewall.enable = false;

  # SSH for headless debugging via USB gadget
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

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
