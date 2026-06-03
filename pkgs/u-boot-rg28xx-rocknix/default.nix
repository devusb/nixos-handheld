# ROCKNIX's prebuilt H700 U-Boot, extracted from
# ROCKNIX-H700.aarch64-20250517.img (bytes 8192..2M of the raw image).
# Mainline u-boot v2025.07-rc3 with anbernic_rg35xx_h700_defconfig +
# ROCKNIX's build env. Used as a known-good baseline alongside
# h700-dtb-rocknix until our own buildUBoot output (u-boot-rg28xx)
# matches their boot behaviour.
{ runCommand }:
runCommand "u-boot-rg28xx-rocknix" { } ''
  mkdir -p $out
  cp ${./u-boot-sunxi-with-spl.bin} $out/u-boot-sunxi-with-spl.bin
''
