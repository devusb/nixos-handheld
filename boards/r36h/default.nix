# R36H board definition — RK3326-based handheld gaming device
# R36H is electrically identical to R36S (landscape shell variant)
{ config, lib, pkgs, ... }:

let
  retroarchPkg = pkgs.retroarch.withCores (cores: with cores; [
    mgba
  ]);
in
{
  nixpkgs.overlays = [
    (final: prev: {
      retroarch-bare = (prev.retroarch-bare.override {
        withWayland = false;
      }).overrideAttrs (old: {
        buildInputs = final.lib.lists.subtractLists [
          final.ffmpeg_7
          final.pipewire
          final.qt6.qtbase
          final.wrapGAppsHook3
        ] old.buildInputs;
        nativeBuildInputs = final.lib.remove
          final.qt6.wrapQtAppsHook
          old.nativeBuildInputs;
        configureFlags = (old.configureFlags or [ ]) ++ [
          "--disable-pipewire"
          "--disable-pulse"
          "--disable-qt"
          "--disable-wayland"
          "--disable-x11"
          "--disable-xinerama"
          "--disable-xrandr"
        ];
      });
    })
  ];
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

  # Kernel modules
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.kernelModules = [
    "panfrost"
  ];

  # Firmware
  hardware.enableRedistributableFirmware = true;

  # Auto-login on tty1 (fallback if RetroArch fails)
  services.getty.autologinUser = "root";

  # Gamer user — runs RetroArch
  users.users.gamer = {
    isNormalUser = true;
    extraGroups = [ "input" "video" "audio" ];
  };

  # RetroArch as systemd service — direct DRM/KMS, no compositor
  systemd.services.retroarch = {
    description = "RetroArch";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    serviceConfig = {
      User = "gamer";
      Group = "users";
      Restart = "on-failure";
      RestartSec = "2";
      RuntimeDirectory = "retroarch";
      Environment = [
        "XDG_RUNTIME_DIR=/run/retroarch"
        "HOME=/home/gamer"
      ];
      ExecStart = pkgs.writeShellScript "start-retroarch" ''
        # Bootstrap config on first boot
        if [ ! -d ~/.config/retroarch ]; then
          mkdir -p ~/.config
          cp -r ${../../files/retroarch} ~/.config/retroarch
          chmod u+w -R ~/.config/retroarch
        fi
        # Always update autoconfig
        mkdir -p ~/.config/retroarch/autoconfig/udev
        cp -f ${../../files/retroarch}/autoconfig/udev/*.cfg ~/.config/retroarch/autoconfig/udev/
        exec ${retroarchPkg}/bin/retroarch --verbose 2>&1
      '';
    };
  };

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

  # GPU
  hardware.graphics.enable = true;
  documentation.enable = false;

  # Debug tools
  environment.systemPackages = with pkgs; [
    retroarchPkg
    htop
    usbutils
    evtest
    lsof
    pciutils
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  # Diagnostics service — dumps hardware info on every boot
  systemd.services.hardware-diagnostics = {
    description = "Dump hardware diagnostics";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ util-linux coreutils iproute2 systemd kmod alsa-utils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "hw-diag" ''
        mkdir -p /var/log
        {
          echo "=== NixOS Hardware Diagnostics ==="
          echo "Date: $(date)"
          echo ""

          echo "=== uname ==="
          uname -a
          echo ""

          echo "=== Input devices ==="
          cat /proc/bus/input/devices 2>/dev/null
          echo ""

          echo "=== Audio: aplay ==="
          aplay -l 2>/dev/null || echo "aplay not available"
          echo ""

          echo "=== GPU: DRI devices ==="
          ls -la /dev/dri/ 2>/dev/null || echo "no /dev/dri"
          echo ""

          echo "=== GPU: panfrost ==="
          dmesg | grep -i "panfrost\|gpu\|mali\|drm" 2>/dev/null
          echo ""

          echo "=== Loaded modules ==="
          lsmod 2>/dev/null
          echo ""

          echo "=== systemctl failed ==="
          systemctl --failed --no-pager 2>/dev/null
          echo ""

          echo "=== RetroArch service ==="
          systemctl status retroarch --no-pager 2>/dev/null
          echo ""

          echo "=== Mount points ==="
          mount 2>/dev/null
          echo ""

          echo "=== Block devices ==="
          lsblk 2>/dev/null
          echo ""

          echo "=== full dmesg ==="
          dmesg

        } > /var/log/diagnostics.txt 2>&1
      '';
    };
  };

  system.stateVersion = "25.05";
}
