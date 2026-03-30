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
    parallel-n64
    opera
    mame2003-plus
    scummvm
  ];
  inherit settings;
}
