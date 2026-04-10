{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.retroarch;

  retroarchPkg = cfg.package.wrapper {
    cores = cfg.cores;
    settings = cfg.settings;
  };
in
{
  options.handheld.retroarch = {
    enable = lib.mkEnableOption "RetroArch kiosk mode (boots directly to RetroArch)";
    package = lib.mkOption {
      type = lib.types.package;
      # ODROIDGO2 variant — in kiosk mode RetroArch owns the backlight
      default = pkgs.retroarch-bare-odroidgo2;
      description = "Base RetroArch package (before wrapper).";
    };
    cores = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs.libretro; [
        mgba
        gambatte
        beetle-ngp
        snes9x
        genesis-plus-gx
        fceumm
        pcsx-rearmed
        fbneo
        melonds
        dosbox-pure
        mupen64plus
        parallel-n64
        opera
        mame2003-plus
        scummvm
        picodrive
        ppsspp
        flycast
      ];
      description = "List of libretro cores to include.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "RetroArch settings attrset for --appendconfig.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gamer";
      description = "User account to run RetroArch as.";
    };
  };

  config = lib.mkMerge [
    # Settings default is applied unconditionally so it can be read even
    # when kiosk RA is disabled (e.g. for eval-time verification).
    {
      handheld.retroarch.settings = lib.mkDefault (
        import ./settings.nix { inherit (config.handheld) romsDirectory; }
      );
    }
    (lib.mkIf cfg.enable {
      users.users.${cfg.user} = {
        isNormalUser = true;
        uid = 1000;
        extraGroups = [
          "input"
          "video"
          "audio"
        ];
      };

      systemd.services.retroarch = {
        description = "RetroArch";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-user-sessions.service" ];
        restartIfChanged = false;
        preStart = "${lib.getExe' pkgs.coreutils "ln"} -sfn ${retroarchPkg}/lib/retroarch/cores /run/retroarch/cores";
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
          ExecStart = "${lib.getExe retroarchPkg} --verbose";
          ExecStopPost = "+${lib.getExe' pkgs.systemd "systemctl"} poweroff";
        };
      };

      environment.systemPackages = [ retroarchPkg ];
    })
  ];
}
