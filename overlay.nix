final: prev: {
  linux-rk3326 = final.callPackage ./pkgs/kernel-rk3326 { };

  retroarch-joypad-autoconfig = prev.callPackage ./pkgs/retroarch-joypad-autoconfig {
    retroarch-joypad-autoconfig = prev.retroarch-joypad-autoconfig;
  };

  retroarch-bare = prev.callPackage ./pkgs/retroarch { retroarch-bare = prev.retroarch-bare; };
  retroarch-handheld = final.callPackage ./pkgs/retroarch/wrapper.nix { };

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
