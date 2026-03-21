{ lib, fetchurl, linuxKernel, ... }:

linuxKernel.manualConfig {
  version = "6.12.74";
  modDirVersion = "6.12.74";

  src = fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.74.tar.xz";
    hash = "sha256-O1busdyaQ38YnKVrgjvjdpmU9ZpOoIlbCOwNIKysoT4=";
  };

  configfile = ./rk3326_defconfig;
  allowImportFromDerivation = true;

  kernelPatches = [
    {
      name = "rk3326-handheld-support";
      patch = ./patches/0001-rk3326-handheld-support.patch;
    }
  ];

  extraMeta = {
    platforms = [ "aarch64-linux" ];
    description = "Linux 6.12.74 with RK3326 handheld patches";
  };
}
