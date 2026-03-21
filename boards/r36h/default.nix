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

  # R36H uses gameconsole-r36s DTB from ohjhas kernel
  handheld.kernelDTB = "rk3326-gameconsole-r36s.dtb";
  handheld.bootIni = ./boot.ini;

  # U-Boot needs its own DTB (ArkOS BSP) for display init before loading Linux
  handheld.ubootDTB = /home/mhelton/misc/r36_boot/BOOT/gameconsole-r36s.dtb;

  # No bootloader — we use U-Boot + boot.ini
  boot.loader.grub.enable = false;

  # Custom kernel
  boot.kernelPackages = let
    kernel = pkgs.callPackage ../../pkgs/kernel-rk3326 { };
  in pkgs.linuxPackagesFor kernel;

  # Skip NixOS kernel config assertions
  system.requiredKernelConfig = lib.mkForce [];

  # Kernel modules — override NixOS defaults which assume x86 hardware
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.kernelModules = [
    "rtl8723bs"
    "panfrost"
    "dwc2"
    "g_ether"
  ];

  # --- Debug logging ---
  # Write debug info to boot partition (FAT32) so we can read it
  # even without display or network
  boot.initrd.preFailCommands = ''
    # If we get here, something failed in stage-1
    echo "=== INITRD FAIL ===" > /mnt-root-debug
    echo "Date: $(date)" >> /mnt-root-debug
    echo "" >> /mnt-root-debug
    echo "=== dmesg ===" >> /mnt-root-debug
    dmesg >> /mnt-root-debug 2>&1
    echo "" >> /mnt-root-debug
    echo "=== mount ===" >> /mnt-root-debug
    mount >> /mnt-root-debug 2>&1
    echo "" >> /mnt-root-debug
    echo "=== blkid ===" >> /mnt-root-debug
    blkid >> /mnt-root-debug 2>&1
    echo "" >> /mnt-root-debug
    echo "=== ls /dev/mmcblk* ===" >> /mnt-root-debug
    ls -la /dev/mmcblk* >> /mnt-root-debug 2>&1
    echo "" >> /mnt-root-debug
    echo "=== ls /dev/disk/by-label ===" >> /mnt-root-debug
    ls -la /dev/disk/by-label/ >> /mnt-root-debug 2>&1

    # Try to mount boot partition and write the log there
    mkdir -p /tmp/bootdebug
    mount /dev/mmcblk0p1 /tmp/bootdebug 2>/dev/null || mount /dev/mmcblk1p1 /tmp/bootdebug 2>/dev/null
    cp /mnt-root-debug /tmp/bootdebug/debug.log 2>/dev/null
    umount /tmp/bootdebug 2>/dev/null
  '';

  # Also log on successful boot (stage-2)
  boot.postBootCommands = ''
    if [ ! -f /var/log/first-boot-done ]; then
      mkdir -p /tmp/bootdebug
      mount /dev/disk/by-label/FIRMWARE /tmp/bootdebug 2>/dev/null || true
      {
        echo "=== STAGE 2 SUCCESS ==="
        echo "Date: $(date)"
        echo ""
        echo "=== uname ==="
        uname -a
        echo ""
        echo "=== dmesg (last 100) ==="
        dmesg | tail -100
        echo ""
        echo "=== mount ==="
        mount
        echo ""
        echo "=== systemctl status ==="
        systemctl status --no-pager 2>&1 || true
      } > /tmp/bootdebug/debug.log 2>&1
      umount /tmp/bootdebug 2>/dev/null || true
      touch /var/log/first-boot-done
    fi
  '';

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
  documentation.enable = false;

  environment.systemPackages = with pkgs; [
    htop
    usbutils
    evtest
  ];

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "25.05";
}
