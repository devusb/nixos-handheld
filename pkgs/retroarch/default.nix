{
  lib,
  retroarch-bare,
  ffmpeg_7,
  pipewire,
  qt6,
  wrapGAppsHook3,
}:
(retroarch-bare.override {
  withWayland = false;
}).overrideAttrs
  (old: {
    buildInputs = lib.lists.subtractLists [
      ffmpeg_7
      pipewire
      qt6.qtbase
      wrapGAppsHook3
    ] old.buildInputs;
    nativeBuildInputs = lib.remove qt6.wrapQtAppsHook old.nativeBuildInputs;
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--disable-pipewire"
      "--disable-pulse"
      "--disable-qt"
      "--disable-wayland"
      "--disable-x11"
      "--disable-xinerama"
      "--disable-xrandr"
    ];
    patches = (old.patches or [ ]) ++ [
      ./odroidgo2-features.patch
    ];
  })
