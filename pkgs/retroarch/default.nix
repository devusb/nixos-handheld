{ retroarch-bare
, libretro
, settings ? { }
}:

retroarch-bare.wrapper {
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
    mupen64plus
    opera
    mame2003-plus
  ];
  inherit settings;
}
