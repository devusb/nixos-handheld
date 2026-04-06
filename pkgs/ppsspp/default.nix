{
  libretro,
}:
libretro.ppsspp.overrideAttrs (old: {
  meta = old.meta // {
    badPlatforms = [ ];
  };
  # ppsspp libretro defaults to desktop GL on Linux; Panfrost/Mali-G31 serves
  # GLES, and our RetroArch is built for GLES, so force the core to GLES too.
  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
    "-DUSING_GLES2=ON"
  ];
  env.NIX_CFLAGS_COMPILE = "-O3 -ffast-math";
})
