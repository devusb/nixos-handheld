{ config, lib, pkgs, ... }:

let
  cfg = config.handheld.gpu;
in
{
  options.handheld.gpu = {
    driver = lib.mkOption {
      type = lib.types.enum [ "panfrost" "mali" ];
      default = "panfrost";
      description = ''
        GPU driver stack to use.

        - panfrost: open-source Mesa driver. Better for RetroArch cores.
        - mali: ARM proprietary blob (mali_kbase + libmali). Better for
          libultraship-based PortMaster ports. Unfree license.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.driver == "panfrost") {
      boot.blacklistedKernelModules = [ "mali_kbase" ];
    })
    (lib.mkIf (cfg.driver == "mali") {
      boot.blacklistedKernelModules = [ "panfrost" ];
      boot.extraModulePackages = [ pkgs.mali-kbase ];
      hardware.graphics.package = pkgs.libmali;

      # PortMaster prebuilt port support — libmali userspace + bwrap FHS env.
      # Only useful in mali mode: the prebuilt binaries open /dev/mali0 directly
      # and would crash with mali_kbase blacklisted under panfrost.
      environment.systemPackages = with pkgs; [
        portmaster-fhs
        portmaster-launch
      ];
    })
    (lib.mkIf (cfg.driver == "mali" && config.handheld.emulationstation.enable) {
      systemd.services.emulationstation.path = with pkgs; [
        portmaster-fhs
        portmaster-launch
      ];

      # Re-link userspace against libmali so RPATH'd libraries find the right
      # GL/GBM at runtime, not just via /run/opengl-driver dispatch.
      #
      # SDL2_classic flows transitively into ES, DraStic, and SDL2_classic_mixer.
      # emulationstation-fcamod additionally takes mesa+libglvnd as direct
      # inputs (CMake reads libglvnd's GLESv2.so path), so it needs an explicit
      # override even though SDL2 is already covered.
      # retroarch-bare's libGL/libGLU/libgbm parameters control its configure
      # flags and final link line.
      # mkAfter so we run after the base overlay defines SDL2_classic,
      # libmali, etc. — otherwise our `prev.SDL2_classic.override` references
      # an undefined attribute and silently does nothing.
      nixpkgs.overlays = lib.mkAfter [
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
          retroarch-bare = prev.retroarch-bare.override {
            libGL = final.libmali;
            libGLU = final.libmali;
            libgbm = final.libmali;
          };
        })
      ];
    })
  ];
}
