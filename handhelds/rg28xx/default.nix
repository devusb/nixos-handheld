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

  # Use ROCKNIX's prebuilt U-Boot blob — known-good bytes from
  # ROCKNIX-H700.aarch64-20250517 release. Swap back to
  # pkgs.u-boot-rg28xx once our built-from-source matches.
  handheld.uboot = pkgs.u-boot-rg28xx-rocknix + "/u-boot-sunxi-with-spl.bin";

  # Source-built RG28XX DTB. Our overlay extends ROCKNIX-patched
  # rg35xx-plus.dts (which adds panel/spi-gpio/backlight nodes) and
  # overrides &panel's compatible to the rg28xx-specific firmware blob.
  hardware.deviceTree = {
    enable = true;
    dtbSource = "${pkgs.h700-dtb}";
    name = "allwinner/sun50i-h700-anbernic-rg28xx.dtb";
  };

  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-h700;

  boot.extraModulePackages = [
    # rocknix-joypad's overlay attribute is kernel-pinned to linux-rk3326
    # for R36H; rebuild against linux-h700. (panel-mipi-dpi-spi is now
    # in-tree via ROCKNIX kernel patch 0110.)
    (pkgs.rocknix-joypad.override { kernel = pkgs.linux-h700; })
  ];

  # Panel init blob the kikuchan98 driver loads from /lib/firmware/panels/.
  hardware.firmware = [ pkgs.rg28xx-panel-firmware ];

  boot.initrd.includeDefaultModules = false;
  # Panel driver is in-tree (=y) via ROCKNIX patch 0110 + defconfig
  # CONFIG_DRM_PANEL_MIPI=y, so we don't have to ferry it via initrd
  # modules.

  boot.kernelModules = [
    "g_ether"
    "panfrost"
    "rocknix_singleadc_joypad"
  ];
  boot.kernelParams = [
    "usbcore.autosuspend=-1"
    # fbcon rotation only affects the stage-1/stage-2 console — cage
    # owns the display past that. Kept as a fallback so kernel logs
    # are readable on the panel if cage ever fails to start.
    "fbcon=rotate:3"
  ];

  # Default panfrost; mali-kbase + libmali wiring on H700 is unverified.
  handheld.gpu.specialisation = {
    enable = false;
    picker.enable = false;
  };

  # PortMaster still off until ES is happy.
  handheld.portmaster.enable = false;

  # USB gadget ethernet (same convention as R36H: 10.0.0.2/24).
  # Disable predictable naming so the kernel-assigned `usb0` (from
  # g_ether) sticks — without this, systemd-udev's predictable scheme
  # renames it on H700's musb-hdrc and networking.interfaces.usb0 below
  # never matches anything.
  networking.usePredictableInterfaceNames = false;
  networking.interfaces.usb0 = {
    ipv4.addresses = [
      {
        address = "10.0.0.2";
        prefixLength = 24;
      }
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # sunxi-mmc on H700 doesn't survive an s2idle cycle: every wake hits
  # `fatal err update clk timeout` on mmc1, the driver detaches the card,
  # and the /roms mount goes I/O-error. ROCKNIX disables suspend entirely
  # to dodge it ("Sleep is currently broken, so we'll disable it" — their
  # H700 platform quirk). AmazinAxel ships the same workaround we use
  # here: bounce the automount on resume so the kernel rescans the slot
  # and re-establishes the mount cleanly. Not a root-cause fix; the
  # underlying driver bug remains.
  powerManagement.resumeCommands = ''
    ${lib.getExe' pkgs.systemd "systemctl"} restart roms.automount 2>/dev/null || true
  '';

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

  # Wayland kiosk owns the panel — wlroots does not auto-rotate via DRM
  # panel-orientation, so the transform is set explicitly here and
  # applied by kanshi inside the cage session.
  handheld.compositor.enable = true;
  handheld.compositor.outputTransform = "90";

  # H700 Gamepad — pure-digital pad (no analog sticks per evtest).
  # Vid 0x484b, pid 0x14df, version 0x0100, bustype 0x0019.
  # GUID computed via CRC-16/ARC of "H700 Gamepad" = 0xa2f6 (LE bytes f6a2).
  # Mapping captured from the ES first-boot wizard; mirrors the R36H
  # Nintendo-style convention (a=east, b=south, x=west, y=north).
  systemd.services.handheld-session.environment.SDL_GAMECONTROLLERCONFIG =
    "1900f6a24b480000df14000000010000,H700 Gamepad,platform:Linux,"
    + "a:b1,b:b0,x:b3,y:b2,"
    + "back:b8,start:b9,guide:b10,"
    + "leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,"
    + "leftstick:b11,rightstick:b12,"
    + "dpup:b13,dpdown:b14,dpleft:b15,dpright:b16,";

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
