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
    runCommand "linux-rk3326-config"
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

        cp ${./rk3326_defconfig} arch/arm64/configs/rk3326_defconfig

        make rk3326_defconfig
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
