{ lib
, retroarch-bare
, retroarch-joypad-autoconfig
, libretro
, ffmpeg_7
, pipewire
, qt6
, wrapGAppsHook3
, settings ? { }
}:

let
  customAutoconfig = retroarch-joypad-autoconfig.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${./autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
    '';
  });

  customBare = (retroarch-bare.override {
    withWayland = false;
    retroarch-joypad-autoconfig = customAutoconfig;
  }).overrideAttrs (old: {
    # Remove unnecessary dependencies (fragile — may need updating on nixpkgs bumps)
    buildInputs = lib.lists.subtractLists [
      ffmpeg_7
      pipewire
      qt6.qtbase
      wrapGAppsHook3
    ] old.buildInputs;
    nativeBuildInputs = lib.remove
      qt6.wrapQtAppsHook
      old.nativeBuildInputs;
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
  });
in
customBare.wrapper {
  cores = with libretro; [
    mgba
    gambatte
    beetle-ngp
    snes9x
    genesis-plus-gx
    fceumm
    pcsx-rearmed
    fbneo
    melonds
    dosbox-pure
  ];
  inherit settings;
}
