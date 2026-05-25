# U-Boot for Anbernic H700 handhelds (RG28XX, RG35XX-2024/Plus/H/SP).
#
# Mainline U-Boot ships a single `anbernic_rg35xx_h700_defconfig` that targets
# all four H700 Anbernic variants — board detection at runtime picks the right
# DTB. ROCKNIX uses the same defconfig.
#
# The H700 is part of the sun50i-h616 family from the SoC perspective, so the
# secure monitor (BL31) comes from `armTrustedFirmwareAllwinnerH616`.
#
# Output: `u-boot-sunxi-with-spl.bin` — a single combined SPL + U-Boot proper
# blob that gets `dd`'d to sector 16 (8 KiB offset) of the SD card by
# `socs/h700.nix`'s `sdImage.postBuildCommands`.
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
