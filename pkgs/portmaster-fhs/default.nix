{
  buildFHSEnv,
  SDL2_classic,
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
}:
buildFHSEnv {
  name = "portmaster-run";
  targetPkgs = _: [
    SDL2_classic
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
  ];
  runScript = "${bash}/bin/bash";
}
