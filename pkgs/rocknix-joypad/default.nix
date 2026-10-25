{
  lib,
  kernel,
}:
kernel.stdenv.mkDerivation {
  pname = "rocknix-singleadc-joypad";
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
    description = "ROCKNIX single-ADC joypad driver (combined analog sticks + GPIO buttons)";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-linux" ];
  };
}
