# Wayland kiosk display session via cage. Owns the systemd service that
# runs cage with the chosen client (currently EmulationStation). cage's
# wlroots takes over the panel; kanshi (started inside the cage session)
# applies the configured transform so every Wayland client renders
# correctly without per-app rotation patches.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.compositor;

  # Kanshi reads this and applies the panel transform once cage's
  # Wayland socket is up. Declarative output config means the transform
  # value lives next to the option in this module, not buried in a
  # shell script. `output *` matches the single connector (DSI-1 on
  # RG28XX) without hardcoding the connector name.
  kanshiConfig = pkgs.writeText "kanshi.conf" ''
    profile {
        output * transform ${cfg.outputTransform}
    }
  '';

  # Cage's child. Starts kanshi in the background to set the transform,
  # waits 500ms so kanshi can actually apply it before child apps query
  # the output (RA in particular caches the output dimensions at first
  # query and won't re-read after rotation lands), then execs the ES
  # launcher in the foreground. When ES exits, the wrapper exits, cage
  # exits, kanshi gets reaped.
  sessionScript = pkgs.writeShellScript "handheld-session-launcher" ''
    ${lib.getExe cfg.kanshiPackage} -c ${kanshiConfig} &
    sleep 0.5
    exec ${config.handheld.emulationstation.execScript}
  '';

  # RA's set_fullscreen deadlocks under cage; pin a viewport instead.
  # glcore presents cleanly; other drivers fight cage for DRM.
  cageRetroarchOverrides = {
    video_driver = lib.mkForce "glcore";
    video_fullscreen = "false";
    video_allow_rotate = "true";
    video_force_aspect = "true";
    aspect_ratio_index = "23";
    custom_viewport_width = "640";
    custom_viewport_height = "480";
    custom_viewport_x = "0";
    custom_viewport_y = "0";
  };
in
{
  options.handheld.compositor = {
    enable = lib.mkEnableOption "cage Wayland kiosk as the display session";

    outputTransform = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "90"
        "180"
        "270"
        "flipped"
        "flipped-90"
        "flipped-180"
        "flipped-270"
      ];
      default = "normal";
      description = ''
        Output transform applied by kanshi to the panel. Use "90" for a
        panel mounted rotated 90° clockwise (RG28XX). wlroots does NOT
        auto-honor the DRM panel-orientation property, so this must be
        set explicitly. Values mirror the kanshi / wlr-output-management
        vocabulary.
      '';
    };

    package = lib.mkPackageOption pkgs "cage" { };

    kanshiPackage = lib.mkPackageOption pkgs "kanshi" { };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.handheld-session = {
      description = "Handheld display session (cage + emulationstation)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-udev-settle.service"
        "pipewire.service"
        "wireplumber.service"
      ];
      requires = [
        "pipewire.service"
        "wireplumber.service"
      ];

      environment = {
        XDG_RUNTIME_DIR = "/run/user/${toString config.handheld.user.uid}";
        HOME = "/home/${config.handheld.user.name}";
        # Without this, XDG_RUNTIME_DIR being set makes wlroots try to
        # nest under a parent Wayland compositor (which doesn't exist on
        # this kiosk) and abort with "Unable to create the wlroots
        # backend". Verified empirically during pre-flight smoke test.
        WLR_BACKENDS = "drm,libinput";
        # libseat tries seatd → logind → builtin in order. We don't run
        # seatd or logind here; force the builtin backend so libseat
        # opens /dev/dri and /dev/input/event* directly using the
        # kiosk user's group perms (video, input). The kernel grants
        # DRM master implicitly because handheld-session owns /dev/tty1.
        LIBSEAT_BACKEND = "builtin";
      };

      serviceConfig = {
        User = config.handheld.user.name;
        Group = "users";
        SupplementaryGroups = [
          "video"
          "input"
          "audio"
          # tty: read/write to /dev/tty0 so libseat's builtin backend can
          # open the active-VT handle to issue VT_ACTIVATE/VT_SETMODE
          # ioctls. (logind/seatd would handle this for us; under
          # builtin we do it ourselves.)
          "tty"
        ];
        # CAP_SYS_TTY_CONFIG: VT_ACTIVATE / VT_SETMODE ioctls themselves
        # need this. CAP_DAC_OVERRIDE: minimal NixOS profile doesn't
        # ship the standard `KERNEL=="tty[0-9]*", MODE="0620"` udev
        # rule, so /dev/tty0 stays at mode 0600 and the tty group bit
        # never helps — DAC override is the cleanest bypass without
        # taking a dependency on logind sessions or custom udev rules.
        #
        # No CapabilityBoundingSet — leaving it at the default (all
        # caps) lets setuid binaries (notably /run/wrappers/bin/sudo)
        # escalate normally for things like ES's "Shutdown System"
        # menu. Restricting it to just the ambient grants would block
        # CAP_SETUID/CAP_SETGID and sudo would silently fail.
        AmbientCapabilities = [
          "CAP_SYS_TTY_CONFIG"
          "CAP_DAC_OVERRIDE"
        ];
        Type = "simple";

        # cage needs a real TTY to take VT ownership.
        TTYPath = "/dev/tty1";
        StandardInput = "tty";
        StandardOutput = "journal";
        StandardError = "journal";

        # Systemd creates /run/user/<uid> for us — no logind user session
        # needed since handheld-session is a system service.
        RuntimeDirectory = "user/${toString config.handheld.user.uid}";
        RuntimeDirectoryMode = "0700";

        Restart = "on-failure";
        RestartSec = "2s";
        StartLimitIntervalSec = 60;

        ExecStart = "${lib.getExe cfg.package} -s -- ${sessionScript}";
      };
    };

    # mkDefault so attrsOf merges with the shared RA settings instead
    # of overriding the whole attrset at normal priority.
    handheld.retroarch.settings = lib.mkDefault cageRetroarchOverrides;
    handheld.emulationstation.retroarchSettings = lib.mkDefault cageRetroarchOverrides;
  };
}
