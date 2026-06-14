{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  libGL,
  zlib,
}:
stdenv.mkDerivation {
  pname = "flycast2021-libretro";
  version = "0-unstable-2025-01-16";

  src = fetchFromGitHub {
    owner = "metallic77";
    repo = "flycast";
    rev = "603814c9f73b773c455d9a497f389d2f93a257fd";
    hash = "sha256-QVbb8mlOwuapCDihDlsCRqtJ+OQq8KuXbC+xOreZtw0=";
  };

  patches = [
    (fetchpatch {
      name = "flycast2021-fix-gcc14.patch";
      url = "https://raw.githubusercontent.com/ROCKNIX/distribution/fd2e34fa837913e5c2c83cb8fc51a8149ba9cf05/projects/ROCKNIX/packages/emulators/libretro/flycast2021-lr/patches/01-fix-gcc14.patch";
      hash = "sha256-QBnw55Aq1YrIkx20rW7AKa+YUVw+airns7Lw9GdkciI=";
    })
    (fetchpatch {
      name = "flycast2021-platform.patch";
      url = "https://raw.githubusercontent.com/ROCKNIX/distribution/fd2e34fa837913e5c2c83cb8fc51a8149ba9cf05/projects/ROCKNIX/packages/emulators/libretro/flycast2021-lr/patches/aarch64/000-platform.patch";
      hash = "sha256-hMY/XeN9ac6ZDnoXo2u3B2lGUtbe1tR9DuUZBU8hwtM=";
    })
    ./002-fix-postprocess-render-symbol.patch
  ];

  # The platform patch leaves the build target as a @DEVICE@ placeholder.
  postPatch = ''
    substituteInPlace Makefile --replace-fail "@DEVICE@" "rk3326"
  '';

  enableParallelBuilding = true;

  # GLES headers for the FORCE_GLES build.
  buildInputs = [
    libGL
    zlib
  ];

  env.NIX_CFLAGS_COMPILE = "-Wno-implicit-function-declaration";

  makeFlags = [
    "platform=rk3326"
    "FORCE_GLES=1"
    "ARCH=aarch64"
    "HAVE_OPENMP=0"
    "HAVE_LTCG=0"
    "HAVE_VULKAN=0"
    "GIT_VERSION=603814c"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm555 flycast_libretro.so \
      $out/lib/retroarch/cores/flycast2021_libretro.so
    runHook postInstall
  '';

  passthru = {
    core = "flycast2021";
    # Cores dir within the package, read by retroarch-bare.wrapper.
    libretroCore = "/lib/retroarch/cores";
  };

  meta = {
    description = "Flycast 2021 (metallic77 low-end fork) libretro core";
    homepage = "https://github.com/metallic77/flycast";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
