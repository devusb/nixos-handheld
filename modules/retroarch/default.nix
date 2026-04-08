{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.retroarch;
in
{
  options.handheld.retroarch = {
    enable = lib.mkEnableOption "RetroArch kiosk mode (boots directly to RetroArch)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.retroarch-handheld.override {
        settings = import ./settings.nix;
      };
      description = "RetroArch package to use.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gamer";
      description = "User account to run RetroArch as.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
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
      preStart = "${lib.getExe' pkgs.coreutils "ln"} -sfn ${cfg.package}/lib/retroarch/cores /run/retroarch/cores";
      serviceConfig = {
        User = cfg.user;
        Group = "users";
        Restart = "on-abnormal";
        RestartSec = "2";
        RuntimeDirectory = "retroarch";
        Environment = [
          "XDG_RUNTIME_DIR=/run/retroarch"
          "HOME=/home/${cfg.user}"
        ];
        ExecStart = "${lib.getExe cfg.package} --verbose";
        ExecStopPost = "+${lib.getExe' pkgs.systemd "systemctl"} poweroff";
      };
    };

    environment.systemPackages = [ cfg.package ];
  };
}
