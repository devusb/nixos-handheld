{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf mkMerge mkOption mkEnableOption mkAfter types;

  cfg = config.handheld.gpu;
  altDriver = if cfg.driver == "panfrost" then "mali" else "panfrost";
in
{
  options.handheld.gpu = {
    driver = mkOption {
      type = types.enum [
        "panfrost"
        "mali"
      ];
      default = "panfrost";
      description = ''
        GPU driver stack to use.

        - panfrost: open-source Mesa driver.
        - mali: ARM proprietary blob (mali_kbase + libmali).
      '';
    };

    specialisation = {
      enable = mkEnableOption "a NixOS specialisation running the alternate GPU driver";

      picker = {
        enable = mkEnableOption "boot-time hold-button picker that swaps into the alternate specialisation";

        eventDeviceName = mkOption {
          type = types.str;
          default = "gpio-keys-vol";
          description = "Input device 'name' (in /sys/class/input/event*/device/name) to query.";
        };

        key = mkOption {
          type = types.str;
          default = "KEY_VOLUMEDOWN";
          description = "evtest key code to check; if held at boot, the alternate specialisation is selected.";
        };
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.driver == "panfrost") {
      boot.blacklistedKernelModules = [ "mali_kbase" ];
      boot.kernelModules = [ "panfrost" ];
    })
    (mkIf (cfg.driver == "mali") {
      boot.blacklistedKernelModules = [ "panfrost" ];
      boot.extraModulePackages = [ pkgs.mali-kbase ];
      boot.kernelModules = [ "mali_kbase" ];
      hardware.graphics.package = pkgs.libmali;

      nixpkgs.overlays = mkAfter [
        (final: prev: {
          SDL2_classic = prev.SDL2_classic.override {
            libgbm = final.libmali;
            libglvnd = final.libmali;
            mesa = final.libmali;
          };
          emulationstation-fcamod = prev.emulationstation-fcamod.override {
            mesa = final.libmali;
            libglvnd = final.libmali;
          };
          portmaster-fhs = prev.portmaster-fhs.override {
            gpuPackages = [ final.libmali ];
          };
        })
      ];
    })
    (mkIf cfg.specialisation.enable {
      specialisation.${altDriver} = {
        inheritParentConfig = true;
        configuration.handheld.gpu.driver = altDriver;
      };
    })
    (mkIf (cfg.specialisation.picker.enable && !config.isSpecialisation) {
      assertions = [
        {
          assertion = cfg.specialisation.enable;
          message = "handheld.gpu.specialisation.picker.enable requires handheld.gpu.specialisation.enable.";
        }
      ];

      boot.initrd.systemd.storePaths = [ pkgs.evtest ];
      boot.initrd.systemd.services.handheld-gpu-picker = {
        description = "GPU specialisation picker";
        wantedBy = [ "initrd.target" ];
        before = [ "initrd-find-nixos-closure.service" ];
        after = [ "initrd-fs.target" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        path = [
          pkgs.coreutils
          pkgs.evtest
        ];
        script = ''
          # Reset to the default driver so the previous boot's choice doesn't
          # stick. /nix/var/nix/profiles/system is the runtime symlink
          # installBootLoader keeps pointed at the active toplevel.
          ln -sfn /nix/var/nix/profiles/system/init /sysroot/init

          eventdev=
          for entry in /sys/class/input/event*; do
            if [ "$(cat "$entry/device/name" 2>/dev/null)" = "${cfg.specialisation.picker.eventDeviceName}" ]; then
              eventdev="/dev/input/$(basename "$entry")"
              break
            fi
          done
          [ -z "$eventdev" ] && exit 0

          # evtest --query exits 10 iff the key is currently held; other non-zero
          # values mean error (device not ready, etc.) — don't treat those as "held".
          set +e
          evtest --query "$eventdev" EV_KEY ${cfg.specialisation.picker.key}
          held=$?
          set -e
          [ $held -eq 10 ] || exit 0

          ln -sfn ${config.specialisation.${altDriver}.configuration.system.build.toplevel}/init \
            /sysroot/init
        '';
      };
    })
  ];
}
