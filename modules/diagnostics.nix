{
  config,
  lib,
  pkgs,
  ...
}:

{
  systemd.services.hardware-diagnostics = {
    description = "Dump hardware diagnostics";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      util-linux
      coreutils
      iproute2
      systemd
      kmod
      alsa-utils
    ];
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

          echo "=== Backlight ==="
          ls -la /sys/class/backlight/backlight/brightness 2>/dev/null
          cat /sys/class/backlight/backlight/brightness 2>/dev/null
          cat /sys/class/backlight/backlight/max_brightness 2>/dev/null
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
}
