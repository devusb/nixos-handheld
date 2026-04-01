{
  lib,
  linuxPackages_latest,
  ...
}:
(linuxPackages_latest.kernel.override {
  kernelPatches = [
    {
      name = "r36s-makefile";
      patch = ./patches/0001-add-r36s-to-makefile.patch;
    }
  ];
  structuredExtraConfig = with lib.kernel; {
    ROCKCHIP_SARADC = module;
    KEYBOARD_GPIO = module;
    INPUT_EVDEV = module;

    # Display (MIPI DSI + Rockchip VOP)
    DRM_ROCKCHIP = module;
    PHY_ROCKCHIP_INNO_DSIDPHY = module;

    # GPU (Panfrost)
    DRM_PANFROST = module;

    # Audio (RK817 codec via I2S)
    SND_SOC_ROCKCHIP_I2S = module;
    SND_SOC_RK817 = module;

    # USB gadget ethernet
    USB_DWC2 = module;
    USB_GADGET = yes;
    USB_ETH = module;
  };
}).overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    cp ${./rk3326-r36s.dts} arch/arm64/boot/dts/rockchip/rk3326-r36s.dts
  '';
})
