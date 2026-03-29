{ config, lib, pkgs, ... }:

{
  # GPU — Panfrost for Mali-G31
  hardware.graphics.enable = true;

  # Allow video group to control backlight
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness"
  '';

  # Power button = suspend
  services.logind.settings.Login.HandlePowerKey = "suspend";

  # Set safe default volume on boot (50%) — protects speakers
  systemd.services.alsa-init = {
    description = "Set default ALSA volume";
    after = [ "sound.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.alsa-utils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "alsa-init" ''
        amixer -c 0 sset 'Master' 50% 2>/dev/null || true
        amixer -c 0 sset 'Headphone' 50% 2>/dev/null || true
        amixer -c 0 sset 'Speaker' 50% 2>/dev/null || true
        amixer -c 0 sset 'Playback' 50% 2>/dev/null || true
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  # Minimize SD card writes
  boot.tmp.useTmpfs = true;
  services.journald.extraConfig = "Storage=volatile";
  boot.kernel.sysctl."vm.swappiness" = 0;
}
