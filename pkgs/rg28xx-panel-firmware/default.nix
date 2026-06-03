# Panel init blob for the Anbernic RG28XX panel, consumed by the
# kikuchan98 panel-mipi-dpi-spi driver via request_firmware.
# Extracted from ROCKNIX-H700.aarch64-20250517 SYSTEM squashfs:
#   /usr/lib/kernel-overlays/base/lib/firmware/panels/anbernic,rg28xx-panel.panel
# The driver computes its firmware filename from the panel's first
# compatible string — "anbernic,rg28xx-panel" → panels/anbernic,rg28xx-panel.panel.
#
# Rotation override: ROCKNIX ships rotation=270 (LEFT_UP) in the blob,
# but on our setup that produces sideways rendering for SDL2/KMSDRM
# clients (ES, RetroArch). Patch the blob's rotation field (big-endian
# u16 at byte offset 20) to 90 (RIGHT_UP) — userspace honoring DRM
# panel-orientation then rotates 90° CCW, matching what fbcon does via
# `fbcon=rotate:3`. See panel-mipi.c struct panel_firmware_config.
{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "rg28xx-panel-firmware";
  version = "rocknix-20250517-rotate90";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -D -m 0644 ${./anbernic_rg28xx-panel.panel} \
      "$out/lib/firmware/panels/anbernic,rg28xx-panel.panel"

    # Overwrite rotation field at byte offset 20-21 with 0x00 0x5A (= 90, big-endian).
    printf '\x00\x5a' | dd of="$out/lib/firmware/panels/anbernic,rg28xx-panel.panel" \
      bs=1 seek=20 count=2 conv=notrunc status=none
    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
}
