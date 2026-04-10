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

  environment.systemPackages = with pkgs; [
    alsa-utils
  ];

  powerManagement.cpuFreqGovernor = "ondemand";

  # Minimize SD card writes
  boot.tmp.useTmpfs = true;
  # services.journald.extraConfig = "Storage=volatile"; # disabled for debugging
  boot.kernel.sysctl."vm.swappiness" = 0;
}
