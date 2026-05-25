# RG28XX board definition — Allwinner H700 horizontal handheld.
# Speculative pre-hardware build; see docs/rg28xx-bringup.md for the
# verification checklist (panel driver, joystick DTS bindings, etc.).
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
    ../../socs/h700.nix
    "${modulesPath}/profiles/minimal.nix"
  ];

  disabledModules = [
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
  ];

  hardware.enableAllHardware = lib.mkForce false;

  handheld.uboot = pkgs.u-boot-rg28xx + "/u-boot-sunxi-with-spl.bin";

  hardware.deviceTree = {
    enable = true;
    dtbSource = "${pkgs.h700-dtb}";
    name = "allwinner/sun50i-h700-anbernic-rg28xx.dtb";
  };

  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-h700;

  # rocknix-joypad's overlay attribute is kernel-pinned to linux-rk3326
  # for R36H; rebuild it here against linux-h700.
  boot.extraModulePackages = [
    (pkgs.rocknix-joypad.override { kernel = pkgs.linux-h700; })
  ];

  boot.initrd.includeDefaultModules = false;

  boot.kernelModules = [
    "g_ether"
    "panfrost"
    "rocknix_singleadc_joypad"
  ];
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  # Default panfrost; mali-kbase + libmali wiring on H700 is unverified.
  handheld.gpu.specialisation = {
    enable = false;
    picker.enable = false;
  };

  handheld.portmaster.enable = true;

  handheld.fakeSuspend = {
    enable = true;
    powerButtonDevice = "axp20x-pek";
  };

  # USB gadget ethernet (same convention as R36H: 10.0.0.2/24)
  networking.interfaces.usb0 = {
    ipv4.addresses = [
      {
        address = "10.0.0.2";
        prefixLength = 24;
      }
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # Second SD card for ROMs (matches R36H's mmcblk1p1 layout assumption)
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

  zramSwap.enable = true;
  zramSwap.memoryPercent = 100;

  networking.hostName = "rg28xx";
  networking.useDHCP = false;
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root.initialPassword = "nixos";

  handheld.emulationstation.enable = true;
  handheld.emulationstation.inputConfigFile = ./es_input.cfg;
  handheld.emulationstation.drastic.configFile = ./drastic.cfg;

  # Vendor/product ID + button map are placeholders until hardware lands;
  # see docs/rg28xx-bringup.md. ES still needs *some* mapping or it
  # refuses to dispatch button events to RetroArch, so this is a
  # known-broken stub that gets overwritten on first bring-up.
  systemd.services.emulationstation.environment.SDL_GAMECONTROLLERCONFIG = lib.mkDefault "";

  console.enable = false;
  documentation.enable = false;

  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
    lsof
    pciutils
    vim
  ];

  system.stateVersion = "25.11";
}
