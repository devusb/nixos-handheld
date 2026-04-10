{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.emulationstation;

  retroarchPkg = cfg.retroarchPackage.wrapper {
    cores = cfg.retroarchCores;
    settings = cfg.retroarchSettings;
  };

  esSystemsCfg = import ./systems.nix {
    inherit pkgs;
    inherit retroarchPkg;
    inherit (config.handheld) romsDirectory;
    drasticEnabled = cfg.drastic.enable;
    drasticPackage = cfg.drastic.package;
    drasticStateDirectory = cfg.drastic.stateDirectory;
  };
  esInputCfg = cfg.inputConfigFile;

  esSettingsCfg = pkgs.writeText "es_settings.cfg" ''

    <?xml version="1.0"?>
    <bool name="DrawClock" value="false" />
    <bool name="ShowHelpPrompts" value="false" />
    <string name="TransitionStyle" value="instant" />
    <bool name="ScreenSaverControls" value="false" />
    <int name="MaxVRAM" value="80" />
    <bool name="HideWindow" value="true" />
    <string name="ThemeSet" value="${cfg.theme.name}" />
  '';

in
{
  options.handheld.emulationstation = {
    enable = lib.mkEnableOption "EmulationStation game browser frontend";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emulationstation-fcamod;
      description = "EmulationStation package to use.";
    };
    inputConfigFile = lib.mkOption {
      type = lib.types.path;
      description = "EmulationStation es_input.cfg file (gamepad button mappings).";
    };
    drastic.enable = lib.mkEnableOption "DraStic Nintendo DS emulator support" // {
      default = true;
    };
    drastic.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.drastic;
      description = "DraStic package.";
    };
    drastic.stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/drastic";
      description = ''
        DraStic working directory. Config, saves, savestates, cheats, and
        profiles live here; symlinks to read-only data from the package
        (game database, BIOS, logos) are also placed here.
      '';
    };
    drastic.configFile = lib.mkOption {
      type = lib.types.path;
      description = "DraStic configuration file (button mappings and emulation settings).";
    };
    configDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/emulationstation/.emulationstation";
      description = ''
        Directory where EmulationStation reads es_systems.cfg,
        es_settings.cfg, es_input.cfg, gamelists, and scraped data.
        Must be writable by handheld.emulationstation.user.
      '';
    };
    theme.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.es-theme-gbz35-mod;
      description = "EmulationStation theme package.";
    };
    theme.name = lib.mkOption {
      type = lib.types.str;
      default = cfg.theme.package.passthru.themeName;
      defaultText = lib.literalExpression "cfg.theme.package.passthru.themeName";
      description = ''
        Theme set name. Defaults to the theme package's `passthru.themeName`;
        override if bringing a theme package without one.
      '';
    };
    retroarchPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.retroarch-bare;
      description = "Base RetroArch package (before wrapper). The module composes the final wrapper with cores and settings.";
    };
    retroarchCores = lib.mkOption {
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
    retroarchSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "RetroArch settings attrset for --appendconfig.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "gamer";
      description = "User account to run EmulationStation as.";
    };
  };

  config = lib.mkIf cfg.enable {
    handheld.emulationstation.retroarchSettings = lib.mkDefault (
      (import ../retroarch/settings.nix { inherit (config.handheld) romsDirectory; }) // {
        # Volume handled by triggerhappy at the system level
        input_volume_up = "nul";
        input_volume_down = "nul";
        audio_volume = "0.0";
      }
    );

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
    environment.etc."emulationstation/themes/${cfg.theme.name}".source = cfg.theme.package;

    # Declarative config in /var/lib/emulationstation/.emulationstation/
    # ES can write gamelists, scraped data, etc. alongside these
    systemd.tmpfiles.settings."10-emulationstation" = {
      "${cfg.configDirectory}" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.configDirectory}/es_systems.cfg" = {
        "L+" = {
          argument = "${esSystemsCfg}";
        };
      };
      "${cfg.configDirectory}/es_settings.cfg" = {
        "L+" = {
          argument = "${esSettingsCfg}";
        };
      };
    };

    # Read-only data from the package is symlinked into the writable state
    # dir so DraStic finds it in cwd at runtime.
    systemd.tmpfiles.settings."11-emulationstation-drastic" = lib.mkIf cfg.drastic.enable {
      "${cfg.drastic.stateDirectory}" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/game_database.xml" = {
        "L+" = {
          argument = "${cfg.drastic.package}/share/drastic/game_database.xml";
        };
      };
      "${cfg.drastic.stateDirectory}/usrcheat.dat" = {
        "L+" = {
          argument = "${cfg.drastic.package}/share/drastic/usrcheat.dat";
        };
      };
      "${cfg.drastic.stateDirectory}/drastic_logo_0.raw" = {
        "L+" = {
          argument = "${cfg.drastic.package}/share/drastic/drastic_logo_0.raw";
        };
      };
      "${cfg.drastic.stateDirectory}/drastic_logo_1.raw" = {
        "L+" = {
          argument = "${cfg.drastic.package}/share/drastic/drastic_logo_1.raw";
        };
      };
      "${cfg.drastic.stateDirectory}/system" = {
        "L+" = {
          argument = "${cfg.drastic.package}/share/drastic/system";
        };
      };
      "${cfg.drastic.stateDirectory}/config" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/backup" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/cheats" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/savestates" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/profiles" = {
        d = {
          user = cfg.user;
          group = "users";
          mode = "0755";
        };
      };
      "${cfg.drastic.stateDirectory}/config/drastic.cfg" = {
        "L+" = {
          argument = "${cfg.drastic.configFile}";
        };
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
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "${lib.getExe' pkgs.systemd "systemctl"} reboot";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${lib.getExe' pkgs.systemd "systemctl"} poweroff";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Volume buttons — gpio-keys-vol on /dev/input/event2
    services.triggerhappy = {
      enable = true;
      user = "root";
      bindings = [
        {
          keys = [ "VOLUMEUP" ];
          event = "press";
          cmd = "${lib.getExe' pkgs.alsa-utils "amixer"} -c 0 sset Master 5%+";
        }
        {
          keys = [ "VOLUMEDOWN" ];
          event = "press";
          cmd = "${lib.getExe' pkgs.alsa-utils "amixer"} -c 0 sset Master 5%-";
        }
      ];
    };

    environment.systemPackages = [
      cfg.package
      retroarchPkg
    ];
  };
}
