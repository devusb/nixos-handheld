{
  config,
  lib,
  pkgs,
  ...
}:

let
  retroarchSettings = import ./settings.nix;
  retroarchPkg = pkgs.retroarch-handheld.override {
    settings = retroarchSettings;
  };
in
{
  # Gamer user — runs RetroArch
  users.users.gamer = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "input"
      "video"
      "audio"
    ];
  };

  # RetroArch as systemd service — direct DRM/KMS, no compositor
  systemd.services.retroarch = {
    description = "RetroArch";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    restartIfChanged = false;
    preStart = "${lib.getExe' pkgs.coreutils "ln"} -sfn ${retroarchPkg}/lib/retroarch/cores /run/retroarch/cores";
    serviceConfig = {
      User = "gamer";
      Group = "users";
      Restart = "on-abnormal";
      RestartSec = "2";
      RuntimeDirectory = "retroarch";
      Environment = [
        "XDG_RUNTIME_DIR=/run/retroarch"
        "HOME=/home/gamer"
      ];
      ExecStart = "${lib.getExe retroarchPkg} --verbose";
      # Clean quit (exit 0) triggers poweroff — this is intentional for kiosk mode.
      # Crashes (signals) trigger restart via on-abnormal.
      # To debug without shutdown: systemctl mask retroarch-poweroff.service
      ExecStopPost = "+${lib.getExe' pkgs.systemd "systemctl"} poweroff";
    };
  };

  environment.systemPackages = [ retroarchPkg ];
}
