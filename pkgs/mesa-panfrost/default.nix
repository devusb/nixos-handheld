{ lib, mesa }:

(mesa.override {
  eglPlatforms = [ ];
  galliumDrivers = [ "panfrost" ];
  vulkanDrivers = [ ];
  vulkanLayers = [ ];
  withValgrind = false;
}).overrideAttrs (old: {
  mesonAutoFeatures = "disabled";
  # Replace mesonFlags entirely — upstream's flags assume a full desktop build
  mesonFlags = [
    "--sysconfdir=/etc"
    "-Dplatforms="
    "-Dgallium-drivers=panfrost"
    "-Dvulkan-drivers="
    "-Dvulkan-layers="
    "-Degl=enabled"
    "-Dgbm=enabled"
    "-Dgles1=enabled"
    "-Dgles2=enabled"
    "-Dglvnd=enabled"
    "-Dglx=disabled"
    "-Dllvm=disabled"
    "-Dlmsensors=disabled"
    "-Dxlib-lease=disabled"
    "-Dgallium-rusticl=false"
    "-Dgallium-extra-hud=false"
    "-Dgallium-va=disabled"
    "-Dgallium-opencl=disabled"
    "-Dinstall-mesa-clc=false"
    "-Dinstall-precomp-compiler=false"
    "-Dopencl-spirv=false"
    "-Dteflon=false"
    "-Dmicrosoft-clc=disabled"
    "-Dintel-rt=disabled"
    "-Dvalgrind=disabled"
    "-Dtools="
  ];
  outputs = lib.lists.subtractLists [ "osmesa" "spirv2dxil" ] old.outputs;
})
