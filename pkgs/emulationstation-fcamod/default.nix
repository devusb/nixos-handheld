{
  lib,
  stdenv,
  fetchFromGitHub,
  writeShellScript,
  gawk,
  cmake,
  pkg-config,
  freeimage,
  SDL2,
  SDL2_mixer,
  freetype,
  curl,
  vlc,
  rapidjson,
  alsa-lib,
  wireplumber,
  mesa,
  libglvnd,
  libdrm,
}:

let
  wpctl = lib.getExe' wireplumber "wpctl";
  volumeScript = writeShellScript "es-get-volume" ''
    ${wpctl} get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | ${lib.getExe gawk} '{printf "%.0f\n", $2 * 100}' || echo "?"
  '';
in
stdenv.mkDerivation {
  pname = "emulationstation-fcamod";
  version = "0-unstable-2026-04-07";

  src = fetchFromGitHub {
    owner = "christianhaitian";
    repo = "EmulationStation-fcamod";
    rev = "c70a664c16d22e394e62fbb76f3156d677fee4f6";
    hash = "sha256-XPD/ZxcIapoQrjfga2WmcA9RtIxjtJPQx0UTRONkO3U=";
    fetchSubmodules = true;
  };

  # Use the 351v branch — libgo2 display code is commented out,
  # uses SDL2 KMSDRM backend directly (no RGA dependency)

  patches = [ ./nixos-handheld.patch ];

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    freeimage
    SDL2
    SDL2_mixer
    freetype
    curl
    vlc
    rapidjson
    alsa-lib
    mesa
    libglvnd
    libdrm
  ];

  cmakeFlags = [
    "-DGLES=ON"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DSDLMIXER_INCLUDE_DIR=${SDL2_mixer.dev}/include/SDL2"
    "-DSDLMIXER_LIBRARY=${SDL2_mixer}/lib/libSDL2_mixer.so"
    "-DOPENGLES_INCLUDE_DIR=${libglvnd.dev}/include"
    "-DOPENGLES_LIBRARIES=${libglvnd}/lib/libGLESv2.so"
  ];

  postPatch = ''
    substituteInPlace es-core/src/resources/ResourceManager.cpp \
      --replace-fail '@out@' '${placeholder "out"}'
    substituteInPlace CMakeLists.txt \
      --replace-fail '@sdl2MixerDev@' '${SDL2_mixer.dev}'
    substituteInPlace CMake/Packages/FindSDL2MIXER.cmake \
      --replace-fail '@sdl2MixerDev@' '${SDL2_mixer.dev}' \
      --replace-fail '@sdl2MixerLib@' '${SDL2_mixer}'
    # Status bar commands — see es-app/src/guis/GuiMenu.cpp for usage:
    #   @batteryCommand@ → bare integer, "%" appended by C++ (e.g. "85")
    #   @volumeCommand@  → bare integer, "%" appended by C++ (e.g. "80")
    #   @wifiCommand@    → short status string (e.g. "up", "down", "N/A")
    substituteInPlace es-app/src/guis/GuiMenu.cpp \
      --replace-fail '@batteryCommand@' 'cat /sys/class/power_supply/battery/capacity 2>/dev/null || cat /sys/class/power_supply/rk817-battery/capacity 2>/dev/null || echo "?"' \
      --replace-fail '@volumeCommand@' '${volumeScript}' \
      --replace-fail '@wifiCommand@' 'echo N/A'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/emulationstation
    cp ../emulationstation $out/bin/
    cp -r ../resources $out/share/emulationstation/
    runHook postInstall
  '';

  meta = {
    description = "EmulationStation frontend (fcamod fork, 351v branch) for handheld gaming devices";
    homepage = "https://github.com/christianhaitian/EmulationStation-fcamod";
    license = lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
    mainProgram = "emulationstation";
  };
}
