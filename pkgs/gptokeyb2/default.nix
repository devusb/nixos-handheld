{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  SDL2,
  libevdev,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gptokeyb2";
  version = "0.2.0-unstable-2025-09-22";

  src = fetchFromGitHub {
    owner = "PortsMaster";
    repo = "gptokeyb2";
    rev = "7100d030fe10a7cd5f3053cd9922249498ab3a8d";
    hash = "sha256-+Iib3gbxRAv+NbrHfSCm8EJPUCCBMkGV23ADrT1ZdXo=";
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    SDL2
    libevdev
  ];

  cmakeFlags = [
    "-DLIBEVDEV_INCLUDE_DIR=${lib.getDev libevdev}/include/libevdev-1.0"
    "-DLIBEVDEV_LIBRARY=${lib.getLib libevdev}/lib/libevdev.so"
    "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
    "-DCMAKE_INSTALL_RPATH=${placeholder "out"}/lib"
  ];

  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  installPhase = ''
    runHook preInstall
    install -Dm755 gptokeyb2 $out/bin/gptokeyb2
    install -Dm755 lib/libinterpose.so $out/lib/libinterpose.so
    ln -s gptokeyb2 $out/bin/gptokeyb
    runHook postInstall
  '';

  meta = {
    description = "Game controller to keyboard/mouse mapper for PortMaster ports";
    homepage = "https://github.com/PortsMaster/gptokeyb2";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "gptokeyb";
  };
})
