{
  libretro,
}:
libretro.mupen64plus.overrideAttrs (_old: {
  # Panfrost on Mali-G31 exposes GL 3.1 / GLES 3.1 — no desktop GL 3.3 core context.
  # FORCE_GLES3=1 switches GLideN64 to a GLES3 context so EGL can match.
  # parallel-rdp / parallel-rsp are Vulkan-only; Panfrost Mali-G31 has no Vulkan driver.
  makeFlags = [
    "platform=unix"
    "ARCH=arm64"
    "WITH_DYNAREC=aarch64"
    "FORCE_GLES3=1"
    "HAVE_THR_AL=1"
    "HAVE_PARALLEL_RDP=0"
    "HAVE_PARALLEL_RSP=0"
  ];
})
