# ROCKNIX's prebuilt H700 U-Boot: mainline u-boot with
# anbernic_rg35xx_h700_defconfig, extracted from a ROCKNIX H700
# release image (bytes 8192..2M of the raw image).
{ runCommand }:
runCommand "u-boot-rg28xx-rocknix" { } ''
  mkdir -p $out
  cp ${./u-boot-sunxi-with-spl.bin} $out/u-boot-sunxi-with-spl.bin
''
