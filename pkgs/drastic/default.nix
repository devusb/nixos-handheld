{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  SDL2,
  alsa-lib,
  zlib,
}:

stdenv.mkDerivation {
  pname = "drastic";
  version = "2.5.0.4";

  src = fetchurl {
    url = "https://github.com/ROCKNIX/packages/raw/51f6f221d5aca2fd13202ef59b778daef4ee7163/drastic.tar.gz";
    hash = "sha256-t7vrdJO8w1VhmIDAkpzycJ4mTweFq3CanDBec7EZmzA=";
  };

  sourceRoot = "drastic/drastic_aarch64";

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    SDL2
    alsa-lib
    zlib
    stdenv.cc.cc.lib # libstdc++, libgcc_s
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/drastic $out/share/drastic/system
    install -m755 drastic $out/bin/drastic
    cp game_database.xml usrcheat.dat $out/share/drastic/
    cp drastic_logo_0.raw drastic_logo_1.raw $out/share/drastic/
    cp system/drastic_bios_arm7.bin system/drastic_bios_arm9.bin $out/share/drastic/system/

    runHook postInstall
  '';

  meta = {
    description = "DraStic Nintendo DS emulator (prebuilt aarch64 binary)";
    homepage = "https://www.drastic-ds.com/";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
    mainProgram = "drastic";
  };
}
