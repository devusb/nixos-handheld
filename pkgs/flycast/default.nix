{
  libretro,
}:
libretro.flycast.overrideAttrs (old: {
  # Panfrost on Mali-G31 has no desktop GL 3.x core context.
  # USE_GLES=ON defines HAVE_OPENGLES so the libretro shell requests
  # RETRO_HW_CONTEXT_OPENGLES3 instead of OPENGL/OPENGL_CORE.
  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
    "-DUSE_GLES=ON"
  ];
})
