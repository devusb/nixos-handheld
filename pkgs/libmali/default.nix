{
  stdenv,
  lib,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  libdrm,
}:
stdenv.mkDerivation {
  pname = "libmali-bifrost-g31";
  version = "g13p0";

  outputs = [ "out" "dev" ];

  src = fetchFromGitHub {
    owner = "ROCKNIX";
    repo = "libmali";
    rev = "0fe30426b822699f0a660268a6040fdafce229d1";
    hash = "sha256-zqIhfIHDE8MZiupPjrX04flwACDS8pcq1tX4S94H0mY=";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ libdrm ];
  propagatedBuildInputs = [ libdrm ];

  postPatch = ''
    patchShebangs scripts/
  '';

  # The meson build uses cc.has_function() to check the prebuilt blob,
  # but these checks fail without libdrm on the link line
  env.NIX_LDFLAGS = "-ldrm";

  mesonFlags = [
    "-Dgpu=bifrost-g31"
    "-Dversion=g13p0"
    "-Dplatform=gbm"
    "-Dopencl-icd=false"
    "-Dwrappers=disabled"
    "-Dkhr-header=true"
    "-Dwayland-egl=false"
    "-Dhooks=true"
  ];

  # Skip the meson wrappers (empty .so stubs with DT_NEEDED → libmali.so).
  # Nix's linker won't resolve symbols through transitive DT_NEEDED entries,
  # so every package built against the wrappers fails with "DSO missing from
  # command line". Direct symlinks put the real symbols where the linker
  # expects them.
  postInstall = ''
    # Patch the prebuilt blob's RUNPATH so the linker can find libdrm
    patchelf --set-rpath "${lib.makeLibraryPath [ libdrm ]}" $out/lib/libmali.so

    ln -sf libmali.so $out/lib/libEGL.so
    ln -sf libmali.so $out/lib/libEGL.so.1
    ln -sf libmali.so $out/lib/libGLESv1_CM.so
    ln -sf libmali.so $out/lib/libGLESv1_CM.so.1
    ln -sf libmali.so $out/lib/libGLESv2.so
    ln -sf libmali.so $out/lib/libGLESv2.so.2
    ln -sf libmali.so $out/lib/libgbm.so
    ln -sf libmali.so $out/lib/libgbm.so.1
  '';

  meta = {
    description = "ARM Mali Bifrost G31 proprietary GPU driver";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.unfree;
  };
}
