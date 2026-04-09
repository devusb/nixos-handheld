# Native SDL2 (not sdl2-compat/SDL3) — needed for DraStic which segfaults
# with SDL3's KMSDRM backend. Minimal build: DRM + ALSA only.
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  alsa-lib,
  libdrm,
  libgbm,
  libglvnd,
  mesa,
  udev,
  libiconv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "SDL2-native";
  version = "2.32.6";

  src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    rev = "release-${finalAttrs.version}";
    hash = "sha256-sXlW+ivDRCNMcZDzZEfOPGvFGU0aE4n/fO+Wxym6GGw=";
  };

  outputs = [ "out" "dev" ];
  outputBin = "dev";

  patches = [ ./find-headers.patch ];

  strictDeps = true;
  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libiconv
    alsa-lib
    libdrm
    libgbm
    libglvnd
    mesa
    udev
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "--disable-oss"
    "--without-x"
    "--disable-video-wayland"
    "--disable-video-x11"
    "--disable-video-opengl"
    "--disable-pulseaudio"
    "--disable-pipewire"
    "--disable-jack"
    "--disable-esd"
    "--disable-arts"
    "--disable-nas"
    "--disable-sndio"
    "--disable-libdecor"
    "--enable-video-kmsdrm"
    "--enable-video-opengles"
    "--enable-alsa"
  ];

  postInstall = ''
    rm $out/lib/*.a
    moveToOutput bin/sdl2-config "$dev"
  '';

  postFixup = let
    rpath = lib.makeLibraryPath [
      alsa-lib
      libdrm
      libgbm
      libglvnd
      mesa
      udev
    ];
  in ''
    for lib in $out/lib/*.so* ; do
      if ! [[ -L "$lib" ]]; then
        patchelf --set-rpath "$(patchelf --print-rpath $lib):${rpath}" "$lib"
      fi
    done
  '';

  setupHook = ./setup-hook.sh;

  meta = {
    description = "Native SDL2 (not sdl2-compat) with KMSDRM support";
    homepage = "http://www.libsdl.org/";
    license = lib.licenses.zlib;
    platforms = lib.platforms.linux;
  };
})
