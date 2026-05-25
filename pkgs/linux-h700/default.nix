{
  lib,
  linuxPackages_latest,
  linuxManualConfig,
  stdenv,
  flex,
  bison,
  perl,
  runCommand,
  ...
}:
let
  inherit (linuxPackages_latest.kernel) src version modDirVersion;

  configfile =
    runCommand "linux-h700-config"
      {
        nativeBuildInputs = [
          stdenv.cc
          flex
          bison
          perl
        ];
        inherit src;
      }
      ''
        unpackPhase
        cd linux-*

        cp ${./h700_defconfig} arch/arm64/configs/h700_defconfig

        make h700_defconfig
        cp .config $out
      '';
in
(linuxManualConfig {
  inherit
    src
    version
    modDirVersion
    configfile
    ;
  allowImportFromDerivation = true;
  extraMeta.branch = lib.versions.majorMinor version;
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      features = { };
    };
  })
