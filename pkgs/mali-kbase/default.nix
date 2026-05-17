{
  lib,
  kernel,
  fetchFromGitHub,
}:
kernel.stdenv.mkDerivation {
  pname = "mali-kbase";
  version = "0-unstable-2026-04-06";

  src = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "mali_kbase";
    rev = "39da994bb6fc8819e5e8c1873907dd21d17e53c1";
    hash = "sha256-hyt6UbFRIBowP3EjLAYKY6SgaGvjCaboU6K5XsnqimQ=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "ARCH=${kernel.stdenv.hostPlatform.linuxArch}"
    "CROSS_COMPILE=${kernel.stdenv.cc.targetPrefix}"
  ];

  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD/product/kernel/drivers/gpu/arm/midgard \
      ARCH=${kernel.stdenv.hostPlatform.linuxArch} \
      CROSS_COMPILE=${kernel.stdenv.cc.targetPrefix} \
      CONFIG_MALI_MIDGARD=m \
      CONFIG_MALI_PLATFORM_NAME=devicetree \
      CONFIG_MALI_REAL_HW=y \
      CONFIG_MALI_CSF_SUPPORT=n \
      CONFIG_MALI_DEVFREQ=y \
      CONFIG_MALI_GATOR_SUPPORT=n \
      modules
  '';

  installPhase = ''
    find . -name '*.ko' -exec install -D {} $out/lib/modules/${kernel.modDirVersion}/extra/{} \;
  '';

  meta = {
    description = "ARM Mali Bifrost GPU kernel module (proprietary kbase driver)";
    license = lib.licenses.gpl2Plus;
    platforms = [ "aarch64-linux" ];
  };
}
