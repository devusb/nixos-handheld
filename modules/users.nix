# Kiosk account for handheld sessions. Declared once here so any
# module that needs the user (ES, RetroArch, cage compositor, the
# /roms mount, …) can reference it without each one re-declaring its
# own users.users.${cfg.user} block. The baseline groups cover what
# every handheld needs; per-device extras append via
# handheld.user.extraGroups.
{
  config,
  lib,
  ...
}:
let
  cfg = config.handheld.user;
in
{
  options.handheld.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "gamer";
      description = "Account that owns the handheld kiosk session.";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID for the kiosk account.";
    };
    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional groups for the kiosk account, on top of the
        baseline (input, video, audio, pipewire).
      '';
    };
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      uid = cfg.uid;
      extraGroups = [
        "input"
        "video"
        "audio"
        "pipewire"
      ] ++ cfg.extraGroups;
    };
  };
}
