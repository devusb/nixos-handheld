{
  lib,
  buildUBoot,
  fetchFromGitHub,
  fetchurl,
  rkbin,
  rkbin-tools,
  ubootTools,
  runCommand,
}:

# RK3326 U-Boot, assembled the ROCKNIX way (see
# https://github.com/ROCKNIX/distribution/blob/main/projects/ROCKNIX/bootloader/rkhelper):
#
#   idbloader.img = mkimage(DDR-init, T=rksd) + miniloader   (SD-card boot header)
#   uboot.img     = loaderimage(u-boot-dtb.bin)              (rkbin tool, qemu-wrapped)
#   trust.img     = trust_merger(BL31)                       (rkbin tool, qemu-wrapped)
#
# All three then dd'd at fixed sector offsets into u-boot-rockchip.bin.
#
# We don't build U-Boot's SPL: RK3326's BootROM caps the rksd-format SPL at
# 0x2800 bytes which nixpkgs gcc 15 overshoots, and the proven upstream-
# Rockchip workaround is to use their miniloader as the first-stage loader
# instead of U-Boot's SPL.
#
# U-Boot source: nixpkgs default (currently v2026.04). Defconfig, DTS, and a
# board-detection patch overlaid from ROCKNIX's distribution repo, which
# ships working firmware for R36S-class RK3326 handhelds in production.

let
  # Pin ROCKNIX's distribution repo for the U-Boot overlay files.
  rocknix = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "distribution";
    rev = "1c858055fc2e3d42e5693a520744a646c1c2176d";
    hash = "sha256-tbElwjj9Y48oz2XNSzHyC52SFeAo9tQW51r9Afw7pRk=";
  };
  ubootOverlay = "${rocknix}/projects/ROCKNIX/devices/RK3326/packages/u-boot";

  uboot-proper = buildUBoot {
    pname = "u-boot-r36s-proper";

    # Pin to v2025.10 to match ROCKNIX. Their k36-clone patch (board detection
    # fallback) is written against this exact upstream version; newer U-Boot
    # tags (e.g. nixpkgs default v2026.04) have drift in board/.../go2.c that
    # breaks one of the patch hunks.
    version = "2025.10";
    src = fetchurl {
      url = "https://ftp.denx.de/pub/u-boot/u-boot-2025.10.tar.bz2";
      sha256 = "0jnzxzh210p54k87d4f25divpnw4q0r937ym78hqzk2nis235w5l";
    };

    defconfig = "rk3326-handheld_defconfig";

    patches = [ "${ubootOverlay}/patches/0001-add-support-for-k36-clone-with-emmc-rk3326.patch" ];

    # ROCKNIX's defconfig + custom DTS files get overlaid into the U-Boot
    # source tree before configure. buildUBoot's default postPatch runs
    # `patchShebangs` on tools/ and scripts/ — we extend it.
    postPatch = ''
      cp -rv ${ubootOverlay}/sources/. .
      patchShebangs tools scripts
    '';

    extraConfig = ''
      # bootcmd: source boot.scr from the FAT firmware partition (mmc 1:1).
      # Overrides ROCKNIX's "bootmeth order script; bootflow scan -b" which
      # expects their extlinux layout that we don't ship.
      CONFIG_BOOTDELAY=0
      CONFIG_USE_BOOTCOMMAND=y
      CONFIG_BOOTCOMMAND="load mmc 1:1 0x00500000 boot.scr && source 0x00500000"

      # Defensive: ensure FS/CMD options boot.cmd uses are present.
      CONFIG_FS_FAT=y
      CONFIG_FS_EXT4=y
      CONFIG_CMD_FAT=y
      CONFIG_CMD_EXT4=y
      CONFIG_CMD_SOURCE=y
      CONFIG_CMD_BOOTI=y
      CONFIG_CMD_FDT=y
      CONFIG_CMD_SETEXPR=y
      CONFIG_CMD_LOAD=y
    '';

    filesToInstall = [ "u-boot-dtb.bin" ];

    # buildUBoot's configurePhase appends extraConfig to .config without
    # re-running Kconfig dependency resolution. olddefconfig validates the
    # combined config.
    postConfigure = "make olddefconfig";

    # Rockchip's mach-rockchip Kconfig hard-`select`s SPL/TPL via
    # CONFIG_ROCKCHIP_PX30, so we can't disable them via Kconfig. Instead we
    # build the u-boot-dtb.bin target directly, bypassing the default `all`
    # target that triggers binman → mkimage rksd → SPL size check.
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES "''${makeFlags[@]}" u-boot-dtb.bin
      runHook postBuild
    '';

    extraMeta.platforms = [ "aarch64-linux" ];
  };
in
runCommand "u-boot-r36s-${uboot-proper.version}"
  {
    nativeBuildInputs = [
      ubootTools
      rkbin-tools
    ];
    passthru = { inherit uboot-proper; };
    meta = {
      description = "U-Boot for the R36S/R36H, assembled the ROCKNIX way";
      platforms = [ "aarch64-linux" ];
    };
  }
  ''
    DDR=${rkbin}/bin/rk33/rk3326_ddr_333MHz_v2.11.bin
    MINILOADER=${rkbin}/bin/rk33/rk3326_miniloader_v1.40.bin
    BL31=${rkbin}/bin/rk33/rk3326_bl31_v1.34.elf
    UBOOT_DTB=${uboot-proper}/u-boot-dtb.bin

    # idbloader.img: SD-card boot header (rksd format) wrapping the DDR-init
    # blob, with the miniloader appended. -C bzip2 matches what ROCKNIX uses.
    mkimage -n px30 -T rksd -d "$DDR" -C bzip2 idbloader.img
    cat "$MINILOADER" >> idbloader.img

    # uboot.img: U-Boot proper wrapped in Rockchip "Loader" image format.
    # Load address 0x00200000 matches CONFIG_TEXT_BASE.
    loaderimage --pack --uboot "$UBOOT_DTB" uboot.img 0x00200000

    # trust.img: BL31 (TF-A) packed for miniloader handoff.
    cat > trust.ini <<EOF
    [BL30_OPTION]
    SEC=0
    [BL31_OPTION]
    SEC=1
    PATH=$BL31
    ADDR=0x00010000
    [BL32_OPTION]
    SEC=0
    [BL33_OPTION]
    SEC=0
    [OUTPUT]
    PATH=trust.img
    EOF
    trust_merger --verbose trust.ini

    # Assemble u-boot-rockchip.bin: dd each piece at the fixed sector offsets
    # the RK3326 miniloader expects. Final image gets dd'd to SD sector 64
    # by socs/rk3326.nix.
    cp idbloader.img u-boot-rockchip.bin
    chmod +w u-boot-rockchip.bin
    dd if=uboot.img of=u-boot-rockchip.bin bs=512 seek=16320 conv=fsync,notrunc
    dd if=trust.img of=u-boot-rockchip.bin bs=512 seek=24512 conv=fsync,notrunc

    install -Dm 0644 u-boot-rockchip.bin $out/u-boot-rockchip.bin
  ''
