{ config, lib, pkgs, ... }:

let
  retroarchSettings = import ./settings.nix;
  retroarchPkg = pkgs.retroarch-handheld.override {
    settings = retroarchSettings;
  };
in
{
  # No virtual consoles — RetroArch owns the display
  console.enable = false;

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
      Restart = "on-abnormal";
      RestartSec = "2";
      RuntimeDirectory = "retroarch";
      Environment = [
        "XDG_RUNTIME_DIR=/run/retroarch"
        "HOME=/home/gamer"
      ];
      ExecStart = "${lib.getExe retroarchPkg} --verbose";
      ExecStopPost = "+${lib.getExe' pkgs.systemd "systemctl"} poweroff";
    };
  };

  environment.systemPackages = [ retroarchPkg ];
}
