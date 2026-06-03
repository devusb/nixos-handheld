# Standalone DTB compilation for Allwinner H700-based handhelds.
#
# Runs cpp + dtc directly on our overlay DTS. The base DTS files
# (sun50i-h700-anbernic-rg35xx-plus.dts and its parent rg35xx-2024.dts) are
# already in mainline Linux, so they come along via the kernel source unpack
# that stdenv does via `inherit (kernel) src`. cpp resolves the include
# chain through the kernel's allwinner DTS directory.
#
# Matches pkgs/rk3326-dtb's pattern; same trick lets DTS changes rebuild in
# ~1s instead of waiting on a full kernel rebuild.
{
  lib,
  stdenv,
  dtc,
  kernel,
}:

stdenv.mkDerivation {
  pname = "h700-dtb";
  inherit (kernel) version src;

  nativeBuildInputs = [ dtc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
      -I include \
      -I scripts/dtc/include-prefixes \
      -I arch/arm64/boot/dts \
      -I arch/arm64/boot/dts/allwinner \
      -o sun50i-h700-anbernic-rg28xx.dts.pre \
      ${./sun50i-h700-anbernic-rg28xx.dts}

    dtc -I dts -O dtb -@ -o sun50i-h700-anbernic-rg28xx.dtb \
      sun50i-h700-anbernic-rg28xx.dts.pre

    runHook postBuild
  '';

  # hardware.deviceTree.dtbSource expects a directory with the vendor subdir layout.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/allwinner
    cp sun50i-h700-anbernic-rg28xx.dtb $out/allwinner/
    runHook postInstall
  '';

  meta = {
    description = "Compiled device tree blob for Anbernic RG28XX (Allwinner H700)";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
