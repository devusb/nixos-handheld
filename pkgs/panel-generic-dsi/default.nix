{
  lib,
  kernel,
}:
kernel.stdenv.mkDerivation {
  pname = "panel-generic-dsi";
  version = kernel.version;
  src = ./drivers;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernel.commonMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
    "INSTALL_MOD_PATH=${placeholder "out"}"
    "INSTALL_MOD_DIR=extra"
  ];

  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];

  meta = {
    description = "Generic MIPI-DSI panel driver (ROCKNIX)";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
