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

        boot.kernelModules = [ "uinput" ];
        services.udev.extraRules = ''
          KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
        '';
      }
      # Ports exec `portmaster-launch` from ES's child shell, so the
      # launcher must be on the PATH of the unit that runs ES — which
      # is emulationstation.service normally, but handheld-session.service
      # (cage) when the compositor owns the display.
      (lib.mkIf config.handheld.emulationstation.enable {
        systemd.services.emulationstation.path = [
          cfg.package
          cfg.launchPackage
        ];
      })
      (lib.mkIf (config.handheld.emulationstation.enable && config.handheld.compositor.enable) {
        systemd.services.handheld-session.path = [
          cfg.package
          cfg.launchPackage
        ];
      })
    ]
  );
}
