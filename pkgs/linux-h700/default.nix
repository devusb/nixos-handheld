# Kernel for Allwinner H700-based handhelds (RG28XX et al.).
#
# Same shape as pkgs/linux-rk3326/default.nix: take the mainline source from
# linuxPackages_latest, run the static defconfig through `make` so Kconfig
# can resolve dependencies, then feed the resulting .config to
# linuxManualConfig. allowImportFromDerivation pulls the .config back into
# Nix evaluation; features={} short-circuits the assertions
# `linuxPackagesFor` would otherwise run against passthru.features.
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
