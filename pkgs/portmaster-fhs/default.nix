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
    ];
  # Win over libglvnd's dispatcher when both are in the sandbox.
  profile = ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath gpuPackages}:$LD_LIBRARY_PATH"
  '';
  runScript = "${bash}/bin/bash";
}
