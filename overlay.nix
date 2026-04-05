final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/linux-rk3326 {
    linuxPackages_latest = prev.linuxPackages_latest;
  };

  rk3326-dtb = final.callPackage ./pkgs/rk3326-dtb {
    kernel = final.linux-rk3326;
  };

  retroarch-joypad-autoconfig = final.callPackage ./pkgs/retroarch-joypad-autoconfig {
    retroarch-joypad-autoconfig = prev.retroarch-joypad-autoconfig;
  };

  retroarch-bare = final.callPackage ./pkgs/retroarch { retroarch-bare = prev.retroarch-bare; };
  retroarch-handheld = final.callPackage ./pkgs/retroarch/wrapper.nix { };

  alsa-utils = final.callPackage ./pkgs/alsa-utils { alsa-utils = prev.alsa-utils; };

  libretro = prev.libretro // {
    parallel-n64 = final.callPackage ./pkgs/parallel-n64 { libretro = prev.libretro; };
    ppsspp = final.callPackage ./pkgs/ppsspp { libretro = prev.libretro; };
  };

  sdl3 = final.callPackage ./pkgs/sdl3 { sdl3 = prev.sdl3; };

  panel-generic-dsi = final.callPackage ./pkgs/panel-generic-dsi {
    kernel = final.linux-rk3326;
  };

  rocknix-joypad = final.callPackage ./pkgs/rocknix-joypad {
    kernel = final.linux-rk3326;
  };
}
