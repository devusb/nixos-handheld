# Standalone DTB compilation for RK3326-based handhelds.
#
# Runs cpp + dtc directly on our DTS. Matches the kernel's own DTS
# invocation in scripts/Makefile.lib (cpp preprocessing, dtc with -@ for
# overlay symbol support). The kernel source provides DT bindings and
# rk3326.dtsi; it's unpacked via stdenv but not built.
#
# DTS changes rebuild in ~1s instead of ~5min kernel rebuild.
{
  lib,
  stdenv,
  dtc,
  kernel,
}:

stdenv.mkDerivation {
  pname = "rk3326-dtb";
  inherit (kernel) version src;

  nativeBuildInputs = [ dtc ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
      -I include \
      -I scripts/dtc/include-prefixes \
      -I arch/arm64/boot/dts \
      -I arch/arm64/boot/dts/rockchip \
      -o rk3326-r36s.dts.pre \
      ${./rk3326-r36s.dts}

    dtc -I dts -O dtb -@ -o rk3326-r36s.dtb rk3326-r36s.dts.pre

    runHook postBuild
  '';

  # hardware.deviceTree.dtbSource expects a directory with the vendor subdir layout.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/rockchip
    cp rk3326-r36s.dtb $out/rockchip/
    runHook postInstall
  '';

  meta = {
    description = "Compiled device tree blobs for RK3326 handhelds";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
