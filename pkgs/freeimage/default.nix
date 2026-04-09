{
  lib,
  stdenv,
  fetchsvn,
  libtiff,
  libpng,
  zlib,
  libwebp,
  libraw,
  openjpeg,
  libjpeg,
  jxrlib,
  imath,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "freeimage";
  version = "3.18.0-unstable-2024-04-18";

  src = fetchsvn {
    url = "svn://svn.code.sf.net/p/freeimage/svn/";
    rev = "1911";
    hash = "sha256-JznVZUYAbsN4FplnuXxCd/ITBhH7bfGKWXep2A6mius=";
  };

  sourceRoot = "${finalAttrs.src.name}/FreeImage/trunk";

  prePatch = ''
    rm -rf Source/Lib* Source/OpenEXR Source/ZLib
  '';

  patchFlags = [
    "-p1"
    "--binary"
  ];

  patches = [
    ./unbundle.diff
    ./CVE-2020-24292.patch
    ./CVE-2020-24293.patch
    ./CVE-2020-24295.patch
    ./CVE-2021-33367.patch
    ./CVE-2021-40263.patch
    ./CVE-2021-40266.patch
    ./CVE-2023-47995.patch
    ./CVE-2023-47997.patch
  ];

  postPatch = ''
    substituteInPlace Makefile.fip --replace-fail "pkg-config" "$PKG_CONFIG"
    substituteInPlace Makefile.gnu --replace-fail "pkg-config" "$PKG_CONFIG"

    # half.h moved from OpenEXR to Imath in OpenEXR 3.x
    find Source -name '*.cpp' -o -name '*.h' | xargs sed -i \
      's|<OpenEXR/half\.h>|<Imath/half.h>|g'

    # Disable EXR plugin — incompatible with OpenEXR 3.x API (seekg/tellg return uint64_t)
    # ES-fcamod doesn't need HDR image support
    rm -f Source/FreeImage/PluginEXR.cpp
    # Remove all references to PluginEXR from all Makefiles
    sed -i 's|[^ ]*PluginEXR[^ ]*||g' Makefile.gnu Makefile.fip Makefile.srcs fipMakefile.srcs
    sed -i 's|s_plugins->AddNode(InitEXR);|// EXR disabled|' Source/FreeImage/Plugin.cpp
    # Remove OpenEXR from pkg-config calls (otherwise all flags are lost)
    # Replace with Imath for half.h support
    sed -i 's|OpenEXR |Imath |g' Makefile.gnu Makefile.fip

    # Remove JPEGTransform (depends on IJG libjpeg transupp internals, not in libjpeg-turbo)
    sed -i 's|[^ ]*JPEGTransform[^ ]*||g' Makefile.gnu Makefile.fip Makefile.srcs fipMakefile.srcs
    rm -f Source/FreeImageToolkit/JPEGTransform.cpp
  '';

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libtiff
    libtiff.dev_private
    libpng
    zlib
    libwebp
    libraw
    openjpeg
    libjpeg
    jxrlib
    imath
  ];

  postBuild = ''
    make -f Makefile.fip
  '';

  INCDIR = "${placeholder "out"}/include";
  INSTALLDIR = "${placeholder "out"}/lib";

  preInstall = ''
    mkdir -p $INCDIR $INSTALLDIR
  '';

  postInstall = ''
    make -f Makefile.fip install
  '';

  enableParallelBuilding = true;

  meta = {
    description = "Open Source library for accessing popular graphics image file formats";
    homepage = "http://freeimage.sourceforge.net/";
    license = lib.licenses.gpl2;
    platforms = [ "aarch64-linux" ];
  };
})
