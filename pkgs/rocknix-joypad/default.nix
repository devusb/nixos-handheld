{
  lib,
  kernel,
}:
kernel.stdenv.mkDerivation {
  pname = "rocknix-singleadc-joypad";
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
    install -D rocknix-singleadc-joypad.ko \
      $out/lib/modules/${kernel.modDirVersion}/extra/rocknix-singleadc-joypad.ko
  '';

  meta = {
    description = "ROCKNIX single-ADC joypad driver (combined analog sticks + GPIO buttons)";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-linux" ];
  };
}
