{
  config,
  lib,
  pkgs,
  ...
}:

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

  # Set hardware volume on boot — RetroArch controls volume in software
  # via its own audio_volume setting (volume buttons adjust RetroArch's
  # internal dB, not the ALSA mixer). 80% hardware (-19dB) gives
  # RetroArch a usable 0-100% software range.
  systemd.services.alsa-init = {
    description = "Set default ALSA volume";
    after = [ "sound.target" "sys-devices-platform-rk817\\x2dsound-sound-card0-controlC0.device" ];
    requires = [ "sys-devices-platform-rk817\\x2dsound-sound-card0-controlC0.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.alsa-utils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "alsa-init" ''
        amixer -c 0 sset 'Master' 80% 2>/dev/null || true
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  # Minimize SD card writes
  boot.tmp.useTmpfs = true;
  # services.journald.extraConfig = "Storage=volatile"; # disabled for debugging
  boot.kernel.sysctl."vm.swappiness" = 0;
}
