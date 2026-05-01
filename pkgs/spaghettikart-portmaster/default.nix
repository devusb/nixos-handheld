{
  lib,
  buildFHSEnv,
  fetchzip,
  makeWrapper,
  SDL2_classic,
  mesa,
  libzip,
  spdlog,
  tinyxml-2,
  libvorbis,
  libogg,
  zlib,
  libpng,
  nlohmann_json,
  openssl,
  stdenv,
  requireFile,
  runCommand,
}:
let
  portmaster-bin = fetchzip {
    url = "https://github.com/PortsMaster-MV/PortMaster-MV-New/releases/download/2025-09-08_1359/spaghettikart.zip";
    hash = "sha256-wl6Aj5iLySeXwQ/ZIcmlqK5uS/PYMTCvOHiZyomytF4=";
    stripRoot = false;
  };

  rom = requireFile {
    name = "baserom.us.z64";
    url = "https://github.com/HarbourMasters/SpaghettiKart";
    hash = "sha256-1rhTjdY/ATLssoVufTKBbtPDDj5HmuzSPPg/troXpdo=";
    message = ''
      Mario Kart 64 US ROM not found in the store. Acquire it and run:

        nix-store --add-fixed sha256 baserom.us.z64
    '';
  };

  gameDir = runCommand "spaghettikart-portmaster-data" { } ''
    mkdir -p $out/bin $out/share/spaghettikart

    # PortMaster prebuilt binary + all its assets
    cp ${portmaster-bin}/spaghettikart/bin/Spaghettify-GLES $out/bin/Spaghettify
    chmod +x $out/bin/Spaghettify
    cp -r ${portmaster-bin}/spaghettikart/libs.aarch64 $out/share/spaghettikart/
    cp ${portmaster-bin}/spaghettikart/spaghetti.o2r $out/share/spaghettikart/
    cp -r ${portmaster-bin}/spaghettikart/torch $out/share/spaghettikart/

    # ROM for in-game extraction
    ln -s ${rom} $out/share/spaghettikart/baserom.us.z64
  '';

  fhs = buildFHSEnv {
    name = "Spaghettify";
    targetPkgs = pkgs: [
      SDL2_classic
      pkgs.SDL2_net
      mesa
      pkgs.libglvnd
      pkgs.libGL
      libzip
      spdlog
      tinyxml-2
      libvorbis
      libogg
      zlib
      libpng
      nlohmann_json
      openssl
    ];
    profile = ''
      export LD_LIBRARY_PATH="${gameDir}/share/spaghettikart/libs.aarch64:$LD_LIBRARY_PATH"
    '';
    runScript = "${gameDir}/bin/Spaghettify";
    extraBwrapArgs = [
      "--bind" "$HOME/.local/share/spaghettikart" "$HOME/.local/share/spaghettikart"
    ];
  };
in
stdenv.mkDerivation {
  pname = "spaghettikart-portmaster";
  version = "2025-09-08";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${fhs}/bin/Spaghettify $out/bin/Spaghettify \
      --run 'mkdir -p ~/.local/share/spaghettikart' \
      --run "ln -sf ${gameDir}/share/spaghettikart/spaghetti.o2r ~/.local/share/spaghettikart/spaghetti.o2r" \
      --run "ln -sf ${gameDir}/share/spaghettikart/baserom.us.z64 ~/.local/share/spaghettikart/baserom.us.z64" \
      --run "rm -rf ~/.local/share/spaghettikart/torch && cp -rL --no-preserve=mode ${gameDir}/share/spaghettikart/torch ~/.local/share/spaghettikart/torch" \
      --run 'cd ~/.local/share/spaghettikart' \
      --set LD_LIBRARY_PATH "${gameDir}/share/spaghettikart/libs.aarch64"
  '';

  meta = {
    description = "SpaghettiKart (PortMaster prebuilt binary)";
    platforms = [ "aarch64-linux" ];
    license = with lib.licenses; [ mit unfree ];
  };
}
