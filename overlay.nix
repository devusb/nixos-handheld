final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/linux-rk3326 {
    linuxPackages_latest = prev.linuxPackages_latest;
  };

  rk3326-dtb = final.callPackage ./pkgs/rk3326-dtb {
    kernel = final.linux-rk3326;
  };

  # h700-dtb compiles only the RG28XX overlay; its base DTS
  # (sun50i-h700-anbernic-rg35xx-plus.dts) and DT bindings are upstream, so
  # the stock linuxPackages_latest source suffices — no dependency on a
  # custom linux-h700 build.
  h700-dtb = final.callPackage ./pkgs/h700-dtb {
    kernel = final.linuxPackages_latest.kernel;
  };

  u-boot-rg28xx = final.callPackage ./pkgs/u-boot-rg28xx { };

  retroarch-joypad-autoconfig = final.callPackage ./pkgs/retroarch-joypad-autoconfig {
    retroarch-joypad-autoconfig = prev.retroarch-joypad-autoconfig;
  };

  retroarch-bare = final.callPackage ./pkgs/retroarch { retroarch-bare = prev.retroarch-bare; };
  retroarch-bare-odroidgo2 = final.retroarch-bare.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./pkgs/retroarch/odroidgo2-features.patch ];
  });

  alsa-utils = final.callPackage ./pkgs/alsa-utils { alsa-utils = prev.alsa-utils; };

  libretro = prev.libretro // {
    parallel-n64 = final.callPackage ./pkgs/parallel-n64 { libretro = prev.libretro; };
    ppsspp = final.callPackage ./pkgs/ppsspp { libretro = prev.libretro; };
    mupen64plus = final.callPackage ./pkgs/mupen64plus { libretro = prev.libretro; };
    flycast = final.callPackage ./pkgs/flycast { libretro = prev.libretro; };
    scummvm = final.callPackage ./pkgs/scummvm { libretro = prev.libretro; };
  };

  sdl3 = final.callPackage ./pkgs/sdl3 { sdl3 = prev.sdl3; };

  panel-generic-dsi = final.callPackage ./pkgs/panel-generic-dsi {
    kernel = final.linux-rk3326;
  };

  rocknix-joypad = final.callPackage ./pkgs/rocknix-joypad {
    kernel = final.linux-rk3326;
  };

  SDL2_classic = final.callPackage ./pkgs/SDL2_classic { };

  freeimage = final.callPackage ./pkgs/freeimage { };
  # ES and DraStic both need SDL2_classic (not sdl2-compat/SDL3) for KMSDRM
  SDL2_classic_mixer = prev.SDL2_mixer.override { SDL2 = final.SDL2_classic; };
  emulationstation-fcamod = final.callPackage ./pkgs/emulationstation-fcamod {
    SDL2 = final.SDL2_classic;
    SDL2_mixer = final.SDL2_classic_mixer;
  };
  es-theme-gbz35-mod = final.callPackage ./pkgs/es-theme-gbz35-mod { };
  drastic = final.callPackage ./pkgs/drastic { SDL2 = final.SDL2_classic; };

  balatro = final.callPackage ./pkgs/balatro {
    love = prev.love;
    balatro = prev.balatro;
  };

  libmali = final.callPackage ./pkgs/libmali { };

  mali-kbase = final.callPackage ./pkgs/mali-kbase {
    kernel = final.linux-rk3326;
  };

  portmaster-fhs = final.callPackage ./pkgs/portmaster-fhs {
    SDL2 = final.SDL2_classic;
  };

  portmaster-launch = final.callPackage ./pkgs/portmaster-launch { };

  gptokeyb2 = final.callPackage ./pkgs/gptokeyb2 { };
}
