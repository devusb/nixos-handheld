{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.handheld.portmaster;
in
{
  options.handheld.portmaster = {
    enable = lib.mkEnableOption "PortMaster prebuilt port support via bwrap FHS env";
    package = lib.mkPackageOption pkgs "portmaster-fhs" { };
    launchPackage = lib.mkPackageOption pkgs "portmaster-launch" { };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # PortMaster prebuilt ports link against the standard GL/GLES names and
        # dispatch via libglvnd at runtime, so the FHS sandbox works on either
        # GPU driver. Mali is faster for libultraship games; panfrost is slower
        # but functionally fine.
        environment.systemPackages = [
          cfg.package
          cfg.launchPackage
        ];
      }
      (lib.mkIf config.handheld.emulationstation.enable {
        systemd.services.emulationstation.path = [
          cfg.package
          cfg.launchPackage
        ];
      })
    ]
  );
}
