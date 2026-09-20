# Native SDL2 (not sdl2-compat/SDL3) — needed for DraStic which segfaults
# with SDL3's KMSDRM backend. Both KMSDRM and Wayland video backends are
# compiled in; ALSA-only audio. SDL picks the backend at runtime: Wayland
# when WAYLAND_DISPLAY is set (under cage), KMSDRM otherwise.
{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  pkg-config,
  alsa-lib,
  libdrm,
  libgbm,
  libglvnd,
  mesa,
  udev,
  libiconv,
  wayland,
  wayland-protocols,
  wayland-scanner,
  libxkbcommon,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "SDL2";
  version = "2.32.6";

  src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    rev = "release-${finalAttrs.version}";
    hash = "sha256-sXlW+ivDRCNMcZDzZEfOPGvFGU0aE4n/fO+Wxym6GGw=";
  };

  outputs = [
    "out"
    "dev"
  ];
  outputBin = "dev";

  patches = [ ./find-headers.patch ];

  # Fix wayland-scanner PATH for cross builds (matches the upstream
  # nixpkgs SDL2 recipe). See libsdl-org/SDL#4860.
  postPatch = ''
    substituteInPlace configure \
      --replace '$(WAYLAND_SCANNER)' 'wayland-scanner'
  '';

  strictDeps = true;
  nativeBuildInputs = [
    pkg-config
    wayland-scanner # build-time scanner binary
  ];

  # SDL2's configure runs `pkg-config --exists wayland-client wayland-scanner
  # wayland-egl wayland-cursor egl xkbcommon` against PKG_CONFIG_PATH, which
  # under strictDeps is populated from buildInputs only. wayland-scanner is
  # split from wayland in modern nixpkgs and ships its own .pc file, so it
  # must appear here too even though we only use it as a build tool.
  buildInputs = [
    libiconv
    alsa-lib
    libdrm
    libgbm
    libglvnd
    mesa
    udev
    wayland
    wayland-protocols
    wayland-scanner
    libxkbcommon
  ];

  enableParallelBuilding = true;

  configureFlags = [
    "--disable-oss"
    "--without-x"
    "--disable-video-x11"
    "--disable-pulseaudio"
    "--disable-pipewire"
    "--disable-jack"
    "--disable-esd"
    "--disable-arts"
    "--disable-nas"
    "--disable-sndio"
    "--disable-libdecor"
    "--enable-video-kmsdrm"
    "--enable-video-wayland"
    "--enable-video-opengles"
    "--enable-alsa"
  ];

  postInstall = ''
    moveToOutput bin/sdl2-config "$dev"
  '';

  postFixup =
    let
      rpath = lib.makeLibraryPath [
        alsa-lib
        libdrm
        libgbm
        libglvnd
        mesa
        udev
        wayland
        libxkbcommon
      ];
    in
    ''
      for lib in $out/lib/*.so* ; do
        if ! [[ -L "$lib" ]]; then
          patchelf --set-rpath "$(patchelf --print-rpath $lib):${rpath}" "$lib"
        fi
      done
    '';

  setupHook = ./setup-hook.sh;

  # Constrained to the 2.x release series — never SDL3.
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version-regex"
      "release-2\\.(.*)"
    ];
  };

  meta = {
    description = "Native SDL2 (not sdl2-compat) with KMSDRM + Wayland support";
    homepage = "http://www.libsdl.org/";
    license = lib.licenses.zlib;
    platforms = lib.platforms.linux;
  };
})
