final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/linux-rk3326 {
    linuxPackages_latest = prev.linuxPackages_latest;
  };

  linux-h700 = final.callPackage ./pkgs/linux-h700 {
    linuxPackages_latest = prev.linuxPackages_latest;
    rg28xx-panel-firmware = final.rg28xx-panel-firmware;
  };

  rk3326-dtb = final.callPackage ./pkgs/rk3326-dtb {
    kernel = final.linux-rk3326;
  };

  # h700-dtb compiles the RG28XX overlay against linux-h700's patched
  # source so cpp's include path resolves to the ROCKNIX-patched
  # rg35xx-plus.dts (which gains the spi-gpio + panel + backlight nodes
  # via patch 0126 et al). Without that, the &panel override doesn't
  # resolve at DT compile time.
  h700-dtb = final.callPackage ./pkgs/h700-dtb {
    kernel = final.linux-h700;
  };

  rg28xx-panel-firmware = final.callPackage ./pkgs/rg28xx-panel-firmware { };

  # Prebuilt SPL+U-Boot blob from ROCKNIX.
  u-boot-rg28xx-rocknix = final.callPackage ./pkgs/u-boot-rg28xx-rocknix { };

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
    flycast2021 = final.callPackage ./pkgs/flycast2021 { };
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
