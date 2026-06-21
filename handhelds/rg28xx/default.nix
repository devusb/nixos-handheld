# RG28XX board definition — Allwinner H700 horizontal handheld.
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

  # Prebuilt SPL+U-Boot blob from ROCKNIX.
  handheld.uboot = pkgs.u-boot-rg28xx-rocknix + "/u-boot-sunxi-with-spl.bin";

  hardware.deviceTree = {
    enable = true;
    dtbSource = "${pkgs.h700-dtb}";
    name = "allwinner/sun50i-h700-anbernic-rg28xx.dtb";
  };

  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-h700;

  boot.extraModulePackages = [
    # rocknix-joypad's default overlay attribute pins a different
    # kernel; rebuild against ours.
    (pkgs.rocknix-joypad.override { kernel = pkgs.linux-h700; })
  ];

  # Panel init blob the kikuchan98 driver loads from /lib/firmware/panels/.
  hardware.firmware = [ pkgs.rg28xx-panel-firmware ];

  boot.initrd.includeDefaultModules = false;

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

  # USB gadget ethernet — 10.0.0.2/24. Disable predictable naming so
  # the kernel-assigned `usb0` (from g_ether) sticks; otherwise
  # systemd-udev's predictable scheme renames it on H700's musb-hdrc
  # and networking.interfaces.usb0 below never matches anything.
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

  # mmc1 wedges across some s2idle resumes. Poll for mmcblk1 to
  # disappear (kernel takes ~3s to give up), then rebind sunxi-mmc
  # to re-run the full probe path the runtime_resume call skips.
  # See docs/sunxi-mmc-s2idle-patch.md.
  powerManagement.resumeCommands = ''
    for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 12); do
      [ -b /dev/mmcblk1 ] || break
      sleep 0.5
    done
    if [ ! -b /dev/mmcblk1 ]; then
      echo 4022000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind 2>/dev/null || true
      echo 4022000.mmc > /sys/bus/platform/drivers/sunxi-mmc/bind 2>/dev/null || true
      for _ in $(${lib.getExe' pkgs.coreutils "seq"} 1 20); do
        [ -b /dev/mmcblk1 ] && break
        sleep 0.2
      done
    fi
    ${lib.getExe' pkgs.systemd "systemctl"} restart roms.automount 2>/dev/null || true
  '';

  # Second SD card for ROMs.
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

  # Prebuilt ports via the bwrap FHS sandbox — runs under panfrost.
  handheld.portmaster.enable = true;

  # Wayland kiosk owns the panel — wlroots does not auto-rotate via DRM
  # panel-orientation, so the transform is set explicitly here and
  # applied by kanshi inside the cage session.
  handheld.compositor.enable = true;
  handheld.compositor.outputTransform = "90";

  # M button (id 10) opens the RA menu.
  handheld.emulationstation.retroarchSettings = lib.mkDefault {
    input_menu_toggle_btn = lib.mkForce "10";
    input_menu_toggle_gamepad_combo = lib.mkForce "0";
  };

  # DraStic saves + states on the ROMs card so they survive reflash.
  handheld.emulationstation.drastic.persistDirectory = "/roms/saves/drastic";

  # H700 Gamepad — pure-digital pad (no analog sticks).
  # Vid 0x484b, pid 0x14df, version 0x0100, bustype 0x0019.
  # GUID computed via CRC-16/ARC of "H700 Gamepad" = 0xa2f6 (LE bytes f6a2).
  # Nintendo-style face buttons: a=east, b=south, x=west, y=north.
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
