{
  libretro,
}:
libretro.ppsspp.overrideAttrs (old: {
  meta = old.meta // {
    badPlatforms = [ ];
  };
})
