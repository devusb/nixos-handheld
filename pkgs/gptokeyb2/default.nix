{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  cmake,
  SDL2,
  libevdev,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gptokeyb2";
  version = "2026.10.05-1355";

  src = fetchFromGitHub {
    owner = "PortsMaster";
    repo = "gptokeyb2";
    tag = finalAttrs.version;
    hash = "sha256-bPEQChkMvyV55sedOtAeN/yOBggxWsQQQIRT0Og+OyU=";
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

  passthru.updateScript = nix-update-script { extraArgs = [ "--flake" ]; };

  meta = {
    description = "Game controller to keyboard/mouse mapper for PortMaster ports";
    homepage = "https://github.com/PortsMaster/gptokeyb2";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "gptokeyb";
  };
})
