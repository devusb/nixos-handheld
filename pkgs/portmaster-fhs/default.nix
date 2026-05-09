{
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
}:
buildFHSEnv {
  name = "portmaster-run";
  targetPkgs = _: [
    SDL2
    SDL2_net
    mesa
    libglvnd
    libGL
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
  runScript = "${bash}/bin/bash";
}
