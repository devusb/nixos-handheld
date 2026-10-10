# Standalone DTB compilation for Allwinner H700-based handhelds.
#
# Runs cpp + dtc directly on the local DTS so DTS-only changes rebuild
# in ~1s instead of waiting on a full kernel rebuild. linux-h700's
# patched source carries the ROCKNIX H700 device trees, so cpp resolves
# the include chain through the kernel's allwinner DTS directory.
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
      ${./rg28xx-nixos.dts}

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
