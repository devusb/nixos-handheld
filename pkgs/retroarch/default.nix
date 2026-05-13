{
  lib,
  retroarch-bare,
  ffmpeg_7,
  qt6,
  wrapGAppsHook3,
}:
(retroarch-bare.override {
  withWayland = false;
}).overrideAttrs
  (old: {
    buildInputs = lib.lists.subtractLists [
      ffmpeg_7
      qt6.qtbase
      wrapGAppsHook3
    ] old.buildInputs;
    nativeBuildInputs = lib.remove qt6.wrapQtAppsHook old.nativeBuildInputs;
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--disable-pulse"
      "--disable-qt"
      "--disable-wayland"
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
