{
  lib,
  retroarch-bare,
  ffmpeg_7,
  qt6,
  wrapGAppsHook3,
  autoAddDriverRunpath,
  libGL ? null,
  libGLU ? null,
  libgbm ? null,
  SDL2_classic,
}:
(retroarch-bare.override (
  {
    # Native Wayland video driver so RetroArch can render as a Wayland
    # client under cage without going through SDL2's Wayland backend.
    withWayland = true;
    # Match the rest of the stack (ES, DraStic) — nixpkgs default SDL2
    # is sdl2-compat (SDL3 shim), which breaks both this and DraStic.
    SDL2 = SDL2_classic;
  }
  // lib.optionalAttrs (libGL != null) { inherit libGL; }
  // lib.optionalAttrs (libGLU != null) { inherit libGLU; }
  // lib.optionalAttrs (libgbm != null) { inherit libgbm; }
)).overrideAttrs
  (old: {
    buildInputs = lib.lists.subtractLists [
      ffmpeg_7
      qt6.qtbase
      wrapGAppsHook3
    ] old.buildInputs;
    nativeBuildInputs = (lib.remove qt6.wrapQtAppsHook old.nativeBuildInputs) ++ [
      autoAddDriverRunpath
    ];
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--disable-pulse"
      "--disable-qt"
      "--disable-x11"
      "--disable-xinerama"
      "--disable-xrandr"
      # Panfrost on Mali-G31 serves GLES 3.1 better than its partial GL 3.1 compat
      # profile, and libretro cores on ARM (mupen64plus-next, parallel-n64, ppsspp)
      # target GLES. GL and GLES are mutually exclusive in RetroArch's build.
      "--disable-opengl"
      "--enable-opengles"
      "--enable-opengles3"
    ];
  })
