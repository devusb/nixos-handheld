{
  lib,
  buildFHSEnv,
  SDL2,
  SDL2_net,
  mesa,
  libglvnd,
  libGL,
  libzip,
  spdlog,
  tinyxml-2,
  libvorbis,
  libogg,
  zlib,
  libpng,
  nlohmann_json,
  openssl,
  bash,
  openal,
  curl,
  unzip,
  util-linux,
  procps,
  freetype,
  fontconfig,
  harfbuzz,
  libjpeg,
  bzip2,
  xz,
  libGLU,
  expat,
  gptokeyb2,
  # Override to `[ libmali ]` in mali mode.
  gpuPackages ? [
    mesa
    libglvnd
    libGL
  ],
}:
buildFHSEnv {
  name = "portmaster-run";
  targetPkgs =
    _:
    [
      SDL2
      SDL2_net
      gptokeyb2
    ]
    ++ gpuPackages
    ++ [
      libzip
      spdlog
      tinyxml-2
      libvorbis
      libogg
      zlib
      libpng
      nlohmann_json
      openssl
      openal
      curl
      unzip
      util-linux
      procps
      freetype
      fontconfig
      harfbuzz
      libjpeg
      bzip2
      xz
      libGLU
      expat
    ];
  # Win over libglvnd's dispatcher when both are in the sandbox.
  # GPTOKEYB is the env var PortMaster launch scripts expect; mod_NixOS.txt
  # can override it but ports without device-specific wiring still work.
  profile = ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath gpuPackages}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export GPTOKEYB=gptokeyb
  '';
  runScript = "${bash}/bin/bash";
}
