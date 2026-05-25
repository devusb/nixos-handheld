# Userspace fake-suspend for handhelds whose SoC lacks working suspend-to-RAM
# (currently: Allwinner H700). Bypasses systemd-suspend entirely.
# See handheld-fake-suspend.sh for the script and tests/ for its bats suite.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.handheld.fakeSuspend;

  fakeSuspendPkg = pkgs.writeShellApplication {
    name = "handheld-fake-suspend";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      evtest
      pulseaudio
      util-linux
    ];
    text = builtins.readFile ./handheld-fake-suspend.sh;
  };

  powerButtonPkg = pkgs.writeShellApplication {
    name = "handheld-power-button";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      evtest
      fakeSuspendPkg
    ];
    text = builtins.readFile ./handheld-power-button.sh;
  };
in
{
  options.handheld.fakeSuspend = {
    enable = lib.mkEnableOption "userspace fake-suspend for handhelds without working S3";

    powerButtonDevice = lib.mkOption {
      type = lib.types.str;
      default = "axp20x-pek";
      description = ''
        Input device name (matched against /sys/class/input/event*/device/name)
        for the power button. The handheld-power-button service resolves this
        to /dev/input/eventN at startup. Default matches Allwinner AXP-series
        PMICs.
      '';
    };

    inputWhitelist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra input device names that stay active during fake-suspend. The
        configured powerButtonDevice is always whitelisted automatically.
        Everything else gets `evtest --grab`'d to swallow input from sleeping
        games and the joypad.
      '';
    };

    shutdownDelay = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Seconds before auto-shutdown if not resumed. 0 disables.";
    };

    parkCores = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Offline all CPUs except cpu0 during fake-suspend.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      fakeSuspendPkg
      powerButtonPkg
      pkgs.evtest
      pkgs.pulseaudio
    ];

    # logind owns power-button events by default — hand them to us instead.
    services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore";

    systemd.tmpfiles.rules = [
      "d /run/handheld-fake-suspend 0755 root root -"
    ];

    systemd.services.handheld-power-button = {
      description = "Watch the handheld power button and trigger fake-suspend";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];

      environment = {
        PARK_CORES = if cfg.parkCores then "1" else "0";
        SHUTDOWN_DELAY = toString cfg.shutdownDelay;
        INPUT_WHITELIST = lib.concatStringsSep ":" ([ cfg.powerButtonDevice ] ++ cfg.inputWhitelist);
        FAKE_SUSPEND_BIN = lib.getExe fakeSuspendPkg;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe powerButtonPkg} ${cfg.powerButtonDevice}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
