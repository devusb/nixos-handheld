{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.emulationstation;

  esSystemsCfg = import ./systems.nix { inherit pkgs; inherit retroarchPkg; };
  esInputCfg = import ./input.nix { inherit pkgs; };

  retroarchPkg = cfg.retroarchPackage;

  esSettingsCfg = pkgs.writeText "es_settings.cfg" ''

    <?xml version="1.0"?>
    <bool name="DrawClock" value="false" />
    <bool name="ShowHelpPrompts" value="false" />
    <string name="TransitionStyle" value="instant" />
    <bool name="ScreenSaverControls" value="false" />
    <int name="MaxVRAM" value="80" />
    <bool name="HideWindow" value="true" />
    <string name="ThemeSet" value="gbz35_mod" />
  '';

  esConfigDir = "/var/lib/emulationstation/.emulationstation";
in
{
  options.handheld.emulationstation = {
    enable = lib.mkEnableOption "EmulationStation game browser frontend";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emulationstation-fcamod;
      description = "EmulationStation package to use.";
    };
    retroarchPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.retroarch-handheld.override {
        settings = import ../retroarch/settings.nix;
      };
      description = "RetroArch package used to launch cores.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gamer";
      description = "User account to run EmulationStation as.";
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

    # ES reads es_input.cfg from /etc/emulationstation/ (hardcoded path)
    environment.etc."emulationstation/es_input.cfg".source = esInputCfg;
    environment.etc."emulationstation/themes/gbz35_mod".source = pkgs.es-theme-gbz35-mod;

    # Declarative config in /var/lib/emulationstation/.emulationstation/
    # ES can write gamelists, scraped data, etc. alongside these
    systemd.tmpfiles.settings."10-emulationstation" = {
      "${esConfigDir}" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${esConfigDir}/es_systems.cfg" = {
        "L+" = {
          argument = "${esSystemsCfg}";
        };
      };
      "${esConfigDir}/es_settings.cfg" = {
        "L+" = {
          argument = "${esSettingsCfg}";
        };
      };

      # DraStic state directory — writable by gamer, store data symlinked
      "/var/lib/drastic" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "/var/lib/drastic/game_database.xml" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/game_database.xml"; };
      };
      "/var/lib/drastic/usrcheat.dat" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/usrcheat.dat"; };
      };
      "/var/lib/drastic/drastic_logo_0.raw" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/drastic_logo_0.raw"; };
      };
      "/var/lib/drastic/drastic_logo_1.raw" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/drastic_logo_1.raw"; };
      };
      "/var/lib/drastic/system" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/system"; };
      };
      "/var/lib/drastic/config" = {
        d = { user = cfg.user; group = "users"; mode = "0755"; };
      };
      "/var/lib/drastic/backup" = {
        d = { user = cfg.user; group = "users"; mode = "0755"; };
      };
      "/var/lib/drastic/cheats" = {
        d = { user = cfg.user; group = "users"; mode = "0755"; };
      };
      "/var/lib/drastic/savestates" = {
        d = { user = cfg.user; group = "users"; mode = "0755"; };
      };
      "/var/lib/drastic/profiles" = {
        d = { user = cfg.user; group = "users"; mode = "0755"; };
      };
      "/var/lib/drastic/config/drastic.cfg" = {
        "L+" = { argument = "${pkgs.drastic}/share/drastic/config/drastic.cfg"; };
      };
    };

    # EmulationStation as systemd service — direct DRM/KMS, no compositor
    systemd.services.emulationstation = {
      description = "EmulationStation";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-user-sessions.service"
        "systemd-tmpfiles-setup.service"
      ];
      serviceConfig = {
        User = cfg.user;
        Group = "users";
        Restart = "on-abnormal";
        RestartSec = "2";
        RuntimeDirectory = "emulationstation";
        Environment = [
          "XDG_RUNTIME_DIR=/run/emulationstation"
          "HOME=/home/${cfg.user}"
          "SDL_VIDEO_CURSOR_HIDDEN=1"
        ];
        ExecStart = pkgs.writeShellScript "emulationstation-run" ''
          while true; do
            rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown
            ${lib.getExe cfg.package} --home /var/lib/emulationstation || true
            [ -f /tmp/es-restart ] && continue
            if [ -f /tmp/es-sysrestart ]; then
              rm -f /tmp/es-sysrestart
              /run/wrappers/bin/sudo ${lib.getExe' pkgs.systemd "systemctl"} reboot
              break
            fi
            if [ -f /tmp/es-shutdown ]; then
              rm -f /tmp/es-shutdown
              /run/wrappers/bin/sudo ${lib.getExe' pkgs.systemd "systemctl"} poweroff
              break
            fi
            break
          done
        '';
      };
    };

    environment.variables.SDL_VIDEO_CURSOR_HIDDEN = "1";

    # Allow user to reboot/poweroff via ES menu
    security.sudo.extraRules = [{
      users = [ cfg.user ];
      commands = [
        { command = "${lib.getExe' pkgs.systemd "systemctl"} reboot"; options = [ "NOPASSWD" ]; }
        { command = "${lib.getExe' pkgs.systemd "systemctl"} poweroff"; options = [ "NOPASSWD" ]; }
      ];
    }];

    environment.systemPackages = [
      cfg.package
      retroarchPkg
    ];
  };
}
