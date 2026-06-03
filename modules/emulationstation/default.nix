{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.emulationstation;

  romsDir = config.handheld.romsDirectory;

  systemType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        fullname = lib.mkOption {
          type = lib.types.str;
          description = "Display name of the system (shown in ES).";
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "${romsDir}/${name}";
          defaultText = lib.literalExpression ''"''${config.handheld.romsDirectory}/<system-name>"'';
          description = "ROM directory for this system.";
        };
        extensions = lib.mkOption {
          type = lib.types.str;
          description = ''Space-separated extension list, e.g. ".gb .GB .zip".'';
        };
        platform = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Scraper platform tag.";
        };
        theme = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Theme entry name.";
        };
        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Full shell command for the system. If null, a default RetroArch
            command is generated from retroarchCore. The command receives
            %ROM% which ES substitutes at launch time.
          '';
        };
        retroarchCore = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            libretro core package for this system, or null for non-RetroArch
            systems (like nds via DraStic). When non-null, this core is
            automatically included in the ES-composed RetroArch wrapper's
            cores list.
          '';
        };
      };
    }
  );

  # nixpkgs libretro packages expose passthru.core (hyphen form); RetroArch
  # expects the .so basename with underscores. e.g. libretro.beetle-ngp has
  # passthru.core = "mednafen-ngp" → mednafen_ngp_libretro.so.
  coreFilename = pkg: (lib.replaceStrings [ "-" ] [ "_" ] pkg.passthru.core) + "_libretro.so";

  mkRetroArchCommand =
    core:
    "${retroarchPkg}/bin/retroarch -L ${retroarchPkg}/lib/retroarch/cores/${coreFilename core} %ROM%";

  defaultSystems = import ./systems.nix {
    inherit lib pkgs;
    drasticEnabled = cfg.drastic.enable;
    drasticPackage = cfg.drastic.package;
    drasticStateDirectory = cfg.drastic.stateDirectory;
  };

  activeSystems = lib.filterAttrs (_: v: v != null) cfg.systems;

  derivedCores = lib.unique (
    lib.filter (c: c != null) (lib.mapAttrsToList (_: sys: sys.retroarchCore) activeSystems)
  );

  retroarchPkg = cfg.retroarchPackage.wrapper {
    cores = derivedCores;
    settings = cfg.retroarchSettings;
  };

  renderCommand =
    sys:
    if sys.command != null then
      sys.command
    else if sys.retroarchCore != null then
      mkRetroArchCommand sys.retroarchCore
    else
      throw "EmulationStation system has neither command nor retroarchCore set";

  systemToXml = name: sys: ''
    <system>
      <name>${name}</name>
      <fullname>${sys.fullname}</fullname>
      <path>${sys.path}</path>
      <extension>${sys.extensions}</extension>
      <command>${renderCommand sys}</command>
      <platform>${sys.platform}</platform>
      <theme>${sys.theme}</theme>
    </system>'';

  esSystemsCfg = pkgs.writeText "es_systems.cfg" ''
    <?xml version="1.0"?>
    <systemList>
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList systemToXml activeSystems)}
    </systemList>
  '';

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
    systems = lib.mkOption {
      type = lib.types.attrsOf (lib.types.nullOr systemType);
      description = ''
        EmulationStation systems, keyed by short name. Overrides the
        defaults in modules/emulationstation/systems.nix entirely.
        The RetroArch wrapper's cores list is derived from each
        entry's retroarchCore.
      '';
      example = lib.literalExpression ''
        {
          snes = {
            fullname = "Super Nintendo";
            extensions = ".smc .sfc .SMC .SFC .zip .ZIP .7z";
            retroarchCore = pkgs.libretro.snes9x;
          };
          dreamcast = {
            fullname = "Sega Dreamcast";
            extensions = ".chd .cdi .gdi";
            retroarchCore = pkgs.libretro.flycast2021;
          };
        }
      '';
    };
    retroarchSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "RetroArch settings attrset for --appendconfig.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = config.handheld.user.name;
      description = "User account to run EmulationStation as.";
    };
    execScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The shell script that launches EmulationStation with the right env,
        restart-loop semantics, and reboot/shutdown handlers. Exposed so
        external services (e.g. handheld-session under cage) can wrap it
        instead of duplicating the launcher logic.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      esExecScript = pkgs.writeShellScript "emulationstation-run" ''
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
    in
    {
    handheld.emulationstation.execScript = esExecScript;

    handheld.emulationstation.systems = lib.mkDefault defaultSystems;

    handheld.emulationstation.retroarchSettings = lib.mkDefault (
      (import ../retroarch/settings.nix { inherit (config.handheld) romsDirectory; })
      // {
        # Volume handled by triggerhappy at the system level
        input_volume_up = "nul";
        input_volume_down = "nul";
        audio_volume = "0.0";
      }
    );

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

    # EmulationStation as systemd service — direct DRM/KMS, no compositor.
    # When handheld.compositor.enable is true, cage owns the display session
    # and runs the same execScript itself; we drop this unit to avoid two
    # things racing for /dev/tty1 and DRM master.
    systemd.services.emulationstation = lib.mkIf (!config.handheld.compositor.enable) {
      description = "EmulationStation";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-user-sessions.service"
        "systemd-tmpfiles-setup.service"
        "pipewire.service"
        "wireplumber.service"
      ];
      requires = [
        "pipewire.service"
        "wireplumber.service"
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
        ExecStart = esExecScript;
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
          cmd = "${lib.getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        }
        {
          keys = [ "VOLUMEDOWN" ];
          event = "press";
          cmd = "${lib.getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        }
      ];
    };

    environment.systemPackages = [
      cfg.package
      retroarchPkg
    ];
    }
  );
}
