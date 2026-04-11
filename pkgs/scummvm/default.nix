{
  libretro,
}:
libretro.scummvm.overrideAttrs (old: {
  # Stock libretro-scummvm builds with platform=unix → HAVE_OPENGL, which asks
  # for a desktop GL context our GLES-only retroarch refuses. platform=rpi3_64
  # flips it to HAVE_OPENGLES2 and matches our context type (Cortex-A53 tuning
  # is ISA-compatible with the R36H's Cortex-A35).
  makeFlags = (old.makeFlags or [ ]) ++ [ "platform=rpi3_64" ];
})
