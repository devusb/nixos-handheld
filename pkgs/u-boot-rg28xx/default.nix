# Mainline U-Boot for Anbernic H700 handhelds (RG28XX, RG35XX-2024/Plus/H/SP).
# Single defconfig covers all four; board detection picks the DTB at boot.
{
  buildUBoot,
  armTrustedFirmwareAllwinnerH616,
}:

buildUBoot {
  defconfig = "anbernic_rg35xx_h700_defconfig";
  extraMeta.platforms = [ "aarch64-linux" ];
  env.BL31 = "${armTrustedFirmwareAllwinnerH616}/bl31.bin";
  filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
}
