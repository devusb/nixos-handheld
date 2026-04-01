{
  lib,
  kernel,
}:
kernel.stdenv.mkDerivation {
  pname = "panel-generic-dsi";
  version = kernel.version;
  src = ./drivers;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD \
      ARCH=${kernel.stdenv.hostPlatform.linuxArch} \
      CROSS_COMPILE=${kernel.stdenv.cc.targetPrefix} \
      modules
  '';

  installPhase = ''
    install -D panel-generic-dsi.ko \
      $out/lib/modules/${kernel.modDirVersion}/extra/panel-generic-dsi.ko
  '';

  meta = {
    description = "Generic MIPI-DSI panel driver (ROCKNIX)";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
