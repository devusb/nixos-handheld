final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/kernel-rk3326 { };

  retroarch-joypad-autoconfig = prev.retroarch-joypad-autoconfig.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${./pkgs/retroarch/autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
    '';
  });

  retroarch-bare =
    (prev.retroarch-bare.override {
      withWayland = false;
    }).overrideAttrs
      (old: {
        buildInputs = final.lib.lists.subtractLists [
          final.ffmpeg_7
          final.pipewire
          final.qt6.qtbase
          final.wrapGAppsHook3
        ] old.buildInputs;
        nativeBuildInputs = final.lib.remove final.qt6.wrapQtAppsHook old.nativeBuildInputs;
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

  alsa-utils = prev.alsa-utils.override { withPipewireLib = false; };

  libretro = prev.libretro // {
    parallel-n64 = prev.libretro.parallel-n64.overrideAttrs (old: {
      meta = old.meta // {
        badPlatforms = [ ];
      };
      postPatch = (old.postPatch or "") + ''
        sed -i 's/static void nullf() {}/static void nullf(...) {}/' mupen64plus-core/src/r4300/new_dynarec/new_dynarec_64.c
        # Fix R_AARCH64_CONDBR19 — conditional branch out of range to invalidate_block
        # Replace b.eq with inverted b.ne + unconditional b (26-bit range vs 19-bit)
        sed -i '/\.E12:/,/b\.eq.*invalidate_block/{s/b\.eq\s*invalidate_block/b.ne .Lskip_invalidate\n\tb invalidate_block\n.Lskip_invalidate:/}' mupen64plus-core/src/r4300/new_dynarec/arm64/linkage_aarch64.S
      '';
    });
  };

  # Strip SDL3 of desktop dependencies
  sdl3 =
    (prev.sdl3.override {
      libdecorSupport = false;
      pipewireSupport = false;
      pulseaudioSupport = false;
      waylandSupport = false;
      x11Support = false;
    }).overrideAttrs
      (old: {
        cmakeFlags = old.cmakeFlags ++ [ "-DSDL_UNIX_CONSOLE_BUILD=ON" ];
        doCheck = false;
      });
}
