{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.gpu;
in
{
  options.handheld.gpu = {
    driver = lib.mkOption {
      type = lib.types.enum [
        "panfrost"
        "mali"
      ];
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
      boot.kernelModules = [ "panfrost" ];
    })
    (lib.mkIf (cfg.driver == "mali") {
      boot.blacklistedKernelModules = [ "panfrost" ];
      boot.extraModulePackages = [ pkgs.mali-kbase ];
      boot.kernelModules = [ "mali_kbase" ];
      hardware.graphics.package = pkgs.libmali;

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
          portmaster-fhs = prev.portmaster-fhs.override {
            gpuPackages = [ final.libmali ];
          };
        })
      ];
    })
  ];
}
