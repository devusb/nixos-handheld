{
  libretro,
}:
libretro.parallel-n64.overrideAttrs (old: {
  meta = old.meta // {
    badPlatforms = [ ];
  };
  postPatch = (old.postPatch or "") + ''
    sed -i 's/static void nullf() {}/static void nullf(...) {}/' mupen64plus-core/src/r4300/new_dynarec/new_dynarec_64.c
    # Fix R_AARCH64_CONDBR19 — conditional branch out of range to invalidate_block
    # Replace b.eq with inverted b.ne + unconditional b (26-bit range vs 19-bit)
    sed -i '/\.E12:/,/b\.eq.*invalidate_block/{s/b\.eq\s*invalidate_block/b.ne .Lskip_invalidate\n\tb invalidate_block\n.Lskip_invalidate:/}' mupen64plus-core/src/r4300/new_dynarec/arm64/linkage_aarch64.S
  '';
})
