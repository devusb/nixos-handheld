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
    "g_ether"
  ];

  # WiFi and Bluetooth firmware
  hardware.enableRedistributableFirmware = true;

  # Auto-login on tty1 (no keyboard available, gamepad only)
  services.getty.autologinUser = "root";

  # USB gadget ethernet — SSH over USB OTG
  # usb0 only exists when g_ether binds and a host is connected
  networking.interfaces.usb0 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "10.0.0.1";
      prefixLength = 24;
    }];
  };
  systemd.network.wait-online.anyInterface = true;

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
    lsof
    pciutils
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  # Diagnostics service — dumps hardware info to boot partition on every boot
  systemd.services.hardware-diagnostics = {
    description = "Dump hardware diagnostics to boot partition";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
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

          echo "=== USB: dwc2 and role switch ==="
          dmesg | grep -i "dwc2\|usb\|role\|otg\|gadget\|hid\|hub" 2>/dev/null
          echo ""

          echo "=== USB: lsusb ==="
          lsusb 2>/dev/null || echo "lsusb not available"
          echo ""

          echo "=== USB: sysfs role ==="
          for f in /sys/class/usb_role/*/role; do echo "$f: $(cat $f 2>/dev/null)"; done
          echo ""

          echo "=== USB: sysfs dwc2 ==="
          cat /sys/bus/platform/drivers/dwc2/ff300000.usb/mode 2>/dev/null || echo "no mode file"
          echo ""

          echo "=== Input devices ==="
          cat /proc/bus/input/devices 2>/dev/null
          echo ""

          echo "=== evtest list ==="
          evtest --list-devices 2>/dev/null || ls /dev/input/event* 2>/dev/null
          echo ""

          echo "=== Audio: aplay ==="
          aplay -l 2>/dev/null || echo "aplay not available"
          echo ""

          echo "=== Audio: amixer ==="
          amixer 2>/dev/null | head -30 || echo "amixer not available"
          echo ""

          echo "=== GPU: DRI devices ==="
          ls -la /dev/dri/ 2>/dev/null || echo "no /dev/dri"
          echo ""

          echo "=== GPU: panfrost ==="
          dmesg | grep -i "panfrost\|gpu\|mali\|drm" 2>/dev/null
          echo ""

          echo "=== Network interfaces ==="
          ip link 2>/dev/null
          echo ""

          echo "=== WiFi ==="
          dmesg | grep -i "wifi\|wlan\|rtl8723\|rtw\|80211" 2>/dev/null
          echo ""

          echo "=== Loaded modules ==="
          lsmod 2>/dev/null
          echo ""

          echo "=== systemctl failed ==="
          systemctl --failed --no-pager 2>/dev/null
          echo ""

          echo "=== systemctl status ==="
          systemctl status --no-pager 2>/dev/null
          echo ""

          echo "=== kernel config checks ==="
          for opt in USB_ROLE_SWITCH USB_DWC2_DUAL_ROLE USB_HID HID_GENERIC USB_ETH; do
            zgrep "CONFIG_$opt" /proc/config.gz 2>/dev/null || echo "CONFIG_$opt: /proc/config.gz not available"
          done
          echo ""

          echo "=== full dmesg ==="
          dmesg

        } > /var/log/diagnostics.txt 2>&1
      '';
    };
  };

  system.stateVersion = "25.05";
}
