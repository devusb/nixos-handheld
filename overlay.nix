final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/kernel-rk3326 { };

  retroarch-joypad-autoconfig = prev.retroarch-joypad-autoconfig.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${./pkgs/retroarch/autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
    '';
  });

  retroarch-bare = (prev.retroarch-bare.override {
    withWayland = false;
  }).overrideAttrs (old: {
    # Remove unnecessary dependencies (fragile — may need updating on nixpkgs bumps)
    buildInputs = final.lib.lists.subtractLists [
      final.ffmpeg_7
      final.pipewire
      final.qt6.qtbase
      final.wrapGAppsHook3
    ] old.buildInputs;
    nativeBuildInputs = final.lib.remove
      final.qt6.wrapQtAppsHook
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
      ./pkgs/retroarch/odroidgo2-features.patch
    ];
  });

  retroarch-handheld = final.callPackage ./pkgs/retroarch { };

  # Strip SDL3 of desktop dependencies — saves ~2.7GB (GTK4, gstreamer, pipewire)
  sdl3 = (prev.sdl3.override {
    libdecorSupport = false;
    pipewireSupport = false;
    pulseaudioSupport = false;
    waylandSupport = false;
    x11Support = false;
  }).overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [ "-DSDL_UNIX_CONSOLE_BUILD=ON" ];
    doCheck = false;
  });
}
